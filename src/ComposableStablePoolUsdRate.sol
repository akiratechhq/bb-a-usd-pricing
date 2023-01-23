// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.7.3;
pragma experimental ABIEncoderV2;

import {IERC20} from "@balancer-labs/v2-solidity-utils/contracts/openzeppelin/IERC20.sol";
// @todo remove
// import "forge-std/console.sol";

interface IOracle {
    function latestRoundData()
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        );
}

// @todo move into its own Interface file
interface IRateProvider {
    /**
     * @dev Returns an 18 decimal fixed point number that is the exchange rate of the token to some other underlying
     * token. The meaning of this rate depends on the context.
     */
    function getRate() external view returns (uint256);
}

interface IComposableStablePool {
    /**
     * @dev Returns an 18 decimal fixed point number that is the exchange rate of the token to some other underlying
     * token. The meaning of this rate depends on the context.
     */
    function getRate() external view returns (uint256);

    /**
     * @dev Returns the index of the Pool's BPT in the Pool tokens array (as returned by IVault.getPoolTokens).
     */
    function getBptIndex() external view returns (uint256);

        /**
     * @dev Returns the rate provider for each of the Pool's tokens. A zero-address entry means there's no rate provider
     * for that token.
     */
    function getRateProviders() external view returns (IRateProvider[] memory);

    function getActualSupply() external view returns (uint256);
}

interface IAaveLinearPool {

    /**
     * @dev For a Linear Pool, the rate represents the appreciation of BPT with respect to the underlying tokens. This
     * rate increases slowly as the wrapped token appreciates in value.
     */
    function getRate() external view returns (uint256);

    /**
     * @notice Return the main token address as an IERC20.
     */
    function getMainToken() external view  returns (IERC20);

    function getVirtualSupply() external view returns (uint256);
}


contract ComposableStablePoolUsdRate {

  IComposableStablePool immutable  POOL;

  // all the stablecoin vs USD Chainlink pairs return 8 decimals
  uint256 constant ORACLE_FEED_DECIMALS = 8;

  // Balancer pools use 18 decimals to represent `getRate` (and not only) values
  uint256 constant BASE_DECIMALS = 18;

  // mapping between the `mainToken` (eg. USDC) in a Linear Pool (eg. `bb-a-USDC`)
  // and the oracle that provides the price for that token
  mapping(address => IOracle) oracles;

  constructor(address _pool, address[] memory _stablecoins, address[] memory _oracles) {
    uint256 len = _stablecoins.length;
    // @todo use Errors lib
    require(_stablecoins.length == _oracles.length, "_stablecoins and _oracles must be the same length");
    require(len > 0, "_stablecoins and _oracles must be non-empty");
    require(_pool != address(0), "_pool address cannot be 0");
    POOL = IComposableStablePool(_pool);
    // @todo ensure all Chainlink feeds return 8 decimals
    // @todo ensure token addresses are ERC20 compatible
    for(uint256 i = 0; i < len; i++) {
      oracles[_stablecoins[i]] = IOracle(address(_oracles[i]));
    }
  }

  function getUsdRate() public view returns (uint256 totalLiquidityUsd, uint256 actualSupply, uint256 bbAUSDVal) { 
    uint256 bptIndex = POOL.getBptIndex();

    // `getRateProviders` will return 4 addresses, one of which is a nil address
    // because the BPT token has no rate provider
    IRateProvider[] memory rateProviders = POOL.getRateProviders();
    for(uint256 i = 0; i < 4; i++) {
      if (i == bptIndex) {
        // console.log("skipping bptIndex: ", bptIndex);
        continue;
      }

      // in the case of `bb-a-USD` this is an AaveLinearPool (eg. `bb-a-USDC`)
      IAaveLinearPool linearPool = IAaveLinearPool(address(rateProviders[i]));
      uint256 subPoolBptUsdValue = _linearPoolUsdValue(linearPool);
      totalLiquidityUsd += subPoolBptUsdValue * linearPool.getVirtualSupply() / 10**BASE_DECIMALS;
    }

    // @todo can getActualSupply be manipulated?
    actualSupply = POOL.getActualSupply();
    bbAUSDVal = totalLiquidityUsd * 10**BASE_DECIMALS / actualSupply;
  }


  /**
   * `mainToken` is the underlying token (stablecoin) and the wrapped token
   * is an Aave wrapped token which is 1:1 with the underlying token.
   * We can use `getRate` vs the usd price of the underlying token
   * to get the usd value of the BPT token.
   **/
  function _linearPoolUsdValue(IAaveLinearPool pool) internal view returns (uint256) {
    IERC20 mainToken = pool.getMainToken();
    // get the price of the `mainToken` in USD
    // (Chainlink returns the price in 1e8 for the USDC, USDT and DAI vs USD pairs)
    // @todo validate updatedAt and answeredInRound to ensure the price data is fresh
    (/*uint80 roundId*/,
    int256 mainTokenUsdPrice,
    /*uint256 startedAt*/,
    /*uint256 updatedAt*/,) = oracles[address(mainToken)].latestRoundData();

    // @todo can `getRate` be manipulated within the same block?
    uint256 rate = pool.getRate();
    uint256 subPoolBptUsdValue = rate * uint256(mainTokenUsdPrice) / 10**ORACLE_FEED_DECIMALS;
    return subPoolBptUsdValue;
  }
}

