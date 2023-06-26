// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.13;

import "../lib/forge-std/src/Test.sol";
import "../contracts/Token.sol";
import "../contracts/PersonalInvite.sol";
import "../contracts/PersonalInvitesBlind.sol";
import "../contracts/PersonalInviteFactory.sol";
import "../contracts/FeeSettings.sol";
import "./resources/FakePaymentToken.sol";

contract PersonalInvitesBlindTest is Test {
    event Deal(
        address indexed currencyPayer,
        address indexed tokenReceiver,
        uint256 tokenAmount,
        uint256 tokenPrice,
        IERC20 currency,
        Token indexed token
    );

    PersonalInviteFactory factory;

    AllowList list;
    FeeSettings feeSettings;
    Token token;
    FakePaymentToken currency;

    PersonalInvitesBlind personalInvites;

    uint256 MAX_INT = type(uint256).max;

    address public constant admin = 0x0109709eCFa91a80626FF3989D68f67f5b1dD120;
    address public constant tokenReceiver = 0x1109709ecFA91a80626ff3989D68f67F5B1Dd121;
    address public constant mintAllower = 0x2109709EcFa91a80626Ff3989d68F67F5B1Dd122;
    address public constant currencyPayer = 0x3109709ECfA91A80626fF3989D68f67F5B1Dd123;
    address public constant owner = 0x6109709EcFA91A80626FF3989d68f67F5b1dd126;
    address public constant currencyReceiver = 0x7109709eCfa91A80626Ff3989D68f67f5b1dD127;
    address public constant paymentTokenProvider = 0x8109709ecfa91a80626fF3989d68f67F5B1dD128;
    address public constant trustedForwarder = 0x9109709EcFA91A80626FF3989D68f67F5B1dD129;

    uint256 public constant price = 10000000;

    uint256 requirements = 92785934;

    function setUp() public {
        list = new AllowList();

        list.set(tokenReceiver, requirements);

        Fees memory fees = Fees(100, 100, 100, 0);
        feeSettings = new FeeSettings(fees, admin);

        token = new Token(trustedForwarder, feeSettings, admin, list, requirements, "token", "TOK");

        personalInvites = new PersonalInvitesBlind(address(token), currencyReceiver, trustedForwarder);

        vm.prank(paymentTokenProvider);
        currency = new FakePaymentToken(0, 18);
    }

    function testPersonalInvites() public {
        console.log(
            "feeCollector currency balance: %s",
            currency.balanceOf(FeeSettings(address(token.feeSettings())).feeCollector())
        );

        uint256 amount = 20000000000000;
        uint256 expiration = block.timestamp + 1000;
        uint256 tokenDecimals = token.decimals();

        vm.startPrank(paymentTokenProvider);
        currency.mint(currencyPayer, (amount * price) / 10 ** tokenDecimals);
        vm.stopPrank();

        // make sure balances are as expected before deployment
        console.log(
            "feeCollector currency balance: %s",
            currency.balanceOf(FeeSettings(address(token.feeSettings())).feeCollector())
        );

        uint currencyAmount = (amount * price) / 10 ** tokenDecimals;
        assertEq(currency.balanceOf(currencyPayer), currencyAmount);
        assertEq(currency.balanceOf(currencyReceiver), 0);
        assertEq(token.balanceOf(tokenReceiver), 0);

        console.log(
            "feeCollector currency balance before deployment: %s",
            currency.balanceOf(FeeSettings(address(token.feeSettings())).feeCollector())
        );
        // make sure balances are as expected after deployment
        uint256 feeCollectorCurrencyBalanceBefore = currency.balanceOf(
            FeeSettings(address(token.feeSettings())).feeCollector()
        );

        /*
         * investor offers to buy tokens
         */
        vm.startPrank(currencyPayer);
        // step 1: commit to investment
        bytes32 bch = keccak256(abi.encodePacked(currencyPayer, tokenReceiver, amount, price, expiration, currency));
        uint256 gasBefore = gasleft();
        personalInvites.offer(bch);
        uint256 gasAfter = gasleft();
        uint256 gasOffer = gasBefore - gasAfter;
        console.log("gas for offer: %s", gasOffer);

        // step 2: approve currency transfer
        currency.approve(address(personalInvites), (amount * price) / 10 ** tokenDecimals);
        vm.stopPrank();

        /*
         * founder accepts investment
         */
        vm.startPrank(admin);
        // step 1: grant minting allowance
        token.increaseMintingAllowance(address(personalInvites), amount);

        // vm.expectEmit(true, true, true, true, address(personalInvites));
        // emit Deal(tokenReceiver, tokenReceiver, amount, price, currency, token);

        gasBefore = gasleft();
        // step 2: accept investment

        personalInvites.accept(bch, tokenReceiver, amount, price, expiration, currency);
        gasAfter = gasleft();
        uint256 gasAccept = gasBefore - gasAfter;
        console.log("gas accept: %s", gasAccept);
        vm.stopPrank();

        console.log(
            "feeCollector currency balance after deployment: %s",
            currency.balanceOf(FeeSettings(address(token.feeSettings())).feeCollector())
        );

        console.log("buyer balance: %s", currency.balanceOf(tokenReceiver));
        console.log("receiver balance: %s", currency.balanceOf(currencyReceiver));
        console.log("buyer token balance: %s", token.balanceOf(tokenReceiver));
        assertEq(currency.balanceOf(tokenReceiver), 0);

        assertEq(
            currency.balanceOf(currencyReceiver),
            currencyAmount - FeeSettings(address(token.feeSettings())).personalInviteFee(currencyAmount)
        );

        console.log(
            "feeCollector currency balance: %s",
            currency.balanceOf(FeeSettings(address(token.feeSettings())).feeCollector())
        );

        assertEq(
            currency.balanceOf(FeeSettings(address(token.feeSettings())).feeCollector()),
            feeCollectorCurrencyBalanceBefore +
                FeeSettings(address(token.feeSettings())).personalInviteFee(currencyAmount),
            "feeCollector currency balance is not correct"
        );

        assertEq(token.balanceOf(tokenReceiver), amount);

        assertEq(
            token.balanceOf(FeeSettings(address(token.feeSettings())).feeCollector()),
            FeeSettings(address(token.feeSettings())).tokenFee(amount)
        );

        console.log("Gas cost for offer and accept transactions: %s", gasOffer + gasAccept);
    }
}
