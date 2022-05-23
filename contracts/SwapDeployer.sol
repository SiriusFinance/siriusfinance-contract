// SPDX-License-Identifier: MIT

pragma solidity 0.8.6;

import "@openzeppelin/contracts-upgradeable-4.2.0/proxy/ClonesUpgradeable.sol";
import "./interfaces/ISwap.sol";
import "./interfaces/IMetaSwap.sol";
import "./OwnerPausableUpgradeable.sol";

contract SwapDeployer is OwnerPausableUpgradeable {
    event NewSwapPool(
        address indexed deployer,
        address swapAddress,
        IERC20Upgradeable[] pooledTokens
    );
    event NewClone(address indexed target, address cloneAddress);

    function __SwapDeployer_init() public initializer {
        __OwnerPausable_init();
    }

    function clone(address target) external returns (address) {
        address newClone = _clone(target);
        emit NewClone(target, newClone);

        return newClone;
    }

    function _clone(address target) internal returns (address) {
        return ClonesUpgradeable.clone(target);
    }

    function deploy(
        address swapAddress,
        IERC20Upgradeable[] memory _pooledTokens,
        uint8[] memory decimals,
        string memory lpTokenName,
        string memory lpTokenSymbol,
        uint256 _a,
        uint256 _fee,
        uint256 _adminFee,
        address lpTokenTargetAddress
    ) external returns (address) {
        address swapClone = _clone(swapAddress);
        ISwap(swapClone).initialize(
            _pooledTokens,
            decimals,
            lpTokenName,
            lpTokenSymbol,
            _a,
            _fee,
            _adminFee,
            lpTokenTargetAddress
        );
        OwnableUpgradeable(swapClone).transferOwnership(owner());
        emit NewSwapPool(msg.sender, swapClone, _pooledTokens);
        return swapClone;
    }

    function deployMetaSwap(
        address metaSwapAddress,
        IERC20Upgradeable[] memory _pooledTokens,
        uint8[] memory decimals,
        string memory lpTokenName,
        string memory lpTokenSymbol,
        uint256 _a,
        uint256 _fee,
        uint256 _adminFee,
        address lpTokenTargetAddress,
        ISwap baseSwap
    ) external returns (address) {
        address metaSwapClone = _clone(metaSwapAddress);
        IMetaSwap(metaSwapClone).initializeMetaSwap(
            _pooledTokens,
            decimals,
            lpTokenName,
            lpTokenSymbol,
            _a,
            _fee,
            _adminFee,
            lpTokenTargetAddress,
            baseSwap
        );
        OwnableUpgradeable(metaSwapClone).transferOwnership(owner());
        emit NewSwapPool(msg.sender, metaSwapClone, _pooledTokens);
        return metaSwapClone;
    }
}
