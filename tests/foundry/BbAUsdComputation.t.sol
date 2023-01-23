// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.7.3;
pragma experimental ABIEncoderV2;

import "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import "forge-std/console.sol";
import {IERC20} from "@balancer-labs/v2-solidity-utils/contracts/openzeppelin/IERC20.sol";

import {BbAUsdComputation} from "../../src/BbAUsdComputation.sol";


contract BbAUsdComputationTest is Test {
  BbAUsdComputation b;

  function setUp() public {
    b = new BbAUsdComputation();
  }

  function testPrice() public { 
    (uint256 totalLiquidityUsd, uint256 actualSupply, uint256 bbAUsdValue) = b.getUsdRate();
    console.log("totalLiquidityUsd: %s", totalLiquidityUsd);
    console.log("actualSupply:      %s", actualSupply);
    console.log("bbAUsdValue:       %s", bbAUsdValue);
  }
}

