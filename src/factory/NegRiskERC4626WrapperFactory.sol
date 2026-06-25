// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.34;

import {IERC4626} from "lib/openzeppelin-contracts/contracts/interfaces/IERC4626.sol";

import {NegRiskERC4626Wrapper} from "src/NegRiskERC4626Wrapper.sol";
import {INegRiskAdapter} from "lib/neg-risk-ctf-adapter/src/interfaces/INegRiskAdapter.sol";

/// @title NegRiskERC4626WrapperFactory
/// @author yashnaman
/// @notice Deploys {NegRiskERC4626Wrapper} instances at deterministic addresses, one per underlying vault.
/// @dev Holds no storage state: the NegRiskAdapter is fixed at construction as an immutable, so every wrapper is bound
/// to it and the CREATE2 salt is the vault address alone. The deployed address is therefore a pure function of
/// (factory, vault) and can be predicted with `getWrapperAddress` before deployment.
contract NegRiskERC4626WrapperFactory {
    /// @notice Emitted when a wrapper is deployed for `vault`.
    event WrapperDeployed(IERC4626 indexed vault, address wrapper);

    /// @notice Thrown when a bound dependency is the zero address.
    error ZeroAddress();

    /// @notice The NegRiskAdapter every deployed wrapper is bound to.
    INegRiskAdapter public immutable NEG_RISK_ADAPTER;

    /// @param negRiskAdapter The NegRiskAdapter whose `wcol` is wrapped and whose `col` is supplied to the vault.
    constructor(INegRiskAdapter negRiskAdapter) {
        require(address(negRiskAdapter) != address(0), ZeroAddress());

        NEG_RISK_ADAPTER = negRiskAdapter;
    }

    /// @notice Deploys the {NegRiskERC4626Wrapper} for `vault` at its deterministic address.
    /// @dev Reverts if a wrapper already exists at the address, so each vault can be deployed only once per factory.
    function deployWrapper(IERC4626 vault) external returns (NegRiskERC4626Wrapper wrapper) {
        wrapper = new NegRiskERC4626Wrapper{salt: _salt(vault)}(NEG_RISK_ADAPTER, vault);

        emit WrapperDeployed(vault, address(wrapper));
    }

    /// @notice Returns the address the wrapper for `vault` is (or would be) deployed at.
    function getWrapperAddress(IERC4626 vault) external view returns (address wrapper) {
        bytes32 initCodeHash =
            keccak256(abi.encodePacked(type(NegRiskERC4626Wrapper).creationCode, abi.encode(NEG_RISK_ADAPTER, vault)));
        bytes32 data = keccak256(abi.encodePacked(bytes1(0xff), address(this), _salt(vault), initCodeHash));
        wrapper = address(uint160(uint256(data)));
    }

    /// @dev The salt is the vault address, so a vault maps to exactly one wrapper per factory.
    function _salt(IERC4626 vault) internal pure returns (bytes32) {
        return bytes32(uint256(uint160(address(vault))));
    }
}
