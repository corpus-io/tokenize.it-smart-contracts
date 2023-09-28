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
 * investment. Then, they can buy tokens from a ContinuousFundraising contract.
 */
contract SwapAndBuy is ERC2771Context, Ownable2Step {
    using SafeERC20 for IERC20;

    /// The continuousFundraising contract that the investor will buy tokens from.
    ContinuousFundraising public continuousFundraising; // todo: make this obsolete by providing it in the call
    IV2SwapRouter public uniswapRouter;

    constructor(
        address trustedForwarder,
        ContinuousFundraising _continuousFundraising,
        IV2SwapRouter _uniswapRouter
    ) ERC2771Context(trustedForwarder) Ownable2Step() {
        continuousFundraising = _continuousFundraising;
        uniswapRouter = _uniswapRouter;
    }

    function swapAndBuy(
        address investorInputTokenAddress,
        address payer,
        uint256 inputTokenMaxAmount,
        uint256 tokenBuyAmount,
        address receiver
    ) external {
        // store token amount of the receiver
        uint256 receiverTokenBalance = IERC20(address(continuousFundraising.token())).balanceOf(receiver);
        // determine how much of the currency is needed to buy the tokens
        uint256 currencyNeeded = continuousFundraising.getTotalPrice(tokenBuyAmount);
        // transfer token to this contract
        IERC20(investorInputTokenAddress).safeTransferFrom(payer, address(this), inputTokenMaxAmount);
        // approve the uniswap router to spend the token
        IERC20(investorInputTokenAddress).safeApprove(address(uniswapRouter), inputTokenMaxAmount);
        // prepare the path for the swap
        address[] memory path = new address[](2);
        path[0] = investorInputTokenAddress;
        path[1] = address(continuousFundraising.currency());
        // swap the token for the currency
        uniswapRouter.swapTokensForExactTokens(currencyNeeded, inputTokenMaxAmount, path, address(this));
        // approve the continuousFundraising contract to spend the currency
        IERC20(address(continuousFundraising.currency())).safeApprove(address(continuousFundraising), currencyNeeded);
        // buy tokens from the continuousFundraising contract, placing tokens in the recipient's address
        continuousFundraising.buy(tokenBuyAmount, receiver);
        // todo: refund any remaining inputToken to the holderAddress
        //check the token balance of the receiver has increased by tokenBuyAmount
        require(
            IERC20(address(continuousFundraising.token())).balanceOf(receiver) == receiverTokenBalance + tokenBuyAmount,
            "SwapAndBuy: token balance of receiver did not increase by tokenBuyAmount"
        );
    }

    /**
     * @dev both Ownable and ERC2771Context have a _msgSender() function, so we need to override and select which one to use.
     */
    function _msgSender() internal view override(Context, ERC2771Context) returns (address) {
        return ERC2771Context._msgSender();
    }

    /**
     * @dev both Ownable and ERC2771Context have a _msgData() function, so we need to override and select which one to use.
     */
    function _msgData() internal view override(Context, ERC2771Context) returns (bytes calldata) {
        return ERC2771Context._msgData();
    }
}
