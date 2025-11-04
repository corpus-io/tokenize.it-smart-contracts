// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.23;

import "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/metatx/ERC2771ContextUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

import "./Token.sol";

/// this struct is used to circumvent the stack too deep error that occurs when passing too many arguments to a function
struct CrowdinvestingInitializerArguments {
    /// Owner of the contract
    address owner;
    /// address that receives the payment (in currency/tokens) when tokens are bought/sold
    address receiver;
    /// smallest amount of tokens per transaction
    uint256 minAmountPerBuyer;
    /// price of a token, expressed as amount of bits of currency per main unit token (e.g.: 2 USDC (6 decimals) per TOK (18 decimals) => price = 2*10^6 ).
    uint256 tokenPrice;
    /// currency used to pay for the token purchase. Must be ERC20, so ether can only be used as wrapped ether (WETH)
    IERC20 currency;
    /// token to be transferred
    Token token;
    /// holder. Tokens/currency will be transferred from this address.
    address holder;
}

/**
 * @title Crowdinvesting
 * @author malteish, cjentzsch
 * @notice This contract represents the offer to buy an amount of tokens at a preset price. It can be used by anyone and there is no limit to the number of times it can be used.
 *      The buyer can decide how many tokens to buy, but has to buy at least minAmount.
 *      The currency the offer is denominated in is set at creation time and can be updated later.
 *      The contract can be paused at any time by the owner, which will prevent any new deals from being made. Then, changes to the contract can be made, like changing the currency, price or requirements.
 *      The contract can be unpaused, which will allow new deals to be made again.
 *      A company will create only one Crowdinvesting contract for their token.
 * @dev The contract inherits from ERC2771Context in order to be usable with Gas Station Network (GSN) https://docs.opengsn.org/faq/troubleshooting.html#my-contract-is-using-openzeppelin-how-do-i-add-gsn-support
 */
contract Crowdinvesting is
    ERC2771ContextUpgradeable,
    Ownable2StepUpgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable
{
    using SafeERC20 for IERC20;

    /// address that receives the currency/tokens when tokens are bought/sold
    address public receiver;
    /// smallest amount of tokens per transaction, in bits (bit = smallest subunit of token)
    uint256 public minAmountPerBuyer;

    /// The price of a token, expressed as amount of bits of currency per main unit token (e.g.: 2 USDC (6 decimals) per TOK (18 decimals) => price = 2*10^6 ).
    /// @dev units: [tokenPrice] = [currency_bits]/[token], so for above example: [tokenPrice] = [USDC_bits]/[TOK]
    uint256 public tokenPrice;

    /// currency used to pay for the token purchase. Must be ERC20, so ether can only be used as wrapped ether (WETH)
    IERC20 public currency;
    /// token to be transferred
    Token public token;
    /// holder. Tokens/currency will be transferred from this address.
    address public holder;

    /// @notice receiver has been changed to `newReceiver`
    /// @param newReceiver address that receives the payment (in currency/tokens) when tokens are bought/sold
    event ReceiverChanged(address indexed newReceiver);
    /// @notice A buyer must at least own `newMinAmountPerBuyer` tokens after buying. If they already own more, they can buy smaller amounts than this, too.
    /// @param newMinAmountPerBuyer smallest amount of tokens a buyer can buy is allowed to own after buying.
    event MinAmountPerBuyerChanged(uint256 newMinAmountPerBuyer);
    /// @notice Price and currency changed.
    /// @param newTokenPrice new price of a token, expressed as amount of bits of currency per main unit token (e.g.: 2 USDC (6 decimals) per TOK (18 decimals) => price = 2*10^6 ).
    /// @param newCurrency new currency used to pay for the token purchase
    event TokenPriceAndCurrencyChanged(uint256 newTokenPrice, IERC20 indexed newCurrency);
    /**
     * @notice `buyer` bought `tokenAmount` tokens for `currencyAmount` currency.
     * @param buyer Address that bought the tokens
     * @param tokenAmount Amount of tokens bought
     * @param currencyAmount Amount of currency paid
     */
    event TokensBought(address indexed buyer, uint256 tokenAmount, uint256 currencyAmount);

    /// @notice holder has been changed to `holder`
    event HolderChanged(address holder);

    /**
     * This constructor creates a logic contract that is used to clone new fundraising contracts.
     * It has no owner, and can not be used directly.
     * @param _trustedForwarder This address can execute transactions in the name of any other address
     */
    constructor(address _trustedForwarder) ERC2771ContextUpgradeable(_trustedForwarder) {
        _disableInitializers();
    }

    /**
     * @notice Sets up the Crowdinvesting. The contract is usable immediately after being initialized.
     * @param _arguments Struct containing all arguments for the initializer
     */
    function initialize(CrowdinvestingInitializerArguments memory _arguments) external initializer {
        require(_arguments.owner != address(0), "owner can not be zero address");
        __Ownable2Step_init(); // sets msgSender() as owner
        _transferOwnership(_arguments.owner); // sets owner as owner

        require(_arguments.receiver != address(0), "receiver can not be zero address");
        require(address(_arguments.currency) != address(0), "currency can not be zero address");
        require(address(_arguments.token) != address(0), "token can not be zero address");
        require(_arguments.holder != address(0), "holder can not be zero address");
        require(_arguments.minAmountPerBuyer != 0, "_minAmountPerBuyer needs to be larger than zero");
        require(_arguments.tokenPrice != 0, "_tokenPrice needs to be a non-zero amount");
        require(
            _arguments.token.allowList().map(address(_arguments.currency)) == TRUSTED_CURRENCY,
            "currency needs to be on the allowlist with TRUSTED_CURRENCY attribute"
        );
        receiver = _arguments.receiver;
        minAmountPerBuyer = _arguments.minAmountPerBuyer;
        tokenPrice = _arguments.tokenPrice;
        token = _arguments.token;
        holder = _arguments.holder;
        currency = _arguments.currency;
    }

    /**
     * Checks if the buy/sell is valid, and if so, transfers the tokens to the buyer/seller.
     * @param _from address that will send the tokens
     * @param _to address that will receive the tokens
     * @param _amount how many tokens to transfer, in bits (bit = smallest subunit of token)
     */
    function _checkAndDeliver(address _from, address _to, uint256 _amount) internal {
        require(_amount >= minAmountPerBuyer, "Buyer needs to buy at least minAmount");
        token.transferFrom(_from, _to, _amount);
    }

    function _getFeeAndFeeReceiver(uint256 _currencyAmount) internal view returns (uint256, address) {
        IFeeSettingsV2 feeSettings = token.feeSettings();
        return (
            feeSettings.crowdinvestingFee(_currencyAmount, address(token)),
            feeSettings.crowdinvestingFeeCollector(address(token))
        );
    }

    /**
     * @notice Buy `amount` tokens and mint them to `_tokenReceiver`.
     * @param _tokenAmount amount of tokens to buy, in bits (smallest subunit of token)
     * @param _maxCurrencyAmount maximum amount of currency to spend, in bits (smallest subunit of currency)
     * @param _tokenReceiver address the tokens should be minted to
     */
    function buy(
        uint256 _tokenAmount,
        uint256 _maxCurrencyAmount,
        address _tokenReceiver
    ) public whenNotPaused nonReentrant {
        // rounding up to the next whole number. Investor is charged up to one currency bit more in case of a fractional currency bit.
        uint256 currencyAmount = Math.ceilDiv(_tokenAmount * getPrice(), 10 ** token.decimals());

        require(currencyAmount <= _maxCurrencyAmount, "Purchase more expensive than _maxCurrencyAmount");

        IERC20 _currency = currency;

        (uint256 fee, address feeCollector) = _getFeeAndFeeReceiver(currencyAmount);
        if (fee != 0) {
            _currency.safeTransferFrom(_msgSender(), feeCollector, fee);
        }

        _currency.safeTransferFrom(_msgSender(), receiver, currencyAmount - fee);
        _checkAndDeliver(holder, _tokenReceiver, _tokenAmount);

        emit TokensBought(_msgSender(), _tokenAmount, currencyAmount);
    }

    /**
     * @notice Sell `amount` tokens and transfer them to `_tokenReceiver`.
     * @param _tokenAmount amount of tokens to sell, in bits (smallest subunit of token)
     * @param _minCurrencyAmount minimum amount of currency to received, in bits (smallest subunit of currency)
     * @param _currencyReceiver address the currency should be transferred to
     */
    function sell(
        uint256 _tokenAmount,
        uint256 _minCurrencyAmount,
        address _currencyReceiver
    ) public whenNotPaused nonReentrant {
        // rounding up to the next whole number. Buyer is charged up to one currency bit more in case of a fractional currency bit.
        uint256 currencyAmount = Math.ceilDiv(_tokenAmount * getPrice(), 10 ** token.decimals());

        IERC20 _currency = currency;

        (uint256 fee, address feeCollector) = _getFeeAndFeeReceiver(currencyAmount);
        if (fee != 0) {
            _currency.safeTransferFrom(holder, feeCollector, fee);
        }

        // the payout after fees needs to be at least as high as the minimum currency amount
        require(currencyAmount - fee >= _minCurrencyAmount, "Payout too low");

        // pay out the currency after fees to the token seller's _currencyReceiver address
        _currency.safeTransferFrom(holder, _currencyReceiver, currencyAmount - fee);

        // get the tokens the caller just sold to us
        _checkAndDeliver(_msgSender(), receiver, _tokenAmount);

        emit TokensBought(_msgSender(), _tokenAmount, currencyAmount);
    }

    /**
     * @notice change the receiver to `_receiver`
     * @param _receiver new receiver
     */
    function setReceiver(address _receiver) external onlyOwner whenPaused {
        require(_receiver != address(0), "receiver can not be zero address");
        receiver = _receiver;
        emit ReceiverChanged(_receiver);
    }

    /**
     * @notice change the minAmountPerBuyer to `_minAmountPerBuyer`
     * @param _minAmountPerBuyer new minAmountPerBuyer
     */
    function setMinAmountPerBuyer(uint256 _minAmountPerBuyer) external onlyOwner whenPaused {
        require(_minAmountPerBuyer != 0, "_minAmountPerBuyer needs to be larger than zero");
        minAmountPerBuyer = _minAmountPerBuyer;
        emit MinAmountPerBuyerChanged(_minAmountPerBuyer);
    }

    /**
     * @notice change currency to `_currency` and tokenPrice to `_tokenPrice`
     * @param _currency new currency
     * @param _tokenPrice new tokenPrice
     */
    function setCurrencyAndTokenPrice(IERC20 _currency, uint256 _tokenPrice) external onlyOwner whenPaused {
        require(address(_currency) != address(0), "currency can not be zero address");
        require(_tokenPrice != 0, "_tokenPrice needs to be a non-zero amount");
        require(
            token.allowList().map(address(_currency)) == TRUSTED_CURRENCY,
            "currency needs to be on the allowlist with TRUSTED_CURRENCY attribute"
        );

        tokenPrice = _tokenPrice;
        currency = _currency;
        emit TokenPriceAndCurrencyChanged(_tokenPrice, _currency);
    }

    function setHolder(address _holder) external onlyOwner whenPaused {
        require(_holder != address(0), "holder can not be zero address");
        holder = _holder;
        emit HolderChanged(_holder);
    }

    /**
     * @notice pause the contract
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @notice unpause the contract
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    /**
     * @dev both Ownable and ERC2771Context have a _msgSender() function, so we need to override and select which one to use.
     */
    function _msgSender() internal view override(ContextUpgradeable, ERC2771ContextUpgradeable) returns (address) {
        return ERC2771ContextUpgradeable._msgSender();
    }

    /**
     * @dev both Ownable and ERC2771Context have a _msgData() function, so we need to override and select which one to use.
     */
    function _msgData() internal view override(ContextUpgradeable, ERC2771ContextUpgradeable) returns (bytes calldata) {
        return ERC2771ContextUpgradeable._msgData();
    }

    /**
     * @dev both Ownable and ERC2771Context have a _contextSuffixLength() function, so we need to override and select which one to use.
     */
    function _contextSuffixLength()
        internal
        view
        virtual
        override(ContextUpgradeable, ERC2771ContextUpgradeable)
        returns (uint256)
    {
        return ERC2771ContextUpgradeable._contextSuffixLength();
    }
}
