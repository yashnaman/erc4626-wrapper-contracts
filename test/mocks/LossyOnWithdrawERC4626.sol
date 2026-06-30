// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.34;

import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {MockERC4626} from "test/mocks/MockERC4626.sol";

/// @title LossyOnWithdrawERC4626
/// @notice An *honest*, ERC-4626-compliant vault that skims a flat `FEE_BIPS` fee to a sink on the way out (withdraw /
/// redeem). The fee is fully reflected in `previewWithdraw` / `previewRedeem`, so the vault never over-reports what an
/// exit will yield. Used to prove the wrapper's `totalAssets` (which prices the wrapper's vault shares through
/// `previewRedeem`) stays solvent and exit-live when the underlying vault charges on withdrawal: holders simply absorb
/// the fee, and the wrapper is never left claiming more than it can pull out.
contract LossyOnWithdrawERC4626 is MockERC4626 {
    uint256 public immutable FEE_BIPS;
    address public constant FEE_SINK = address(0xFEE5);

    constructor(IERC20 _asset, uint256 feeBips) MockERC4626(_asset) {
        FEE_BIPS = feeBips;
    }

    /// @dev Gross assets leaving the pool so that, after the fee is skimmed, `netAssets` remain for the receiver.
    /// Rounds up so the fee is never under-charged.
    function _grossUp(uint256 netAssets) internal view returns (uint256) {
        return (netAssets * 10_000 + (10_000 - FEE_BIPS) - 1) / (10_000 - FEE_BIPS);
    }

    /// @dev Net assets the receiver keeps after the fee is skimmed from `grossAssets`.
    function _net(uint256 grossAssets) internal view returns (uint256) {
        return grossAssets - grossAssets * FEE_BIPS / 10_000;
    }

    /* PREVIEWS (fee-inclusive) */

    function previewRedeem(uint256 shares) external view override returns (uint256) {
        return _net(convertToAssets(shares));
    }

    function previewWithdraw(uint256 assets) external view override returns (uint256) {
        uint256 gross = _grossUp(assets);
        uint256 supply = totalSupply;
        // Round shares up so the vault never burns too few for the assets it pays out.
        return supply == 0 ? gross : (gross * supply + totalAssets() - 1) / totalAssets();
    }

    /* EXITS (skim the fee to the sink) */

    function withdraw(uint256 assets, address receiver, address owner) external override returns (uint256 shares) {
        uint256 gross = _grossUp(assets);
        uint256 supply = totalSupply;
        shares = supply == 0 ? gross : (gross * supply + totalAssets() - 1) / totalAssets();
        _spendShares(owner, shares);
        require(asset_.transfer(receiver, assets), "transfer failed");
        if (gross > assets) require(asset_.transfer(FEE_SINK, gross - assets), "fee transfer failed");
        emit Withdraw(msg.sender, receiver, owner, assets, shares);
    }

    function redeem(uint256 shares, address receiver, address owner) external override returns (uint256 assets) {
        uint256 gross = convertToAssets(shares);
        assets = _net(gross);
        _spendShares(owner, shares);
        require(asset_.transfer(receiver, assets), "transfer failed");
        if (gross > assets) require(asset_.transfer(FEE_SINK, gross - assets), "fee transfer failed");
        emit Withdraw(msg.sender, receiver, owner, assets, shares);
    }
}
