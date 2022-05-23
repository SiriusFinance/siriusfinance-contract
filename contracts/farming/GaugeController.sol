// SPDX-License-Identifier: MIT
//@notice Controls liquidity gauges and the issuance of coins through the gauges
pragma solidity 0.8.6;

import "@openzeppelin/contracts-upgradeable-4.2.0/utils/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable-4.2.0/utils/math/MathUpgradeable.sol";
import "../OwnerPausableUpgradeable.sol";
import "../interfaces/IVotingEscrow.sol";
import "../libraries/Integers.sol";

contract GaugeController is OwnerPausableUpgradeable {
    using SafeMathUpgradeable for uint256;
    using MathUpgradeable for uint256;
    using Integers for int128;

    struct Point {  
        uint256 bias;
        uint256 slope;
    }
    
    struct VotedSlope{
        uint256 slope;
        uint256 power;
        uint256 end;
    }

    event AddType(string name, uint256 typeId);
    event NewTypeWeight(uint256 typeId, uint256 time, uint256 weight, uint256 totalWeight);
    event NewGaugeWeight(address gaugeAddress, uint256 time, uint256 weight, uint256 totalWeight);

    event VoteForGauge(uint256 time, address user, address gaugeAddr, uint256 weight);
    event NewGauge(address addr, uint256 gaugeType, uint256 weight);

    // 7 * 86400 seconds - all future times are rounded by week
    uint256 constant WEEK = 604800;
    // Cannot change weight votes more often than once in 10 days
    uint256 constant WEIGHT_VOTE_DELAY = 10 * 86400;
    uint256 constant MULTIPLIER = 10 ** 18;

    address public token;  // SRS token
    address public votingEscrow; // Voting escrow SRS

    // Gauge parameters
    // All numbers are "fixed point" on the basis of 1e18
    uint256 public nGaugeTypes;
    uint256 public nGauges;
    mapping(uint256 => string) public gaugeTypeNames;

    // Needed for enumeration
    address[1000000000] public gauges;

    // we increment values by 1 prior to storing them here so we can rely on a value
    // of zero as meaning the gauge has not been set
    mapping(address => uint256) gaugeTypes_;

    mapping(address => mapping(address => VotedSlope)) public voteUserSlopes;  // user -> gauge_addr -> VotedSlope
    mapping(address => uint256) public voteUserPower;  // Total vote power used by user
    mapping(address => mapping(address => uint256)) public lastUserVote;  // Last user vote's timestamp for each gauge address

    // Past and scheduled points for gauge weight, sum of weights per type, total weight
    // Point is for bias+slope
    // changes_* are for changes in slope
    // time_* are for the last change timestamp
    // timestamps are rounded to whole weeks

    mapping(address => mapping(uint256 => Point)) public pointsWeight;  // gauge_addr -> time -> Point
    mapping(address => mapping(uint256 => uint256)) public changesWeight; // gauge_addr -> time -> slope
    mapping(address => uint256) public timeWeight;  // gauge_addr -> last scheduled time (next week)

    mapping(uint256 => mapping(uint256 => Point)) public pointsSum;  // type_id -> time -> Point
    mapping(uint256 => mapping(uint256 => uint256)) public changesSum;  // type_id -> time -> slope
    uint256[1000000000] public timeSum;  // type_id -> last scheduled time (next week)

    mapping(uint256=>uint256) public pointsTotal;  // time -> total weight
    uint256 public timeTotal;  // last scheduled time

    mapping(uint256 => mapping(uint256 => uint256)) public pointsTypeWeight;  // type_id -> time -> type weight
    uint256[1000000000] public timeTypeWeight; // type_id -> last scheduled time (next week)


    function __GaugeController_init(address _token, address _veToken)
        external
        initializer
        returns (bool)
    {
        require(_token != address(0), "Minter: !token");
        require(_veToken != address(0), "Minter: !veToken");

        __OwnerPausable_init();

        token = _token;
        votingEscrow = _veToken;
        timeTotal = block.timestamp / WEEK * WEEK;
    }


    /**
     * @notice Get gauge type for address
     * @param _addr Gauge address
     * @return Gauge type id
     */
    function gaugeTypes(address _addr) external view returns(uint256) {
        
        uint256 gaugeType = gaugeTypes_[_addr];
        require(gaugeType != 0, "GaugeController: !gaugeType"); 

        return gaugeType - 1;
    }

    /**
     * @notice Fill historic type weights week-over-week for missed checkins and return the type weight for the future week
     * @param _gaugeType Gauge type id
     * @return Type weight
     */
    function _getTypeWeight(uint256 _gaugeType) internal returns(uint256) {
        uint256 t = timeTypeWeight[_gaugeType];
        if (t > 0) {
            uint256 w = pointsTypeWeight[_gaugeType][t];
            for(uint256 i = 0; i < 500; i ++) {
                if (t > block.timestamp) {
                    break;
                }
                t += WEEK;
                pointsTypeWeight[_gaugeType][t] = w;
                if (t > block.timestamp) {
                    timeTypeWeight[_gaugeType] = t;
                }
            }
            return w;
        }
        else {
            return 0;
        }

    }


    /**
     * @notice Fill sum of gauge weights for the same type week-over-week for missed checkins and return the sum for the future week
     * @param _gaugeType Gauge type id
     * @return Sum of weights
     */
    function _getSum(uint256 _gaugeType) internal returns(uint256) {
        uint256 t = timeSum[_gaugeType];
        if (t > 0){
            Point memory pt = pointsSum[_gaugeType][t];
            for(uint256 i = 0; i < 500; i ++) {
                if (t > block.timestamp) {
                    break;
                }
                t += WEEK;
                uint256 dBias = pt.slope * WEEK;
                if (pt.bias > dBias) {
                    pt.bias = pt.bias - dBias;
                    uint256 dSlope = changesSum[_gaugeType][t];
                    pt.slope = pt.slope - dSlope;
                }
                else {
                    pt.bias = 0;
                    pt.slope = 0;
                }
                pointsSum[_gaugeType][t] = pt;
                if (t > block.timestamp){
                    timeSum[_gaugeType] = t;
                }
            }
            return pt.bias;

        }
        else{
            return 0;
        }
    }


    /**
     * @notice Fill historic total weights week-over-week for missed checkins and return the total for the future week
     * @return Total weight
     */
    function _getTotal() internal returns(uint256) {
        
        uint256 t = timeTotal;
        uint256 _nGaugeTypes = nGaugeTypes;
        if (t > block.timestamp) {
            // If we have already checkpointed - still need to change the value
            t = t.sub(WEEK);
        }
        uint256 pt = pointsTotal[t];

        for(uint256 gaugeType; gaugeType < 100; gaugeType++) {
            if (gaugeType == _nGaugeTypes) {
                break;
            }
            _getSum(gaugeType);
            _getTypeWeight(gaugeType);
        }

        for(uint256 i; i < 500; i++){
            if (t > block.timestamp) {
                break;
            }
            t += WEEK;
            pt = 0;
            // Scales as n_types * n_unchecked_weeks (hopefully 1 at most)
            for(uint256 gaugeType; gaugeType < 100; gaugeType++) {
                if (gaugeType == _nGaugeTypes) {
                    break;
                }
                uint256 typeSum = pointsSum[gaugeType][t].bias;
                uint256 typeWeight = pointsTypeWeight[gaugeType][t];
                pt += typeSum * typeWeight;
            }
            pointsTotal[t] = pt;

            if (t > block.timestamp) {
                timeTotal = t;
            }
        }
        return pt;

    }


    /**
     * @notice Fill historic gauge weights week-over-week for missed checkins and return the total for the future week
     * @param _gaugeAddr Address of the gauge
     * @return Gauge weight
     */
    function _getWeight(address _gaugeAddr) internal returns(uint256) {
        uint256 t = timeWeight[_gaugeAddr];
        if (t > 0) {
            Point memory pt = pointsWeight[_gaugeAddr][t];
            for(uint256 i; i < 500; i++){
                if (t > block.timestamp) {
                    break;
                }
                t += WEEK;
                uint256 dBias = pt.slope * WEEK;
                if (pt.bias > dBias) {
                    pt.bias -= dBias;
                    uint256 dSlope = changesWeight[_gaugeAddr][t];
                    pt.slope -= dSlope;
                }
                else{
                    pt.bias = 0;
                    pt.slope = 0;
                }
                pointsWeight[_gaugeAddr][t] = pt;
                if (t > block.timestamp) {
                    timeWeight[_gaugeAddr] = t;
                }
            }
            return pt.bias;

        }
        else{
            return 0;
        }

    }

    
    /**
     * @notice Add gauge `addr` of type `_gaugeType` with weight `weight`
     * @param _addr Gauge address
     * @param _gaugeType Gauge type
     * @param _weight Gauge weight
     */
    function addGauge(address _addr, uint256 _gaugeType, uint256 _weight) external onlyOwner {
        require(_gaugeType >= 0 && _gaugeType < nGaugeTypes, "GaugeController: !gaugeType");
        require(gaugeTypes_[_addr] == 0, "GaugeController: addr");   //dev: cannot add the same gauge twice

        uint256 n = nGauges;
        nGauges = n + 1;
        gauges[n] = _addr;

        gaugeTypes_[_addr] = _gaugeType + 1;
        uint256 nextTime = (block.timestamp + WEEK) / WEEK * WEEK;

        if (_weight > 0) {
            uint256 typeWeight = _getTypeWeight(_gaugeType);
            uint256 oldSum = _getSum(_gaugeType);
            uint256 oldTotal = _getTotal();

            pointsSum[_gaugeType][nextTime].bias = _weight + oldSum;
            timeSum[_gaugeType] = nextTime;
            pointsTotal[nextTime] = oldTotal + typeWeight * _weight;
            timeTotal = nextTime;

            pointsWeight[_addr][nextTime].bias = _weight;

        }

        if (timeSum[_gaugeType] == 0) {
            timeSum[_gaugeType] = nextTime;
        }
        timeWeight[_addr] = nextTime;

        emit NewGauge(_addr, _gaugeType, _weight);

    }
  

    /**
     * @notice Checkpoint to fill data common for all gauges
     */
    function checkpoint() external {
        _getTotal();
    }


    /**
     * @notice Checkpoint to fill data for both a specific gauge and common for all gauges 
     * @param _addr Gauge address
     */
    function checkpointGauge(address _addr) external {
        _getWeight(_addr);
        _getTotal();
    }



    /**
     * @notice Get Gauge relative weight (not more than 1.0) normalized to 1e18
            (e.g. 1.0 == 1e18). Inflation which will be received by it is
            inflation_rate * relative_weight / 1e18
     * @param _addr Gauge address
     * @param _time Relative weight at the specified timestamp in the past or present
     * @return Value of relative weight normalized to 1e18
     */
    function _gaugeRelativeWeight(address _addr, uint256 _time) internal view returns(uint256) {
        // return 1 ether;
        uint256 t = _time / WEEK * WEEK;
        uint256 _totalWeight = pointsTotal[t];

        if (_totalWeight > 0) {
            uint256 gaugeType = gaugeTypes_[_addr] - 1;
            uint256 _typeWeight = pointsTypeWeight[gaugeType][t];
            uint256 _gaugeWeight = pointsWeight[_addr][t].bias;
            return MULTIPLIER * _typeWeight * _gaugeWeight / _totalWeight;
        }else {
            return 0;
        }

    }



    /**
     * @notice Get Gauge relative weight (not more than 1.0) normalized to 1e18
            (e.g. 1.0 == 1e18). Inflation which will be received by it is
            inflation_rate * relative_weight / 1e18
     * @param _addr Gauge address
     * @param _time Relative weight at the specified timestamp in the past or present
     * @return Value of relative weight normalized to 1e18
     */
    function gaugeRelativeWeight(address _addr, uint256 _time) external view returns(uint256) {
        return _gaugeRelativeWeight(_addr, _time);

    }



    /**
     * @notice Get gauge weight normalized to 1e18 and also fill all the unfilled
            values for type and gauge records
     * @dev Any address can call, however nothing is recorded if the values are filled already
     * @param _addr Gauge address
     * @param _time Relative weight at the specified timestamp in the past or present
     * @return Value of relative weight normalized to 1e18
     */
    function gaugeRelativeWeightWrite(address _addr, uint256 _time) external returns (uint256) {
        _getWeight(_addr);
        _getTotal();  // Also calculates get_sum
        return _gaugeRelativeWeight(_addr, _time);
    }



    /**
     * @notice Change type weight
     * @param _typeId Type id
     * @param _weight New type weight
     */
    function _changeTypeWeight(uint256 _typeId, uint256 _weight) internal {
        uint256 oldWeight = _getTypeWeight(_typeId);
        uint256 oldSum = _getSum(_typeId);
        uint256 _totalWeight = _getTotal();
        uint256 nextTime = (block.timestamp + WEEK) / WEEK * WEEK;

        _totalWeight = _totalWeight + (oldSum * _weight) - (oldSum * oldWeight);
        pointsTotal[nextTime] = _totalWeight;
        pointsTypeWeight[_typeId][nextTime] = _weight;
        timeTotal = nextTime;
        timeTypeWeight[_typeId] = nextTime;

        emit NewTypeWeight(_typeId, nextTime, _weight, _totalWeight);
    }

    
    /**
     * @notice Add gauge type with name `_name` and weight `weight`
     * @param _name Name of gauge type
     * @param _weight Weight of gauge type
     */
    function addType(string memory _name, uint256 _weight) external onlyOwner {
        uint256 typeId = nGaugeTypes;
        gaugeTypeNames[typeId] = _name;
        nGaugeTypes = typeId + 1;
        require(_weight != 0, "GaugeController: !_weight");
        _changeTypeWeight(typeId, _weight);
        emit AddType(_name, typeId);
        
    }



    /**
     * @notice Change gauge type `type_id` weight to `weight`
     * @param _typeId Gauge type id
     * @param _weight New Gauge weight
     */
    function changeTypeWeight(uint256 _typeId, uint256 _weight) external onlyOwner {
        _changeTypeWeight(_typeId, _weight);

    }


    
    /**
     * 
     */
    function _changeGaugeWeight(address _addr, uint256 _weight) internal {
        // Change gauge weight
        // Only needed when testing in reality
        uint256 gaugeType = gaugeTypes_[_addr].sub(1);
        uint256 oldGaugeWeight = _getWeight(_addr);
        uint256 typeWeight = _getTypeWeight(gaugeType);
        uint256 oldSum = _getSum(gaugeType);
        uint256 _totalWeight = _getTotal();
        uint256 nextTime = (block.timestamp + WEEK) / WEEK * WEEK;

        pointsWeight[_addr][nextTime].bias = _weight;
        timeWeight[_addr] = nextTime;

        uint256 newSum = oldSum + _weight - oldGaugeWeight;
        pointsSum[gaugeType][nextTime].bias = newSum;
        timeSum[gaugeType] = nextTime;

        _totalWeight = _totalWeight + (oldSum * _weight) - (oldSum * typeWeight);
        pointsTotal[nextTime] = _totalWeight;
        timeTotal = nextTime;

        emit NewGaugeWeight(_addr, block.timestamp, _weight, _totalWeight);

    }


    
    /**
     * @notice Change weight of gauge `addr` to `weight`
     * @param _addr `GaugeController` contract address
     * @param _weight New Gauge weight
     */ 
    function changeGaugeWeight(address _addr, uint256 _weight) external onlyOwner {
        _changeGaugeWeight(_addr, _weight);
    }



    /**
     * @notice Allocate voting power for changing pool weights
     * @param _gaugeAddr Gauge which `msg.sender` votes for
     * @param _userWeight Weight for a gauge in bps (units of 0.01%). Minimal is 0.01%. Ignored if 0
     */
     struct VoteGauge {
        uint256 oldDt;
        uint256 oldBias;
        uint256 newDt;
        uint256 newBias;
        uint256 oldWeightBias;
        uint256 oldWeightSlope;
        uint256 oldSumBias;
        uint256 oldSumSlope;
     }
    function voteForGaugeWeights(address _gaugeAddr, uint256 _userWeight) external {

        uint256 slope = IVotingEscrow(votingEscrow).getLastUserSlope(msg.sender).toUint256();
        uint256 lockEnd = IVotingEscrow(votingEscrow).locked__end(msg.sender);
        
        uint256 nextTime = (block.timestamp + WEEK) / WEEK * WEEK;
        require(lockEnd > nextTime, "GaugeController: Your token lock expires too soon");
        require (_userWeight >= 0 && _userWeight <= 10000, "GaugeController: You used all your voting power");
        require (block.timestamp >= lastUserVote[msg.sender][_gaugeAddr] + WEIGHT_VOTE_DELAY, "GaugeController: Cannot vote so often");

        uint256 gaugeType = gaugeTypes_[_gaugeAddr] - 1;
        require(gaugeType >= 0, "GaugeController: Gauge not added"); 
        // Prepare slopes and biases in memory
        VotedSlope memory oldSlope = voteUserSlopes[msg.sender][_gaugeAddr];
        
        VotedSlope memory newSlope;
        newSlope.slope = slope * _userWeight / 10000;
        newSlope.end = lockEnd;
        newSlope.power = _userWeight;
        
         uint256 powerUsed;
        {
            // Check and update powers (weights) used
            powerUsed = voteUserPower[msg.sender];
            powerUsed = powerUsed + newSlope.power - oldSlope.power;
            voteUserPower[msg.sender] = powerUsed;
            require(powerUsed >= 0 && powerUsed <= 10000, "GaugeController: Used too much power");
        }

        // Remove old and schedule new slope changes
        // Remove slope changes for old slopes
        // Schedule recording of initial slope for nextTime
        VoteGauge memory _voteGauge;

        _voteGauge.oldDt = 0;
        if (oldSlope.end > nextTime) {
            _voteGauge.oldDt = oldSlope.end - nextTime;
        }
        _voteGauge.oldBias = oldSlope.slope * _voteGauge.oldDt;

        _voteGauge.newDt = lockEnd - nextTime;  // dev: raises when expired
        _voteGauge.newBias = newSlope.slope * _voteGauge.newDt;

        _voteGauge.oldWeightBias = _getWeight(_gaugeAddr);
        _voteGauge.oldWeightSlope = pointsWeight[_gaugeAddr][nextTime].slope;
        _voteGauge.oldSumBias = _getSum(gaugeType);
        _voteGauge.oldSumSlope = pointsSum[gaugeType][nextTime].slope;

        pointsWeight[_gaugeAddr][nextTime].bias = (_voteGauge.oldWeightBias + _voteGauge.newBias).max(_voteGauge.oldBias) - _voteGauge.oldBias;
        pointsSum[gaugeType][nextTime].bias = (_voteGauge.oldSumBias + _voteGauge.newBias).max(_voteGauge.oldBias) - _voteGauge.oldBias;
        if (oldSlope.end > nextTime) {
            pointsWeight[_gaugeAddr][nextTime].slope = (_voteGauge.oldWeightSlope + newSlope.slope).max(oldSlope.slope) - oldSlope.slope;
            pointsSum[gaugeType][nextTime].slope = (_voteGauge.oldSumSlope + newSlope.slope).max(oldSlope.slope) - oldSlope.slope;
        }
        else {
            pointsWeight[_gaugeAddr][nextTime].slope  += newSlope.slope;
            pointsSum[gaugeType][nextTime].slope += newSlope.slope;
        }
        
        if (oldSlope.end > block.timestamp) {
            // Cancel old slope changes if they still didn't happen
            changesWeight[_gaugeAddr][oldSlope.end] -= oldSlope.slope;
            changesSum[gaugeType][oldSlope.end] -= oldSlope.slope;
        }
        // Add slope changes for new slopes
        changesWeight[_gaugeAddr][newSlope.end] += newSlope.slope;
        changesSum[gaugeType][newSlope.end] += newSlope.slope;

        _getTotal();

        voteUserSlopes[msg.sender][_gaugeAddr] = newSlope;

        // Record last action time
        lastUserVote[msg.sender][_gaugeAddr] = block.timestamp;

        emit VoteForGauge(block.timestamp, msg.sender, _gaugeAddr, _userWeight);

    }


    /**
     * @notice Get current gauge weight
     * @param _addr Gauge address
     * @return Gauge weight
     */
    function getGaugeWeight(address _addr) external view returns(uint256) {
        return pointsWeight[_addr][timeWeight[_addr]].bias;
    }


    /**
     * @notice Get current type weight
     * @param _typeId Type id
     * @return Type weight
     */
    function getTypeWeight(uint256 _typeId) external view returns(uint256) {
        return pointsTypeWeight[_typeId][timeTypeWeight[_typeId]];
    }

    
    /**
     * @notice Get current total (type-weighted) weight
     * @return Total weight
     */
    function getTotalWeight() external view returns (uint256) {
        return pointsTotal[timeTotal];
    }


    /**
     * @notice Get sum of gauge weights per type
     * @param _typeId Type id
     * @return Sum of gauge weights
     */
    function getWeightsSumPerType(uint256 _typeId) external view returns(uint256) {
        return pointsSum[_typeId][timeSum[_typeId]].bias;
    }

    function getGaugeList(uint256 _index, uint256 _offset) external view returns (address[] memory _addr) {
        require(_index < nGauges, "GaugeController: !_index");
        if(_index + _offset > nGauges) {
            _offset = nGauges - _index;
        }
        _addr = new address[](_offset);

        for (uint256 i = 0; i < _offset; i++) {
            _addr[i] = gauges[i + _index];
        }
    }

}































