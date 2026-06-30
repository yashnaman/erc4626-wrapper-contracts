// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {WrapperFixture} from "test/shared/WrapperFixture.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";

/// @title WrapperInvariants
/// @notice Shared, wrapper-agnostic invariant suite. Bounded handlers (which never revert under an honest vault, so
/// `fail_on_revert = true` also proves exit liveness) drive random deposit/mint/withdraw/redeem/yield sequences; the
/// invariants then assert the wrapper stays solvent, reports `totalAssets` from nothing but its vault shares, holds no
/// dust, and lets every holder exit. Mixed onto each per-wrapper fixture so it runs against both real stacks.
abstract contract WrapperInvariants is WrapperFixture {
    uint256 internal constant MIN_INV_AMOUNT = 1e6;
    uint256 internal constant MAX_INV_AMOUNT = 1e24;
    uint256 internal constant VAULT_SEED = 1e30;

    address[] internal actors;

    /// @dev Wire up the invariant run: seed the vault deep (so its share price stays ~1 and honest deposits never round
    /// to zero shares), register the actors, and target only the bounded handlers. Called from the concrete suite's
    /// `setUp` after the fixture has deployed the stack.
    function _initInvariant() internal {
        actors = [ALICE, BOB, CAROL];

        MockERC20(address(underlyingAsset)).mint(address(this), VAULT_SEED);
        underlyingAsset.approve(address(underlyingVault), VAULT_SEED);
        underlyingVault.deposit(VAULT_SEED, address(this));

        bytes4[] memory selectors = new bytes4[](5);
        selectors[0] = this.depositHandler.selector;
        selectors[1] = this.mintHandler.selector;
        selectors[2] = this.withdrawHandler.selector;
        selectors[3] = this.redeemHandler.selector;
        selectors[4] = this.accrueYieldHandler.selector;
        targetSelector(FuzzSelector({addr: address(this), selectors: selectors}));
        targetContract(address(this));
    }

    function _actor(uint256 seed) internal view returns (address) {
        return actors[seed % actors.length];
    }

    /* ---------------------------------------------------------------------- */
    /*                          HANDLERS (never revert)                       */
    /* ---------------------------------------------------------------------- */

    function depositHandler(uint256 actorSeed, uint256 amount) external {
        amount = bound(amount, MIN_INV_AMOUNT, MAX_INV_AMOUNT);
        _deposit(_actor(actorSeed), amount);
    }

    function mintHandler(uint256 actorSeed, uint256 shares) external {
        address actor = _actor(actorSeed);
        // Bound the *asset* cost into range, then mint the shares that cost buys.
        uint256 assets = bound(shares, MIN_INV_AMOUNT, MAX_INV_AMOUNT);
        uint256 mintShares = wrapper.previewDeposit(assets);
        if (mintShares == 0) return;
        uint256 cost = wrapper.previewMint(mintShares);

        _giveWrapperAsset(actor, cost);
        vm.startPrank(actor);
        wrapperAsset.approve(address(wrapper), cost);
        wrapper.mint(mintShares, actor);
        vm.stopPrank();
    }

    function withdrawHandler(uint256 actorSeed, uint256 assets) external {
        address actor = _actor(actorSeed);
        uint256 maxAssets = wrapper.maxWithdraw(actor);
        if (maxAssets == 0) return;
        assets = bound(assets, 1, maxAssets);
        vm.prank(actor);
        wrapper.withdraw(assets, actor, actor);
    }

    function redeemHandler(uint256 actorSeed, uint256 shares) external {
        address actor = _actor(actorSeed);
        uint256 held = wrapper.balanceOf(actor);
        if (held == 0) return;
        _redeem(actor, bound(shares, 1, held));
    }

    function accrueYieldHandler(uint256 amount) external {
        amount = bound(amount, 0, MAX_INV_AMOUNT);
        if (amount == 0) return;
        _accrueYield(amount);
    }

    /* ---------------------------------------------------------------------- */
    /*                              INVARIANTS                                */
    /* ---------------------------------------------------------------------- */

    /// @dev The wrapper never owes holders more than its vault-share backing can pay.
    function invariant_solvency() public view {
        uint256 owed;
        for (uint256 i; i < actors.length; ++i) {
            owed += wrapper.previewRedeem(wrapper.balanceOf(actors[i]));
        }
        assertLe(owed, wrapper.totalAssets(), "holders owed <= totalAssets");
    }

    /// @dev `totalAssets` is reported from nothing but the wrapper's vault shares.
    function invariant_totalAssetsBacked() public view {
        assertEq(wrapper.totalAssets(), _backing(), "totalAssets == vault-share backing");
    }

    /// @dev The wrapper holds no stray wrapper/underlying asset (NegRisk also checks position ids).
    function invariant_noDust() public view {
        _assertNoDust();
    }

    /// @dev Every holder can redeem their full balance at once (exit liveness). Run against a rolled-back snapshot.
    function invariant_allHoldersCanRedeem() public {
        uint256 snap = vm.snapshotState();
        for (uint256 i; i < actors.length; ++i) {
            uint256 held = wrapper.balanceOf(actors[i]);
            if (held > 0) _redeem(actors[i], held);
        }
        vm.revertToState(snap);
    }
}
