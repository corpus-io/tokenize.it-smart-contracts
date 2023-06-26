// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.17;

import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/metatx/ERC2771Context.sol";
import "./Token.sol";

contract PersonalInvitesBlind is ERC2771Context {
    using SafeERC20 for IERC20;

    Token public immutable token;

    mapping(bytes32 => address) public commitments;

    // todo: do we want to be more dynamic with currencyReceiver?
    address public currencyReceiver;

    event Deal(
        address indexed currencyPayer,
        address indexed tokenReceiver,
        uint256 tokenAmount,
        uint256 tokenPrice,
        IERC20 currency,
        bytes32 commitmentId
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

    function offer(bytes32 _bch) public {
        // changing a commitments payer is not possible for 2 reasons:
        // 1. the payer is part of the bch, so changing the payer would change the bch
        // 2. once the bch is public, 3rd parties could try to re-commit the bch with a different payer,
        //   which would result in the accept function failing
        require(commitments[_bch] == address(0), "commitment already exists");
        /* 
            commitments can only be made by the payer of the currency. Otherwise, an attacker
            could create commitments that use the allowances of other users.
        */
        commitments[_bch] = _msgSender();

        // todo: emit event with commitment id
    }

    function accept(
        bytes32 _bch,
        address _tokenReceiver,
        uint256 _tokenAmount,
        uint256 _tokenPrice,
        uint256 _expiration,
        IERC20 _currency
    ) public {
        // _msgSender() must be a token admin. Todo: add role InviteClaimer or similar.
        require(token.hasRole(token.DEFAULT_ADMIN_ROLE(), _msgSender()), "Caller is not a token admin");

        // check that the commitment exists and matches the contents provided
        require(commitments[_bch] != address(0), "commitment does not exist");
        address currencyPayer = commitments[_bch];
        // todo: add salt to hash
        require(
            _bch ==
                keccak256(
                    abi.encodePacked(currencyPayer, _tokenReceiver, _tokenAmount, _tokenPrice, _expiration, _currency)
                ),
            "commitment does not match"
        );

        require(block.timestamp <= _expiration, "Deal expired");

        // rounding up to the next whole number. Investor is charged up to one currency bit more in case of a fractional currency bit.
        uint256 currencyAmount = Math.ceilDiv(_tokenAmount * _tokenPrice, 10 ** token.decimals());

        IFeeSettingsV1 feeSettings = token.feeSettings();
        uint256 fee = feeSettings.personalInviteFee(currencyAmount);
        if (fee != 0) {
            _currency.safeTransferFrom(currencyPayer, feeSettings.feeCollector(), fee);
        }
        _currency.safeTransferFrom(currencyPayer, currencyReceiver, (currencyAmount - fee));

        token.mint(_tokenReceiver, _tokenAmount);

        commitments[_bch] = address(0);

        emit Deal(currencyPayer, _tokenReceiver, _tokenAmount, _tokenPrice, _currency, _bch);
    }
}
