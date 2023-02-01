// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import {IOracle} from "./interfaces/IOracle.sol";
import {IComposableStablePool} from "./interfaces/IComposableStablePool.sol";
import {IAaveLinearPool} from "./interfaces/IAaveLinearPool.sol";
import {IRateProvider} from "./interfaces/IRateProvider.sol";
import {IComposableStablePoolUsdRate} from "./interfaces/IComposableStablePoolUsdRate.sol";

import {IERC20} from "@balancer-labs/v2-solidity-utils/contracts/openzeppelin/IERC20.sol";


contract ComposableStablePoolUsdRate is IComposableStablePoolUsdRate {
  IComposableStablePool immutable  POOL;

  // all the stablecoin vs USD Chainlink pairs return 8 decimals
  uint256 constant ORACLE_FEED_DECIMALS = 8;

  // Balancer pools use 18 decimals to represent `getRate` (and not only) values
  uint256 constant BASE_DECIMALS = 18;

  // mapping between the `mainToken` (eg. USDC) in a Linear Pool
  // and the oracle that provides the price for that token
  mapping(address => IOracle) oracles;

  constructor(address _pool, address[] memory _stablecoins, address[] memory _oracles) {
    require(_stablecoins.length == _oracles.length, "ARG_LEN_DIFF");
    uint256 len = _stablecoins.length;
    require(len > 0, "ARG_LEN_NIL");
    require(_pool != address(0), "ARG_POOL_NIL");

    POOL = IComposableStablePool(_pool);
    for(uint256 i = 0; i < len; i++) {
      IOracle oracle = IOracle(address(_oracles[i]));
      require(oracle.decimals() == ORACLE_FEED_DECIMALS, "ORACLE_FEED_DECIMALS");
      oracles[_stablecoins[i]] = IOracle(address(_oracles[i]));
    }
  }

  function decimals() public view override returns (uint8) {
    return uint8(BASE_DECIMALS);
  }


  function getUsdRate() public view override returns (uint256 totalLiquidityUsd, uint256 actualSupply, uint256 bbAUSDVal) { 
    uint256 bptIndex = POOL.getBptIndex();

    // `getRateProviders` will return 4 addresses, one of which is a nil address
    // because the BPT token has no rate provider
    IRateProvider[] memory rateProviders = POOL.getRateProviders();
    for(uint256 i = 0; i < 4; i++) {
      if (i == bptIndex) {
        // skip bpt token
        continue;
      }

      // in the case of `bb-a-USD` this is an AaveLinearPool (eg. `bb-a-USDC`)
      IAaveLinearPool linearPool = IAaveLinearPool(address(rateProviders[i]));
      uint256 subPoolBptUsdValue = _linearPoolBPTUsdValue(linearPool);
      totalLiquidityUsd += subPoolBptUsdValue * linearPool.getVirtualSupply() / 10**BASE_DECIMALS;
    }

    // @todo can getActualSupply be manipulated?
    actualSupply = POOL.getActualSupply();
    bbAUSDVal = totalLiquidityUsd * 10**BASE_DECIMALS / actualSupply;
  }
  function latestRoundData() external view override returns (
      uint80 roundId,
      int256 answer,
      uint256 startedAt,
      uint256 updatedAt,
      uint80 answeredInRound
    ) {
      (,,bbAUSDVal) = this.getUsdRate();
      return (0, int256(bbAUSDVal), 0, 0, 0);
    }

  /**
   * `mainToken` is the underlying token (stablecoin) and the wrapped token
   * is an Aave wrapped token which is 1:1 to the underlying token.
   * We can use `getRate` vs the usd price of the underlying token
   * to get the usd value of the BPT token.
   **/
  function _linearPoolBPTUsdValue(IAaveLinearPool pool) internal view returns (uint256) {
    IERC20 mainToken = pool.getMainToken();
    // get the price of the `mainToken` in USD
    // Chainlink returns the price in 1e8 for the USDC, USDT and DAI vs USD pairs
    (
      /*uint80 roundId*/,
      int256 mainTokenUsdPrice,
      uint256 startedAt,
      /*uint256 updatedAt*/,
    ) = oracles[address(mainToken)].latestRoundData();
    require(mainTokenUsdPrice > 0, "ORACLE_PRICE_ZERO");
    require(startedAt != 0, "ORACLE_ROUND_NOT_COMPLETE");
    // consider a price stale if it's older than 24 hours
    // @todo allow this to be configurable?
    require(block.timestamp <= startedAt + (3600 * 24), "ORACLE_STALE_PRICE");

    // @todo can `getRate` be manipulated within the same block?
    uint256 rate = pool.getRate();
    uint256 subPoolBptUsdValue = rate * uint256(mainTokenUsdPrice) / 10**ORACLE_FEED_DECIMALS;
    return subPoolBptUsdValue;
  }
}

