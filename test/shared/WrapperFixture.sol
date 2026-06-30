// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {Test} from "lib/forge-std/src/Test.sol";
import {IERC20} from "lib/forge-std/src/interfaces/IERC20.sol";
import {IERC4626} from "lib/openzeppelin-contracts/contracts/interfaces/IERC4626.sol";

import {MockERC20} from "test/mocks/MockERC20.sol";
import {MockERC4626} from "test/mocks/MockERC4626.sol";

/// @title WrapperFixture
/// @notice Wrapper-agnostic test fixture: the shared state, hooks and helpers used by both the unit matrix
/// ({WrapperUnitTests}) and the invariant suite ({WrapperInvariants}). A per-wrapper fixture (NegRisk, pUSD) deploys a
/// real wrap/unwrap stack in `setUp` and implements the hooks; the behaviour layers then drive the wrapper purely
/// through the ERC-4626 surface, so all logic is written once and runs against every real stack.
abstract contract WrapperFixture is Test {
    /* Bounds for fuzzed amounts (6-decimal assets), kept clear of overflow in the share math. */
    uint256 internal constant MIN_AMOUNT = 1;
    uint256 internal constant MAX_AMOUNT = 1e24;
    /// @dev Amounts large enough that sub-unit rounding does not dominate proportional/yield assertions.
    uint256 internal constant MIN_FAIR_AMOUNT = 1e6;

    address internal ALICE;
    address internal BOB;
    address internal CAROL;

    /* Set by the concrete fixture's setUp(). */
    IERC4626 internal wrapper; // the wrapper under test, over `underlyingVault`
    IERC20 internal wrapperAsset; // the wrapper's ERC-4626 asset (wcol / pUSD)
    IERC20 internal underlyingAsset; // the asset the wrapper supplies to the vault (col / USDC.e), a MockERC20
    MockERC4626 internal underlyingVault; // the honest yield source

    function setUp() public virtual {
        ALICE = makeAddr("Alice");
        BOB = makeAddr("Bob");
        CAROL = makeAddr("Carol");
    }

    /* ---------------------------------------------------------------------- */
    /*                      HOOKS (concrete fixture implements)               */
    /* ---------------------------------------------------------------------- */

    /// @dev Mint `amount` of the wrapper asset to `to`, fully backed so the wrapper's unwrap leg works for real.
    function _giveWrapperAsset(address to, uint256 amount) internal virtual;

    /// @dev Deploy a fresh wrapper of the fixture's type bound to `vault`, reusing the already-deployed wrap/unwrap
    /// infrastructure. Used both for the default wrapper and for the lossy-vault variant.
    function _deployWrapperOverVault(IERC4626 vault) internal virtual returns (IERC4626);

    /// @dev Assert the wrapper holds no stray value beyond its vault shares. The default covers the wrapper and
    /// underlying assets; the NegRisk fixture extends it to the conditional-token position ids.
    function _assertNoDust() internal view virtual {
        assertEq(wrapperAsset.balanceOf(address(wrapper)), 0, "wrapperAsset dust");
        assertEq(underlyingAsset.balanceOf(address(wrapper)), 0, "underlyingAsset dust");
    }

    /* ---------------------------------------------------------------------- */
    /*                              SHARED HELPERS                            */
    /* ---------------------------------------------------------------------- */

    /// @dev Simulate yield by minting underlying straight into the vault, lifting its share price.
    function _accrueYield(uint256 amount) internal {
        MockERC20(address(underlyingAsset)).mint(address(underlyingVault), amount);
    }

    function _deposit(address user, uint256 amount) internal returns (uint256 shares) {
        _giveWrapperAsset(user, amount);
        vm.startPrank(user);
        wrapperAsset.approve(address(wrapper), amount);
        shares = wrapper.deposit(amount, user);
        vm.stopPrank();
    }

    function _redeem(address user, uint256 shares) internal returns (uint256 assets) {
        vm.prank(user);
        assets = wrapper.redeem(shares, user, user);
    }

    function _redeemAll(address user) internal returns (uint256 assets) {
        return _redeem(user, wrapper.balanceOf(user));
    }

    /// @dev The redeemable value the wrapper is backed by: the vault shares it holds, priced at the vault.
    function _backing() internal view returns (uint256) {
        return underlyingVault.previewRedeem(underlyingVault.balanceOf(address(wrapper)));
    }
}
