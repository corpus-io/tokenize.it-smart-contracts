// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/metatx/ERC2771Context.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";



interface MintableERC20 is IERC20Metadata {
    function mint(address, uint256) external returns (bool);
}

/**
@notice This contract represents the offer to buy an amount of tokens at a preset price. It is created for a specific buyer and can only be claimed once and only by that buyer.
    The buyer can decide how many tokens to buy, but has to buy at least minAmount and can buy at most maxAmount. The offer expires after a preset time. It can be cancelled before that time, too.
    The currency the offer is denominated in is set at creation time and can not be changed.
    It is likely a company will create many PersonalInvites for specific investors to buy their one corpusToken.

 */
contract PersonalInvite is ERC2771Context, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    // @dev: address that calls the deal function, pays with currency and receives tokens
    address payable public buyer;
    // @dev: address that receives the currency
    address payable public receiver;
    /// @dev smallest amount of tokens that can be minted, in bits (bit = smallest subunit of token)
    uint public minAmount; // in smallest subunit of token
    /// @dev largest amount of tokens that can be minted, in bits (bit = smallest subunit of token)
    uint public maxAmount; // in smallest subunit of token
    /**
     @dev amount of subunits of currency per main unit token (e.g.: 2 USDC (6 decimals) per TOK (18 decimals) => price = 2*10^6 ). 
     @dev units: [tokenPrice] = [currency_bits]/[token], so for above example: [tokenPrice] = [USDC_bits]/[TOK]
     */
    uint public tokenPrice; 
    /// @dev block.timestamp after which the invite is no longer valid
    uint public expiration;
    /// @dev currency used to pay for the token mint
    IERC20 public currency;
    /// @dev token to be minted
    MintableERC20 public token;

    event Deal(address indexed buyer, uint amount, uint tokenPrice, IERC20 indexed currency, MintableERC20 indexed token);

    constructor(address _trustedForwarder, address payable _buyer, address payable _receiver, uint _minAmount, uint _maxAmount, uint _tokenPrice, uint _expiration, IERC20 _currency, MintableERC20 _token) ERC2771Context(_trustedForwarder) {
        buyer = _buyer;
        receiver = _receiver;
        minAmount = _minAmount;
        maxAmount = _maxAmount;
        tokenPrice = _tokenPrice;
        expiration = _expiration;
        currency = _currency;
        token = _token;

        require(_buyer != address(0), "_buyer can not be zero address");
        require(_receiver != address(0), "_receiver can not be zero address");
        require(_minAmount <= _maxAmount, "_minAmount needs to be smaller or equal to _maxAmount");
        require(_tokenPrice != 0, "_tokenPrice can not be zero");
        require(_expiration > block.timestamp, "Expiration date needs to be in the future");

        // after creating the contract, it needs to be set up as minter
    }

    /**
    @notice Allows the invited investor (buyer) to buy tokens from the contract. The currency used for payment are transferred to the receiver and the tokens are minted to the buyer.
    @param _tokenAmount Amount of tokens to buy, bits (bit = smallest subunit of token). [tok_bits]
     */
    function deal(uint _tokenAmount) nonReentrant public {
        require(buyer == _msgSender(), "Only the personally invited buyer can take this deal");
        require(minAmount <= _tokenAmount && _tokenAmount <= maxAmount, "Amount needs to be inbetween minAmount and maxAmount");
        require(block.timestamp <= expiration, "Deal expired");

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
        require((_tokenAmount * tokenPrice) % (10**token.decimals()) == 0, "Amount * tokenprice needs to be a multiple of 10**token.decimals()");
        currency.safeTransferFrom(buyer, receiver, (_tokenAmount * tokenPrice) / (10**token.decimals()) );
        require(token.mint(buyer, _tokenAmount), "Minting new tokens failed");

        emit Deal(buyer, _tokenAmount, tokenPrice, currency, token);


        // gas optimizations
        
        delete buyer;
        delete receiver;
        delete minAmount;
        delete maxAmount;
        delete tokenPrice;
        delete expiration;
        delete currency;
        delete token;
        
        //selfdestruct(buyer); // this should give the caller a gas refund, but in my tests it increased the gas costs
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

    /**
     @notice Contract can be destroyed by owner, which would prevent the deal from being dealt
     @dev Can also be called at any time to help reduce ethereum state bloat.
    */
    function revoke() public onlyOwner {
        selfdestruct(buyer);
    }
}
