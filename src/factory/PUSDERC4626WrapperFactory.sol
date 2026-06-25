// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.34;

import {IERC4626} from "lib/openzeppelin-contracts/contracts/interfaces/IERC4626.sol";

import {PUSDERC4626Wrapper} from "src/PUSDERC4626Wrapper.sol";
import {ICollateralOnramp, ICollateralOfframp} from "src/interface/IPolyCollateral.sol";

/// @title PUSDERC4626WrapperFactory
/// @author yashnaman
/// @notice Deploys {PUSDERC4626Wrapper} instances at deterministic addresses, one per underlying vault.
/// @dev Holds no storage state: the onramp and offramp are fixed at construction as immutables, so every wrapper is
/// bound to them and the CREATE2 salt is the vault address alone. The deployed address is therefore a pure function of
/// (factory, vault) and can be predicted with `getWrapperAddress` before deployment.
contract PUSDERC4626WrapperFactory {
    /// @notice Emitted when a wrapper is deployed for `vault`.
    event WrapperDeployed(IERC4626 indexed vault, address wrapper);

    /// @notice Thrown when a bound dependency is the zero address.
    error ZeroAddress();

    /// @notice The onramp every deployed wrapper is bound to.
    ICollateralOnramp public immutable ONRAMP;

    /// @notice The offramp every deployed wrapper is bound to.
    ICollateralOfframp public immutable OFFRAMP;

    /// @param onramp The onramp that wraps the backing asset into `pUSD`.
    /// @param offramp The offramp that unwraps `pUSD` into the backing asset.
    constructor(ICollateralOnramp onramp, ICollateralOfframp offramp) {
        require(address(onramp) != address(0) && address(offramp) != address(0), ZeroAddress());

        ONRAMP = onramp;
        OFFRAMP = offramp;
    }

    /// @notice Deploys the {PUSDERC4626Wrapper} for `vault` at its deterministic address.
    /// @dev Reverts if a wrapper already exists at the address, so each vault can be deployed only once per factory.
    function deployWrapper(IERC4626 vault) external returns (PUSDERC4626Wrapper wrapper) {
        wrapper = new PUSDERC4626Wrapper{salt: _salt(vault)}(vault, ONRAMP, OFFRAMP);

        emit WrapperDeployed(vault, address(wrapper));
    }

    /// @notice Returns the address the wrapper for `vault` is (or would be) deployed at.
    function getWrapperAddress(IERC4626 vault) external view returns (address wrapper) {
        bytes32 initCodeHash =
            keccak256(abi.encodePacked(type(PUSDERC4626Wrapper).creationCode, abi.encode(vault, ONRAMP, OFFRAMP)));
        bytes32 data = keccak256(abi.encodePacked(bytes1(0xff), address(this), _salt(vault), initCodeHash));
        wrapper = address(uint160(uint256(data)));
    }

    /// @dev The salt is the vault address, so a vault maps to exactly one wrapper per factory.
    function _salt(IERC4626 vault) internal pure returns (bytes32) {
        return bytes32(uint256(uint160(address(vault))));
    }
}
