// SPDX-License-Identifier: MIT
pragma solidity 0.8.6;

import "@openzeppelin/contracts-upgradeable-4.2.0/token/ERC20/extensions/ERC20BurnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable-4.2.0/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "./interfaces/IERC20Extended.sol";
import "./libraries/Integers.sol";
import "./OwnerPausableUpgradeable.sol";


/**
 * @title Voting Escrow
 * @notice Votes have a weight depending on time, so that users are
 *         committed to the future of (whatever they are voting for)
 * @dev Vote weight decays linearly over time. Lock time cannot be
 *      more than `MAXTIME` (3 years).
 * @dev Ported from vyper (https://github.com/curvefi/curve-dao-contracts/blob/master/contracts/VotingEscrow.vy)
 */

// Voting escrow to have time-weighted votes
// Votes have a weight depending on time, so that users are committed
// to the future of (whatever they are voting for).
// The weight in this implementation is linear, and lock cannot be more than maxtime:
// w ^
// 1 +        /
//   |      /
//   |    /
//   |  /
//   |/
// 0 +--------+------> time
//       maxtime (3 years)

contract VotingEscrow is OwnerPausableUpgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using Integers for uint256;
    using Integers for int128;

    struct Point {
        int128 bias;
        int128 slope; // - dweight / dt
        uint256 ts;
        uint256 blk; // block
    }

    struct LockedBalance {
        int128 amount;
        uint256 end;
    }

    int128 public constant DEPOSIT_FOR_TYPE = 0;
    int128 public constant CRETE_LOCK_TYPE = 1;
    int128 public constant INCREASE_LOCK_AMOUNT = 2;
    int128 public constant INCREASE_UNLOCK_TIME = 3;

    uint256 public constant WEEK = 7 days;
    uint256 public constant MAXTIME = 3 * 365 days;
    uint256 public constant MULTIPLIER = 10**18;
    uint256 public constant MAX_WITHDRAWAL_PENALTY = 50 * 10 ** 16; // 50%

    address public token;
    uint256 public supply;
    mapping(address => LockedBalance) public locked;
    uint256 public epoch;

    mapping(uint256 => Point) public pointHistory; // epoch -> unsigned point
    mapping(address => mapping(uint256 => Point)) public userPointHistory; // user -> Point[user_epoch]
    mapping(address => uint256) public userPointEpoch;
    mapping(uint256 => int128) public slopeChanges; // time -> signed slope change

    string public name;
    string public symbol;
    uint8 public decimals;

    // Checker for whitelisted (smart contract) wallets which are allowed to deposit
    // The goal is to prevent tokenizing the escrow
    address public futureSmartWalletChecker;
    address public smartWalletChecker;

    address public penaltyCollector;
    uint256 public earlyWithdrawPenaltyRate;

    event Deposit(address indexed provider, uint256 value, uint256 indexed locktime, int128 _type, uint256 ts);
    event Withdraw(address indexed provider, uint256 value, uint256 ts);
    event Supply(uint256 prevSupply, uint256 supply);

    function __VotingEscrow_init(
        address tokenAddr,
        string memory _name,
        string memory _symbol
    ) public virtual initializer {
        
        __OwnerPausable_init();

        token = tokenAddr;

        pointHistory[0].blk = block.number;
        pointHistory[0].ts = block.timestamp;

        name = _name;
        symbol = _symbol;
        decimals = IERC20Extended(tokenAddr).decimals();
        earlyWithdrawPenaltyRate = 30 * 10 ** 16; // 30%

    }


    /**
     * @notice Get the most recently recorded rate of voting power decrease for `addr`
     * @param _addr Address of the user wallet
     * @return Value of the slope
     */
    function getLastUserSlope(address _addr) external view returns (int128) {
        uint256 uepoch = userPointEpoch[_addr];
        return userPointHistory[_addr][uepoch].slope;
    }

    /**
     * @notice Get the timestamp for checkpoint `_idx` for `_addr`
     * @param _addr User wallet address
     * @param _idx User epoch number
     * @return Epoch time of the checkpoint
     */
    function userPointHistory__ts(address _addr, uint256 _idx) external view returns (uint256) {
        return userPointHistory[_addr][_idx].ts;
    }

    /**
     * @notice Get timestamp when `_addr`'s lock finishes
     * @param _addr User wallet
     * @return Epoch time of the lock end
     */
    function locked__end(address _addr) external view returns (uint256) {
        return locked[_addr].end;
    }

    /**
     * @notice Record global and per-user data to checkpoint
     * @param _addr User's wallet address. No user checkpoint if 0x0
     * @param _oldLocked Pevious locked amount / end lock time for the user
     * @param _newLocked New locked amount / end lock time for the user
     */
    function _checkpoint(
        address _addr,
        LockedBalance memory _oldLocked,
        LockedBalance memory _newLocked
    ) internal {
        Point memory uOld;
        Point memory uNew;
        int128 oldDslope;
        int128 newDslope;
        uint256 _epoch = epoch;

        if (_addr != address(0)) {
            // Calculate slopes and biases
            // Kept at zero when they have to
            if (_oldLocked.end > block.timestamp && _oldLocked.amount > 0) {
                uOld.slope = _oldLocked.amount / MAXTIME.toInt128();
                uOld.bias = uOld.slope * (_oldLocked.end - block.timestamp).toInt128();
            }
            if (_newLocked.end > block.timestamp && _newLocked.amount > 0) {
                uNew.slope = _newLocked.amount / MAXTIME.toInt128();
                uNew.bias = uNew.slope * (_newLocked.end - block.timestamp).toInt128();
            }

            // Read values of scheduled changes in the slope
            // _oldLocked.end can be in the past and in the future
            // _newLocked.end can ONLY by in the FUTURE unless everything expired: than zeros
            oldDslope = slopeChanges[_oldLocked.end];
            if (_newLocked.end != 0) {
                if (_newLocked.end == _oldLocked.end) newDslope = oldDslope;
                else newDslope = slopeChanges[_newLocked.end];
            }
        }

        Point memory lastPoint = Point({bias: 0, slope: 0, ts: block.timestamp, blk: block.number});
        if (_epoch > 0) lastPoint = pointHistory[_epoch];
        uint256 lastCheckpoint = lastPoint.ts;
        // initialLastPoint is used for extrapolation to calculate block number
        // (approximately, for *At methods) and save them
        // as we cannot figure that out exactly from inside the contract
        Point memory initialLastPoint = lastPoint;
        uint256 blockSlope; // dblock/dt
        if (block.timestamp > lastPoint.ts)
            blockSlope = (MULTIPLIER * (block.number - lastPoint.blk)) / (block.timestamp - lastPoint.ts);
        // If last point is already recorded in this block, slope=0
        // But that's ok b/c we know the block in such case

        {
            // Go over weeks to fill history and calculate what the current point is
            uint256 ti = lastCheckpoint / WEEK * WEEK;
            for (uint256 i; i < 255; i++) {
                // Hopefully it won't happen that this won't get used in 5 years!
                // If it does, users will be able to withdraw but vote weight will be broken
                ti += WEEK;
                int128 dSlope;
                if (ti > block.timestamp) ti = block.timestamp;
                else dSlope = slopeChanges[ti];
                lastPoint.bias =  lastPoint.bias - (lastPoint.slope * (ti - lastCheckpoint).toInt128());
                lastPoint.slope = lastPoint.slope + dSlope;
                if (lastPoint.bias < 0)
                    // This can happen
                    lastPoint.bias = 0;
                if (lastPoint.slope < 0)
                    // This cannot happen - just in case
                    lastPoint.slope = 0;
                lastCheckpoint = ti;
                lastPoint.ts = ti;
                lastPoint.blk = initialLastPoint.blk + (blockSlope * (ti - initialLastPoint.ts)) / MULTIPLIER;
                _epoch += 1;
                if (ti == block.timestamp) {
                    lastPoint.blk = block.number;
                    break;
                } else pointHistory[_epoch] = lastPoint;
            }
        }

        epoch = _epoch;
        // Now pointHistory is filled until t=now

        if (_addr != address(0)) {
            // If last point was in this block, the slope change has been applied already
            // But in such case we have 0 slope(s)
            lastPoint.slope += (uNew.slope - uOld.slope);
            lastPoint.bias += (uNew.bias - uOld.bias);
            if (lastPoint.slope < 0) lastPoint.slope = 0;
            if (lastPoint.bias < 0) lastPoint.bias = 0;
        }

        // Record the changed point into history
        pointHistory[_epoch] = lastPoint;

        if (_addr != address(0)) {
            // Schedule the slope changes (slope is going down)
            // We subtract new_user_slope from [_newLocked.end]
            // and add old_user_slope to [_oldLocked.end]
            if (_oldLocked.end > block.timestamp) {
                // oldDslope was <something> - uOld.slope, so we cancel that
                oldDslope += uOld.slope;
                if (_newLocked.end == _oldLocked.end) oldDslope -= uNew.slope; // It was a new deposit, not extension
                slopeChanges[_oldLocked.end] = oldDslope;
            }

            if (_newLocked.end > block.timestamp) {
                if (_newLocked.end > _oldLocked.end) {
                    newDslope -= uNew.slope; // old slope disappeared at this point
                    slopeChanges[_newLocked.end] = newDslope;
                }
                // else: we recorded it already in oldDslope
            }

            // Now handle user history
            uint256 userEpoch = userPointEpoch[_addr] + 1;

            userPointEpoch[_addr] = userEpoch;
            uNew.ts = block.timestamp;
            uNew.blk = block.number;
            userPointHistory[_addr][userEpoch] = uNew;
        }
    }

    /**
     * @notice Deposit and lock tokens for a user
     * @param _addr User's wallet address
     * @param _value Amount to deposit
     * @param _unlockTime New time when to unlock the tokens, or 0 if unchanged
     * @param _locked Previous locked amount / timestamp
     */
    function _depositFor(
        address _addr,
        uint256 _value,
        uint256 _unlockTime,
        LockedBalance memory _locked,
        int128 _type
    ) internal {
        uint256 supplyBefore = supply;

        supply = supplyBefore + _value;
        LockedBalance memory oldlocked = _locked;
        // Adding to existing lock, or if a lock is expired - creating a new one
        _locked.amount += _value.toInt128();
        if (_unlockTime != 0) _locked.end = _unlockTime;
        locked[_addr] = _locked;

        // Possibilities:
        // Both oldlocked.end could be current or expired (>/< block.timestamp)
        // value == 0 (extend lock) or value > 0 (add to lock or extend lock)
        // _locked.end > block.timestamp (always)
        _checkpoint(_addr, oldlocked, _locked);

        if (_value != 0) IERC20Upgradeable(token).safeTransferFrom(_addr, address(this), _value);

        emit Deposit(_addr, _value, _locked.end, _type, block.timestamp);
        emit Supply(supplyBefore, supply);
    }

    /**
     * @notice Record global data to checkpoint
     */
    function checkpoint() external {
        _checkpoint(address(0), LockedBalance(0, 0), LockedBalance(0, 0));
    }

    /**
     * @notice Deposit `_value` tokens for `_addr` and add to the lock
     * @dev Anyone (even a smart contract) can deposit for someone else, but
     *      cannot extend their locktime and deposit for a brand new user
     * @param _addr User's wallet address
     * @param _value Amount to add to user's lock
     */
    function depositFor(address _addr, uint256 _value) external nonReentrant {
        LockedBalance memory _locked = locked[_addr];

        require(_value > 0); // dev: need non-zero value
        require(_locked.amount > 0, "No existing lock found");
        require(_locked.end > block.timestamp, "Cannot add to expired lock. Withdraw");

        _depositFor(_addr, _value, 0, _locked, DEPOSIT_FOR_TYPE);
    }

    /**
     * @notice Deposit `_value` tokens for `msg.sender` and lock until `_unlockTime`
     * @param _value Amount to deposit
     * @param _unlockTime Epoch time when tokens unlock, rounded down to whole weeks
     */
    function createLock(uint256 _value, uint256 _unlockTime) external nonReentrant  {
        // assert_not_contract(msg.sender);
        uint256 unlockTime = _unlockTime / WEEK * WEEK; // Locktime is rounded down to weeks
        LockedBalance memory _locked = locked[msg.sender];

        require(_value > 0); // dev: need non-zero value
        require(_locked.amount == 0, "Withdraw old tokens first");
        require(unlockTime > block.timestamp, "Can only lock until time in the future");
        require(unlockTime <= block.timestamp + MAXTIME, "Voting lock can be 3 years max");

        _depositFor(msg.sender, _value, unlockTime, _locked, CRETE_LOCK_TYPE);
    }

    /**
     * @notice Deposit `_value` additional tokens for `msg.sender`
     *          without modifying the unlock time
     * @param _value Amount of tokens to deposit and add to the lock
     */
    function increaseAmount(uint256 _value) external nonReentrant {
        // assert_not_contract(msg.sender);
        LockedBalance memory _locked = locked[msg.sender];

        require(_value > 0); // dev: need non-zero value
        require(_locked.amount > 0, "No existing lock found");
        require(_locked.end > block.timestamp, "Cannot add to expired lock. Withdraw");

        _depositFor(msg.sender, _value, 0, _locked, INCREASE_LOCK_AMOUNT);
    }

    /**
     * @notice Extend the unlock time for `msg.sender` to `_unlockTime`
     * @param _unlockTime New epoch time for unlocking
     */
    function increaseUnlockTime(uint256 _unlockTime) external nonReentrant {
        // assert_not_contract(msg.sender);
        LockedBalance memory _locked = locked[msg.sender];
        uint256 unlockTime = _unlockTime / WEEK * WEEK; // Locktime is rounded down to weeks

        require(_locked.end > block.timestamp, "Lock expired");
        require(_locked.amount > 0, "Nothing is locked");
        require(unlockTime > _locked.end, "Can only increase lock duration");
        require(unlockTime <= block.timestamp + MAXTIME, "Voting lock can be 3 years max");

        _depositFor(msg.sender, 0, unlockTime, _locked, INCREASE_UNLOCK_TIME);
    }

    /**
     * @notice Withdraw all tokens for `msg.sender`
     * @dev Only possible if the lock has expired
     */
    function withdraw() external nonReentrant {
        LockedBalance memory _locked = locked[msg.sender];
        require(block.timestamp >= _locked.end, "The lock didn't expire");
        uint256 value = _locked.amount.toUint256();

        locked[msg.sender] = LockedBalance(0, 0);
        uint256 supplyBefore = supply;
        supply = supplyBefore - value;

        // old_locked can have either expired <= timestamp or zero end
        // _locked has only 0 end
        // Both can have >= 0 amount
        _checkpoint(msg.sender, _locked, LockedBalance(0, 0));

        IERC20Upgradeable(token).safeTransfer(msg.sender, value);

        emit Withdraw(msg.sender, value, block.timestamp);
        emit Supply(supplyBefore, supply);
    }

    // The following ERC20/minime-compatible methods are not real balanceOf and supply!
    // They measure the weights for the purpose of voting, so they don't represent
    // real coins.

    /**
     * @notice Binary search to estimate timestamp for block number
     * @param _block Block to find
     * @param maxEpoch Don't go beyond this epoch
     * @return Approximate timestamp for block
     */
    function findBlockEpoch(uint256 _block, uint256 maxEpoch) internal view returns (uint256) {
        uint256 _min;
        uint256 _max = maxEpoch;
        for (uint256 i; i < 128; i++) {
            if (_min >= _max) break;
            uint256 _mid = (_min + _max + 1) / 2;
            if (pointHistory[_mid].blk <= _block) _min = _mid;
            else _max = _mid - 1;
        }
        return _min;
    }

    function balanceOf(address _addr) public view returns (uint256) {
        return balanceOf(_addr, block.timestamp);
    }

    /**
     * @notice Get the current voting power for `msg.sender`
     * @dev Adheres to the ERC20 `balanceOf` interface for Aragon compatibility
     * @param _addr User wallet address
     * @param _t Epoch time to return voting power at
     * @return User voting power
     */
    function balanceOf(address _addr, uint256 _t) public view returns (uint256) {
        uint256 _epoch = userPointEpoch[_addr];
        if (_epoch == 0) return 0;
        else {
            Point memory lastPoint = userPointHistory[_addr][_epoch];
            lastPoint.bias -= lastPoint.slope * (_t - lastPoint.ts).toInt128();
            if (lastPoint.bias < 0) lastPoint.bias = 0;
            return lastPoint.bias.toUint256();
        }
    }

    /**
     * @notice Measure voting power of `addr` at block height `_block`
     * @dev Adheres to MiniMe `balanceOfAt` interface: https://github.com/Giveth/minime
     * @param _addr User's wallet address
     * @param _block Block to calculate the voting power at
     * @return Voting power
     */
    function balanceOfAt(address _addr, uint256 _block) external view returns (uint256) {
        // Copying and pasting totalSupply code because Vyper cannot pass by
        // reference yet
        require(_block <= block.number);

        // Binary search
        uint256 _min;
        uint256 _max = userPointEpoch[_addr];
        for (uint256 i; i < 128; i++) {
            if (_min >= _max) break;
            uint256 _mid = (_min + _max + 1) / 2;
            if (userPointHistory[_addr][_mid].blk <= _block) _min = _mid;
            else _max = _mid - 1;
        }

        Point memory upoint = userPointHistory[_addr][_min];

        uint256 maxEpoch = epoch;
        uint256 _epoch = findBlockEpoch(_block, maxEpoch);
        Point memory point0 = pointHistory[_epoch];
        uint256 dBlock;
        uint256 dT;
        if (_epoch < maxEpoch) {
            Point memory point1 = pointHistory[_epoch + 1];
            dBlock = point1.blk - point0.blk;
            dT = point1.ts - point0.ts;
        } else {
            dBlock = block.number - point0.blk;
            dT = block.timestamp - point0.ts;
        }
        uint256 blockTime = point0.ts;
        if (dBlock != 0) blockTime += (dT * (_block - point0.blk)) / dBlock;

        upoint.bias -= upoint.slope * (blockTime - upoint.ts).toInt128();
        if (upoint.bias >= 0) return upoint.bias.toUint256();
        else return 0;
    }

    /**
     * @notice Calculate total voting power at some point in the past
     * @param _point The point (bias/slope) to start search from
     * @param _t Time to calculate the total voting power at
     * @return Total voting power at that time
     */
    function supplyAt(Point memory _point, uint256 _t) internal view returns (uint256) {
        Point memory lastPoint = _point;
        uint256 ti = lastPoint.ts / WEEK * WEEK;
        for (uint256 i; i < 255; i++) {
            ti += WEEK;
            int128 dSlope;
            if (ti > _t) ti = _t;
            else dSlope = slopeChanges[ti];
            lastPoint.bias -= lastPoint.slope * (ti - lastPoint.ts).toInt128();
            if (ti == _t) break;
            lastPoint.slope += dSlope;
            lastPoint.ts = ti;
        }

        if (lastPoint.bias < 0) lastPoint.bias = 0;
        return lastPoint.bias.toUint256();
    }

    function totalSupply() public view returns (uint256) {
        return totalSupply(block.timestamp);
    }

    /**
     * @notice Calculate total voting power
     * @dev Adheres to the ERC20 `totalSupply` interface for Aragon compatibility
     * @return Total voting power
     */
    function totalSupply(uint256 _t) public view returns (uint256) {
        uint256 _epoch = epoch;
        Point memory lastPoint = pointHistory[_epoch];
        return supplyAt(lastPoint, _t);
    }

    /**
     * @notice Calculate total voting power at some point in the past
     * @param _block Block to calculate the total voting power at
     * @return Total voting power at `_block`
     */
    function totalSupplyAt(uint256 _block) external view returns (uint256) {
        require(_block < block.number);
        uint256 _epoch = epoch;
        uint256 targetEpoch = findBlockEpoch(_block, _epoch);

        Point memory point = pointHistory[targetEpoch];
        uint256 dt;
        if (targetEpoch < _epoch) {
            Point memory pointNext = pointHistory[targetEpoch + 1];
            if (point.blk != pointNext.blk)
                dt = ((_block - point.blk) * (pointNext.ts - point.ts)) / (pointNext.blk - point.blk);
        } else if (point.blk != block.number)
            dt = ((_block - point.blk) * (block.timestamp - point.ts)) / (block.number - point.blk);
        // Now dt contains info on how far are we beyond point

        return supplyAt(point, point.ts + dt);
    }

    // This will charge PENALTY if lock is not expired yet
    function emergencyWithdraw() external nonReentrant {
        LockedBalance memory _locked = locked[msg.sender];
        uint256 value = _locked.amount.toUint256();

        require(_locked.amount > 0, "Nothing to withdraw");

        locked[msg.sender] = LockedBalance(0, 0);
        uint256 supplyBefore = supply;
        supply = supplyBefore - value;

        // old_locked can have either expired <= timestamp or zero end
        // _locked has only 0 end
        // Both can have >= 0 amount
        _checkpoint(msg.sender, _locked, LockedBalance(0, 0));
        
        if(block.timestamp < _locked.end) {
            uint256 _fee = value * earlyWithdrawPenaltyRate / MULTIPLIER;
            _penalize(_fee);
            value -= _fee;
        }
        IERC20Upgradeable(token).safeTransfer(msg.sender, value);

        emit Withdraw(msg.sender, value, block.timestamp);
        emit Supply(supplyBefore, supply);
    }

    function _penalize(uint256 _amount) internal {
        if (penaltyCollector != address(0)) {
            // send to collector if `penaltyCollector` set
            IERC20Upgradeable(token).safeTransfer(penaltyCollector, _amount);
        } else {
            ERC20BurnableUpgradeable(token).burn(_amount);
        }
    }

    function setPenaltyCollector(address _addr) external onlyOwner {
        penaltyCollector = _addr;
    }

    function setEarlyWithdrawPenaltyRate(uint256 _rate) external onlyOwner {
        require(_rate <= MAX_WITHDRAWAL_PENALTY, "VotingEscrow: !rate"); // <= 50%
        earlyWithdrawPenaltyRate = _rate;
    }
}