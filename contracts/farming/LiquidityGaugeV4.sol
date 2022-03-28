// SPDX-License-Identifier: MIT
//@notice Controls liquidity gauges and the issuance of coins through the gauges
pragma solidity 0.8.6;

import "../OwnerPausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable-4.2.0/utils/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable-4.2.0/token/ERC20/extensions/ERC20BurnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable-4.2.0/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable-4.2.0/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable-4.2.0/utils/math/MathUpgradeable.sol";


import "../interfaces/IGaugeController.sol";
import "../interfaces/IMinter.sol";
import "../interfaces/IVotingEscrow.sol";
import "../interfaces/IERC20Extended.sol";
import "../interfaces/ISRS.sol";


contract LiquidityGauge is OwnerPausableUpgradeable, ERC20BurnableUpgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using MathUpgradeable for uint256;
    using SafeMathUpgradeable for uint256;
    
    event Deposit(address indexed provider, uint256 value);
    event Withdraw(address indexed provider, uint256 value);
    event UpdateLiquidityLimit(address user, uint256 originalBalance, uint256 originalSupply, uint256 workingBalance, uint256 workingSupply);

    struct Reward {
        address token;
        address distributor;
        uint256 periodFinish;
        uint256 rate;
        uint256 lastUpdate;
        uint256 integral;
    }

    
    uint256 public constant MAX_REWARDS = 8;
    uint256 public constant TOKENLESS_PRODUCTION = 40;
    uint256 public constant WEEK = 604800;
    uint256 public constant MULTIPLIER = 10 ** 18;

    //
    address public MINTER;
    address public SRS;
    address public VOTING_ESCROW;
    address public GAUGE_CONTROLLER;
    // address public constant VEBOOST_PROXY = 0x8E0c00ed546602fD9927DF742bbAbF726D5B0d16;

    
    address public lpToken;
    uint256 public futureEpochTime;

    mapping(address => uint256) public workingBalances;
    uint256 public workingSupply;

    // The goal is to be able to calculate ∫(rate * balance / totalSupply dt) from 0 till checkpoint
    // All values are kept in units of being multiplied by 1e18
    uint256 public period;
    uint256[100000000000000000000000000000] public periodTimestamp;

    // 1e18 * ∫(rate(t) / totalSupply(t) dt) from 0 till checkpoint
    uint256[100000000000000000000000000000] public integrateInvSupply;  // bump epoch when rate() changes

    // 1e18 * ∫(rate(t) / totalSupply(t) dt) from (last_action) till checkpoint
    mapping(address => uint256) public integrateInvSupplyOf;
    mapping(address => uint256) public integrateCheckpointOf;

    // ∫(balance * rate(t) / totalSupply(t) dt) from 0 till checkpoint
    // Units: rate * t = already number of coins per address to issue
    mapping(address => uint256) public integrateFraction;

    uint256 public inflationRate;

    // For tracking external rewards
    uint256 public rewardCount;
    address[MAX_REWARDS] public rewardTokens;

    mapping(address => Reward) public rewardData;

    // claimant -> default reward receiver
    mapping(address => address) public rewardsReceiver;

    // reward token -> claiming address -> integral
    mapping(address => mapping(address => uint256)) public rewardIntegralFor;

    // user -> [uint128 claimable amount][uint128 claimed amount]
    mapping(address => mapping(address => uint256)) public claimData;

    bool public isKilled;
    
    /**
     * @notice Contract constructor
     * @param _lpToken Liquidity Pool contract address
     */
    function __LiquidityGauge_init(address _lpToken, address _minter, address _srs, address _veToken, address _gaugeCtrl)
        external
        initializer
    {

        require(_lpToken != address(0), "LiquidityGauge: !lp");
        require(_minter != address(0), "LiquidityGauge: !minter");
        require(_srs != address(0), "LiquidityGauge: !srs");
        require(_veToken != address(0), "LiquidityGauge: !ve");
        require(_gaugeCtrl != address(0), "LiquidityGauge: !gaugeCtrl");

        lpToken = _lpToken;

        string memory symbol = IERC20Extended(_lpToken).symbol();
        __ERC20_init(string(abi.encodePacked("Sirius Finance ", symbol, " Gauge Deposit")), string(abi.encodePacked(symbol, "-gauge")));

        MINTER = _minter;
        SRS = _srs;
        VOTING_ESCROW = _veToken;
        GAUGE_CONTROLLER = _gaugeCtrl;

        periodTimestamp[0] = block.timestamp;
        inflationRate = ISRS(SRS).rate();
        futureEpochTime = ISRS(SRS).futureEpochTimeWrite();

    }

    function integrateCheckpoint() external view returns(uint256) {
        return periodTimestamp[period];
    }


    /**
     * @notice Calculate limits which depend on the amount of SRS token per-user.
            Effectively it calculates working balances to apply amplification
            of SRS production by SRS
     * @param _addr User address
     * @param _l User's amount of liquidity (LP tokens)
     * @param _L Total amount of liquidity (LP tokens)
     */
    function _updateLiquidityLimit(address _addr, uint256 _l, uint256 _L) internal {

        // To be called after totalSupply is updated
        // uint256 votingBalance = VotingEscrowBoost(VEBOOST_PROXY).adjustedBalanceOf(_addr);
        uint256 votingBalance = IERC20Upgradeable(VOTING_ESCROW).balanceOf(_addr);
        uint256 votingTotal = IERC20Upgradeable(VOTING_ESCROW).totalSupply();

        uint256 lim = _l * TOKENLESS_PRODUCTION / 100;
        if (votingTotal > 0) {
            lim += _L * votingBalance / votingTotal * (100 - TOKENLESS_PRODUCTION) / 100;
        }

        lim = _l.min(lim);
        uint256 oldBal = workingBalances[_addr];
        workingBalances[_addr] = lim;
        uint256 _workingSupply = workingSupply.add(lim).sub(oldBal);
        workingSupply = _workingSupply;

        emit UpdateLiquidityLimit(_addr, _l, _L, lim, workingSupply);
    }
    

    /**
     * @notice Claim pending rewards and checkpoint rewards for a user
     */
    struct CheckpointRewards {
        address _user;
        uint256 _totalSupply;
        bool _claim;
        address _receiver;
    }
    function _checkpointRewards(CheckpointRewards memory _para) internal {

        uint256 userBalance = 0;
        address receiver = _para._receiver;
        if (_para._user != address(0)) {
            userBalance = balanceOf(_para._user);
            if (_para._claim && _para._receiver == address(0)) {
                // if receiver is not explicitly declared, check if a default receiver is set
                receiver = rewardsReceiver[_para._user];
                if (receiver == address(0)) {
                    // if no default receiver is set, direct claims to the user
                    receiver = _para._user;
                }
            }
        }

        uint256 _rewardCount = rewardCount;
        for (uint256 i = 0; i < MAX_REWARDS; i++) {
            
            if (i == _rewardCount)
                break;
            address token = rewardTokens[i];

            uint256 integral = rewardData[token].integral;
            {
                uint256 lastUpdate = block.timestamp.min(rewardData[token].periodFinish);
                uint256 duration = lastUpdate.sub(rewardData[token].lastUpdate);
                if (duration != 0) {
                    rewardData[token].lastUpdate = lastUpdate;
                    if (_para._totalSupply != 0) {
                        integral = integral.add(duration.mul(rewardData[token].rate).mul(MULTIPLIER).div(_para._totalSupply));
                        rewardData[token].integral = integral;
                    }
                }
            }

            if (_para._user != address(0)) {
                {
                    uint256 integralFor = rewardIntegralFor[token][_para._user];
                    uint256 newClaimable = 0;

                    if (integralFor < integral) {
                        rewardIntegralFor[token][_para._user] = integral;
                        newClaimable = userBalance * (integral.sub(integralFor)).div(MULTIPLIER);
                    }
                    uint256 _claimData = claimData[_para._user][token];
                    uint256 totalClaimable = (_claimData >> 128).add(newClaimable);
                    if (totalClaimable > 0) {

                        uint256 totalClaimed = _claimData.mod(2 ** 128);
                        if (_para._claim) {
                            IERC20Upgradeable(token).safeTransfer(_para._receiver, totalClaimable);
                            claimData[_para._user][token] = totalClaimed + totalClaimable;
                        }
                        else if(newClaimable > 0) {
                            claimData[_para._user][token] = totalClaimed + (totalClaimable << 128);
                        }
                    }
                }
            }

        }
    }


    
    /**
     * @notice Checkpoint for a user
     * @param _addr User address
     */
    function _checkpoint(address _addr) internal {

        uint256 _period = period;
        uint256 _periodTime = periodTimestamp[_period];
        uint256 _integrateInvSupply = integrateInvSupply[_period];
        uint256 rate = inflationRate;
        uint256 newRate = rate;
        uint256 prevFutureEpoch = futureEpochTime;
        if (prevFutureEpoch >= _periodTime) {
            futureEpochTime = ISRS(SRS).futureEpochTimeWrite();
            newRate = ISRS(SRS).rate();
            inflationRate = newRate;
        }

        if (isKilled){
            // Stop distributing inflation as soon as killed
            rate = 0;
        }

        // Update integral of 1/supply
        if (block.timestamp > _periodTime) {

            uint256 _workingSupply = workingSupply;
            IGaugeController(GAUGE_CONTROLLER).checkpointGauge(address(this));
            uint256 prevWeekTime = _periodTime;
            uint256 weekTime = ((_periodTime + WEEK) / WEEK * WEEK).min(block.timestamp);

            for (uint256 i; i < 500; i++) {

                uint256 dt = weekTime.sub(prevWeekTime);
                uint256 w = IGaugeController(GAUGE_CONTROLLER).gaugeRelativeWeight(address(this), prevWeekTime / WEEK * WEEK);

                if (_workingSupply > 0) {
                    if (prevFutureEpoch >= prevWeekTime && prevFutureEpoch < weekTime) {
                        // If we went across one or multiple epochs, apply the rate
                        // of the first epoch until it ends, and then the rate of
                        // the last epoch.
                        // If more than one epoch is crossed - the gauge gets less,
                        // but that'd meen it wasn't called for more than 1 year
                        _integrateInvSupply += rate * w * (prevFutureEpoch - prevWeekTime) / _workingSupply;
                        //rate * w * (prev_future_epoch - prev_week_time) / _working_supply
                        rate = newRate;
                        _integrateInvSupply += rate * w * (weekTime - prevFutureEpoch) / _workingSupply;
                        //rate * w * (week_time - prev_future_epoch) / _working_supply
                    }
                    else {
                        _integrateInvSupply += rate * w * dt / _workingSupply;
                    }
                    // On precisions of the calculation
                    // rate ~= 10e18
                    // last_weight > 0.01 * 1e18 = 1e16 (if pool weight is 1%)
                    // _workingSupply ~= TVL * 1e18 ~= 1e26 ($100M for example)
                    // The largest loss is at dt = 1
                    // Loss is 1e-9 - acceptable
                }

                if (weekTime == block.timestamp) {
                    break;
                }
                prevWeekTime = weekTime;
                weekTime = (weekTime + WEEK).min(block.timestamp);
            }

        }

        _period += 1;
        period = _period;
        periodTimestamp[_period] = block.timestamp;
        integrateInvSupply[_period] = _integrateInvSupply;

        // Update user-specific integrals
        uint256 _workingBalance = workingBalances[_addr];
        integrateFraction[_addr] += _workingBalance * (_integrateInvSupply - integrateInvSupplyOf[_addr]) / MULTIPLIER;
        integrateInvSupplyOf[_addr] = _integrateInvSupply;
        integrateCheckpointOf[_addr] = block.timestamp;

    }


    /**
     * @notice Record a checkpoint for `addr`
     * @param _addr User address
     * @return bool success
     */
    function userCheckpoint(address _addr) external returns(bool) {
        require(msg.sender == _addr || msg.sender == MINTER, "LiquidityGauge: !unauthorized");  // dev: unauthorized
        _checkpoint(_addr);
        _updateLiquidityLimit(_addr, balanceOf(_addr), totalSupply());
        return true;
    }


    /**
     * @notice Get the number of claimable tokens per user
     * @dev This function should be manually changed to "view" in the ABI
     * @return uint256 number of claimable tokens per user
     */
    function claimableTokens(address _addr) external returns(uint256) {
        _checkpoint(_addr);
        return integrateFraction[_addr] - IMinter(MINTER).minted(_addr, address(this));
    }


    /**
     * @notice Get the number of already-claimed reward tokens for a user
     * @param _addr Account to get reward amount for
     * @param _token Token to get reward amount for
     * @return uint256 Total amount of `_token` already claimed by `_addr`
     */
    function claimedReward(address _addr, address _token) external view returns(uint256) {
        return claimData[_addr][_token].mod(2**128);
    }


    
    /**
     * @notice Get the number of claimable reward tokens for a user
     * @param _user Account to get reward amount for
     * @param _rewardToken Token to get reward amount for
     * @return uint256 Claimable reward token amount
     */
    function claimableReward(address _user, address _rewardToken) external view returns(uint256) {
        uint256 integral = rewardData[_rewardToken].integral;
        uint256 totalSupply = totalSupply();
        if (totalSupply != 0) {
            uint256 lastUpdate = block.timestamp.min(rewardData[_rewardToken].periodFinish);
            uint256 duration = lastUpdate.sub(rewardData[_rewardToken].lastUpdate);
            integral = integral.add(duration.mul(rewardData[_rewardToken].rate).mul(MULTIPLIER).div(totalSupply));
        }

        uint256 integralFor = rewardIntegralFor[_rewardToken][_user];
        uint256 newClaimable = balanceOf(_user).mul(integral.sub(integralFor)).div(MULTIPLIER);

        return (claimData[_user][_rewardToken] >> 128).add(newClaimable);
    }


    
    /**
     * @notice Set the default reward receiver for the caller.
     * @dev When set to ZERO_ADDRESS, rewards are sent to the caller
     * @param _receiver Receiver address for any rewards claimed via `claim_rewards`
     */
    function setRewardsReceiver(address _receiver) external {
        rewardsReceiver[msg.sender] = _receiver;
    }



    
    /**
     * @notice Claim available reward tokens for `_addr`
     * @param _addr Address to claim for
     * @param _receiver Address to transfer rewards to - if set to
                     ZERO_ADDRESS, uses the default reward receiver
                     for the caller
     */
    function claimRewards(address _addr, address _receiver) external nonReentrant {
        
        if (_receiver != address(0)) {
            require(_addr == msg.sender, "LiquidityGauge: !addr");   // dev: cannot redirect when claiming for another user
        }
        
        CheckpointRewards memory param;
        param._user = _addr;
        param._totalSupply = totalSupply();
        param._claim = true;
        param._receiver = _receiver;
        _checkpointRewards(param);

    }


    /**
     * @notice Kick `addr` for abusing their boost
     * @dev Only if either they had another voting event, or their voting escrow lock expired
     * @param _addr Address to kick
     */
    function kick(address _addr) external {
        
        uint256 tLast = integrateCheckpointOf[_addr];
        uint256 tVe = IVotingEscrow(VOTING_ESCROW).userPointHistory__ts(
            _addr, IVotingEscrow(VOTING_ESCROW).userPointEpoch(_addr)
        );
        uint256 _balance = balanceOf(_addr);

        require(IERC20Upgradeable(VOTING_ESCROW).balanceOf(_addr) == 0 || tVe > tLast, "LiquidityGauge: !allowed");  // dev: kick not allowed
        require(workingBalances[_addr] > _balance * TOKENLESS_PRODUCTION / 100, "LiquidityGauge: !needed");   // dev: kick not needed

        _checkpoint(_addr);
        _updateLiquidityLimit(_addr, balanceOf(_addr), totalSupply());

    }


    
    /**
     * @notice Deposit `_value` LP tokens
     * @dev Depositting also claims pending reward tokens
     * @param _value Number of tokens to deposit
     * @param _addr Address to deposit for
     */
    function deposit(uint256 _value, address _addr, bool _claimRewards) external nonReentrant {

        _checkpoint(_addr);

        if (_value != 0) {
            bool isRewards = rewardCount != 0;
            uint256 totalSupply = totalSupply();
            if (isRewards) {
                CheckpointRewards memory param;
                param._user = _addr;
                param._totalSupply = totalSupply;
                param._claim = _claimRewards;
                param._receiver = address(0);
                _checkpointRewards(param);
            }

            _mint(_addr, _value);
            uint256 newBalance = balanceOf(_addr);
            _updateLiquidityLimit(_addr, newBalance, totalSupply);

            IERC20Upgradeable(lpToken).safeTransferFrom(msg.sender, address(this), _value);
        }

        emit Deposit(_addr, _value);
    }

    

    /**
     * @notice Withdraw `_value` LP tokens
     * @dev Withdrawing also claims pending reward tokens
     * @param _value Number of tokens to withdraw
     */
    function withdraw(uint256 _value, bool _claimRewards) external nonReentrant {
        _checkpoint(msg.sender);
        if (_value != 0) {
            bool isRewards = rewardCount != 0;
            uint256 totalSupply = totalSupply();
            if (isRewards) {
                CheckpointRewards memory param;
                param._user = msg.sender;
                param._totalSupply = totalSupply;
                param._claim = _claimRewards;
                param._receiver = address(0);
                _checkpointRewards(param);
            }

            _burn(msg.sender, _value);
            uint256 newBalance = balanceOf(msg.sender);
            _updateLiquidityLimit(msg.sender, newBalance, totalSupply);

            IERC20Upgradeable(lpToken).transfer(msg.sender, _value);
        }

        emit Withdraw(msg.sender, _value);
    }



    function _transfer2(address _from, address _to, uint256 _value) internal {

        _checkpoint(_from);
        _checkpoint(_to);

        if (_value != 0) {
            uint256 _totalSupply = totalSupply();
            bool isRewards = rewardCount != 0;
            if (isRewards) {
                CheckpointRewards memory param;
                param._user = _from;
                param._totalSupply = _totalSupply;
                param._claim = false;
                param._receiver = address(0);
                _checkpointRewards(param);
            }
            
            uint256 newBalance = balanceOf(_from).sub(_value);
            // self.balanceOf[_from] = new_balance
            _updateLiquidityLimit(_from, newBalance, _totalSupply);

            if (isRewards) {
                CheckpointRewards memory param2;
                param2._user = _to;
                param2._totalSupply = _totalSupply;
                param2._claim = false;
                param2._receiver = address(0);
                _checkpointRewards(param2);
            }
            newBalance = balanceOf(_to).add(_value);
            // self.balanceOf[_to] = new_balance
            _updateLiquidityLimit(_to, newBalance, _totalSupply);
            _transfer(_from, _to, _value);

        }
        
    }



    /**
     * @notice Transfer token for a specified address
     * @dev Transferring claims pending reward tokens for the sender and receiver
     * @param _to The address to transfer to.
     * @param _value The amount to be transferred.
     */
    function transfer(address _to, uint256 _value) public nonReentrant override returns(bool) {
        _transfer2(msg.sender, _to, _value);
        return true;
    }


    
    /**
     * @notice Set the active reward contract
     */
    function addReward(address _rewardToken, address _distributor) external onlyOwner {

        uint256 _rewardCount = rewardCount;
        require(_rewardCount < MAX_REWARDS, "LiquidityGauge: !rewardCount"); 
        require(rewardData[_rewardToken].distributor == address(0), "LiquidityGauge: !distributor" );

        rewardData[_rewardToken].distributor = _distributor;
        rewardTokens[_rewardCount] = _rewardToken;
        rewardCount = _rewardCount + 1;

    }



    /**
     * 
     */
    function setRewardDistributor(address _rewardToken, address _distributor) external {
        address currentDistributor = rewardData[_rewardToken].distributor;

        require(msg.sender == currentDistributor || msg.sender == owner(), "LiquidityGauge: !auth");
        require(currentDistributor != address(0), "LiquidityGauge: !current"); 
        require(_distributor != address(0), "LiquidityGauge: !distributor"); 

        rewardData[_rewardToken].distributor = _distributor;
    }


    
    function depositRewardToken(address _rewardToken, uint256 _amount) external nonReentrant {
        require(msg.sender == rewardData[_rewardToken].distributor, "idityGauge: !auth"); 

        CheckpointRewards memory param;
        param._user = address(0);
        param._totalSupply = totalSupply();
        param._claim = false;
        param._receiver = address(0);
        _checkpointRewards(param);
        IERC20Upgradeable(_rewardToken).safeTransferFrom(msg.sender, address(this), _amount);

        uint256 periodFinish = rewardData[_rewardToken].periodFinish;
        if (block.timestamp >= periodFinish) {
            rewardData[_rewardToken].rate = _amount / WEEK;
        }
        else {
            uint256 remaining = periodFinish - block.timestamp;
            uint256 leftover = remaining * rewardData[_rewardToken].rate;
            rewardData[_rewardToken].rate = (_amount + leftover) / WEEK;
        }

        rewardData[_rewardToken].lastUpdate = block.timestamp;
        rewardData[_rewardToken].periodFinish = block.timestamp.add(WEEK);

    }



    /**
     * @notice Set the killed status for this contract
     * @dev When killed, the gauge always yields a rate of 0 and so cannot mint CRV
     * @param _isKilled Killed status to set
     */
    function setKilled(bool _isKilled) external onlyOwner { 
        isKilled = _isKilled;
    }
    



}