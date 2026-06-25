// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.34;

/// @title IWrappedCollateral
/// @author yashnaman
/// @notice Minimal interface for Polymarket's WrappedCollateral (`wcol`): an ERC-20 that wraps an underlying
/// collateral token 1:1 for use inside the NegRisk / ConditionalTokens system.
/// @dev Only the entry points this wrapper needs are declared.
interface IWrappedCollateral {
    /// @notice Mints `_amount` of wrapped collateral to `_to`, pulling the underlying from the caller.
    /// @dev Restricted to the WrappedCollateral owner (the NegRiskAdapter), so it cannot be called directly here.
    /// @param _to The address to receive the wrapped collateral.
    /// @param _amount The amount to wrap.
    function wrap(address _to, uint256 _amount) external;

    /// @notice Burns `_amount` of the caller's wrapped collateral and returns the underlying to `_to`.
    /// @dev Permissionless: callable by any holder.
    /// @param _to The address to receive the unwrapped underlying.
    /// @param _amount The amount to unwrap.
    function unwrap(address _to, uint256 _amount) external;
}
