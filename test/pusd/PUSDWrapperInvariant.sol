// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {PUSDFixture} from "test/pusd/PUSDFixture.sol";
import {WrapperFixture} from "test/shared/WrapperFixture.sol";
import {WrapperInvariants} from "test/shared/WrapperInvariants.sol";

/// @notice The shared wrapper invariants run against the real pUSD collateral stack.
contract PUSDWrapperInvariant is PUSDFixture, WrapperInvariants {
    function setUp() public override(PUSDFixture, WrapperFixture) {
        PUSDFixture.setUp();
        _initInvariant();
    }
}
