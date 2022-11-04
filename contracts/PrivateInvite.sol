// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

interface MintableERC20 is IERC20Metadata {
    function mint(address, uint256) external returns (bool);
}

/**
@notice This contract represents the offer to buy an amount of tokens at a preset price. It is created for a specific buyer and can only be claimed once and only by that buyer.
    The buyer can decide how many tokens to buy, but has to buy at least minAmount and can buy at most maxAmount. The offer expires after a preset time. It can be cancelled before that time, too.
    The currency the offer is denominated in is set at creation time and can not be changed.
    It is likely a company will create many PersonalInvites for specific investors to buy their one corpusToken.

 */
contract PrivateInvite {

    using SafeERC20 for IERC20;

    event Deal(address indexed buyer, uint amount, uint tokenPrice, IERC20 currency, MintableERC20 indexed token);

    constructor(address payable _buyer, address payable _receiver, uint _amount, uint _tokenPrice, uint _expiration, IERC20 _currency, MintableERC20 _token) {
        
        require(_buyer != address(0), "_buyer can not be zero address");
        require(_receiver != address(0), "_receiver can not be zero address");
        require(_tokenPrice != 0, "_tokenPrice can not be zero");
        require(block.timestamp <= _expiration, "Deal expired");

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
        require((_amount * _tokenPrice) % (10**_token.decimals()) == 0, "Amount * tokenprice needs to be a multiple of 10**token.decimals()");
        _currency.safeTransferFrom(_buyer, _receiver, (_amount * _tokenPrice) / (10**_token.decimals()) );
        require(_token.mint(_buyer, _amount), "Minting new tokens failed");

        emit Deal(_buyer, _amount, _tokenPrice, _currency, _token);
    }
}
