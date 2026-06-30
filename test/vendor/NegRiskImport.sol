// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

// This file exists only to force Foundry to compile the real NegRiskAdapter (Solidity 0.8.19) into an artifact so the
// 0.8.34 tests can deploy it via `vm.deployCode` without importing it (which would clash on the pinned compiler
// version). Mirrors the CTImport.sol pattern used for the 0.5.x ConditionalTokens.
import {NegRiskAdapter} from "lib/neg-risk-ctf-adapter/src/NegRiskAdapter.sol";
