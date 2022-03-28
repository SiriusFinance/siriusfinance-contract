// SPDX-License-Identifier: MIT
pragma solidity 0.8.6;

interface IGaugeController {
    function gaugeTypes(address) external view returns (uint256);
    function gaugeRelativeWeight(address, uint256) external view returns(uint256);
    function checkpointGauge(address) external;
}