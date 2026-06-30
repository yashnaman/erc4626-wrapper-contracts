// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {WrapperFixture} from "test/shared/WrapperFixture.sol";
import {IERC4626} from "lib/openzeppelin-contracts/contracts/interfaces/IERC4626.sol";
import {LossyOnWithdrawERC4626} from "test/mocks/LossyOnWithdrawERC4626.sol";

/// @title WrapperUnitTests
/// @notice The shared, wrapper-agnostic unit matrix. It drives a wrapper purely through the ERC-4626 surface and
/// asserts the two things the wrappers own: the wrap/unwrap bridge conserves value 1:1 and leaves no dust, and
/// `totalAssets` reports exactly the redeemable value of the vault shares the wrapper holds. Mixed onto each
/// per-wrapper fixture so every `test_*` runs against both real stacks.
abstract contract WrapperUnitTests is WrapperFixture {
    /* ---------------------------------------------------------------------- */
    /*                            ROUNDTRIP / 1:1                             */
    /* ---------------------------------------------------------------------- */

    /// @dev deposit → redeem-all returns ~ the deposit (never more), leaves no dust and drains the vault shares.
    function test_deposit_redeem_roundtrip(uint256 amount) public {
        amount = bound(amount, MIN_AMOUNT, MAX_AMOUNT);

        uint256 shares = _deposit(ALICE, amount);
        assertGt(shares, 0, "shares minted");
        assertEq(wrapperAsset.balanceOf(ALICE), 0, "asset pulled in full");

        uint256 out = _redeemAll(ALICE);
        assertLe(out, amount, "no value created on roundtrip");
        assertApproxEqAbs(out, amount, 2, "roundtrip ~ deposit");
        assertEq(wrapperAsset.balanceOf(ALICE), out, "asset returned to user");
        assertEq(underlyingVault.balanceOf(address(wrapper)), 0, "vault shares drained");
        _assertNoDust();
    }

    /// @dev mint → withdraw exercises the other two entry points: `mint` pulls exactly the previewed asset budget, and
    /// a `withdraw` of the realised assets (plus sweeping any dust share) drains the wrapper with no dust.
    function test_mint_withdraw_roundtrip(uint256 sharesSeed) public {
        // Pick a share quantity, then fund exactly the assets `mint` will price it at (wrapper is empty, so the
        // preview is exact). Share range maps to an asset budget within [~1, MAX_AMOUNT] given the 1e6 offset.
        uint256 shares = bound(sharesSeed, 1e6, 1e30);
        uint256 budget = wrapper.previewMint(shares);
        vm.assume(budget > 0 && budget <= MAX_AMOUNT);

        _giveWrapperAsset(ALICE, budget);
        vm.startPrank(ALICE);
        wrapperAsset.approve(address(wrapper), budget);
        uint256 assetsIn = wrapper.mint(shares, ALICE);
        vm.stopPrank();

        assertEq(assetsIn, budget, "mint pulls exactly the previewed budget");
        assertEq(wrapper.balanceOf(ALICE), shares, "minted exactly the requested shares");

        uint256 maxAssets = wrapper.maxWithdraw(ALICE); // hoisted: an arg call would consume the prank
        vm.prank(ALICE);
        wrapper.withdraw(maxAssets, ALICE, ALICE);
        if (wrapper.balanceOf(ALICE) > 0) _redeemAll(ALICE); // sweep any dust share

        assertEq(wrapper.balanceOf(ALICE), 0, "all shares burned");
        assertLe(wrapperAsset.balanceOf(ALICE), assetsIn, "no value created");
        _assertNoDust();
    }

    /// @dev The deposit leg pulls exactly `amount` of wrapper asset and supplies exactly `amount` to the vault.
    function test_deposit_suppliesExactAssetsToVault(uint256 amount) public {
        amount = bound(amount, MIN_AMOUNT, MAX_AMOUNT);

        uint256 vaultAssetsBefore = underlyingVault.totalAssets();
        _deposit(ALICE, amount);

        assertEq(underlyingVault.totalAssets() - vaultAssetsBefore, amount, "exactly `amount` supplied to vault");
        _assertNoDust();
    }

    /* ---------------------------------------------------------------------- */
    /*                          TOTALASSETS REPORTING                         */
    /* ---------------------------------------------------------------------- */

    /// @dev `totalAssets` is exactly the redeemable value of the vault shares held — before and after a deposit.
    function test_totalAssets_equalsBacking(uint256 amount) public {
        amount = bound(amount, MIN_AMOUNT, MAX_AMOUNT);

        assertEq(wrapper.totalAssets(), 0, "empty wrapper reports nothing");
        _deposit(ALICE, amount);
        assertEq(wrapper.totalAssets(), _backing(), "totalAssets == vault-share backing");
    }

    /// @dev Yield accrued in the vault flows straight into `totalAssets`.
    function test_totalAssets_tracksYield(uint256 amount, uint256 yield) public {
        amount = bound(amount, MIN_FAIR_AMOUNT, MAX_AMOUNT);
        yield = bound(yield, 1, MAX_AMOUNT);

        _deposit(ALICE, amount);
        uint256 before = wrapper.totalAssets();
        _accrueYield(yield);

        assertEq(wrapper.totalAssets(), _backing(), "still equals backing after yield");
        assertGt(wrapper.totalAssets(), before, "yield lifts totalAssets");
        assertApproxEqAbs(wrapper.totalAssets(), before + yield, 2, "lift ~ yield");
    }

    /* ---------------------------------------------------------------------- */
    /*                             YIELD / FAIRNESS                           */
    /* ---------------------------------------------------------------------- */

    /// @dev A holder who stays through accrued yield redeems for more than they put in.
    function test_yield_flowsToHolder(uint256 amount, uint256 yield) public {
        amount = bound(amount, MIN_FAIR_AMOUNT, MAX_AMOUNT);
        yield = bound(yield, MIN_FAIR_AMOUNT, MAX_AMOUNT);

        _deposit(ALICE, amount);
        _accrueYield(yield);
        uint256 out = _redeemAll(ALICE);

        assertGt(out, amount, "holder earns the yield");
        assertLe(out, amount + yield, "never more than deposit plus yield");
    }

    /// @dev Two holders share yield in proportion to their deposits.
    function test_yield_proportionalAcrossHolders() public {
        uint256 a = 300e6;
        uint256 b = 100e6;
        uint256 yield = 80e6;

        _deposit(ALICE, a);
        _deposit(BOB, b);
        _accrueYield(yield);

        uint256 aliceOut = _redeemAll(ALICE);
        uint256 bobOut = _redeemAll(BOB);

        assertGt(aliceOut, a, "Alice earns yield");
        assertGt(bobOut, b, "Bob earns yield");
        // (aliceOut - a) / a ~ (bobOut - b) / b  ->  cross-multiplied to avoid division.
        assertApproxEqRel((aliceOut - a) * b, (bobOut - b) * a, 0.001e18, "gains proportional to stake");
    }

    /// @dev A later depositor does not dilute an earlier one: Alice's redeemable value is unchanged by Bob's deposit.
    function test_secondDepositorDoesNotDilute() public {
        uint256 a = 1_000e6;
        _deposit(ALICE, a);
        uint256 aliceRedeemableBefore = wrapper.previewRedeem(wrapper.balanceOf(ALICE));

        _deposit(BOB, 7_777e6);
        uint256 aliceRedeemableAfter = wrapper.previewRedeem(wrapper.balanceOf(ALICE));

        assertApproxEqAbs(aliceRedeemableAfter, aliceRedeemableBefore, 1, "Bob's deposit does not move Alice");
        assertApproxEqAbs(_redeemAll(ALICE), a, 2, "Alice still redeems her deposit");
    }

    /// @dev One holder exiting does not impair another's full exit.
    function test_exitDoesNotImpairOthers() public {
        uint256 a = 1_000e6;
        uint256 b = 2_500e6;
        _deposit(ALICE, a);
        _deposit(BOB, b);

        assertApproxEqAbs(_redeemAll(BOB), b, 2, "Bob redeems his deposit");
        assertApproxEqAbs(_redeemAll(ALICE), a, 2, "Alice unaffected by Bob's exit");
        assertEq(underlyingVault.balanceOf(address(wrapper)), 0, "vault fully drained");
        _assertNoDust();
    }

    /* ---------------------------------------------------------------------- */
    /*                           SOLVENCY / EDGES                             */
    /* ---------------------------------------------------------------------- */

    /// @dev Everyone can exit at once; the wrapper is drained to zero with no dust (exit liveness + full drain).
    function test_fullDrain_noDust() public {
        _deposit(ALICE, 1_000e6);
        _deposit(BOB, 333e6);
        _deposit(CAROL, 1e6);
        _accrueYield(50e6);

        _redeemAll(CAROL);
        _redeemAll(ALICE);
        _redeemAll(BOB);

        assertEq(wrapper.totalSupply(), 0, "all shares burned");
        // A residual vault share worth a sub-unit of asset can be stranded by floor rounding — that is dust the wrapper
        // keeps (it favours solvency, never a user), so bound the residual *value*, not the raw share count.
        assertLe(_backing(), 1, "residual backing is dust");
        _assertNoDust();
    }

    /// @dev The smallest possible deposit round-trips without reverting and never pays out more than it took.
    function test_dustDeposit_roundtrips() public {
        uint256 shares = _deposit(ALICE, 1);
        assertGt(shares, 0, "even 1 unit mints shares");
        uint256 out = _redeemAll(ALICE);
        assertLe(out, 1, "never returns more than deposited");
        _assertNoDust();
    }

    /// @dev `withdraw(assets)` burns exactly `previewWithdraw(assets)` shares.
    function test_withdraw_burnsPreviewedShares(uint256 amount) public {
        amount = bound(amount, MIN_FAIR_AMOUNT, MAX_AMOUNT);
        _deposit(ALICE, amount);

        uint256 take = wrapper.maxWithdraw(ALICE) / 2;
        vm.assume(take > 0);
        uint256 expectedShares = wrapper.previewWithdraw(take);
        uint256 sharesBefore = wrapper.balanceOf(ALICE);

        vm.prank(ALICE);
        wrapper.withdraw(take, ALICE, ALICE);

        assertEq(sharesBefore - wrapper.balanceOf(ALICE), expectedShares, "burned previewed shares");
    }

    /// @dev With an honest fee-on-withdraw vault, `totalAssets` (priced via the vault's net `previewRedeem`) stays
    /// solvent: the holder simply absorbs the fee, the wrapper never claims more than it can pull out, and it drains
    /// cleanly. Proves our reporting choice is safe when the underlying charges on the way out.
    function test_lossyOnWithdrawVault_staysSolvent() public {
        LossyOnWithdrawERC4626 lossy = new LossyOnWithdrawERC4626(underlyingAsset, 100); // 1% withdraw fee
        IERC4626 lossyWrapper = _deployWrapperOverVault(IERC4626(address(lossy)));

        uint256 amount = 1_000e6;
        _giveWrapperAsset(ALICE, amount);
        vm.startPrank(ALICE);
        wrapperAsset.approve(address(lossyWrapper), amount);
        uint256 shares = lossyWrapper.deposit(amount, ALICE);

        // totalAssets is already net of the withdraw fee — the wrapper never over-reports.
        assertLe(lossyWrapper.totalAssets(), amount, "totalAssets net of the exit fee");

        uint256 out = lossyWrapper.redeem(shares, ALICE, ALICE);
        vm.stopPrank();

        assertLt(out, amount, "holder absorbs the 1% fee");
        assertGt(out, amount * 98 / 100, "but recovers ~99%");
        assertEq(lossy.balanceOf(address(lossyWrapper)), 0, "lossy wrapper drained cleanly");
        assertEq(wrapperAsset.balanceOf(address(lossyWrapper)), 0, "no wrapper-asset dust");
        assertEq(underlyingAsset.balanceOf(address(lossyWrapper)), 0, "no underlying dust");
    }
}
