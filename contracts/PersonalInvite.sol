// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./Token.sol";

/**
@notice This contract represents the offer to buy an amount of tokens at a preset price. It is created for a specific buyer and can only be claimed once and only by that buyer.
    All parameters of the invitation (buyer, amount, tokenPrice, currency, token) are immutable (see description of CREATE2).
    It is likely a company will create many PersonalInvites for specific investors to buy their one token.
    The use of CREATE2 (https://docs.openzeppelin.com/cli/2.8/deploying-with-create2) enables this invitation to be privacy preserving until it is accepted through 
    granting of an allowance to the PersonalInvite's future address and deployment of the PersonalInvite. 
@dev This contract is deployed using CREATE2 (https://docs.openzeppelin.com/cli/2.8/deploying-with-create2), using a deploy factory. That makes the future address of this contract 
    deterministic: it can be computed from the parameters of the invitation. This allows the company and buyer to grant allowances to the future address of this contract 
    before it is deployed.
    The process of deploying this contract is as follows:
    1. Company and investor agree on the terms of the invitation (buyer, amount, tokenPrice, currency, token) and a salt (used for deployment only).
    2. With the help of a deploy factory, the company computes the future address of the PersonalInvite contract.
    3. The company grants a token minting allowance of amount to the future address of the PersonalInvite contract.
    4. The buyer grants a currency allowance of amount*tokenPrice / 10**tokenDecimals to the future address of the PersonalInvite contract.
    5. Finally, company, buyer or anyone else deploys the PersonalInvite contract using the deploy factory.
    Because all of the execution logic is in the constructor, the deployment of the PersonalInvite contract is the last step. During the deployment, the newly 
    minted tokens will be transferred to the buyer and the currency will be transferred to the company's receiver address.

 */
contract PersonalInvite {
    using SafeERC20 for IERC20;

    event Deal(
        address indexed buyer,
        uint256 amount,
        uint256 tokenPrice,
        IERC20 currency,
        Token indexed token
    );

    constructor(
        address _buyer,
        address _receiver,
        uint256 _amount,
        uint256 _tokenPrice,
        uint256 _expiration,
        IERC20 _currency,
        Token _token
    ) {
        require(_buyer != address(0), "_buyer can not be zero address");
        require(_receiver != address(0), "_receiver can not be zero address");
        require(_tokenPrice != 0, "_tokenPrice can not be zero");
        require(block.timestamp <= _expiration, "Deal expired");

        // rounding up to the next whole number. Investor is charged up to one currency bit more in case of a fractional currency bit.
        uint256 currencyAmount = Math.ceilDiv(
            _amount * _tokenPrice,
            10 ** _token.decimals()
        );

        FeeSettings feeSettings = _token.feeSettings();
        uint256 fee = feeSettings.personalInviteFee(currencyAmount);
        if (fee != 0) {
            _currency.safeTransferFrom(_buyer, feeSettings.feeCollector(), fee);
        }
        _currency.safeTransferFrom(_buyer, _receiver, (currencyAmount - fee));
        _token.mint(_buyer, _amount);
        emit Deal(_buyer, _amount, _tokenPrice, _currency, _token);
    }
}
