// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.17;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/metatx/ERC2771Context.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@uniswap/swap-router-contracts/contracts/interfaces/IV2SwapRouter.sol";
import "./Token.sol";
import "./ContinuousFundraising.sol";

/**
 * @title SwapAndBuy
 * @author malteish
 * @notice This contract allows an investor to swap an ERC20 token they own for the currency that is needed for
 * investment. The investment is executed in the same transaction. If any step fails, the transaction is reverted.
 * @dev One deployment can handle any number of ContinuousFundraising contracts and currencies.
 */
contract SwapAndBuy is ERC2771Context {
    using SafeERC20 for IERC20;

    IV2SwapRouter public uniswapRouter; // could be provided as a parameter in the swapAndBuy function, too

    constructor(address trustedForwarder, IV2SwapRouter _uniswapRouter) ERC2771Context(trustedForwarder) {
        uniswapRouter = _uniswapRouter;
    }

    function swapAndBuy(
        address investorInputTokenAddress,
        uint256 inputTokenMaxAmount,
        ContinuousFundraising continuousFundraising,
        uint256 tokenBuyAmount,
        address receiver
    ) external {
        /*
         * preparations
         */
        // store token amount of the receiver
        uint256 receiverTokenBalance = IERC20(address(continuousFundraising.token())).balanceOf(receiver);
        // determine how much of the currency is needed to buy the tokens
        uint256 currencyNeeded = continuousFundraising.getTotalPrice(tokenBuyAmount);
        // transfer token to this contract
        IERC20(investorInputTokenAddress).safeTransferFrom(_msgSender(), address(this), inputTokenMaxAmount);
        // approve the uniswap router to spend the token
        IERC20(investorInputTokenAddress).safeApprove(address(uniswapRouter), inputTokenMaxAmount);

        /*
         * token swap
         */
        // prepare the path for the swap
        address[] memory path = new address[](2);
        path[0] = investorInputTokenAddress;
        path[1] = address(continuousFundraising.currency());
        // swap the token for the currency
        uniswapRouter.swapTokensForExactTokens(currencyNeeded, inputTokenMaxAmount, path, address(this));

        /*
         * investment
         */
        // approve the continuousFundraising contract to spend the currency
        IERC20(address(continuousFundraising.currency())).safeApprove(address(continuousFundraising), currencyNeeded);
        // buy tokens from the continuousFundraising contract, placing tokens in the recipient's address
        continuousFundraising.buy(tokenBuyAmount, receiver);
        // todo: refund any remaining inputToken to the holderAddress

        /*
         * final check
         */
        //check the token balance of the receiver has increased by tokenBuyAmount. Revert if that is not the case.
        require(
            IERC20(address(continuousFundraising.token())).balanceOf(receiver) == receiverTokenBalance + tokenBuyAmount,
            "SwapAndBuy: token balance of receiver did not increase by tokenBuyAmount"
        );

        // todo: pay for execution using the token the investor holds through the gas station network?
    }

    /**
     * @dev both Ownable and ERC2771Context have a _msgSender() function, so we need to override and select which one to use.
     */
    function _msgSender() internal view override(ERC2771Context) returns (address) {
        return ERC2771Context._msgSender();
    }

    /**
     * @dev both Ownable and ERC2771Context have a _msgData() function, so we need to override and select which one to use.
     */
    function _msgData() internal view override(ERC2771Context) returns (bytes calldata) {
        return ERC2771Context._msgData();
    }
}
