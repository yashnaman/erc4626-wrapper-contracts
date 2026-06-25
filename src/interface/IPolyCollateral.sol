// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.34;

/// @title IPolyCollateral
/// @author yashnaman
/// @notice Minimal interfaces for Polymarket's collateral token (`pUSD`) and its permissionless on/off ramps,
/// covering only the entry points the PUSD wrapper relies on.

/// @notice The Polymarket collateral token, which wraps either USDC or USDC.e as its backing asset.
interface ICollateralToken {
    /// @notice The USDC token address accepted as backing.
    function USDC() external view returns (address);

    /// @notice The USDC.e token address accepted as backing.
    function USDCE() external view returns (address);
}

/// @notice Permissionless onramp that wraps a backing asset into the collateral token.
interface ICollateralOnramp {
    /// @notice The collateral token this ramp mints.
    function COLLATERAL_TOKEN() external view returns (address);

    /// @notice Wraps `_amount` of `_asset` into collateral tokens minted to `_to`, pulling `_asset` from the caller.
    /// @param _asset The backing asset to wrap (USDC or USDC.e).
    /// @param _to The address to receive the collateral tokens.
    /// @param _amount The amount to wrap.
    function wrap(address _asset, address _to, uint256 _amount) external;
}

/// @notice Permissionless offramp that unwraps the collateral token back into a backing asset.
interface ICollateralOfframp {
    /// @notice The collateral token this ramp burns.
    function COLLATERAL_TOKEN() external view returns (address);

    /// @notice Unwraps `_amount` of collateral into `_asset` sent to `_to`, pulling the collateral from the caller.
    /// @param _asset The backing asset to receive (USDC or USDC.e).
    /// @param _to The address to receive the backing asset.
    /// @param _amount The amount to unwrap.
    function unwrap(address _asset, address _to, uint256 _amount) external;
}
