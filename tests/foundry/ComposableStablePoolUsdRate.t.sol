// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.7.3;
pragma experimental ABIEncoderV2;

import "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import "forge-std/console.sol";
import {IERC20} from "@balancer-labs/v2-solidity-utils/contracts/openzeppelin/IERC20.sol";

import {ComposableStablePoolUsdRate} from "../../contracts/ComposableStablePoolUsdRate.sol";

contract ComposableStablePoolUsdRateTest is Test {
  // address of `bb-a-usd` pool
  address constant BB_A_USD_ADDY = 0xA13a9247ea42D743238089903570127DdA72fE44;

  address[] stablecoins;
  address[] oracles;

  // integration test
  // @todo create unit test: mock oracles and pool
  function testPrice() public {
    stablecoins = [
      0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48, // USDC
      0xdAC17F958D2ee523a2206206994597C13D831ec7, // USDT
      0x6B175474E89094C44Da98b954EedeAC495271d0F // DAI
    ];
    oracles = [
      0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6, // USDC/USD price feed
      0x3E7d1eAB13ad0104d2750B8863b489D65364e32D, // USDT/USD price feed
      0xAed0c38402a5d19df6E4c03F4E2DceD6e29c1ee9 // DAI/USD price feed
    ];

    ComposableStablePoolUsdRate b = new ComposableStablePoolUsdRate(
      BB_A_USD_ADDY, stablecoins, oracles
    );


    (uint256 totalLiquidityUsd, uint256 actualSupply, uint256 bbAUsdValue) = b.getUsdRate();
    console.log("totalLiquidityUsd: %s", totalLiquidityUsd);
    console.log("actualSupply:      %s", actualSupply);
    console.log("bbAUsdValue:       %s", bbAUsdValue);

    assertTrue(totalLiquidityUsd > 0, "totalLiquidityUsd is zero");
    assertTrue(actualSupply > 0, "actualSupply is zero");
    assertTrue(bbAUsdValue > 0, "bbAUsdValue is zero");
  }
}

