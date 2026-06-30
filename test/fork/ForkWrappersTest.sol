// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {Test} from "lib/forge-std/src/Test.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/interfaces/IERC20.sol";
import {IERC4626} from "lib/openzeppelin-contracts/contracts/interfaces/IERC4626.sol";

import {PUSDERC4626Wrapper} from "src/PUSDERC4626Wrapper.sol";
import {NegRiskERC4626Wrapper} from "src/NegRiskERC4626Wrapper.sol";
import {PUSDERC4626WrapperFactory} from "src/factory/PUSDERC4626WrapperFactory.sol";
import {NegRiskERC4626WrapperFactory} from "src/factory/NegRiskERC4626WrapperFactory.sol";
import {ICollateralOnramp, ICollateralOfframp} from "src/interface/IPolyCollateral.sol";
import {INegRiskAdapter} from "lib/neg-risk-ctf-adapter/src/interfaces/INegRiskAdapter.sol";

/// @notice Integration smoke test against the live Polygon contracts: confirms the real ramps / NegRisk adapter honour
/// the wrapper's assumptions (asset routing, decimals, 1:1 wrap-unwrap) at a pinned block. The systematic coverage
/// lives in the local NegRisk/pUSD suites; here we just round-trip deposit/redeem and mint/withdraw through the real
/// stacks and assert value is conserved with no dust left behind.
contract ForkWrappersTest is Test {
    uint256 constant FORK_BLOCK = 89_124_689;

    IERC4626 constant VAULT = IERC4626(0xb1403908F772E4374BB151F7C67E88761a0Eb4f1);
    ICollateralOnramp constant ONRAMP = ICollateralOnramp(0x93070a847efEf7F70739046A929D47a521F5B8ee);
    ICollateralOfframp constant OFFRAMP = ICollateralOfframp(0x2957922Eb93258b93368531d39fAcCA3B4dC5854);
    INegRiskAdapter constant NEG_RISK = INegRiskAdapter(0xd91E80cF2E7be2e162c6513ceD06f1dD0dA35296);

    IERC20 constant USDCE = IERC20(0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174);

    PUSDERC4626WrapperFactory pusdFactory;
    NegRiskERC4626WrapperFactory negRiskFactory;

    IERC4626 pusdWrapper;
    IERC4626 negWrapper;
    IERC20 pusd;
    IERC20 wcol;

    address user = address(0xBEEF);
    uint256 amount = 1_000e6;

    function setUp() public {
        vm.createSelectFork(vm.envString("POLYGON_RPC_URL"), FORK_BLOCK);

        pusdFactory = new PUSDERC4626WrapperFactory(ONRAMP, OFFRAMP);
        negRiskFactory = new NegRiskERC4626WrapperFactory(NEG_RISK);

        pusdWrapper = IERC4626(address(pusdFactory.deployWrapper(VAULT)));
        negWrapper = IERC4626(address(negRiskFactory.deployWrapper(VAULT)));
        pusd = IERC20(ONRAMP.COLLATERAL_TOKEN());
        wcol = IERC20(NEG_RISK.wcol());

        vm.label(address(VAULT), "YieldVault");
        vm.label(address(USDCE), "USDC.e");
        vm.label(address(pusd), "pUSD");
        vm.label(address(wcol), "WCOL");
        vm.label(user, "user");
    }

    /* ------------------------------- PUSD -------------------------------- */

    function test_PUSD_factoryAddress() public view {
        assertEq(address(pusdWrapper), pusdFactory.getWrapperAddress(VAULT), "wrapper at predicted address");
    }

    function test_PUSD_depositRedeem() public {
        _seedPusd(amount);
        _checkDepositRedeem(pusdWrapper, pusd);
    }

    function test_PUSD_mintWithdraw() public {
        _seedPusd(amount);
        _checkMintWithdraw(pusdWrapper, pusd);
    }

    /* ------------------------------ NEGRISK ------------------------------ */

    function test_NegRisk_factoryAddress() public view {
        assertEq(address(negWrapper), negRiskFactory.getWrapperAddress(VAULT), "wrapper at predicted address");
    }

    function test_NegRisk_depositRedeem() public {
        _seedWcol(amount);
        _checkDepositRedeem(negWrapper, wcol);
    }

    function test_NegRisk_mintWithdraw() public {
        _seedWcol(amount);
        _checkMintWithdraw(negWrapper, wcol);
    }

    /* ------------------------------ HELPERS ------------------------------ */

    /// @dev Mint pUSD to the user by wrapping USDC.e through the live onramp.
    function _seedPusd(uint256 amt) internal {
        deal(address(USDCE), user, amt);
        vm.startPrank(user);
        USDCE.approve(address(ONRAMP), amt);
        ONRAMP.wrap(address(USDCE), user, amt);
        vm.stopPrank();
        assertEq(pusd.balanceOf(user), amt, "user pUSD seeded");
    }

    /// @dev Give the user wcol directly (fully backed by USDC.e at the fork block).
    function _seedWcol(uint256 amt) internal {
        deal(address(wcol), user, amt);
        assertEq(wcol.balanceOf(user), amt, "user wcol seeded");
    }

    /// @dev deposit → redeem-all conserves value (never more out than in) and leaves no dust on the wrapper.
    function _checkDepositRedeem(IERC4626 w, IERC20 asset) internal {
        vm.startPrank(user);
        asset.approve(address(w), amount);
        uint256 shares = w.deposit(amount, user);
        assertGt(shares, 0, "shares minted");
        assertEq(asset.balanceOf(user), 0, "asset pulled in full");

        uint256 out = w.redeem(shares, user, user);
        vm.stopPrank();

        assertLe(out, amount, "no value created");
        assertApproxEqAbs(out, amount, 2, "roundtrip ~ deposit");
        assertEq(asset.balanceOf(user), out, "asset returned to user");
        _assertNoDust(w, asset);
    }

    /// @dev mint → withdraw (sweeping any dust share) exercises the other two entry points, conserves value, no dust.
    function _checkMintWithdraw(IERC4626 w, IERC20 asset) internal {
        uint256 shares = w.previewDeposit(amount);
        uint256 budget = w.previewMint(shares); // <= amount

        vm.startPrank(user);
        asset.approve(address(w), budget);
        uint256 assetsIn = w.mint(shares, user);
        vm.stopPrank();
        assertLe(assetsIn, amount, "mint within budget");
        assertEq(w.balanceOf(user), shares, "minted requested shares");

        uint256 maxAssets = w.maxWithdraw(user);
        vm.prank(user);
        w.withdraw(maxAssets, user, user);
        if (w.balanceOf(user) > 0) {
            vm.prank(user);
            w.redeem(w.balanceOf(user), user, user);
        }

        assertEq(w.balanceOf(user), 0, "all shares burned");
        assertLe(asset.balanceOf(user), assetsIn, "no value created");
        _assertNoDust(w, asset);
    }

    function _assertNoDust(IERC4626 w, IERC20 asset) internal view {
        assertEq(asset.balanceOf(address(w)), 0, "no wrapper-asset dust");
        assertEq(USDCE.balanceOf(address(w)), 0, "no underlying dust");
    }
}
