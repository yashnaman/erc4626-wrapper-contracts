// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.34;

import {ERC4626, BaseERC4626Wrapper} from "src/BaseERC4626Wrapper.sol";
import {IERC4626} from "lib/openzeppelin-contracts/contracts/interfaces/IERC4626.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/interfaces/IERC20.sol";
import {SafeERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

import {INegRiskAdapter} from "lib/neg-risk-ctf-adapter/src/interfaces/INegRiskAdapter.sol";
import {CTHelpers} from "lib/neg-risk-ctf-adapter/src/libraries/CTHelpers.sol";
import {IConditionalTokens} from "lib/neg-risk-ctf-adapter/src/interfaces/IConditionalTokens.sol";

import {IERC1155Receiver} from "lib/openzeppelin-contracts/contracts/token/ERC1155/IERC1155Receiver.sol";
import {IERC165} from "lib/openzeppelin-contracts/contracts/interfaces/IERC165.sol";

import {IWrappedCollateral} from "src/interface/IWrappedCollateral.sol";

/// @title NegRiskERC4626Wrapper
/// @author yashnaman
/// @notice A {BaseERC4626Wrapper} whose wrapper asset is the NegRisk wrapped collateral (`wcol`). It earns yield by
/// supplying the underlying collateral (e.g. USDC.e) to the underlying vault, while letting holders stay denominated in
/// `wcol`, the token used as collateral inside NegRisk / ConditionalTokens markets.
/// @dev `wcol` cannot be minted directly (`WrappedCollateral.wrap` is restricted to the NegRiskAdapter), so wrapping
/// the underlying back into `wcol` is done by splitting through the adapter and merging back through ConditionalTokens.
contract NegRiskERC4626Wrapper is BaseERC4626Wrapper, IERC1155Receiver {
    using SafeERC20 for IERC20;

    /* ERRORS */

    /// @notice Thrown when the underlying vault's asset is not the NegRiskAdapter's unwrapped collateral.
    error UnderlyingVaultAssetIsNotUnwrappedCollateral();

    /* IMMUTABLES & CONSTANTS */

    /// @notice The NegRisk wrapped collateral (`wcol`), which is this wrapper's ERC-4626 asset.
    IWrappedCollateral public immutable WRAPPED_COLLATERAL;

    /// @notice The NegRiskAdapter used to split unwrapped collateral into outcome tokens.
    INegRiskAdapter public immutable NEG_RISK_ADAPTER;

    /// @notice The ConditionalTokens contract used to merge outcome tokens back into wrapped collateral.
    IConditionalTokens public immutable CONDITIONAL_TOKENS;

    /// @notice The parent collection id used for every position. Fixed to zero (top-level binary market).
    bytes32 public constant PARENT_COLLECTION_ID = bytes32(0);

    /// @notice The condition id whose binary split/merge the wrapper round-trips through to convert between unwrapped
    /// collateral and `wcol`.
    /// @dev Split and merge only require the condition to be prepared, never resolved, so any prepared condition works
    /// permanently. The constructor prepares a throwaway market purely to obtain such a condition deterministically,
    /// rather than trusting a caller-supplied market id.
    bytes32 public immutable CONDITION_ID;

    /* CONSTRUCTOR */

    /// @param negRiskAdapter The NegRiskAdapter whose `wcol` is wrapped and whose `col` is supplied to the vault.
    /// @param underlyingVault The underlying vault; its asset must be the adapter's unwrapped collateral (`col`).
    constructor(INegRiskAdapter negRiskAdapter, IERC4626 underlyingVault)
        BaseERC4626Wrapper(underlyingVault, IERC20(negRiskAdapter.wcol()))
    {
        NEG_RISK_ADAPTER = negRiskAdapter;
        CONDITIONAL_TOKENS = IConditionalTokens(negRiskAdapter.ctf());
        WRAPPED_COLLATERAL = IWrappedCollateral(negRiskAdapter.wcol());

        // Prepare a throwaway market to derive a permanently splittable/mergeable binary condition (oracle is the
        // adapter, outcomeCount is 2).
        bytes32 marketId = negRiskAdapter.prepareMarket(0, "");
        bytes32 questionId = negRiskAdapter.prepareQuestion(marketId, "");
        CONDITION_ID = CTHelpers.getConditionId(address(negRiskAdapter), questionId, 2);

        // The vault must hold the adapter's unwrapped collateral, since that is what the wrapper unwraps `wcol` into
        // and supplies to the vault.
        IERC20 unwrappedCollateral = IERC20(negRiskAdapter.col());
        require(underlyingVault.asset() == address(unwrappedCollateral), UnderlyingVaultAssetIsNotUnwrappedCollateral());

        // Pre-approve the adapter to pull unwrapped collateral on every split.
        unwrappedCollateral.forceApprove(address(negRiskAdapter), type(uint256).max);
    }

    /* WRAP / UNWRAP HOOKS */

    /// @dev Wraps unwrapped collateral (already held by this contract) back into `wcol`: split it into outcome tokens
    /// via the neg risk adapter, then merge those outcome tokens through ConditionalTokens, which returns `wcol`. This detour is
    /// required because `WrappedCollateral.wrap` is callable only by the neg risk adapter.
    function _wrapAndTransfer(address to, uint256 amount) internal override {
        NEG_RISK_ADAPTER.splitPosition(CONDITION_ID, amount);
        CONDITIONAL_TOKENS.mergePositions(
            address(WRAPPED_COLLATERAL), PARENT_COLLECTION_ID, CONDITION_ID, _partition(), amount
        );

        ERC4626._transferOut(to, amount);
    }

    /// @dev Unwraps `wcol` into the underlying collateral; the direct path is permissionless.
    function _unwrap(uint256 amount) internal override {
        WRAPPED_COLLATERAL.unwrap(address(this), amount);
    }

    /* INTERNAL */

    /// @dev Returns the partition for a binary conditional token: the partition [1,2] = [0b01, 0b10].
    function _partition() internal pure returns (uint256[] memory partition) {
        assembly ("memory-safe") {
            partition := mload(0x40)
            mstore(partition, 2)
            mstore(add(partition, 0x20), 1)
            mstore(add(partition, 0x40), 2)
            mstore(0x40, add(partition, 0x60))
        }
    }

    /* ERC-1155 RECEIVER */

    /// @inheritdoc IERC165
    function supportsInterface(bytes4 interfaceId) external pure override returns (bool) {
        return interfaceId == type(IERC1155Receiver).interfaceId || interfaceId == type(IERC165).interfaceId;
    }

    /// @inheritdoc IERC1155Receiver
    function onERC1155Received(address, address, uint256, uint256, bytes calldata) external pure returns (bytes4) {
        return this.onERC1155Received.selector;
    }

    /// @inheritdoc IERC1155Receiver
    function onERC1155BatchReceived(address, address, uint256[] calldata, uint256[] calldata, bytes calldata)
        external
        pure
        returns (bytes4)
    {
        return this.onERC1155BatchReceived.selector;
    }
}
