// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.23;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "./Token.sol";
/**
 * @notice Contains all information necessary to execute a PrivateOffer.
 */

/**
 * @notice Contains information necessary to deploy a PrivateOffer that is selected by the seller.
 * @dev This struct does influence the address of the PrivateOffer contract.
 */
struct PrivateOfferFixedArguments {
    /// address receiving the payment in currency.
    address currencyReceiver;
    /// address holding the tokens. If 0, the token will be minted.
    address tokenHolder;
    /// minimum amount of tokens to be bought.
    uint256 minTokenAmount;
    /// maximum amount of tokens to be bought.
    uint256 maxTokenAmount;
    /// price company and investor agreed on, see docs/price.md.
    uint256 tokenPrice;
    /// timestamp after which the invitation is no longer valid.
    uint256 expiration;
    /// currency used for payment
    IERC20 currency;
    /// token to be bought
    Token token;
}

/**
 * @notice Contains information necessary to deploy a PrivateOffer that is selected by the buyer.
 * @dev This struct does not influence the address of the PrivateOffer contract.
 */
struct PrivateOfferVariableArguments {
    /// address holding the currency. Must have given sufficient allowance to this contract.
    address currencyPayer;
    /// address receiving the tokens. Must have sufficient attributes in AllowList to be able to receive tokens or the TRANSFERER role.
    address tokenReceiver;
    /// amount of tokens to buy
    uint256 tokenAmount;
}

/**
 * @title PrivateOffer
 * @author malteish, cjentzsch
 * @notice This contract represents the offer to buy an amount of tokens at a preset price. It can only be claimed once and only by a buyer who knows the offer details and salt.
 *     Some parameters of the invitation (currencyReceiver, minTokenAmount, maxTokenAmount, tokenPrice, currency, token) are immutable.
 *     Other can be changed by the buyer at the time of deployment (tokenAmount, currencyPayer, tokenReceiver).
 *     It is likely a company will create many PrivateOffers for specific investors to buy their one token.
 *     The use of cloning enables this invitation to be privacy preserving until it is accepted through granting of an allowance to the PrivateOffer's future address and deployment of the PrivateOffer.
 * @dev This contract is cloned, using a factory. That makes the future address of this contract deterministic: it can be computed from the fixed parameters of the invitation and a salt. This allows the company and buyer to grant allowances to the future address of this contract before it is deployed.
 *     The process of deploying this contract is as follows:
 *     1. Company and investor agree on the terms of the invitation (fixedArguments) and a salt (used for deployment only).
 *     2. With the help of a clone factory, the company computes the future address of the PrivateOffer contract.
 *     3. The company grants a token minting allowance or an allowance to transfer tokens from the tokenHolder to the future address of the PrivateOffer contract.
 *     4. The investor grants a currency allowance of amount*tokenPrice / 10**tokenDecimals to the future address of the PrivateOffer contract, using their currencyPayer address.
 *     5. Finally, company, buyer or anyone else deploys the PrivateOffer contract using the clone factory.
 *     Because all of the execution logic is in the initialize function, the deployment of the PrivateOffer contract is the last step. During the deployment, tokens will be
 *     minted to the buyer or transferred from the tokenHolder to the buyer, and the currency will be transferred to the company's receiver address.
 */
contract PrivateOffer is Initializable {
    using SafeERC20 for IERC20;

    /**
     * @notice Emitted when a PrivateOffer is deployed. `currencyPayer` paid for `tokenAmount` tokens at `tokenPrice` per token. The tokens were minted to `tokenReceiver`.
     *    The token is deployed at `token` and the currency is `currency`.
     * @param currencyPayer address that paid the currency
     * @param tokenReceiver address that received the tokens
     * @param tokenAmount amount of tokens that were bought
     * @param tokenPrice price company and investor agreed on, see docs/price.md.
     * @param currency currency used for payment
     * @param token contract of the token that was bought
     */
    event Deal(
        address indexed currencyPayer,
        address indexed tokenReceiver,
        uint256 tokenAmount,
        uint256 tokenPrice,
        IERC20 currency,
        Token indexed token
    );

    /**
     * @notice Disables the constructor, to make the logic contract safe for cloning.
     */
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initializes the PrivateOffer contract, executing the deal.
     * @param _fixedArguments The fixed arguments of the PrivateOffer.
     * @param _variableArguments The variable arguments of the PrivateOffer.
     */
    function initialize(
        PrivateOfferFixedArguments calldata _fixedArguments,
        PrivateOfferVariableArguments memory _variableArguments
    ) external initializer {
        require(_variableArguments.currencyPayer != address(0), "_arguments.currencyPayer can not be zero address");
        require(_variableArguments.tokenReceiver != address(0), "_arguments.tokenReceiver can not be zero address");
        require(_fixedArguments.currencyReceiver != address(0), "_arguments.currencyReceiver can not be zero address");
        require(_fixedArguments.tokenPrice != 0, "_arguments.tokenPrice can not be zero"); // a simple mint from the token contract will do in that case
        require(block.timestamp <= _fixedArguments.expiration, "Deal expired");
        require(_fixedArguments.token != Token(address(0)), "_arguments.token can not be zero address");
        require(_fixedArguments.currency != IERC20(address(0)), "_arguments.currency can not be zero address");
        require(_variableArguments.tokenAmount != 0, "_arguments.tokenAmount can not be zero");
        require(
            _fixedArguments.token.allowList().map(address(_fixedArguments.currency)) == TRUSTED_CURRENCY,
            "currency needs to be on the allowlist with TRUSTED_CURRENCY attribute"
        );
        // the next two checks also implicitly ensure that minTokenAmount <= maxTokenAmount
        require(
            _variableArguments.tokenAmount >= _fixedArguments.minTokenAmount,
            "tokenAmount is less than minTokenAmount"
        );
        require(
            _variableArguments.tokenAmount <= _fixedArguments.maxTokenAmount,
            "tokenAmount is greater than maxTokenAmount"
        );

        // rounding up to the next whole number. Investor is charged up to one currency bit more in case of a fractional currency bit.
        uint256 currencyAmount = Math.ceilDiv(
            _variableArguments.tokenAmount * _fixedArguments.tokenPrice,
            10 ** _fixedArguments.token.decimals()
        );

        IFeeSettingsV2 feeSettings = _fixedArguments.token.feeSettings();
        uint256 fee = feeSettings.privateOfferFee(currencyAmount, address(_fixedArguments.token));
        if (fee != 0) {
            _fixedArguments.currency.safeTransferFrom(
                _variableArguments.currencyPayer,
                feeSettings.privateOfferFeeCollector(address(_fixedArguments.token)),
                fee
            );
        }
        _fixedArguments.currency.safeTransferFrom(
            _variableArguments.currencyPayer,
            _fixedArguments.currencyReceiver,
            (currencyAmount - fee)
        );

        if (_fixedArguments.tokenHolder != address(0)) {
            _fixedArguments.token.transferFrom(
                _fixedArguments.tokenHolder,
                _variableArguments.tokenReceiver,
                _variableArguments.tokenAmount
            );
        } else {
            _fixedArguments.token.mint(_variableArguments.tokenReceiver, _variableArguments.tokenAmount);
        }

        emit Deal(
            _variableArguments.currencyPayer,
            _variableArguments.tokenReceiver,
            _variableArguments.tokenAmount,
            _fixedArguments.tokenPrice,
            _fixedArguments.currency,
            _fixedArguments.token
        );
        selfdestruct(payable(msg.sender));
    }
}
