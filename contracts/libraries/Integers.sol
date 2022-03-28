// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.6;

library Integers {
    function toInt128(uint256 u) internal pure returns (int128) {
        return int128(uint128(u));
    }

    function toUint256(int128 i) internal pure returns (uint256) {
        return uint256(int256(i));
    }
}