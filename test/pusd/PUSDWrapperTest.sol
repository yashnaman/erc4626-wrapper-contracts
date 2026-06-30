// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {PUSDFixture} from "test/pusd/PUSDFixture.sol";
import {WrapperFixture} from "test/shared/WrapperFixture.sol";
import {WrapperUnitTests} from "test/shared/WrapperUnitTests.sol";
import {IERC20} from "lib/forge-std/src/interfaces/IERC20.sol";
import {IERC4626} from "lib/openzeppelin-contracts/contracts/interfaces/IERC4626.sol";

import {MockERC20} from "test/mocks/MockERC20.sol";
import {MockERC4626} from "test/mocks/MockERC4626.sol";

import {PUSDERC4626Wrapper} from "src/PUSDERC4626Wrapper.sol";
import {PUSDERC4626WrapperFactory} from "src/factory/PUSDERC4626WrapperFactory.sol";
import {ICollateralOnramp, ICollateralOfframp} from "src/interface/IPolyCollateral.sol";
import {CollateralOfframp} from "lib/ctf-exchange-v2/src/collateral/CollateralOfframp.sol";

/// @title PUSDWrapperTest
/// @notice The shared wrapper unit matrix run against the real pUSD collateral stack, plus pUSD-specific construction
/// and factory checks.
contract PUSDWrapperTest is PUSDFixture, WrapperUnitTests {
    /// @dev Disambiguate the diamond (PUSDFixture and WrapperUnitTests both reach WrapperFixture).
    function setUp() public override(PUSDFixture, WrapperFixture) {
        PUSDFixture.setUp();
    }

    /// @dev The onramp and offramp must reference the same collateral token.
    function test_constructor_revertsOnRampMismatch() public {
        MockERC20 usdce2 = new MockERC20("USDC.e2", "USDCe2", 6);
        (,, CollateralOfframp otherOfframp) = _deployCollateralStack(usdce2);
        vm.expectRevert(PUSDERC4626Wrapper.RampCollateralTokenMismatch.selector);
        new PUSDERC4626Wrapper(
            IERC4626(address(underlyingVault)),
            ICollateralOnramp(address(onramp)),
            ICollateralOfframp(address(otherOfframp))
        );
    }

    /// @dev The vault's asset must be one of the collateral token's backing assets (USDC / USDC.e).
    function test_constructor_revertsOnWrongVaultAsset() public {
        MockERC20 other = new MockERC20("Other", "OTH", 6);
        MockERC4626 badVault = new MockERC4626(IERC20(address(other)));
        vm.expectRevert(PUSDERC4626Wrapper.UnderlyingVaultAssetIsNotValidCollateral.selector);
        new PUSDERC4626Wrapper(
            IERC4626(address(badVault)), ICollateralOnramp(address(onramp)), ICollateralOfframp(address(offramp))
        );
    }

    function test_factory_deterministicAddressAndSingleDeploy() public {
        PUSDERC4626WrapperFactory factory =
            new PUSDERC4626WrapperFactory(ICollateralOnramp(address(onramp)), ICollateralOfframp(address(offramp)));
        MockERC4626 freshVault = new MockERC4626(underlyingAsset);

        address predicted = factory.getWrapperAddress(IERC4626(address(freshVault)));
        address deployed = address(factory.deployWrapper(IERC4626(address(freshVault))));
        assertEq(deployed, predicted, "deployed at predicted address");

        vm.expectRevert(); // CREATE2 collision: one wrapper per (factory, vault)
        factory.deployWrapper(IERC4626(address(freshVault)));
    }

    function test_factory_revertsOnZeroRamp() public {
        vm.expectRevert(PUSDERC4626WrapperFactory.ZeroAddress.selector);
        new PUSDERC4626WrapperFactory(ICollateralOnramp(address(0)), ICollateralOfframp(address(offramp)));
    }
}
