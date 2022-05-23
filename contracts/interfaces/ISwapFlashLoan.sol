// SPDX-License-Identifier: MIT

pragma solidity 0.8.6;

import "./ISwap.sol";

interface ISwapFlashLoan is ISwap {
    function flashLoan(
        address receiver,
        IERC20Upgradeable token,
        uint256 amount,
        bytes memory params
    ) external;
}
