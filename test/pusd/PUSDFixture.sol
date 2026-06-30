// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {WrapperFixture} from "test/shared/WrapperFixture.sol";
import {IERC20} from "lib/forge-std/src/interfaces/IERC20.sol";
import {IERC4626} from "lib/openzeppelin-contracts/contracts/interfaces/IERC4626.sol";

import {MockERC20} from "test/mocks/MockERC20.sol";
import {MockERC4626} from "test/mocks/MockERC4626.sol";

import {PUSDERC4626Wrapper} from "src/PUSDERC4626Wrapper.sol";
import {ICollateralOnramp, ICollateralOfframp} from "src/interface/IPolyCollateral.sol";

import {CollateralToken} from "lib/ctf-exchange-v2/src/collateral/CollateralToken.sol";
import {CollateralOnramp} from "lib/ctf-exchange-v2/src/collateral/CollateralOnramp.sol";
import {CollateralOfframp} from "lib/ctf-exchange-v2/src/collateral/CollateralOfframp.sol";
import {LibClone} from "lib/ctf-exchange-v2/lib/solady/src/utils/LibClone.sol";

/// @title PUSDFixture
/// @notice Deploys a real, local Polymarket collateral stack (the pUSD CollateralToken behind its UUPS proxy + the
/// permissionless on/off ramps), with the backing-asset custodian modelled as an EOA that approves the collateral
/// token, and implements the {WrapperFixture} hooks against it. The wrap/unwrap legs are exercised for real. Shared by
/// the unit and invariant suites.
abstract contract PUSDFixture is WrapperFixture {
    address internal constant VAULT_EOA = address(0xC0FFEE);

    CollateralToken internal pusd;
    CollateralOnramp internal onramp;
    CollateralOfframp internal offramp;

    function setUp() public virtual override {
        super.setUp();

        MockERC20 usdce = new MockERC20("USDC.e", "USDCe", 6);
        (pusd, onramp, offramp) = _deployCollateralStack(usdce);

        // The backing-asset custodian (an EOA here) must let the collateral token pull on unwrap.
        vm.prank(VAULT_EOA);
        usdce.approve(address(pusd), type(uint256).max);

        underlyingAsset = IERC20(address(usdce));
        underlyingVault = new MockERC4626(IERC20(address(usdce)));
        wrapperAsset = IERC20(address(pusd));
        wrapper = _deployWrapperOverVault(IERC4626(address(underlyingVault)));
    }

    /* ---------------------------------------------------------------------- */
    /*                                 HOOKS                                  */
    /* ---------------------------------------------------------------------- */

    function _deployWrapperOverVault(IERC4626 vault) internal override returns (IERC4626) {
        return IERC4626(
            address(
                new PUSDERC4626Wrapper(vault, ICollateralOnramp(address(onramp)), ICollateralOfframp(address(offramp)))
            )
        );
    }

    /// @dev Mint pUSD by wrapping freshly-minted USDC.e through the real onramp (which routes the backing to the vault).
    function _giveWrapperAsset(address to, uint256 amount) internal override {
        MockERC20(address(underlyingAsset)).mint(to, amount);
        vm.startPrank(to);
        underlyingAsset.approve(address(onramp), amount);
        onramp.wrap(address(underlyingAsset), to, amount);
        vm.stopPrank();
    }

    /* ---------------------------------------------------------------------- */
    /*                                 HELPERS                                */
    /* ---------------------------------------------------------------------- */

    /// @dev Deploy a full pUSD collateral stack backed by `backing` (used for both USDC and USDC.e slots), owned by
    /// this fixture, with both ramps granted the wrapper role.
    function _deployCollateralStack(MockERC20 backing)
        internal
        returns (CollateralToken token, CollateralOnramp on, CollateralOfframp off)
    {
        CollateralToken impl = new CollateralToken(address(backing), address(backing), VAULT_EOA);
        token = CollateralToken(LibClone.deployERC1967(address(impl)));
        token.initialize(address(this));

        on = new CollateralOnramp(address(this), address(this), address(token));
        off = new CollateralOfframp(address(this), address(this), address(token));
        token.addWrapper(address(on));
        token.addWrapper(address(off));
    }
}
