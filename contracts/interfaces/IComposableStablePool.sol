// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.7.3;

import {IRateProvider} from "./IRateProvider.sol";

interface IComposableStablePool {
    /**
     * @dev This function returns the appreciation of BPT relative to the underlying tokens, as an 18 decimal fixed
     * point number. It is simply the ratio of the invariant to the BPT supply.
     *
     * The total supply is initialized to equal the invariant, so this value starts at one. During Pool operation the
     * invariant always grows and shrinks either proportionally to the total supply (in scenarios with no price impact,
     * e.g. proportional joins), or grows faster and shrinks more slowly than it (whenever swap fees are collected or
     * the token rates increase). Therefore, the rate is a monotonically increasing function.
     *
     * WARNING: since this function reads balances directly from the Vault, it is potentially subject to manipulation
     * via reentrancy. However, this can only happen if one of the tokens in the Pool contains some form of callback
     * behavior in the `transferFrom` function (like ERC777 tokens do). These tokens are strictly incompatible with the
     * Vault and Pool design, and are not safe to be used.
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
     * @dev Returns the effective BPT supply.
     *
     * In other pools, this would be the same as `totalSupply`, but there are two key differences here:
     *  - this pool pre-mints BPT and holds it in the Vault as a token, and as such we need to subtract the Vault's
     *    balance to get the total "circulating supply". This is called the 'virtualSupply'.
     *  - the Pool owes debt to the Protocol in the form of unminted BPT, which will be minted immediately before the
     *    next join or exit. We need to take these into account since, even if they don't yet exist, they will
     *    effectively be included in any Pool operation that involves BPT.
     *
     * In the vast majority of cases, this function should be used instead of `totalSupply()`.
     */
    function getActualSupply() external view returns (uint256);
}
