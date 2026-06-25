// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.34;

import {
    IERC4626,
    ERC4626,
    ERC20,
    IERC20
} from "lib/openzeppelin-contracts/contracts/token/ERC20/extensions/ERC4626.sol";
import {SafeERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20Metadata} from "lib/openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";

/// @title BaseERC4626Wrapper
/// @author yashnaman
/// @notice A thin ERC-4626 wrapper that routes a wrapped collateral token through an underlying ERC4626 vault. Its own
/// `asset()` is the wrapper asset (e.g. NegRiskAdapter's `wcol` or new Polymarket collateral token `pUSD`); on deposit it unwraps that asset into the
/// vault's underlying asset (e.g. USDC.e) and supplies it to `UNDERLYING_VAULT`, and on withdrawal it reverses the
/// flow. Holders therefore keep their position denominated in the wrapped collateral while earning the vault's yield.
/// @dev Subclasses implement the wrap/unwrap leg for a specific collateral system. The conversion MUST be exactly 1:1
/// between the wrapper asset and the underlying asset, otherwise share accounting and `totalAssets` break.
/// @dev Relies on the `_transferIn` / `_transferOut` extension hooks of the OpenZeppelin `ERC4626` pinned in `lib`;
/// these are not present in upstream OpenZeppelin releases and overriding them is what lets the wrapper interpose the
/// unwrap-and-deposit / withdraw-and-wrap steps around the standard ERC-4626 flow.
/// @dev The inherited `maxDeposit` / `maxMint` / `maxWithdraw` / `maxRedeem` getters are NOT bounded by
/// `UNDERLYING_VAULT`'s own deposit cap or available withdraw liquidity, since every deposit/withdrawal is forwarded
/// to it. They can therefore over-report: a deposit/withdrawal sized off these views may revert at the underlying
/// vault when it is capped, paused, or illiquid. This is a liveness/composability caveat only (no fund loss); funds
/// already supplied stay redeemable once the underlying vault frees up.
abstract contract BaseERC4626Wrapper is ERC4626 {
    using SafeERC20 for IERC20;

    /* IMMUTABLES & CONSTANTS */

    /// @notice The underlying vault that the unwrapped asset is supplied to; the source of yield for this wrapper.
    IERC4626 public immutable UNDERLYING_VAULT;

    /// @notice The asset held by the underlying vault (`UNDERLYING_VAULT.asset()`), i.e. the token the wrapper asset
    /// unwraps into and that is actually deposited to earn yield.
    IERC20 public immutable UNDERLYING_ASSET;

    /* CONSTRUCTOR */

    /// @param underlyingVault The underlying vault to supply the unwrapped asset to.
    /// @param wrapperAsset The wrapper's own ERC-4626 asset: the wrapped collateral token users deposit and that is
    /// unwrapped 1:1 into `underlyingVault.asset()`.
    constructor(IERC4626 underlyingVault, IERC20 wrapperAsset) ERC4626(wrapperAsset) ERC20("", "") {
        UNDERLYING_VAULT = underlyingVault;

        IERC20 underlyingAsset = IERC20(underlyingVault.asset());
        // Pre-approve the vault to pull the unwrapped asset on every deposit.
        underlyingAsset.forceApprove(address(underlyingVault), type(uint256).max);

        UNDERLYING_ASSET = underlyingAsset;
    }

    /* WRAP / UNWRAP HOOKS */

    /// @dev Wraps `amount` of the underlying asset back into the wrapper asset and transfers it to `to`. Must wrap
    /// exactly 1:1; the recipient transfer is the subclass's responsibility.
    function _wrapAndTransfer(address to, uint256 amount) internal virtual;

    /// @dev Unwraps `amount` of the wrapper asset (already held by this contract) into the underlying asset, which must
    /// end up in this contract so it can be supplied to `UNDERLYING_VAULT`. Must unwrap exactly 1:1.
    function _unwrap(uint256 amount) internal virtual;

    /* DEPOSIT / WITHDRAW BRIDGE */

    /// @dev Deposit leg: pull the wrapper asset from the depositor, unwrap it, and supply the underlying to the vault.
    function _transferIn(address from, uint256 assets) internal override {
        super._transferIn(from, assets);
        _unwrap(assets);
        UNDERLYING_VAULT.deposit(assets, address(this));
    }

    /// @dev Withdraw leg: redeem the underlying from the vault, then wrap it and forward it to the receiver.
    function _transferOut(address to, uint256 assets) internal override {
        UNDERLYING_VAULT.withdraw(assets, address(this), address(this));
        _wrapAndTransfer(to, assets);
    }

    /* METADATA */

    /// @inheritdoc IERC20Metadata
    function name() public view override(ERC20, IERC20Metadata) returns (string memory) {
        return string.concat("Wrapped ", UNDERLYING_VAULT.name());
    }

    /// @inheritdoc IERC20Metadata
    function symbol() public view override(ERC20, IERC20Metadata) returns (string memory) {
        return string.concat("W-", UNDERLYING_VAULT.symbol());
    }

    /* VIEW */

    /// @inheritdoc ERC4626
    /// @dev Backed entirely by the vault shares this contract holds, valued at their current redeemable amount.
    function totalAssets() public view override returns (uint256) {
        return UNDERLYING_VAULT.previewRedeem(UNDERLYING_VAULT.balanceOf(address(this)));
    }

    /// @inheritdoc ERC4626
    /// @dev Offsets share decimals by 6, giving 1e6 virtual shares to harden the empty-vault share price against
    /// inflation attacks (mirrors the virtual-shares mitigation used in the core YieldBearingOutcomeTokens vault).
    function _decimalsOffset() internal pure override returns (uint8) {
        return 6;
    }
}
