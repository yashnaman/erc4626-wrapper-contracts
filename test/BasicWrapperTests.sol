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

contract ForkWrappersTest is Test {
    uint256 constant FORK_BLOCK = 89_124_689;

    IERC4626 constant VAULT = IERC4626(0xb1403908F772E4374BB151F7C67E88761a0Eb4f1);
    ICollateralOnramp constant ONRAMP = ICollateralOnramp(0x93070a847efEf7F70739046A929D47a521F5B8ee);
    ICollateralOfframp constant OFFRAMP = ICollateralOfframp(0x2957922Eb93258b93368531d39fAcCA3B4dC5854);
    INegRiskAdapter constant NEG_RISK = INegRiskAdapter(0xd91E80cF2E7be2e162c6513ceD06f1dD0dA35296);

    IERC20 constant USDCE = IERC20(0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174);

    PUSDERC4626WrapperFactory pusdFactory;
    NegRiskERC4626WrapperFactory negRiskFactory;

    address user = address(0xBEEF);
    uint256 amount = 1_000e6;

    function setUp() public {
        vm.createSelectFork(vm.envString("POLYGON_RPC_URL"), FORK_BLOCK);

        pusdFactory = new PUSDERC4626WrapperFactory(ONRAMP, OFFRAMP);
        negRiskFactory = new NegRiskERC4626WrapperFactory(NEG_RISK);

        vm.label(address(VAULT), "YieldVault");
        vm.label(address(ONRAMP), "Onramp");
        vm.label(address(OFFRAMP), "Offramp");
        vm.label(address(NEG_RISK), "NegRiskAdapter");
        vm.label(address(USDCE), "USDC.e");
        vm.label(ONRAMP.COLLATERAL_TOKEN(), "pUSD");
        vm.label(NEG_RISK.wcol(), "WCOL");
        vm.label(0xC417fD8E9661c0d2120B64a04Bb3278C17E99DB1, "pUSD_CustodyVault");
        vm.label(0xF25212E676D1F7F89Cd72fFEe66158f541246445, "YieldVault_Strategy");
        vm.label(user, "user");
    }

    function test_PUSD_DepositWithdraw() public {
        address predicted = pusdFactory.getWrapperAddress(VAULT);
        PUSDERC4626Wrapper wrapper = pusdFactory.deployWrapper(VAULT);
        assertEq(address(wrapper), predicted, "wrapper at predicted address");
        IERC20 pusd = IERC20(ONRAMP.COLLATERAL_TOKEN());

        // mint pUSD to the user by wrapping USDC.e through the onramp
        deal(address(USDCE), user, amount);
        vm.startPrank(user);
        USDCE.approve(address(ONRAMP), amount);
        ONRAMP.wrap(address(USDCE), user, amount);
        assertEq(pusd.balanceOf(user), amount, "user pUSD after wrap");

        // deposit pUSD into the wrapper
        pusd.approve(address(wrapper), amount);
        uint256 shares = wrapper.deposit(amount, user);
        assertEq(pusd.balanceOf(user), 0, "user pUSD after deposit");
        assertEq(wrapper.balanceOf(user), shares, "user shares after deposit");
        assertGt(shares, 0, "shares minted");

        // redeem all shares back to pUSD
        uint256 assetsOut = wrapper.redeem(shares, user, user);
        vm.stopPrank();

        assertApproxEqAbs(assetsOut, amount, 2, "assets out ~ deposited");
        assertEq(pusd.balanceOf(user), assetsOut, "user pUSD after redeem");
        assertEq(wrapper.balanceOf(user), 0, "user shares after redeem");
    }

    function test_NegRisk_DepositWithdraw() public {
        address predicted = negRiskFactory.getWrapperAddress(VAULT);
        NegRiskERC4626Wrapper wrapper = negRiskFactory.deployWrapper(VAULT);
        assertEq(address(wrapper), predicted, "wrapper at predicted address");
        IERC20 wcol = IERC20(NEG_RISK.wcol());

        // give the user wrapped collateral (it is fully backed by USDC.e on the fork)
        deal(address(wcol), user, amount);
        assertEq(wcol.balanceOf(user), amount, "user wcol balance");

        // deposit wcol into the wrapper
        vm.startPrank(user);
        wcol.approve(address(wrapper), amount);
        uint256 shares = wrapper.deposit(amount, user);
        assertEq(wcol.balanceOf(user), 0, "user wcol after deposit");
        assertEq(wrapper.balanceOf(user), shares, "user shares after deposit");
        assertGt(shares, 0, "shares minted");

        // redeem all shares back to wcol
        uint256 assetsOut = wrapper.redeem(shares, user, user);
        vm.stopPrank();

        assertApproxEqAbs(assetsOut, amount, 2, "assets out ~ deposited");
        assertEq(wcol.balanceOf(user), assetsOut, "user wcol after redeem");
        assertEq(wrapper.balanceOf(user), 0, "user shares after redeem");
    }
}
