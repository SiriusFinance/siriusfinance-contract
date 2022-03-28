// SPDX-License-Identifier: MIT
pragma solidity 0.8.6;

import "../interfaces/IGaugeController.sol";
import "../interfaces/ILiquidityGauge.sol";
import "../interfaces/IERC20Mint.sol";
import "../OwnerPausableUpgradeable.sol";

contract Minter is OwnerPausableUpgradeable {

    address public token;
    address public controller;

    //user -> gauge -> value
    mapping(address => mapping(address => uint256)) public minted;
    //minter -> user -> can mint?
    mapping(address => mapping(address => bool)) public allowedToMintFor;


    event Minted(address indexed recipient, address gauge, uint256 minted);

    function __Minter_init(address _token, address _controller)
        external
        initializer
        returns (bool)
    {
        require(_token != address(0), "Minter: !token");
        require(_controller != address(0), "Minter: !controller");

        __OwnerPausable_init();

        token = _token;
        controller = _controller;
        return true;
    }

    function _mintFor(address _gaugeAddr, address _for) internal {
        require(IGaugeController(controller).gaugeTypes(_gaugeAddr) >= 0, "Minter: !gauge"); 

        ILiquidityGauge(_gaugeAddr).userCheckpoint(_for);
        uint256 totalMint = ILiquidityGauge(_gaugeAddr).integrateFraction(_for);
        uint256 toMint = totalMint - minted[_for][_gaugeAddr];

        if (toMint != 0){
            IERC20Mint(token).mint(_for, toMint);
            minted[_for][_gaugeAddr] = totalMint;

            emit Minted(_for, _gaugeAddr, totalMint);
        }
    }


    
    /**
     * @notice Mint everything which belongs to `msg.sender` and send to them
     * @param _gaugeAddr `LiquidityGauge` address to get mintable amount from
     */
    function mint(address _gaugeAddr) external nonReentrant() {
        _mintFor(_gaugeAddr, msg.sender);
    }

    /**
     * @notice Mint everything which belongs to `msg.sender` across multiple gauges
     * @param _gaugeAddrs List of `LiquidityGauge` addresses
     */
    function mintMany(address[8] memory _gaugeAddrs) external nonReentrant() {
        for(uint256 i =0; i < _gaugeAddrs.length; i++){
            if(_gaugeAddrs[i] == address(0)) {
                break;
            }
            _mintFor(_gaugeAddrs[i], msg.sender);
        }
    }

    /**
     * @notice Mint tokens for `_for`
     * @dev Only possible when `msg.sender` has been approved via `toggle_approve_mint`
     * @param _gaugeAddr `LiquidityGauge` address to get mintable amount from
     * @param _for Address to mint to
     */
    function mintFor(address _gaugeAddr, address _for) external nonReentrant() {
        if(allowedToMintFor[msg.sender][_for]){
            _mintFor(_gaugeAddr, _for);
        }
    }


    /**
     * @notice allow `_mintingUser` to mint for `msg.sender`
     * @param _mintingUser Address to toggle permission for
     */
    function toggleApproveMint(address _mintingUser) external {
        allowedToMintFor[_mintingUser][msg.sender] = !allowedToMintFor[_mintingUser][msg.sender];
    }
    
}