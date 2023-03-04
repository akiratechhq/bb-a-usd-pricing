// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import '@openzeppelin/contracts/math/SafeMath.sol';
import {IOracle} from "./interfaces/IOracle.sol";
import {IComposableStablePool} from "./interfaces/IComposableStablePool.sol";
import {IAaveLinearPool} from "./interfaces/IAaveLinearPool.sol";
import {IRateProvider} from "./interfaces/IRateProvider.sol";

import {IERC20} from "@balancer-labs/v2-solidity-utils/contracts/openzeppelin/IERC20.sol";


/**
 * Given a Composable Stable Pool (CSP) formed of 3 AaveLinearPools,
 * this contract computes the price of its BPT token relative to USD.
 *
 * For each of the underlying Aave Linear Pools it computes the price
 * of their BPT token in USD:
 *
 *   `aavelp_bpt_usd_price = A_LINEARP.getRate() * CHAINLINK_ORACLE_PRICE`
 *
 * Where the `CHAINLINK_ORACLE_PRICE` is the value returned by
 * the oracle that provides the price for the `mainToken` of
 * the Linear Pool (eg. USDC for `bb-a-USDC` pool).
 *
 * The final price of the Composable Stable Pool BPT token in USD is:
 *
 * ```
 *  csp_bpt_price = (
 *    (aavelp_bpt1_usd_price * liquidity1) +
 *    (aavelp_bpt2_usd_price * liquidity2) +
 *    (aavelp_bpt3_usd_price * liquidity3)
 *  ) / CSP.getActualSupply()
 *
 * where: liquidity{1,2,3} is the `cash + managed` value of
 *   VAULT.getPoolTokenInfo(bb-a-USD.poolId, AaveLinearPool{1,2,3}.address)
 * ```
 */
contract ComposableStablePoolUsdRate is IOracle {
  using SafeMath for uint256;

  // for example `bb-a-USD`
  IComposableStablePool immutable POOL;

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
    // immutable values cannot be read during contract creation time
    // therefore we cannot use `POOL` here
    IRateProvider[] memory rateProviders = IComposableStablePool(_pool).getRateProviders();
    // `getRateProviders` will return 4 addresses, one of which is a nil address
    // because the BPT token has no rate provider
    require(rateProviders.length == len + 1, "ARG_RATE_PROVIDERS_STABLECOINS_LEN_DIFF");

    for(uint256 i = 0; i < len; i++) {
      IOracle oracle = IOracle(address(_oracles[i]));
      require(oracle.decimals() == ORACLE_FEED_DECIMALS, "ORACLE_FEED_DECIMALS");
      oracles[_stablecoins[i]] = IOracle(address(_oracles[i]));
    }
  }

  function decimals() public view override returns (uint8) {
    return uint8(BASE_DECIMALS);
  }

  function getUsdRate() public view returns (uint256 totalLiquidityUsd, uint256 actualSupply, uint256 bbAUSDVal) { 
    uint256 bptIndex = POOL.getBptIndex();
    bytes32 compPoolId = POOL.getPoolId();

    IRateProvider[] memory rateProviders = POOL.getRateProviders();
    for(uint256 i = 0; i < 4; i++) {
      if (i == bptIndex) {
        // skip bpt token
        continue;
      }

      // in the case of `bb-a-USD` this is an AaveLinearPool (eg. `bb-a-USDC`)
      address lpAddr = address(rateProviders[i]);
      IAaveLinearPool lp = IAaveLinearPool(lpAddr);
      // this will revert if the token is not part of the pool
      (
          uint256 cash,
          uint256 managed,
          /*uint256 lastChangeBlock*/,
          /*address assetManager*/
      ) = POOL.getVault().getPoolTokenInfo(compPoolId, IERC20(lpAddr));

      // This addition cannot overflow due to the Vault's balance limits.
      uint256 lpBal = cash + managed;

      uint256 subPoolBptUsdValue = _linearPoolBPTUsdValue(lp);
      totalLiquidityUsd = totalLiquidityUsd.add(
        subPoolBptUsdValue.mul(lpBal).div(10**BASE_DECIMALS)
      );
    }

    actualSupply = POOL.getActualSupply();
    bbAUSDVal = totalLiquidityUsd.mul(10**BASE_DECIMALS).div(actualSupply);
  }

  /**
   * This function is here to meet the IOracle interface spec.
   * It wraps `getUsdRate` function and returns values that can be validated
   * by the caller as if this was a Chainlink oracle feed.
   */
  function latestRoundData() external view override returns (
      uint80 roundId,
      int256 answer,
      uint256 startedAt,
      uint256 updatedAt,
      uint80 answeredInRound
    ) {
      (,, uint256 rate) = this.getUsdRate();
      // return values that can be validated by caller
      // as if this was a Chainlink oracle feed.
      return (1, int256(rate), block.timestamp, block.timestamp, 1);
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
      uint80 roundId,
      int256 mainTokenUsdPrice,
      uint256 startedAt,
      /*uint256 updatedAt*/,
      uint80 answeredInRound
    ) = oracles[address(mainToken)].latestRoundData();

    require(mainTokenUsdPrice > 0, "ORACLE_PRICE_ZERO");
    require(startedAt != 0, "ORACLE_ROUND_NOT_COMPLETE");
    // consider a price stale if it's older than 24 hours
    // @todo allow this to be configurable?
    require(startedAt + (3600 * 24) > block.timestamp , "ORACLE_STALE_PRICE");
    require(answeredInRound >= roundId, "STALE_PRICE_ROUND");

    uint256 rate = pool.getRate();
    uint256 subPoolBptUsdValue = rate.mul(uint256(mainTokenUsdPrice)).div(10**ORACLE_FEED_DECIMALS);
    return subPoolBptUsdValue;
  }
}
