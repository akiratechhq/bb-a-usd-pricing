// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.7.6;
import {IERC20} from "@balancer-labs/v2-solidity-utils/contracts/openzeppelin/IERC20.sol";

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

    /**
     * @notice Returns the number of tokens in circulation.
     *
     * @dev In other pools, this would be the same as `totalSupply`, but since this pool pre-mints BPT and holds it in
     * the Vault as a token, we need to subtract the Vault's balance to get the total "circulating supply". Both the
     * totalSupply and Vault balance can change. If users join or exit using swaps, some of the preminted BPT are
     * exchanged, so the Vault's balance increases after joins and decreases after exits. If users call the recovery
     * mode exit function, the totalSupply can change as BPT are burned.
     */

    function getVirtualSupply() external view returns (uint256);
}
