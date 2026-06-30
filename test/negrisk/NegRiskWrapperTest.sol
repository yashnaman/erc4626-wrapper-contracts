// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {NegRiskFixture} from "test/negrisk/NegRiskFixture.sol";
import {WrapperFixture} from "test/shared/WrapperFixture.sol";
import {WrapperUnitTests} from "test/shared/WrapperUnitTests.sol";
import {IERC20} from "lib/forge-std/src/interfaces/IERC20.sol";
import {IERC4626} from "lib/openzeppelin-contracts/contracts/interfaces/IERC4626.sol";

import {MockERC20} from "test/mocks/MockERC20.sol";
import {MockERC4626} from "test/mocks/MockERC4626.sol";

import {NegRiskERC4626Wrapper} from "src/NegRiskERC4626Wrapper.sol";
import {NegRiskERC4626WrapperFactory} from "src/factory/NegRiskERC4626WrapperFactory.sol";
import {INegRiskAdapter} from "lib/neg-risk-ctf-adapter/src/interfaces/INegRiskAdapter.sol";

/// @title NegRiskWrapperTest
/// @notice The shared wrapper unit matrix run against the real NegRisk stack, plus NegRisk-specific construction and
/// factory checks.
contract NegRiskWrapperTest is NegRiskFixture, WrapperUnitTests {
    /// @dev Disambiguate the diamond (NegRiskFixture and WrapperUnitTests both reach WrapperFixture).
    function setUp() public override(NegRiskFixture, WrapperFixture) {
        NegRiskFixture.setUp();
    }

    function _assertNoDust() internal view override(NegRiskFixture, WrapperFixture) {
        NegRiskFixture._assertNoDust();
    }

    /// @dev The vault's asset must be the adapter's unwrapped collateral.
    function test_constructor_revertsOnWrongVaultAsset() public {
        MockERC20 other = new MockERC20("Other", "OTH", 6);
        MockERC4626 badVault = new MockERC4626(IERC20(address(other)));
        vm.expectRevert(NegRiskERC4626Wrapper.UnderlyingVaultAssetIsNotUnwrappedCollateral.selector);
        new NegRiskERC4626Wrapper(neg, IERC4626(address(badVault)));
    }

    function test_factory_deterministicAddressAndSingleDeploy() public {
        NegRiskERC4626WrapperFactory factory = new NegRiskERC4626WrapperFactory(neg);
        MockERC4626 freshVault = new MockERC4626(underlyingAsset);

        address predicted = factory.getWrapperAddress(IERC4626(address(freshVault)));
        address deployed = address(factory.deployWrapper(IERC4626(address(freshVault))));
        assertEq(deployed, predicted, "deployed at predicted address");

        vm.expectRevert(); // CREATE2 collision: one wrapper per (factory, vault)
        factory.deployWrapper(IERC4626(address(freshVault)));
    }

    function test_factory_revertsOnZeroAdapter() public {
        vm.expectRevert(NegRiskERC4626WrapperFactory.ZeroAddress.selector);
        new NegRiskERC4626WrapperFactory(INegRiskAdapter(address(0)));
    }
}
