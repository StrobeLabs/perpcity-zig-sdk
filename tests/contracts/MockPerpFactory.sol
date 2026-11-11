// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "./MockPerp.sol";

struct WithdrawalConfig {
    uint128 capacity;
    uint128 refillPerSecond;
    uint48 challengeWindow;
}

/// @title MockPerpFactory
/// @notice Deploys MockPerp instances behind the v1.0.0 `createPerp` signature
/// and emits the v1.0.0 `PerpCreated` event so the SDK can decode the produced
/// perp address.
contract MockPerpFactory {
    error EmaWindowTooLow();
    error ZeroAddress();
    error ZeroWindow();

    event PerpCreated(
        address perp,
        bytes32 poolId,
        Modules modules,
        uint256 initialIndex,
        uint24 emaWindow,
        uint32 latency,
        uint256 protocolFee,
        uint160 sqrtPriceX96,
        int24 tick,
        address owner
    );

    function createPerp(
        address owner,
        address governor,
        Modules memory mods,
        uint24 emaWindow,
        uint32 latency,
        bytes32 salt,
        WithdrawalConfig memory withdrawalConfig
    ) external returns (address perp) {
        require(emaWindow != 0, EmaWindowTooLow());
        require(governor != address(0), ZeroAddress());
        require(withdrawalConfig.challengeWindow != 0, ZeroWindow());

        // Stand-in for the WithdrawalController clone the real factory deploys.
        address controller = address(uint160(uint256(keccak256(abi.encodePacked(msg.sender, salt, "controller")))));
        MockPerp p = new MockPerp(owner, governor, controller, mods, emaWindow, latency);
        perp = address(p);
        bytes32 poolId = keccak256(abi.encodePacked(perp, salt));
        emit PerpCreated(perp, poolId, mods, 1 << 96, emaWindow, latency, 0, uint160(1) << 96, int24(0), owner);
    }
}
