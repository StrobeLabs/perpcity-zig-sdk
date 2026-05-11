// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/// @title MockBeacon
/// @notice IBeacon implementation returning a configurable constant index.
contract MockBeacon {
    uint256 public IDX;

    event IndexUpdated(uint256 index);

    constructor(uint256 initialIndex) {
        IDX = initialIndex;
        emit IndexUpdated(initialIndex);
    }

    function index() external view returns (uint256) {
        return IDX;
    }

    function twAvg(uint32) external view returns (uint256) {
        return IDX;
    }

    function setIndex(uint256 newIndex) external {
        IDX = newIndex;
        emit IndexUpdated(newIndex);
    }
}
