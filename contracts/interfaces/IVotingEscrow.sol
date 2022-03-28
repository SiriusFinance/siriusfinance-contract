// SPDX-License-Identifier: MIT
pragma solidity 0.8.6;

interface IVotingEscrow {
    function locked__of(address _addr) external view returns (uint256);

    function locked__end(address _addr) external view returns (uint256);

    function depositFor(address _addr, uint256 _value) external;

    function createLock(uint256 _value, uint256 _days) external;

    function increaseAmount(uint256 _value) external;

    function increaseUnlockTime(uint256 _days) external;

    function withdraw() external;

    function getLastUserSlope(address _addr) external view returns (int128);

    function userPointHistory__ts(address _addr, uint256 _idx) external view returns (uint256);

    function userPointEpoch(address) external view returns (uint256);

}