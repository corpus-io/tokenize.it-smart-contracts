// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import "@openzeppelin/contracts/utils/math/Math.sol";

import "./common/TokenSwapBase.sol";

/// this struct is used to circumvent the stack too deep error that occurs when passing too many arguments to a function
struct TokenSwapInitializerArguments {
    /// Owner of the contract
    address owner;
    /// address that receives the payment (in currency/tokens) when tokens are bought/sold
    address receiver;
    /// holder. Tokens/currency will be transferred from this address.
    address holder;
    /// price of a token, expressed as amount of bits of currency per main unit token (e.g.: 2 USDC (6 decimals) per TOK (18 decimals) => price = 2*10^6 ).
    uint256 tokenPrice;
    /// currency used to pay for the token purchase. Must be ERC20, so ether can only be used as wrapped ether (WETH)
    IERC20 currency;
    /// token to be transferred
    Token token;
}

/**
 * @title TokenSwap
 * @author malteish, cjentzsch
 * @notice This contract represents the offer to buy or sell an amount of tokens at a preset price.
 *      It can be used by anyone as long as not all tokens have been bought or sold.
 *      Note that the total size of the order is determined by the allowance granted or funds available in the holder address (e.g. a buy oder
 *      will buy tokens until it can not pay the seller anymore because it ran out of allowance or holder runs out of currency).
 *      The buyer or seller can decide how many tokens to buy or sell, capped by the amount still available.
 *      The currency the offer is denominated in is set at creation time and cannot be changed.
 *      The contract can be paused at any time by the owner, which will prevent any new deals from being made.
 *      The contract can be unpaused, which will allow new deals to be made again.
 *      Contract as sell order: A token holder wanting to sell their tokens can create a TokenSwap contract with the desired price and give it an allowance to transfer their tokens.
 *          Then any party wanting to buy tokens can do so through the buy function.
 *      Contract as buy order: A party wanting to buy tokens can create a TokenSwap contract with the desired price and grant it an allowance in currency.
 *          Then any party wanting to sell tokens can do so through the sell function.
 * @dev The contract inherits from ERC2771Context in order to be usable with Gas Station Network (GSN) https://docs.opengsn.org/faq/troubleshooting.html#my-contract-is-using-openzeppelin-how-do-i-add-gsn-support
 */
contract TokenSwap is TokenSwapBase {
    using SafeERC20 for IERC20;

    /// holder. Tokens/currency will be transferred from this address.
    address public holder;

    /**
     * @notice `seller` sold `tokenAmount` tokens for `currencyAmount` currency.
     * @param seller Address that sold the tokens
     * @param tokenAmount Amount of tokens sold
     * @param currencyAmount Amount of currency received
     */
    event TokensSold(address indexed seller, uint256 tokenAmount, uint256 currencyAmount);

    /**
     * This constructor creates a logic contract that is used to clone new fundraising contracts.
     * It has no owner, and can not be used directly.
     * @param _trustedForwarder This address can execute transactions in the name of any other address
     */
    constructor(address _trustedForwarder) TokenSwapBase(_trustedForwarder) {}

    /**
     * @notice unpause the contract
     */
    function unpause() external override onlyOwner {
        _unpause();
    }

    /**
     * @notice Sets up the TokenSwap. The contract is usable immediately after being initialized.
     * @param _arguments Struct containing all arguments for the initializer
     */
    function initialize(TokenSwapInitializerArguments memory _arguments) external initializer {
        require(_arguments.tokenPrice != 0, "_tokenPrice needs to be a non-zero amount");
        _initializeBase(
            _arguments.owner,
            _arguments.tokenPrice,
            _arguments.currency,
            _arguments.token,
            _arguments.receiver
        );

        require(_arguments.holder != address(0), "holder can not be zero address");
        holder = _arguments.holder;
    }

    /**
     * @notice Buy `amount` tokens and transfer them to `_tokenReceiver`.
     * @param _tokenAmount amount of tokens to buy, in bits (smallest subunit of token)
     * @param _maxCurrencyAmount maximum amount of currency to spend, in bits (smallest subunit of currency)
     * @param _tokenReceiver address the tokens should be transferred to
     */
    function buy(
        uint256 _tokenAmount,
        uint256 _maxCurrencyAmount,
        address _tokenReceiver
    ) public whenNotPaused nonReentrant {
        // rounding up to the next whole number. Investor is charged up to one currency bit more in case of a fractional currency bit.
        uint256 currencyAmount = Math.ceilDiv(_tokenAmount * tokenPrice, 10 ** token.decimals());

        require(currencyAmount <= _maxCurrencyAmount, "Purchase more expensive than _maxCurrencyAmount");

        (uint256 fee, address feeCollector) = _getFeeAndFeeReceiver(currencyAmount);
        if (fee != 0) {
            currency.safeTransferFrom(_msgSender(), feeCollector, fee);
        }

        currency.safeTransferFrom(_msgSender(), receiver, currencyAmount - fee);
        token.transferFrom(holder, _tokenReceiver, _tokenAmount);

        emit TokensBought(_msgSender(), _tokenAmount, currencyAmount);
    }

    /**
     * @notice Sell `amount` tokens and transfer them to `_tokenReceiver`.
     * @param _tokenAmount amount of tokens to sell, in bits (smallest subunit of token)
     * @param _minCurrencyAmount minimum amount of currency to receive, in bits (smallest subunit of currency)
     * @param _currencyReceiver address the currency should be transferred to
     */
    function sell(
        uint256 _tokenAmount,
        uint256 _minCurrencyAmount,
        address _currencyReceiver
    ) public whenNotPaused nonReentrant {
        // rounding down. Seller receives at most the exact price, protecting the holder.
        uint256 currencyAmount = (_tokenAmount * tokenPrice) / (10 ** token.decimals());

        (uint256 fee, address feeCollector) = _getFeeAndFeeReceiver(currencyAmount);
        if (fee != 0) {
            currency.safeTransferFrom(holder, feeCollector, fee);
        }

        // the payout after fees needs to be at least as high as the minimum currency amount
        require(currencyAmount - fee >= _minCurrencyAmount, "Payout too low");

        // pay out the currency after fees to the token seller's _currencyReceiver address
        currency.safeTransferFrom(holder, _currencyReceiver, currencyAmount - fee);

        // get the tokens the caller just sold to us
        token.transferFrom(_msgSender(), receiver, _tokenAmount);

        emit TokensSold(_msgSender(), _tokenAmount, currencyAmount);
    }
}
