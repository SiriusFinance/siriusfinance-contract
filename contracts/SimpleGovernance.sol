// SPDX-License-Identifier: MIT

pragma solidity 0.8.6;

import "./OwnerPausableUpgradeable.sol";

abstract contract SimpleGovernance is OwnerPausableUpgradeable {
    address public governance;
    address public pendingGovernance;

    event SetGovernance(address indexed governance, address indexed oldGovernance);
    event ChangeGovernance(address indexed sender, address indexed oldGovernance, address indexed newGovernance);

    /**
     * @notice Changes governance of this contract
     */
    modifier onlyGovernance() {
        require(
            _msgSender() == governance,
            "only governance can perform this action"
        );
        _;
    }

    /**
     * @notice Changes governance of this contract
     * @dev Only governance can call this function. The new governance must call `acceptGovernance` after.
     * @param newGovernance new address to become the governance
     */
    function changeGovernance(address newGovernance) external onlyGovernance {
        require(
            newGovernance != governance,
            "governance must be different from current one"
        );
        require(newGovernance != address(0), "governance cannot be empty");
        pendingGovernance = newGovernance;
        emit ChangeGovernance(msg.sender, governance, newGovernance);
    }

    /**
     * @notice Accept the new role of governance
     * @dev `changeGovernance` must be called first to set `pendingGovernance`
     */
    function acceptGovernance() external {
        address _pendingGovernance = pendingGovernance;
        require(
            _pendingGovernance != address(0),
            "changeGovernance must be called first"
        );
        require(
            _msgSender() == _pendingGovernance,
            "only pendingGovernance can accept this role"
        );
        pendingGovernance = address(0);
        governance = _msgSender();
        emit SetGovernance(_msgSender(), _pendingGovernance);
    }
}
