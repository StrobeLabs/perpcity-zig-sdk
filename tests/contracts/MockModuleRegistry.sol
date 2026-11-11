// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/// @title MockModuleRegistry
/// @notice Minimal IModuleRegistry. enum Module is encoded as uint8:
/// {Pricing=0, Funding=1, Fees=2, MarginRatios=3, PriceImpact=4}.
contract MockModuleRegistry {
    mapping(uint8 => mapping(address => bool)) public modules;

    event ModuleRegistered(uint8 moduleType, address module);

    event ModuleUnregistered(uint8 moduleType, address module);

    function registerModule(uint8 moduleType, address module) external {
        modules[moduleType][module] = true;
        emit ModuleRegistered(moduleType, module);
    }

    function unregisterModule(uint8 moduleType, address module) external {
        modules[moduleType][module] = false;
        emit ModuleUnregistered(moduleType, module);
    }
}
