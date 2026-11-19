// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/// @title MockBeacon
/// @notice IBeacon implementation returning a configurable index, stamped with
/// the block time it was last set (beacons v1.0.0 `index()` shape).
contract MockBeacon {
    uint256 public IDX;
    uint256 public UPDATED_AT;

    event IndexUpdated(uint256 index);

    constructor(uint256 initialIndex) {
        IDX = initialIndex;
        UPDATED_AT = block.timestamp;
        emit IndexUpdated(initialIndex);
    }

    function index() external view returns (uint256, uint256) {
        return (IDX, UPDATED_AT);
    }

    function twAvg(uint32) external view returns (uint256) {
        return IDX;
    }

    function setIndex(uint256 newIndex) external {
        IDX = newIndex;
        UPDATED_AT = block.timestamp;
        emit IndexUpdated(newIndex);
    }
}
