# ERC-4626 Collateral Wrappers

ERC-4626 wrappers are vaults that can handle wrapped Polymarket collateral tokens. Each wrapper is itself an ERC-4626 vault whose `asset()` is a wrapped collateral token (NegRisk's wrapped collateral (`wcol`) or the Polymarket collateral token (`pUSD`)) and whose shares accrue the yield of an underlying ERC-4626 underlying vault. Holders keep their position denominated in the collateral they started with, but the collateral no longer sits idle.

A wrapper bridges two tokens that are convertible 1:1. On deposit it pulls the wrapper asset, unwraps it into the underlying vault's underlying asset (e.g. USDC.e), and supplies that asset to the underlying vault, minting wrapper shares for the redeemable amount. On withdrawal it reverses the flow: it redeems the underlying asset from the underlying vault, wraps it back into the wrapper asset, and sends it to the receiver. The whole scheme rests on the wrap/unwrap conversion being exactly 1:1; share accounting and `totalAssets` (the redeemable value of the yield-vault shares the wrapper holds) follow from that identity, never from market prices. The wrapper plugs into the deposit/withdraw flow through the `_transferIn` / `_transferOut` extension hooks of the OpenZeppelin `ERC4626` pinned in `lib`, which is what lets it interpose the unwrap-and-supply / redeem-and-wrap steps around the standard ERC-4626 path.

## Repository Structure

[`BaseERC4626Wrapper.sol`](src/BaseERC4626Wrapper.sol) is the abstract core: it holds the `UNDERLYING_VAULT` and `UNDERLYING_ASSET`, overrides the ERC-4626 transfer hooks to unwrap-then-supply and redeem-then-wrap, and exposes two abstract hooks — `_wrapAndTransfer` and `_unwrap` — that each collateral system fills in. It also fixes the share decimals offset to 6 (1e6 virtual shares) to harden the empty-vault share price against inflation attacks.

[`NegRiskERC4626Wrapper.sol`](src/NegRiskERC4626Wrapper.sol) wraps NegRisk wrapped collateral (`wcol`). Because `wcol` cannot be minted directly, it re-wraps the underlying by splitting through the `NEG_RISK_ADAPTER` and merging back through `CONDITIONAL_TOKENS`, round-tripping a binary `CONDITION_ID` it prepares at deployment. It also implements the ERC-1155 receiver hooks so it can hold outcome tokens mid-conversion.

[`PUSDERC4626Wrapper.sol`](src/PUSDERC4626Wrapper.sol) wraps the Polymarket collateral token (`pUSD`), unwrapping it into its backing asset (USDC or USDC.e) through the `OFFRAMP` and wrapping it back through the `ONRAMP`.

The `src/interface` directory holds the external-dependency interfaces. [`IWrappedCollateral.sol`](src/interface/IWrappedCollateral.sol) describes the NegRisk `wcol` wrap/unwrap surface, and [`IPolyCollateral.sol`](src/interface/IPolyCollateral.sol) describes the Polymarket collateral token and its on/off ramps.

The `test` directory contains the fork-based test suite exercising both wrappers against live Polygon state.

## License

Files in this repository are publicly available under license GPL-2.0-or-later.
