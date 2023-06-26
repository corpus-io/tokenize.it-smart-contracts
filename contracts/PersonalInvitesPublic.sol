// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.17;

import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/metatx/ERC2771Context.sol";
import "./Token.sol";

contract PersonalInvitesPublic is ERC2771Context {
    using SafeERC20 for IERC20;

    Token public immutable token;

    struct investmentOffer {
        address currencyPayer;
        address tokenReceiver;
        uint256 tokenAmount;
        uint256 tokenPrice;
        uint256 expiration;
        IERC20 currency;
    }

    mapping(uint256 => investmentOffer) public commitments;

    uint256 public nextId = 0;

    // todo: do we want to be more dynamic with currencyReceiver?
    address public currencyReceiver;

    event Deal(
        address indexed currencyPayer,
        address indexed tokenReceiver,
        uint256 tokenAmount,
        uint256 tokenPrice,
        IERC20 currency,
        uint256 commitmentId
    );

    constructor(
        address _token,
        address _currencyReceiver,
        address _trustedForwarder
    ) ERC2771Context(_trustedForwarder) {
        token = Token(_token);
        currencyReceiver = _currencyReceiver;
    }

    // todo: add a function to cancel a commitment
    // todo: add function to reject a commitment
    // todo: add function to update currencyReceiver

    function offer(
        address _tokenReceiver,
        uint256 _tokenAmount,
        uint256 _tokenPrice,
        uint256 _expiration,
        IERC20 _currency
    ) public returns (uint256) {
        require(_tokenReceiver != address(0), "_tokenReceiver can not be zero address");
        require(_tokenPrice != 0, "_tokenPrice can not be zero");
        require(block.timestamp <= _expiration, "Deal expired");

        /* 
            commitments can only be made by the payer of the currency. Otherwise, an attacker
            could create commitments that use the allowances of other users.
        */
        commitments[nextId] = investmentOffer(
            _msgSender(),
            _tokenReceiver,
            _tokenAmount,
            _tokenPrice,
            _expiration,
            _currency
        );

        // todo: decide on where to safeguard currencies! List of acceptable currencies?

        nextId++;

        // todo: emit event with commitment id
        return nextId - 1;
    }

    function accept(uint256 _commitmentId) public {
        // _msgSender() must be a token admin. Todo: add role InviteClaimer or similar.
        require(token.hasRole(token.DEFAULT_ADMIN_ROLE(), _msgSender()), "Caller is not a token admin");

        investmentOffer memory commitment = commitments[_commitmentId];
        require(block.timestamp <= commitment.expiration, "Deal expired");

        // rounding up to the next whole number. Investor is charged up to one currency bit more in case of a fractional currency bit.
        uint256 currencyAmount = Math.ceilDiv(commitment.tokenAmount * commitment.tokenPrice, 10 ** token.decimals());

        IFeeSettingsV1 feeSettings = token.feeSettings();
        uint256 fee = feeSettings.personalInviteFee(currencyAmount);
        if (fee != 0) {
            commitment.currency.safeTransferFrom(commitment.currencyPayer, feeSettings.feeCollector(), fee);
        }
        commitment.currency.safeTransferFrom(commitment.currencyPayer, currencyReceiver, (currencyAmount - fee));

        token.mint(commitment.tokenReceiver, commitment.tokenAmount);

        commitments[_commitmentId] = investmentOffer(address(0), address(0), 0, 0, 0, IERC20(address(0)));

        emit Deal(
            commitment.currencyPayer,
            commitment.tokenReceiver,
            commitment.tokenAmount,
            commitment.tokenPrice,
            commitment.currency,
            _commitmentId
        );
    }
}
