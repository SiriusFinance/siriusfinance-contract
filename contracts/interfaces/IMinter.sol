// SPDX-License-Identifier: MIT

pragma solidity 0.8.6;

interface IMinter {
    function minted(address, address) external view returns (uint256);
}