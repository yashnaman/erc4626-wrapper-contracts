// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {Script} from "lib/forge-std/src/Script.sol";
import {IERC4626} from "lib/openzeppelin-contracts/contracts/interfaces/IERC4626.sol";

import {PUSDERC4626Wrapper} from "src/PUSDERC4626Wrapper.sol";
import {NegRiskERC4626Wrapper} from "src/NegRiskERC4626Wrapper.sol";
import {PUSDERC4626WrapperFactory} from "src/factory/PUSDERC4626WrapperFactory.sol";
import {NegRiskERC4626WrapperFactory} from "src/factory/NegRiskERC4626WrapperFactory.sol";
import {ICollateralOnramp, ICollateralOfframp} from "src/interface/IPolyCollateral.sol";
import {INegRiskAdapter} from "lib/neg-risk-ctf-adapter/src/interfaces/INegRiskAdapter.sol";

/// @notice Deploys a factory per collateral system, then deploys each wrapper through its factory, against the live
/// Polygon addresses used in the fork tests.
contract DeployWrappers is Script {
    IERC4626 constant VAULT = IERC4626(0xb1403908F772E4374BB151F7C67E88761a0Eb4f1);
    ICollateralOnramp constant ONRAMP = ICollateralOnramp(0x93070a847efEf7F70739046A929D47a521F5B8ee);
    ICollateralOfframp constant OFFRAMP = ICollateralOfframp(0x2957922Eb93258b93368531d39fAcCA3B4dC5854);
    INegRiskAdapter constant NEG_RISK = INegRiskAdapter(0xd91E80cF2E7be2e162c6513ceD06f1dD0dA35296);

    function run()
        external
        returns (
            PUSDERC4626WrapperFactory pusdFactory,
            PUSDERC4626Wrapper pusdWrapper,
            NegRiskERC4626WrapperFactory negRiskFactory,
            NegRiskERC4626Wrapper negRiskWrapper
        )
    {
        vm.startBroadcast();

        pusdFactory = new PUSDERC4626WrapperFactory(ONRAMP, OFFRAMP);
        pusdWrapper = pusdFactory.deployWrapper(VAULT);

        negRiskFactory = new NegRiskERC4626WrapperFactory(NEG_RISK);
        negRiskWrapper = negRiskFactory.deployWrapper(VAULT);

        vm.stopBroadcast();
    }
}
