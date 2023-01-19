// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.7.3;
pragma experimental ABIEncoderV2;

import "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import "forge-std/console.sol";
import {IVault} from "@balancer-labs/v2-vault/contracts/interfaces/IVault.sol";
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

    /**
     * @dev Returns this Pool's ID, used when interacting with the Vault (to e.g. join the Pool or swap with it).
     */
    function getPoolId() external view returns (bytes32);
    function getVault() external view returns (IVault);
}

interface IAaveLinearPool {

    /**
     * @dev For a Linear Pool, the rate represents the appreciation of BPT with respect to the underlying tokens. This
     * rate increases slowly as the wrapped token appreciates in value.
     */
    function getRate() external view returns (uint256);

    /**
     * @notice Return the conversion rate between the wrapped and main tokens.
     * @dev This is an 18-decimal fixed point value.
     */
    function getWrappedTokenRate() external view returns (uint256);

    /**
     * @notice Return the main token address as an IERC20.
     */
    function getMainToken() external view  returns (IERC20);
    /**
     * @dev Returns the Pool's wrapped token.
     */
    function getWrappedToken() external view returns (IERC20);

    function symbol() external view returns (string memory);

    /**
     * @dev Returns this Pool's ID, used when interacting with the Vault (to e.g. join the Pool or swap with it).
     */
    function getPoolId() external view returns (bytes32);
    function getVault() external view returns (IVault);
}

interface IERC20Extra is IERC20 {
    function symbol() external view returns (string memory);
    function decimals() external view returns (uint256);
}

interface ILendingPool {
  function getReserveData(address asset) external view returns (ReserveData memory);
}
interface IStaticATokenLM {
    /**
     * @notice Converts a static amount (scaled balance on aToken) to the aToken/underlying value,
     * using the current liquidity index on Aave
     * @param amount The amount to convert from
     * @return uint256 The dynamic amount
     **/
    function staticToDynamicAmount(uint256 amount) external view returns (uint256);

    /**
     * @notice Converts an aToken or underlying amount to the what it is denominated on the aToken as
     * scaled balance, function of the principal and the liquidity index
     * @param amount The amount to convert from
     * @return uint256 The static (scaled) amount
     **/
    function dynamicToStaticAmount(uint256 amount) external view returns (uint256);

    function rate() external view returns (uint256);
}


struct ReserveData {
  //the liquidity index. Expressed in ray
  uint128 liquidityIndex;
}

contract BbAUsdComputation is Test {

  // address of `bb-a-usd` pool
  address constant BB_A_USD_ADDY = 0xA13a9247ea42D743238089903570127DdA72fE44;

  // all the stablecoin vs USD Chainlink pairs return 8 decimals
  uint256 constant ORACLE_FEED_DECIMALS = 8;

  // Balancer pools use 18 decimals to represent `getRate` (and not only) values
  uint256 constant BASE_DECIMALS = 18;

  // mapping between the `mainToken` (eg. USDC) in a Linear Pool (eg. `bb-a-USDC`)
  // and the oracle that provides the price for that token
  mapping(address => IOracle) oracles;

  function setUp() public {
    // @todo ensure all Chainlink feeds return 8 decimals
    // @todo ensure token addresses are ERC20 compatible
    oracles[0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48] = IOracle(0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6); // USDC/USD price feed
    
    oracles[0xdAC17F958D2ee523a2206206994597C13D831ec7] = IOracle(0x3E7d1eAB13ad0104d2750B8863b489D65364e32D); // USDT/USD price feed

    oracles[0x6B175474E89094C44Da98b954EedeAC495271d0F] = IOracle(0xAed0c38402a5d19df6E4c03F4E2DceD6e29c1ee9); // DAI/USD price feed
  }

  function testPrice() public { 
    IComposableStablePool pool = IComposableStablePool(BB_A_USD_ADDY);
    uint256 rate = pool.getRate();
    console.log("rate: ", rate);
    uint256 bptIndex = pool.getBptIndex();
    console.log("bptIndex: ", bptIndex);
    bytes32 poolId = pool.getPoolId();
    IVault vault = IVault(pool.getVault());
    (
      IERC20[] memory tokens,
      uint256[] memory balances,
      /*uint256 lastChangeBlock*/
    ) = vault.getPoolTokens(poolId);

    // `getRateProviders` will return 4 addresses, one of which is a nil address
    // because the BPT token has no rate provider
    IRateProvider[] memory rateProviders = pool.getRateProviders();
    // `bb-a-usd` liquidity expressed in USD
    uint256 totalLiquidityUsd = 0;
    // @todo remove this
    uint256 totalTokenBalance = 0;
    for(uint256 i = 0; i < 4; i++) {
      if (i == bptIndex) {
        console.log("skipping bptIndex: ", bptIndex);
        continue;
      }

      // in the case of `bb-a-USD` this is an AaveLinearPool (eg. `bb-a-USDC`)
      IAaveLinearPool subPool = IAaveLinearPool(address(rateProviders[i]));
      totalLiquidityUsd += _getAaveLiearPoolPrice(subPool) * subPool.getRate() / 10**BASE_DECIMALS;
      uint256 tokenIndex = _getTokensIndex(tokens, address(subPool));
      uint256 tokenBalance = balances[tokenIndex];
      console.log("tokenBalance: ", tokenBalance);
      totalTokenBalance += tokenBalance;
    }

    console.log("totalTokenBalance: ", totalTokenBalance);
    console.log("totalLiquidityUsd: ", totalLiquidityUsd);
    console.log("@block.number: ", block.number);
  }

  function _getTokensIndex(IERC20[] memory tokens, address token) internal returns (uint256) {
    for(uint256 i = 0; i < tokens.length; i++) {
      if (address(tokens[i]) == token) {
        return i;
      }
    }
    console.log("_getTokensIndex: could not find token: ", token);
    assertTrue(false, "could not find token in tokens array");
  }

  function _getAaveLiearPoolPrice(IAaveLinearPool pool) internal view returns (uint256 rateInUsd) {
    console.log("-----------------------");
    string memory symbol = pool.symbol();
    console.log("subpool symbol: ", symbol); 
    uint256 rate = pool.getRate();
    console.log("rate: ", rate);
    // `mainToken` represents the stablecoin in the pool
    // eg. for a `bb-a-USDC` pool, `mainToken` will be USDC
    IERC20 mainToken = pool.getMainToken();
    // `wrappedToken` represents the Aave wrapped token in the pool
    // eg. for a `bb-a-USDC` pool, `wrappedToken` will be a Wrapped aUSDC token
    // uint256 wrappedTokenRate = pool.getWrappedTokenRate();
    // console.log("wrappedTokenRate: ", wrappedTokenRate);

    bytes32 poolId = pool.getPoolId();
    IVault vault = IVault(pool.getVault());
    (
      IERC20[] memory tokens,
      uint256[] memory balances,
      /*uint256 lastChangeBlock*/
    ) = vault.getPoolTokens(poolId);

    // get the price of the `mainToken` in USD (Chainlink returns the price in 1e8 for the USDC, USDT and DAI vs USD pairs)
    // @todo validate updatedAt and answeredInRound to ensure the price data is fresh
    (/*uint80 roundId*/, int256 mainTokenUsdPrice, /*uint256 startedAt*/, /*uint256 updatedAt*/,) = oracles[address(mainToken)].latestRoundData();

    for(uint256 i = 0; i < 3; i++) {
      if(address(tokens[i]) == address(pool)) {
        continue;
      }

      console.log("Token: ", IERC20Extra(address(tokens[i])).symbol(), IERC20Extra(address(tokens[i])).decimals(), address(tokens[i]));
      console.log("Balance: ", balances[i]);
      // (a)USDT, (a)USDC have 6 decimals but (a)DAI has 18
      // we use this divider to ensure that we "normalize"
      // the price to 6 decimals across the board
      uint256 decimalsDiff = 1;
      uint256 tokenDecimals = IERC20Extra(address(tokens[i])).decimals();
      if (tokenDecimals > 6) {
        decimalsDiff = 10 ** (tokenDecimals - 6);
      }

      if (address(tokens[i]) == address(mainToken)) {
        uint256 mainTokenValue = uint256(mainTokenUsdPrice) * balances[i] / 10**ORACLE_FEED_DECIMALS / decimalsDiff;
        console.log("mainTokenValue: ", mainTokenValue);
        rateInUsd += mainTokenValue;
        continue;
      }

      IStaticATokenLM aToken = IStaticATokenLM(address(pool.getWrappedToken()));
      if (address(tokens[i]) == address(aToken)) {
        // uint256 wrappedTokenRate = pool.getWrappedTokenRate();
        // console.log("wrappedTokenRate: ", wrappedTokenRate);
        // console.log("StaticATokenLM rate: ", aToken.rate());
        // uint256 wrappedTokenBalance = aToken.staticToDynamicAmount(balances[i]);
        // console.log("wrappedTokenBalance: ", wrappedTokenBalance);

        uint256 wrappedtokensValue = balances[i] * uint256(mainTokenUsdPrice) / 10**ORACLE_FEED_DECIMALS / decimalsDiff;
        console.log("wrappedtokensValue: ", wrappedtokensValue);
        rateInUsd += wrappedtokensValue;
        continue;
      }

      revert("unexpected token in pool");
    }
    
    console.log("mainTokenPrice: ", uint256(mainTokenUsdPrice));
    console.log("rateInUsd: ", rateInUsd);
  }
}

