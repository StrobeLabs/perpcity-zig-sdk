// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "./MockPerp.sol";

/// @title MockPerpFactory
/// @notice Deploys MockPerp instances and emits PerpCreated with the v0.1.0
/// event signature so the SDK can decode the produced perp address.
contract MockPerpFactory {
    mapping(address => bool) public perps;

    event PerpCreated(
        address perp,
        bytes32 poolId,
        Modules modules,
        uint256 initialIndex,
        uint24 emaWindow,
        uint256 protocolFee,
        uint160 sqrtPriceX96,
        int24 tick,
        address owner,
        string name,
        string symbol,
        string tokenUri
    );

    function createPerp(
        address owner,
        string memory name,
        string memory symbol,
        string memory tokenUri,
        Modules memory mods,
        uint24 emaWindow,
        bytes32 salt
    ) external returns (address perp) {
        MockPerp p = new MockPerp(owner, mods, 0);
        perp = address(p);
        perps[perp] = true;
        bytes32 poolId = keccak256(abi.encodePacked(perp, salt));
        emit PerpCreated(
            perp,
            poolId,
            mods,
            1e18,
            emaWindow,
            0,
            uint160(1) << 96,
            int24(0),
            owner,
            name,
            symbol,
            tokenUri
        );
    }
}
