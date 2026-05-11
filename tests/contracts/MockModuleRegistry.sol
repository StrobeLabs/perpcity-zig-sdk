// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/// @title MockModuleRegistry
/// @notice Minimal IModuleRegistry. enum Module is encoded as uint8:
/// {Pricing=0, Funding=1, Fees=2, MarginRatios=3, Lockup=4, PriceImpact=5}.
contract MockModuleRegistry {
    mapping(uint8 => mapping(address => bool)) public modules;

    event ModuleRegistered(uint8 moduleType, address module);

    function registerModule(uint8 moduleType, address module) external {
        modules[moduleType][module] = true;
        emit ModuleRegistered(moduleType, module);
    }
}
