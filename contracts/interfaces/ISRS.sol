// SPDX-License-Identifier: MIT
pragma solidity 0.8.6;

interface ISRS {
    function rate() external returns (uint256);

    function futureEpochTimeWrite() external returns (uint256);
}