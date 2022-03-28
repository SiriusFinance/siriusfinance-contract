// SPDX-License-Identifier: MIT
pragma solidity 0.8.6;

interface IGovernanceToken {
    function locked__of(address _addr) external view returns (uint256);

    function locked__end(address _addr) external view returns (uint256);

    function voting_power_unlock_time(uint256 _value, uint256 _unlock_time) external view returns (uint256);

    function voting_power_locked_days(uint256 _value, uint256 _days) external view returns (uint256);

    function deposit_for(address _addr, uint256 _value) external;

    function create_lock(uint256 _value, uint256 _days) external;

    function increase_amount(uint256 _value) external;

    function increase_unlock_time(uint256 _days) external;

    function withdraw() external;
}