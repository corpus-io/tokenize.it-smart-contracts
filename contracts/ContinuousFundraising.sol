// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./PersonalInvite.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/metatx/ERC2771Context.sol";



/*
This contract represents the offer to buy an amount of tokens at a preset price. It can be used by anyone and there is no limit to the number of times it can be used.
The buyer can decide how many tokens to buy, but has to buy at least minAmount and can buy at most maxAmount.
The currency the offer is denominated in is set at creation time and can be updated later.
The contract can be paused at any time by the owner, which will prevent any new deals from being made. Then, changes to the contract can be made, like changing the currency, price or requirements.
The contract can be unpaused after "delay", which will allow new deals to be made again.

A company will create only one ContinuousFundraising contract for their token (or one for each currency if they want to accept multiple currencies).

The contract inherits from ERC2771Context in order to be usable with Gas Station Network (GSN) https://docs.opengsn.org/faq/troubleshooting.html#my-contract-is-using-openzeppelin-how-do-i-add-gsn-support

 */
contract ContinuousFundraising is Ownable, Pausable, ReentrancyGuard, ERC2771Context {
    /// @notice address that receives the currency when tokens are bought
    address public currencyReceiver;
    /// @notice smallest amount of tokens that can be minted, in bits (bit = smallest subunit of token)
    uint public minAmountPerBuyer;
    /// @notice largest amount of tokens that can be minted, in bits (bit = smallest subunit of token)
    uint public maxAmountPerBuyer;
    /**
     @notice amount of bits of currency per main unit token (e.g.: 2 USDC (6 decimals) per TOK (18 decimals) => price = 2*10^6 ). 
     @dev units: [tokenPrice] = [currency_bits]/[token], so for above example: [tokenPrice] = [USDC_bits]/[TOK]
     */
    uint public tokenPrice;
    /// @notice total amount of tokens that CAN BE minted through this contract, in bits (bit = smallest subunit of token)
    uint public maxAmountOfTokenToBeSold;
    /// @notice total amount of tokens that HAVE BEEN minted through this contract, in bits (bit = smallest subunit of token)
    uint public tokensSold;
    /// @notice currency used to pay for the token mint. Must be ERC20, so ether can only be used as wrapped ether (WETH)
    IERC20 public currency;
    /// @notice token to be minted
    MintableERC20 public token; 

    // delay is calculated from pause or parameter change to unpause. 
    uint public constant delay = 1 days;
    // timestamp of the last time the contract was paused
    uint public lastPause;

    // keeps track of how much each buyer has bought, in order to enforce maxAmountPerBuyer
    mapping(address => uint256) public tokensBought;

    event CurrencyReceiverChanged(address);
    event MinAmountPerBuyerChanged(uint);
    event MaxAmountPerBuyerChanged(uint);
    event TokenPriceChanged(uint);
    event MaxAmountOfTokenToBeSoldChanged(uint);
    event CurrencyChanged(IERC20);

    /**
     * @dev Constructor that passes the trusted forwarder to the ERC2771Context constructor
     */
    constructor(address _trustedForwarder, address payable _currencyReceiver, uint _minAmountPerBuyer, uint _maxAmountPerBuyer, uint _tokenPrice, uint _maxAmountOfTokenToBeSold, IERC20 _currency, MintableERC20 _token) ERC2771Context(_trustedForwarder) {
        currencyReceiver = _currencyReceiver;
        minAmountPerBuyer = _minAmountPerBuyer;
        maxAmountPerBuyer = _maxAmountPerBuyer;
        tokenPrice = _tokenPrice;
        maxAmountOfTokenToBeSold = _maxAmountOfTokenToBeSold;
        currency = _currency;
        token = _token;
        
        require(_currencyReceiver != address(0), "buyer can not be zero address");
        require(_minAmountPerBuyer <= _maxAmountPerBuyer, "_minAmount needs to be smaller or equal to _maxAmount");
        require(_tokenPrice != 0, "_tokenPrice needs to be a non-zero amount");
        require(_maxAmountOfTokenToBeSold != 0, "_maxAmountOfTokenToBeSold needs to be larger than zero");

        // after creating the contract, it needs to be set up as minter (in the token contract)
    }

    /**
     @notice buy tokens
     @param _amount amount of tokens to buy, in bits (smallest subunit of token)
     */
    function buy(uint _amount) public whenNotPaused nonReentrant returns(bool) {
        require(tokensSold + _amount <= maxAmountOfTokenToBeSold, "Not enough tokens to sell left");
        require(minAmountPerBuyer <= _amount, "Amount needs to be larger than or equal to minAmount");
         /**
        @dev To avoid rounding errors, tokenprice needs to be multiple of 10**token.decimals(). This is checked for here. 
            With:
                _tokenAmount = a * [token_bits]
                tokenPrice = p * [currency_bits]/[token]
            The currency amount is calculated as: 
                currencyAmount = _tokenAmount * tokenPrice 
                = a * p * [currency_bits]/[token] * [token_bits]  with 1 [token] = (10**token.decimals) [token_bits]
                = a * p * [currency_bits] / (10**token.decimals)
         */
        require((_amount * tokenPrice) % (10**token.decimals()) == 0, "Amount * tokenprice needs to be a multiple of 10**token.decimals()");
        require(tokensBought[_msgSender()] + _amount <= maxAmountPerBuyer, "Total amount of bought tokens needs to be lower than or equal to maxAmount");
        tokensSold += _amount;
        tokensBought[_msgSender()] += _amount;
        require(currency.transferFrom(_msgSender(), currencyReceiver,(_amount * tokenPrice) / (10**token.decimals())), "Sending defined currency tokens failed");
        require(token.mint(_msgSender(), _amount), "Minting new tokens failed");
        return true;
    }

    /**
     @notice change the currencyReceiver
     @param _currencyReceiver new currencyReceiver
     */
    function setCurrencyReceiver(address _currencyReceiver) onlyOwner whenPaused public {
        require(_currencyReceiver != address(0), "receiver can not be zero address");
        currencyReceiver = _currencyReceiver;
        emit CurrencyReceiverChanged(_currencyReceiver);
        lastPause = block.timestamp;
    }

    /**
     @notice change the minAmountPerBuyer
     @param _minAmountPerBuyer new minAmountPerBuyer
     */
    function setMinAmountPerBuyer(uint _minAmountPerBuyer) onlyOwner whenPaused public {
        require(_minAmountPerBuyer <= maxAmountPerBuyer, "_minAmount needs to be smaller or equal to maxAmount");
        minAmountPerBuyer = _minAmountPerBuyer;
        emit MinAmountPerBuyerChanged(_minAmountPerBuyer);
        lastPause = block.timestamp;
    }

    /**
     @notice change the maxAmountPerBuyer
     @param _maxAmountPerBuyer new maxAmountPerBuyer
     */
    function setMaxAmountPerBuyer(uint _maxAmountPerBuyer) onlyOwner whenPaused public {
        require(minAmountPerBuyer <= _maxAmountPerBuyer, "_maxAmount needs to be larger or equal to minAmount");
        maxAmountPerBuyer = _maxAmountPerBuyer;
        emit MaxAmountPerBuyerChanged(_maxAmountPerBuyer);
        lastPause = block.timestamp;
    }

    /**
     @notice change currency and tokenPrice
     @param _currency new currency     
     @param _tokenPrice new tokenPrice
     */
    function setCurrencyAndTokenPrice(IERC20 _currency, uint _tokenPrice) onlyOwner whenPaused public {
        require(_tokenPrice != 0, "_tokenPrice needs to be a non-zero amount");
        tokenPrice = _tokenPrice;
        emit TokenPriceChanged(_tokenPrice);
        currency = _currency;
        emit CurrencyChanged(_currency);
        lastPause = block.timestamp;
    }

    /**
     @notice change the maxAmountOfTokenToBeSold
     @param _maxAmountOfTokenToBeSold new maxAmountOfTokenToBeSold
     */
    function setMaxAmountOfTokenToBeSold(uint _maxAmountOfTokenToBeSold) onlyOwner whenPaused public {
        require(_maxAmountOfTokenToBeSold != 0, "_maxAmountOfTokenToBeSold needs to be larger than zero");
        maxAmountOfTokenToBeSold = _maxAmountOfTokenToBeSold;
        emit MaxAmountOfTokenToBeSoldChanged(_maxAmountOfTokenToBeSold);
        lastPause = block.timestamp;
    }

    /**
     @notice pause the contract
     */
    function pause() public onlyOwner {
        _pause();
        lastPause = block.timestamp;
    }

    /**
     @notice unpause the contract
     */
    function unpause() public onlyOwner {
        require(block.timestamp > lastPause + delay, "There needs to be at minumum one day to change parameters");
        _unpause();
    }
}
