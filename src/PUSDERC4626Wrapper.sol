// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.34;

import {BaseERC4626Wrapper} from "src/BaseERC4626Wrapper.sol";
import {IERC4626} from "lib/openzeppelin-contracts/contracts/interfaces/IERC4626.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/interfaces/IERC20.sol";
import {SafeERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

import {ICollateralToken, ICollateralOnramp, ICollateralOfframp} from "src/interface/IPolyCollateral.sol";

/// @title PUSDERC4626Wrapper
/// @author yashnaman
/// @notice A {BaseERC4626Wrapper} whose wrapper asset is Polymarket's collateral token (`pUSD`). It unwraps `pUSD`
/// into its backing asset (USDC or USDC.e) through the offramp, supplies that asset to the underlying vault, and wraps it
/// back into `pUSD` through the onramp on withdrawal, so holders stay denominated in `pUSD` while earning yield.
/// @dev Wrap/unwrap go through the permissionless on/off ramps and are assumed to be 1:1. If a ramp pauses or stops
/// honouring the 1:1 conversion, deposits and withdrawals revert; funds already supplied remain in the underlying
/// vault and are not lost, but become temporarily unredeemable through this wrapper until the ramp resumes.
contract PUSDERC4626Wrapper is BaseERC4626Wrapper {
    using SafeERC20 for IERC20;

    /* ERRORS */

    /// @notice Thrown when the onramp and offramp reference different collateral tokens.
    error RampCollateralTokenMismatch();

    /// @notice Thrown when the underlying vault's asset is neither of the collateral token's backing assets (USDC/USDC.e).
    error UnderlyingVaultAssetIsNotValidCollateral();

    /* IMMUTABLES & CONSTANTS */

    /// @notice The onramp used to wrap the backing asset into `pUSD`.
    ICollateralOnramp public immutable ONRAMP;

    /// @notice The offramp used to unwrap `pUSD` back into the backing asset.
    ICollateralOfframp public immutable OFFRAMP;

    /// @notice The Polymarket collateral token (`pUSD`), which is this wrapper's ERC-4626 asset.
    address public immutable COLLATERAL_TOKEN;

    /* CONSTRUCTOR */

    /// @param underlyingVault The underlying vault; its asset must be one of the collateral token's backing assets.
    /// @param onramp The onramp that wraps the backing asset into `pUSD`.
    /// @param offramp The offramp that unwraps `pUSD` into the backing asset.
    constructor(IERC4626 underlyingVault, ICollateralOnramp onramp, ICollateralOfframp offramp)
        BaseERC4626Wrapper(underlyingVault, IERC20(onramp.COLLATERAL_TOKEN()))
    {
        address collateralToken = onramp.COLLATERAL_TOKEN();
        require(offramp.COLLATERAL_TOKEN() == collateralToken, RampCollateralTokenMismatch());

        // The vault must hold one of the collateral token's backing assets, since that is what the wrapper unwraps
        // `pUSD` into and supplies to the vault.
        address asset = underlyingVault.asset();
        require(
            asset == ICollateralToken(collateralToken).USDC() || asset == ICollateralToken(collateralToken).USDCE(),
            UnderlyingVaultAssetIsNotValidCollateral()
        );

        ONRAMP = onramp;
        OFFRAMP = offramp;
        COLLATERAL_TOKEN = collateralToken;

        // Pre-approve the onramp to pull the backing asset on wrap, and the offramp to pull `pUSD` on unwrap.
        UNDERLYING_ASSET.forceApprove(address(onramp), type(uint256).max);
        IERC20(collateralToken).forceApprove(address(offramp), type(uint256).max);
    }

    /* WRAP / UNWRAP HOOKS */

    /// @dev Wraps the backing asset (already held by this contract) into `pUSD` minted directly to `to`.
    function _wrapAndTransfer(address to, uint256 amount) internal override {
        ONRAMP.wrap(address(UNDERLYING_ASSET), to, amount);
    }

    /// @dev Unwraps `pUSD` into the backing asset, returned to this contract for supply to the vault.
    function _unwrap(uint256 amount) internal override {
        OFFRAMP.unwrap(address(UNDERLYING_ASSET), address(this), amount);
    }
}
