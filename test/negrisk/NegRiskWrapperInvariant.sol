// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {NegRiskFixture} from "test/negrisk/NegRiskFixture.sol";
import {WrapperFixture} from "test/shared/WrapperFixture.sol";
import {WrapperInvariants} from "test/shared/WrapperInvariants.sol";

/// @notice The shared wrapper invariants run against the real NegRisk stack.
contract NegRiskWrapperInvariant is NegRiskFixture, WrapperInvariants {
    function setUp() public override(NegRiskFixture, WrapperFixture) {
        NegRiskFixture.setUp();
        _initInvariant();
    }

    function _assertNoDust() internal view override(NegRiskFixture, WrapperFixture) {
        NegRiskFixture._assertNoDust();
    }
}
