// SPDX-License-Identifier: MIT
pragma solidity 0.8.6;

import "@openzeppelin/contracts-4.2.0/access/Ownable.sol";
import "@openzeppelin/contracts-4.2.0/security/Pausable.sol";

/**
 * @title OwnerPausable
 * @notice An ownable contract allows the owner to pause and unpause the
 * contract without a delay.
 * @dev Only methods using the provided modifiers will be paused.
 */
contract OwnerPausable is Ownable, Pausable {
    /**
     * @notice Pause the contract. Revert if already paused.
     */
    function pause() external onlyOwner {
        Pausable._pause();
    }

    /**
     * @notice Unpause the contract. Revert if already unpaused.
     */
    function unpause() external onlyOwner {
        Pausable._unpause();
    }
}
