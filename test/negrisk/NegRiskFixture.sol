// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {WrapperFixture} from "test/shared/WrapperFixture.sol";
import {IERC20} from "lib/forge-std/src/interfaces/IERC20.sol";
import {IERC4626} from "lib/openzeppelin-contracts/contracts/interfaces/IERC4626.sol";
import {IERC1155Receiver} from "lib/openzeppelin-contracts/contracts/token/ERC1155/IERC1155Receiver.sol";
import {IERC165} from "lib/openzeppelin-contracts/contracts/interfaces/IERC165.sol";

import {MockERC20} from "test/mocks/MockERC20.sol";
import {MockERC4626} from "test/mocks/MockERC4626.sol";

import {NegRiskERC4626Wrapper} from "src/NegRiskERC4626Wrapper.sol";
import {INegRiskAdapter} from "lib/neg-risk-ctf-adapter/src/interfaces/INegRiskAdapter.sol";
import {IConditionalTokens} from "lib/neg-risk-ctf-adapter/src/interfaces/IConditionalTokens.sol";

/// @title NegRiskFixture
/// @notice Deploys a real, local NegRisk stack (Gnosis ConditionalTokens + NegRiskAdapter + its WrappedCollateral) and
/// implements the {WrapperFixture} hooks against it. The wrap leg — split through the adapter, merge back through
/// ConditionalTokens — is exercised for real, so the dust check also covers the conditional-token position ids. Shared
/// by the unit and invariant suites.
abstract contract NegRiskFixture is WrapperFixture, IERC1155Receiver {
    address internal constant VAULT_EOA = address(0xC0FFEE);

    IConditionalTokens internal ct;
    INegRiskAdapter internal neg;
    bytes32 internal conditionId;
    uint256 internal yesPositionId;
    uint256 internal noPositionId;

    function setUp() public virtual override {
        super.setUp();

        ct = IConditionalTokens(_deployConditionalTokens());
        MockERC20 col = new MockERC20("Collateral", "COL", 6);
        neg = INegRiskAdapter(
            vm.deployCode("NegRiskAdapter.sol:NegRiskAdapter", abi.encode(ct, address(col), VAULT_EOA))
        );

        underlyingAsset = IERC20(address(col));
        underlyingVault = new MockERC4626(IERC20(address(col)));
        wrapperAsset = IERC20(neg.wcol());
        wrapper = _deployWrapperOverVault(IERC4626(address(underlyingVault)));

        conditionId = NegRiskERC4626Wrapper(address(wrapper)).CONDITION_ID();
        yesPositionId = ct.getPositionId(neg.wcol(), ct.getCollectionId(bytes32(0), conditionId, 1));
        noPositionId = ct.getPositionId(neg.wcol(), ct.getCollectionId(bytes32(0), conditionId, 2));
    }

    /* ---------------------------------------------------------------------- */
    /*                                 HOOKS                                  */
    /* ---------------------------------------------------------------------- */

    function _deployWrapperOverVault(IERC4626 vault) internal override returns (IERC4626) {
        return IERC4626(address(new NegRiskERC4626Wrapper(neg, vault)));
    }

    /// @dev Mint `wcol` the legitimate way: split fresh collateral into outcome tokens through the adapter, merge them
    /// back into `wcol` through ConditionalTokens (the same round-trip the wrapper's wrap leg uses), then hand it over.
    function _giveWrapperAsset(address to, uint256 amount) internal override {
        MockERC20(address(underlyingAsset)).mint(address(this), amount);
        underlyingAsset.approve(address(neg), amount);
        neg.splitPosition(conditionId, amount);
        ct.mergePositions(neg.wcol(), bytes32(0), conditionId, _partition(), amount);
        wrapperAsset.transfer(to, amount);
    }

    /// @dev Extend the dust check: the wrap leg must never leave outcome tokens stranded on the wrapper.
    function _assertNoDust() internal view virtual override {
        super._assertNoDust();
        assertEq(ct.balanceOf(address(wrapper), yesPositionId), 0, "YES position dust");
        assertEq(ct.balanceOf(address(wrapper), noPositionId), 0, "NO position dust");
    }

    /* ---------------------------------------------------------------------- */
    /*                                 HELPERS                                */
    /* ---------------------------------------------------------------------- */

    function _deployConditionalTokens() internal returns (address addr) {
        bytes memory code = vm.getCode("lib/neg-risk-ctf-adapter/artifacts/ConditionalTokens.json");
        assembly {
            addr := create(0, add(code, 0x20), mload(code))
        }
        require(addr != address(0), "CT deploy failed");
    }

    function _partition() internal pure returns (uint256[] memory partition) {
        partition = new uint256[](2);
        partition[0] = 1;
        partition[1] = 2;
    }

    /* ERC-1155 RECEIVER (the fixture receives outcome tokens while seeding wcol) */

    function onERC1155Received(address, address, uint256, uint256, bytes calldata) external pure returns (bytes4) {
        return this.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(address, address, uint256[] calldata, uint256[] calldata, bytes calldata)
        external
        pure
        returns (bytes4)
    {
        return this.onERC1155BatchReceived.selector;
    }

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == type(IERC1155Receiver).interfaceId || interfaceId == type(IERC165).interfaceId;
    }
}
