// SPDX-License-Identifier: MIT

pragma solidity 0.8.6;

interface ILiquidityGauge {
    function integrateFraction(address) external view returns (uint256);
    function userCheckpoint(address) external returns (bool);

}