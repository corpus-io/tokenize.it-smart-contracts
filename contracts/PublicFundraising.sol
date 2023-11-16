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
import "./interfaces/IPriceDynamic.sol";

/**
 * @title PublicFundraising
 * @author malteish, cjentzsch
 * @notice This contract represents the offer to buy an amount of tokens at a preset price. It can be used by anyone and there is no limit to the number of times it can be used.
 *      The buyer can decide how many tokens to buy, but has to buy at least minAmount and can buy at most maxAmount.
 *      The currency the offer is denominated in is set at creation time and can be updated later.
 *      The contract can be paused at any time by the owner, which will prevent any new deals from being made. Then, changes to the contract can be made, like changing the currency, price or requirements.
 *      The contract can be unpaused after "delay", which will allow new deals to be made again.
 *      A company will create only one PublicFundraising contract for their token.
 * @dev The contract inherits from ERC2771Context in order to be usable with Gas Station Network (GSN) https://docs.opengsn.org/faq/troubleshooting.html#my-contract-is-using-openzeppelin-how-do-i-add-gsn-support
 */
contract PublicFundraising is
    ERC2771ContextUpgradeable,
    Ownable2StepUpgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable
{
    using SafeERC20 for IERC20;

    /// @notice Minimum waiting time between pause or parameter change and unpause.
    /// @dev delay is calculated from pause or parameter change to unpause.
    uint256 public constant delay = 1 days;

    /// address that receives the currency when tokens are bought
    address public currencyReceiver;
    /// smallest amount of tokens that can be minted, in bits (bit = smallest subunit of token)
    uint256 public minAmountPerBuyer;
    /// largest amount of tokens that can be minted, in bits (bit = smallest subunit of token)
    uint256 public maxAmountPerBuyer;

    /// The price of a token, expressed as amount of bits of currency per main unit token (e.g.: 2 USDC (6 decimals) per TOK (18 decimals) => price = 2*10^6 ).
    /// @dev units: [tokenPrice] = [currency_bits]/[token], so for above example: [tokenPrice] = [USDC_bits]/[TOK]
    /// @dev priceBase is the base price, which is used if no dynamic pricing is active
    uint256 public priceBase;
    /// minimum price of a token. Limits how far the price can drop when dynamic pricing is active
    uint256 public priceMin;
    /// maximum price of a token. Limits how far the price can rise when dynamic pricing is active
    uint256 public priceMax;
    /// dynamic pricing oracle, which can implement various pricing strategies
    IPriceDynamic public priceOracle;

    /// total amount of tokens that CAN BE minted through this contract, in bits (bit = smallest subunit of token)
    uint256 public maxAmountOfTokenToBeSold;
    /// total amount of tokens that HAVE BEEN minted through this contract, in bits (bit = smallest subunit of token)
    uint256 public tokensSold;
    /// currency used to pay for the token mint. Must be ERC20, so ether can only be used as wrapped ether (WETH)
    IERC20 public currency;
    /// token to be minted
    Token public token;

    /// timestamp of the last time the contract was paused or a parameter was changed
    uint256 public coolDownStart;

    /// This mapping keeps track of how much each buyer has bought, in order to enforce maxAmountPerBuyer
    mapping(address => uint256) public tokensBought;

    /// During every buy, the lastBuyDate is checked. If it is in the past, the buy is rejected.
    /// @dev setting this to 0 disables this feature.
    uint256 public lastBuyDate;

    /// @notice CurrencyReceiver has been changed to `newCurrencyReceiver`
    /// @param newCurrencyReceiver address that receives the payment (in currency) when tokens are bought
    event CurrencyReceiverChanged(address indexed newCurrencyReceiver);
    /// @notice A buyer must at least own `newMinAmountPerBuyer` tokens after buying. If they already own more, they can buy smaller amounts than this, too.
    /// @param newMinAmountPerBuyer smallest amount of tokens a buyer can buy is allowed to own after buying.
    event MinAmountPerBuyerChanged(uint256 newMinAmountPerBuyer);
    /// @notice A buyer can buy at most `newMaxAmountPerBuyer` tokens, from this contract, even if they split the buys into multiple transactions.
    /// @param newMaxAmountPerBuyer largest amount of tokens a buyer can buy from this contract
    event MaxAmountPerBuyerChanged(uint256 newMaxAmountPerBuyer);
    /// @notice Price and currency changed.
    /// @param newTokenPrice new price of a token, expressed as amount of bits of currency per main unit token (e.g.: 2 USDC (6 decimals) per TOK (18 decimals) => price = 2*10^6 ).
    /// @param newCurrency new currency used to pay for the token purchase
    event TokenPriceAndCurrencyChanged(uint256 newTokenPrice, IERC20 indexed newCurrency);
    /// @param newMaxAmountOfTokenToBeSold new total amount of tokens that can be minted through this contract, in bits (bit = smallest subunit of token)´
    event MaxAmountOfTokenToBeSoldChanged(uint256 newMaxAmountOfTokenToBeSold);
    /**
     * @notice `buyer` bought `tokenAmount` tokens for `currencyAmount` currency.
     * @param buyer Address that bought the tokens
     * @param tokenAmount Amount of tokens bought
     * @param currencyAmount Amount of currency paid
     */
    event TokensBought(address indexed buyer, uint256 tokenAmount, uint256 currencyAmount);
    /**
     * @notice Dynamic pricing got activiated using `priceOracle` with `priceMin`as the minimum price, and `priceMax` as the maximum price.
     * @param priceOracle Oracle providing the current price through the `getPrice` function.
     * @param priceMin minimal price
     * @param priceMax maximal price
     */
    event DynamicPricingActivated(address priceOracle, uint256 priceMin, uint256 priceMax);
    /// @notice Dynamic pricing has been deactivated and priceBase is used
    event DynamicPricingDeactivated();

    /**
     * This constructor creates a logic contract that is used to clone new fundraising contracts.
     * It has no owner, and can not be used directly.
     * @param _trustedForwarder This address can execute transactions in the name of any other address
     */
    constructor(address _trustedForwarder) ERC2771ContextUpgradeable(_trustedForwarder) {
        _disableInitializers();
    }

    /**
     * @notice Sets up the PublicFundraising. The contract is usable immediately after being initialized, but does need a minting allowance for the token.
     * @param _owner Owner of the contract
     * @param _currencyReceiver address that receives the payment (in currency) when tokens are bought
     * @param _minAmountPerBuyer smallest amount of tokens a buyer is allowed to buy when buying for the first time
     * @param _maxAmountPerBuyer largest amount of tokens a buyer can buy from this contract
     * @param _tokenPrice price of a token, expressed as amount of bits of currency per main unit token (e.g.: 2 USDC (6 decimals) per TOK (18 decimals) => price = 2*10^6 ).
     * @param _maxAmountOfTokenToBeSold total amount of tokens that can be minted through this contract
     * @param _currency currency used to pay for the token mint. Must be ERC20, so ether can only be used as wrapped ether (WETH)
     * @param _token token to be sold
     */
    function initialize(
        address _owner,
        address _currencyReceiver,
        uint256 _minAmountPerBuyer,
        uint256 _maxAmountPerBuyer,
        uint256 _tokenPrice,
        uint256 _maxAmountOfTokenToBeSold,
        IERC20 _currency,
        Token _token,
        uint256 _lastBuyDate
    ) external initializer {
        require(_owner != address(0), "owner can not be zero address");
        __Ownable2Step_init(); // sets msgSender() as owner
        _transferOwnership(_owner); // sets owner as owner

        currencyReceiver = _currencyReceiver;
        minAmountPerBuyer = _minAmountPerBuyer;
        maxAmountPerBuyer = _maxAmountPerBuyer;
        priceBase = _tokenPrice;
        maxAmountOfTokenToBeSold = _maxAmountOfTokenToBeSold;
        currency = _currency;
        token = _token;
        lastBuyDate = _lastBuyDate;
        require(_currencyReceiver != address(0), "currencyReceiver can not be zero address");
        require(address(_currency) != address(0), "currency can not be zero address");
        require(address(_token) != address(0), "token can not be zero address");
        require(
            _minAmountPerBuyer <= _maxAmountPerBuyer,
            "_minAmountPerBuyer needs to be smaller or equal to _maxAmountPerBuyer"
        );
        require(_tokenPrice != 0, "_tokenPrice needs to be a non-zero amount");
        require(_maxAmountOfTokenToBeSold != 0, "_maxAmountOfTokenToBeSold needs to be larger than zero");
    }

    function activateDynamicPricing(
        IPriceDynamic _priceOracle,
        uint256 _priceMin,
        uint256 _priceMax
    ) external onlyOwner whenPaused {
        require(address(_priceOracle) != address(0), "_priceOracle can not be zero address");
        priceOracle = _priceOracle;
        require(_priceMin <= priceBase, "_priceMin needs to be smaller or equal to priceBase");
        priceMin = _priceMin;
        require(priceBase <= _priceMax, "_priceMax needs to be larger or equal to priceBase");
        priceMax = _priceMax;
        coolDownStart = block.timestamp;

        emit DynamicPricingActivated(address(_priceOracle), _priceMin, _priceMax);
    }

    function deactivateDynamicPricing() external onlyOwner whenPaused {
        priceOracle = IPriceDynamic(address(0));
        coolDownStart = block.timestamp;

        emit DynamicPricingDeactivated();
    }

    function getPrice() public view returns (uint256) {
        if (address(priceOracle) != address(0)) {
            return Math.min(Math.max(priceOracle.getPrice(priceBase), priceMin), priceMax);
        }

        return priceBase;
    }

    function _checkAndDeliver(uint256 _amount, address _tokenReceiver) internal {
        require(tokensSold + _amount <= maxAmountOfTokenToBeSold, "Not enough tokens to sell left");
        require(tokensBought[_tokenReceiver] + _amount >= minAmountPerBuyer, "Buyer needs to buy at least minAmount");
        require(
            tokensBought[_tokenReceiver] + _amount <= maxAmountPerBuyer,
            "Total amount of bought tokens needs to be lower than or equal to maxAmount"
        );

        if (lastBuyDate != 0 && block.timestamp > lastBuyDate) {
            revert("Last buy date has passed: not selling tokens anymore.");
        }

        tokensSold += _amount;
        tokensBought[_tokenReceiver] += _amount;

        token.mint(_tokenReceiver, _amount);
    }

    function _getFeeAndFeeReceiver(uint256 _currencyAmount) internal view returns (uint256, address) {
        IFeeSettingsV2 feeSettings = token.feeSettings();
        return (feeSettings.publicFundraisingFee(_currencyAmount), feeSettings.publicFundraisingFeeCollector());
    }

    /**
     * @notice Buy `amount` tokens and mint them to `_tokenReceiver`.
     * @param _amount amount of tokens to buy, in bits (smallest subunit of token)
     * @param _tokenReceiver address the tokens should be minted to
     */
    function buy(uint256 _amount, address _tokenReceiver) public whenNotPaused nonReentrant {
        // rounding up to the next whole number. Investor is charged up to one currency bit more in case of a fractional currency bit.
        uint256 currencyAmount = Math.ceilDiv(_amount * getPrice(), 10 ** token.decimals());

        (uint256 fee, address feeCollector) = _getFeeAndFeeReceiver(currencyAmount);
        if (fee != 0) {
            currency.safeTransferFrom(_msgSender(), feeCollector, fee);
        }

        currency.safeTransferFrom(_msgSender(), currencyReceiver, currencyAmount - fee);
        _checkAndDeliver(_amount, _tokenReceiver);

        emit TokensBought(_msgSender(), _amount, currencyAmount);
    }

    /// ERC 677 compatibility - TransferAndCall
    function onTokenTransfer(
        address _from,
        uint256 _currencyAmount,
        bytes calldata _data
    ) external whenNotPaused nonReentrant returns (bool) {
        require(_msgSender() == address(currency), "only the currency contract can call this function");

        // if a recipient address was provided in data, use it as receiver. Otherwise, use _from as receiver.
        address tokenReceiver;
        if (_data.length == 32) {
            tokenReceiver = abi.decode(_data, (address));
        } else {
            tokenReceiver = _from;
        }
        uint256 amount = (_currencyAmount * 10 ** token.decimals()) / getPrice();

        // move payment to currencyReceiver and feeCollector
        (uint256 fee, address feeCollector) = _getFeeAndFeeReceiver(_currencyAmount);
        currency.safeTransfer(feeCollector, fee);
        currency.safeTransfer(currencyReceiver, _currencyAmount - fee);

        _checkAndDeliver(amount, tokenReceiver);

        emit TokensBought(_from, amount, _currencyAmount);

        // return true is an antipattern, but required by the interface
        return true;
    }

    /**
     * @notice change the currencyReceiver to `_currencyReceiver`
     * @param _currencyReceiver new currencyReceiver
     */
    function setCurrencyReceiver(address _currencyReceiver) external onlyOwner whenPaused {
        require(_currencyReceiver != address(0), "receiver can not be zero address");
        currencyReceiver = _currencyReceiver;
        emit CurrencyReceiverChanged(_currencyReceiver);
        coolDownStart = block.timestamp;
    }

    /**
     * @notice change the minAmountPerBuyer to `_minAmountPerBuyer`
     * @param _minAmountPerBuyer new minAmountPerBuyer
     */
    function setMinAmountPerBuyer(uint256 _minAmountPerBuyer) external onlyOwner whenPaused {
        require(_minAmountPerBuyer <= maxAmountPerBuyer, "_minAmount needs to be smaller or equal to maxAmount");
        minAmountPerBuyer = _minAmountPerBuyer;
        emit MinAmountPerBuyerChanged(_minAmountPerBuyer);
        coolDownStart = block.timestamp;
    }

    /**
     * @notice change the maxAmountPerBuyer to `_maxAmountPerBuyer`
     * @param _maxAmountPerBuyer new maxAmountPerBuyer
     */
    function setMaxAmountPerBuyer(uint256 _maxAmountPerBuyer) external onlyOwner whenPaused {
        require(minAmountPerBuyer <= _maxAmountPerBuyer, "_maxAmount needs to be larger or equal to minAmount");
        maxAmountPerBuyer = _maxAmountPerBuyer;
        emit MaxAmountPerBuyerChanged(_maxAmountPerBuyer);
        coolDownStart = block.timestamp;
    }

    /**
     * @notice change currency to `_currency` and tokenPrice to `_tokenPrice`
     * @param _currency new currency
     * @param _tokenPrice new tokenPrice
     */
    function setCurrencyAndTokenPrice(IERC20 _currency, uint256 _tokenPrice) external onlyOwner whenPaused {
        require(address(_currency) != address(0), "currency can not be zero address");
        require(_tokenPrice != 0, "_tokenPrice needs to be a non-zero amount");
        priceBase = _tokenPrice;
        currency = _currency;
        emit TokenPriceAndCurrencyChanged(_tokenPrice, _currency);
        coolDownStart = block.timestamp;
    }

    /**
     * @notice change the maxAmountOfTokenToBeSold to `_maxAmountOfTokenToBeSold`
     * @param _maxAmountOfTokenToBeSold new maxAmountOfTokenToBeSold
     */
    function setMaxAmountOfTokenToBeSold(uint256 _maxAmountOfTokenToBeSold) external onlyOwner whenPaused {
        require(_maxAmountOfTokenToBeSold != 0, "_maxAmountOfTokenToBeSold needs to be larger than zero");
        maxAmountOfTokenToBeSold = _maxAmountOfTokenToBeSold;
        emit MaxAmountOfTokenToBeSoldChanged(_maxAmountOfTokenToBeSold);
        coolDownStart = block.timestamp;
    }

    /// set auto pause date
    function setLastBuyDate(uint256 _lastBuyDate) external onlyOwner whenPaused {
        lastBuyDate = _lastBuyDate;
        coolDownStart = block.timestamp;
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
        require(block.timestamp > coolDownStart + delay, "There needs to be at minimum one day to change parameters");
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
}
