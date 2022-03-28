// SPDX-License-Identifier: MIT

pragma solidity 0.8.6;

import "@openzeppelin/contracts-4.2.0/security/Pausable.sol";
import "@openzeppelin/contracts-4.2.0/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-4.2.0/proxy/Clones.sol";
import "@openzeppelin/contracts-4.2.0/token/ERC20/extensions/ERC20VotesComp.sol";
import "./Vesting.sol";
import "./SimpleGovernance.sol";

/**
 * @title Sirius Finance token
 * @notice A token that is deployed with fixed amount and appropriate vesting contracts.
 * Transfer is blocked for a period of time until the governance can toggle the transferability.
 */
contract SRS is ERC20Permit, Pausable, SimpleGovernance {
    using SafeERC20 for IERC20;

    // Token max supply is 1,000,000,000 * 1e18 = 1e27
    uint256 public immutable govCanUnpauseAfter;
    uint256 public immutable anyoneCanUnpauseAfter;
    address public immutable vestingContractTarget;

    //Supply parameters 
    uint256 public constant YEAR = 86400 * 365;
    uint256 public constant RATE_REDUCTION_TIME = YEAR;
    uint256 public constant INITIAL_SUPPLY = 570000000 ether;
    uint256 public constant INITIAL_RATE = 60000000 ether / YEAR;      //first year
    uint256 public constant RATE_REDUCTION_COEFFICIENT = 1150000000000000000;
    uint256 public constant RATE_DENOMINATOR = 10 ** 18;
    uint256 public constant INFLATION_DELAY = 0;//86400;

    //Supply variables
    uint256 public miningEpoch;
    uint256 public startEpochTime;
    uint256 public rate;

    uint256 public startEpochSupply;
    mapping(address => bool) public allowedTransferee;
    address public minter;

    event Allowed(address indexed target);
    event Disallowed(address indexed target);
    event VestingContractDeployed(
        address indexed beneficiary,
        address vestingContract
    );

    event UpdateMiningParameters(uint256 time, uint256 rate, uint256 supply);   
    event SetMinter(address minter);


    struct Recipient {
        address to;
        uint256 amount;
        uint256 startTimestamp;
        uint256 cliffPeriod;
        uint256 durationPeriod;
        uint256 cliffRatio;
    }

    /**
     * @notice Initializes SRS token with specified governance address and recipients. For vesting
     * durations and amounts, please refer to our documentation on token distribution schedule.
     * @param governance_ address of the governance who will own this contract
     * @param pausePeriod_ time in seconds since the deployment. After this period, this token can be unpaused
     * by the governance.
     * @param vestingContractTarget_ logic contract of Vesting.sol to use for cloning
     */
    constructor(
        address governance_,
        uint256 pausePeriod_,
        address vestingContractTarget_
    ) public ERC20("Sirius Finance", "SRS") ERC20Permit("Sirius Finance") {
        require(governance_ != address(0), "SRS: governance cannot be empty");
        require(
            vestingContractTarget_ != address(0),
            "SRS: vesting contract target cannot be empty"
        );
        require(
            pausePeriod_ >= 0 && pausePeriod_ <= 52 weeks,
            "SRS: pausePeriod must be in between 0 and 52 weeks"
        );

        // Set state variables
        vestingContractTarget = vestingContractTarget_;
        governance = governance_;
        govCanUnpauseAfter = block.timestamp + pausePeriod_;
        anyoneCanUnpauseAfter = block.timestamp + 52 weeks;

        // Allow governance to transfer tokens
        allowedTransferee[governance_] = true;

        // Mint tokens to governance
        _mint(governance, INITIAL_SUPPLY);

        // Pause transfers at deployment
        if (pausePeriod_ > 0) {
            _pause();
        }

        emit SetGovernance(governance_);

        startEpochTime = block.timestamp + INFLATION_DELAY - RATE_REDUCTION_TIME;
        miningEpoch = 0;
        rate = 0;
        startEpochSupply = INITIAL_SUPPLY;
    }

    /**
     * @notice Set the minter address
     * @dev Only callable once, when minter has not yet been set
     * @param _minter Address of the minter
     */
    function setMinter(address _minter) external onlyGovernance {
        require(_minter != address(0), "SRS: !_minter");
        minter = _minter;
        emit SetMinter(_minter);
    }

    /**
     * @dev Update mining rate and supply at the start of the epoch
         Any modifying mining call must also call this
     */
    function _updateMiningParameters() private {
        uint256 _rate = rate;
        uint256 _startEpochSupply = startEpochSupply;

        startEpochTime += RATE_REDUCTION_TIME;
        miningEpoch += 1;

        if (_rate == 0) {
            _rate = INITIAL_RATE;
        }else{
            _startEpochSupply += _rate * RATE_REDUCTION_TIME;
            startEpochSupply = _startEpochSupply;
            _rate = _rate * RATE_DENOMINATOR / RATE_REDUCTION_COEFFICIENT;
        }

        rate = _rate;

        emit UpdateMiningParameters(block.timestamp, _rate, _startEpochSupply);

    } 


    /**
      * @notice Update mining rate and supply at the start of the epoch
        @dev Callable by any address, but only once per epoch
            Total supply becomes slightly larger if this function is called late
    
     */
    function updateMiningParameters() external {
        require(block.timestamp >= startEpochTime + RATE_REDUCTION_TIME, "too soon");   // dev: too soon!
        _updateMiningParameters();
    }

    /**
     * @notice Get timestamp of the current mining epoch start while simultaneously updating mining parameters
     * @return Timestamp of the epoch
    */
    function startEpochTimeWrite() external returns (uint256) {
        uint256 _startEpochTime = startEpochTime;
        if (block.timestamp >= _startEpochTime + RATE_REDUCTION_TIME) {
            _updateMiningParameters();
            return startEpochTime;
        }
        else {
            return _startEpochTime;
        }

    }


    /**
     * @notice Get timestamp of the next mining epoch start while simultaneously updating mining parameters
     * @return Timestamp of the next epoch
    */
    function futureEpochTimeWrite() external returns (uint256) {
        uint256 _startEpochTime = startEpochTime;
        if (block.timestamp >= _startEpochTime + RATE_REDUCTION_TIME) {
            _updateMiningParameters();
            return startEpochTime + RATE_REDUCTION_TIME;
        }
        else {
            return _startEpochTime + RATE_REDUCTION_TIME;
        }
    }

    function _availableSupply() internal view returns (uint256){
        return startEpochSupply + (block.timestamp - startEpochTime) * rate;
    }

    /**
     * @notice Current number of tokens in existence (claimed or unclaimed)
     */
    function availableSupply() external view returns (uint256){
        return _availableSupply();
    }

    
    /**
     * @notice How much supply is mintable from start timestamp till end timestamp
     * @param _start Start of the time interval (timestamp)
     * @param _end End of the time interval (timestamp)
     * @return Tokens mintable from `start` till `end`
     */
    function mintableInTimeframe(uint256 _start, uint256 _end) external view returns(uint256) {
        require(_start <= _end, "SRS: !start");   // dev: start > end
        uint256 toMint = 0;
        uint256 currentEpochTime = startEpochTime;
        uint256 currentRate = rate;

        // Special case if end is in future (not yet minted) epoch
        if (_end > currentEpochTime + RATE_REDUCTION_TIME){
            currentEpochTime += RATE_REDUCTION_TIME;
            currentRate = currentRate * RATE_DENOMINATOR / RATE_REDUCTION_COEFFICIENT;
        }

        require(_end <= currentEpochTime + RATE_REDUCTION_TIME, "SRS: !end");   // dev: too far in future

        // SRS will not work in 100 years. 
        for (uint256 i = 0; i < 100; i++) {

            if (_end >= currentEpochTime){
                uint256 currentEnd = _end;
                if (currentEnd > currentEpochTime + RATE_REDUCTION_TIME)
                    currentEnd = currentEpochTime + RATE_REDUCTION_TIME;

                uint256 currentStart = _start;
                if (currentStart >= currentEpochTime + RATE_REDUCTION_TIME)
                    break;  // We should never get here but what if...
                else if (currentStart < currentEpochTime)
                    currentStart = currentEpochTime;

                toMint += currentRate * (currentEnd - currentStart);

                if (_start >= currentEpochTime)
                    break;
            }

            currentEpochTime -= RATE_REDUCTION_TIME;
            currentRate = currentRate * RATE_REDUCTION_COEFFICIENT / RATE_DENOMINATOR;  // double-division with rounding made rate a bit less => good
            require(currentRate <= INITIAL_RATE, "SRS: !currentRate");   // This should never happen

        }  

        return toMint;

    }


    /**
     * @notice Mint `_value` tokens and assign them to `_to`
     * @dev Emits a Transfer event originating from 0x00
     * @param _to The account that will receive the created tokens
     * @param _value The amount that will be created
     * @return bool success
     */
    function mint(address _to, uint256 _value) external returns(bool) {
        require(msg.sender == minter, "SRS: !minter");   // dev: minter only
        require(_to != address(0), "SRS: !to");   // dev: zero address

        if (block.timestamp >= startEpochTime + RATE_REDUCTION_TIME) {
            _updateMiningParameters();
        }

        uint256 _totalSupply = totalSupply() + _value;
        require(_totalSupply <= _availableSupply(), "SRS: !value");   // dev: exceeds allowable mint amount
        _mint(_to, _value);

        return true;
    }
    

    /**
     * @notice Burn `_value` tokens belonging to `msg.sender`
     * @dev Emits a Transfer event with a destination of 0x00
     * @param _value The amount that will be burned
     * @return bool success
     */
    function burn(uint256 _value) external returns(bool) {
        _burn(msg.sender, _value);
        return true;
    }
    

    /**
     * @notice Deploys a clone of the vesting contract for the given recipient. Details about vesting and token
     * release schedule can be found on https://docs.sirius.finance
     * @param recipient Recipient of the token through the vesting schedule.
     */
    function deployNewVestingContract(Recipient memory recipient)
        public
        onlyGovernance
        returns (address)
    {
        require(
            recipient.durationPeriod > 0,
            "SRS: duration for vesting cannot be 0"
        );

        // Deploy a clone rather than deploying a whole new contract
        Vesting vestingContract = Vesting(Clones.clone(vestingContractTarget));

        // Initialize the clone contract for the recipient
        vestingContract.initialize(
            address(this),
            recipient.to,
            recipient.startTimestamp,
            recipient.cliffPeriod,
            recipient.durationPeriod,
            recipient.cliffRatio
        );

        // Send tokens to the contract
        IERC20(address(this)).safeTransferFrom(
            msg.sender,
            address(vestingContract),
            recipient.amount
        );

        // Add the vesting contract to the allowed transferee list
        allowedTransferee[address(vestingContract)] = true;
        emit Allowed(address(vestingContract));
        emit VestingContractDeployed(recipient.to, address(vestingContract));

        return address(vestingContract);
    }

    /**
     * @notice Changes the transferability of this token.
     * @dev When the transfer is not enabled, only those in allowedTransferee array can
     * transfer this token.
     */
    function enableTransfer() external {
        require(paused(), "SRS: transfer is enabled");
        uint256 unpauseAfter = msg.sender == governance
            ? govCanUnpauseAfter
            : anyoneCanUnpauseAfter;
        require(
            block.timestamp > unpauseAfter,
            "SRS: cannot enable transfer yet"
        );
        _unpause();
    }

    /**
     * @notice Add the given addresses to the list of allowed addresses that can transfer during paused period.
     * Governance will add auxiliary contracts to the allowed list to facilitate distribution during the paused period.
     * @param targets Array of addresses to add
     */
    function addToAllowedList(address[] memory targets)
        external
        onlyGovernance
    {
        for (uint256 i = 0; i < targets.length; i++) {
            allowedTransferee[targets[i]] = true;
            emit Allowed(targets[i]);
        }
    }

    /**
     * @notice Remove the given addresses from the list of allowed addresses that can transfer during paused period.
     * @param targets Array of addresses to remove
     */
    function removeFromAllowedList(address[] memory targets)
        external
        onlyGovernance
    {
        for (uint256 i = 0; i < targets.length; i++) {
            allowedTransferee[targets[i]] = false;
            emit Disallowed(targets[i]);
        }
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal override {
        super._beforeTokenTransfer(from, to, amount);
        require(!paused() || allowedTransferee[from], "SRS: paused");
        require(to != address(this), "SRS: invalid recipient");
    }

    /**
     * @notice Transfers any stuck tokens or ether out to the given destination.
     * @dev Method to claim junk and accidentally sent tokens. This will be only used to rescue
     * tokens that are mistakenly sent by users to this contract.
     * @param token Address of the ERC20 token to transfer out. Set to address(0) to transfer ether instead.
     * @param to Destination address that will receive the tokens.
     * @param balance Amount to transfer out. Set to 0 to select all available amount.
     */
    function rescueTokens(
        IERC20 token,
        address payable to,
        uint256 balance
    ) external onlyGovernance {
        require(to != address(0), "SRS: invalid recipient");

        if (token == IERC20(address(0))) {
            // for Ether
            uint256 totalBalance = address(this).balance;
            balance = balance == 0
                ? totalBalance
                : Math.min(totalBalance, balance);
            require(balance > 0, "SRS: trying to send 0 ETH");
            // slither-disable-next-line arbitrary-send
            (bool success, ) = to.call{value: balance}("");
            require(success, "SRS: ETH transfer failed");
        } else {
            // any other erc20
            uint256 totalBalance = token.balanceOf(address(this));
            balance = balance == 0
                ? totalBalance
                : Math.min(totalBalance, balance);
            require(balance > 0, "SRS: trying to send 0 balance");
            token.safeTransfer(to, balance);
        }
    }
}
