// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/// @title MockProtocolFeeManager
/// @notice Stores and returns a configurable protocol fee plus simple owner check.
contract MockProtocolFeeManager {
    uint256 public protocolFee;
    address public immutable OWNER;

    event ProtocolFeeSet(uint256 protocolFee);

    constructor(uint256 initialFee) {
        OWNER = msg.sender;
        protocolFee = initialFee;
        emit ProtocolFeeSet(initialFee);
    }

    function setProtocolFee(uint256 newProtocolFee) external {
        require(msg.sender == OWNER, "MockProtocolFeeManager: NOT_OWNER");
        protocolFee = newProtocolFee;
        emit ProtocolFeeSet(newProtocolFee);
    }

    function canCollectProtocolFees(address caller) external view returns (bool) {
        return caller == OWNER;
    }
}
