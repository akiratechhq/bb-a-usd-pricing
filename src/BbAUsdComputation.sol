// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.7.3;
pragma experimental ABIEncoderV2;

import {IERC20} from "@balancer-labs/v2-solidity-utils/contracts/openzeppelin/IERC20.sol";


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


contract BbAUsdComputation {

  // address of `bb-a-usd` pool
  address constant BB_A_USD_ADDY = 0xA13a9247ea42D743238089903570127DdA72fE44;

  // all the stablecoin vs USD Chainlink pairs return 8 decimals
  uint256 constant ORACLE_FEED_DECIMALS = 8;

  // Balancer pools use 18 decimals to represent `getRate` (and not only) values
  uint256 constant BASE_DECIMALS = 18;

  // mapping between the `mainToken` (eg. USDC) in a Linear Pool (eg. `bb-a-USDC`)
  // and the oracle that provides the price for that token
  mapping(address => IOracle) oracles;

  // @todo allow passing in the oracle feeds for the stablecoins
  constructor() public {
    // @todo ensure all Chainlink feeds return 8 decimals
    // @todo ensure token addresses are ERC20 compatible
    oracles[0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48] = IOracle(0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6); // USDC/USD price feed
    
    oracles[0xdAC17F958D2ee523a2206206994597C13D831ec7] = IOracle(0x3E7d1eAB13ad0104d2750B8863b489D65364e32D); // USDT/USD price feed

    oracles[0x6B175474E89094C44Da98b954EedeAC495271d0F] = IOracle(0xAed0c38402a5d19df6E4c03F4E2DceD6e29c1ee9); // DAI/USD price feed
  }

  function getUsdRate() public view returns (uint256 totalLiquidityUsd, uint256 actualSupply, uint256 bbAUSDVal) { 
    IComposableStablePool pool = IComposableStablePool(BB_A_USD_ADDY);
    uint256 bptIndex = pool.getBptIndex();

    // `getRateProviders` will return 4 addresses, one of which is a nil address
    // because the BPT token has no rate provider
    IRateProvider[] memory rateProviders = pool.getRateProviders();
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
    actualSupply = pool.getActualSupply();
    bbAUSDVal = totalLiquidityUsd * 10**BASE_DECIMALS / actualSupply;

    // console.log("totalLiquidityUsd: ", totalLiquidityUsd);
    // console.log("actualSupply: ", actualSupply);
    // console.log("bbAUSDVal: ", bbAUSDVal);
    // console.log("@block.number: ", block.number);
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

