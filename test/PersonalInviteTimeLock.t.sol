// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.13;

import "../lib/forge-std/src/Test.sol";
import "../contracts/Token.sol";
import "../contracts/PersonalInvite.sol";
import "../contracts/PersonalInviteFactory.sol";
import "../contracts/FeeSettings.sol";
import "./resources/FakePaymentToken.sol";
import "../node_modules/@openzeppelin/contracts/finance/VestingWallet.sol";

contract PersonalInviteTimeLockTest is Test {
    PersonalInviteFactory factory;

    AllowList list;
    FeeSettings feeSettings;
    Token token;
    FakePaymentToken currency;

    uint256 MAX_INT = 115792089237316195423570985008687907853269984665640564039457584007913129639935;

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
        factory = new PersonalInviteFactory();
        list = new AllowList();

        list.set(tokenReceiver, requirements);

        Fees memory fees = Fees(100, 100, 100, 0);
        feeSettings = new FeeSettings(fees, admin);

        token = new Token(trustedForwarder, feeSettings, admin, list, requirements, "token", "TOK");
        vm.prank(paymentTokenProvider);
        currency = new FakePaymentToken(0, 18);
    }

    /**
     * @notice Test that the timeLock works as expected
     */
    function testTimeLock() public {
        uint lockDuration = 1000;
        uint tokenAmount = 300;

        // create the time lock
        VestingWallet timeLock = new VestingWallet(
            tokenReceiver,
            uint64(block.timestamp + lockDuration),
            0 // all tokens are released at once
        );

        // add time lock and token receiver to the allow list
        list.set(address(timeLock), requirements);
        list.set(tokenReceiver, requirements);

        // transfer some ERC20 tokens to the time lock
        vm.startPrank(admin);
        token.increaseMintingAllowance(admin, tokenAmount);
        token.mint(address(timeLock), tokenAmount);
        vm.stopPrank();

        // try releasing tokens before the lock expires
        timeLock.release(address(token));

        // check that no tokens were released
        assertEq(token.balanceOf(tokenReceiver), 0);

        // wait for the lock to expire
        vm.warp(lockDuration + 2); // +2 to account for block time, which starts at 1 in these tests

        // release tokens
        timeLock.release(address(token));

        // check that tokens were released
        assertEq(token.balanceOf(tokenReceiver), tokenAmount, "wrong token amount released");
    }

    function testPersonalInviteWithTimeLock(uint256 rawSalt, uint64 lockDuration, uint64 attemptDuration) public {
        vm.assume(lockDuration > attemptDuration);
        vm.assume(attemptDuration > 0);
        vm.assume(lockDuration < type(uint64).max / 2);

        // check current time is 0 -> makes math easier further down
        uint256 startTime = block.timestamp;

        // create vesting wallet as token receiver
        VestingWallet timeLock = new VestingWallet(
            tokenReceiver,
            uint64(startTime + lockDuration),
            0 // all tokens are released at once
        );

        // add time lock and token receiver to the allow list
        list.set(address(timeLock), requirements);

        //uint rawSalt = 0;
        bytes32 salt = bytes32(rawSalt);

        //bytes memory creationCode = type(PersonalInvite).creationCode;
        uint256 tokenAmount = 20000000000000;
        uint256 expiration = block.timestamp + 1000;
        uint256 tokenDecimals = token.decimals();
        uint256 currencyAmount = (tokenAmount * price) / 10 ** tokenDecimals;

        address expectedAddress = factory.getAddress(
            salt,
            currencyPayer,
            address(timeLock),
            currencyReceiver,
            tokenAmount,
            price,
            expiration,
            currency,
            token
        );

        vm.prank(admin);
        token.increaseMintingAllowance(expectedAddress, tokenAmount);

        vm.prank(paymentTokenProvider);
        currency.mint(currencyPayer, currencyAmount);

        vm.prank(currencyPayer);
        currency.approve(expectedAddress, currencyAmount);

        // make sure balances are as expected before deployment

        console.log("feeCollector currency balance: %s", currency.balanceOf(token.feeSettings().feeCollector()));

        assertEq(currency.balanceOf(currencyPayer), currencyAmount);
        assertEq(currency.balanceOf(currencyReceiver), 0);
        assertEq(currency.balanceOf(address(timeLock)), 0);
        assertEq(token.balanceOf(address(timeLock)), 0);

        console.log(
            "feeCollector currency balance before deployment: %s",
            currency.balanceOf(token.feeSettings().feeCollector())
        );

        address inviteAddress = factory.deploy(
            salt,
            currencyPayer,
            address(timeLock),
            currencyReceiver,
            tokenAmount,
            price,
            expiration,
            currency,
            token
        );

        assertEq(inviteAddress, expectedAddress, "deployed contract address is not correct");

        console.log("payer balance: %s", currency.balanceOf(currencyPayer));
        console.log("receiver balance: %s", currency.balanceOf(currencyReceiver));
        console.log("timeLock token balance: %s", token.balanceOf(address(timeLock)));

        assertEq(currency.balanceOf(currencyPayer), 0);

        assertEq(
            currency.balanceOf(currencyReceiver),
            currencyAmount - token.feeSettings().personalInviteFee(currencyAmount)
        );

        assertEq(
            currency.balanceOf(token.feeSettings().feeCollector()),
            token.feeSettings().personalInviteFee(currencyAmount),
            "feeCollector currency balance is not correct"
        );

        assertEq(token.balanceOf(address(timeLock)), tokenAmount);

        assertEq(token.balanceOf(token.feeSettings().feeCollector()), token.feeSettings().tokenFee(tokenAmount));

        /*
         * PersonalInvite worked properly, now test the time lock
         */
        // immediate release should not work
        assertEq(token.balanceOf(tokenReceiver), 0, "investor vault should have no tokens");
        timeLock.release(address(token));
        assertEq(token.balanceOf(tokenReceiver), 0, "investor vault should still have no tokens");

        // too early release should not work
        vm.warp(startTime + attemptDuration);
        timeLock.release(address(token));
        assertEq(token.balanceOf(tokenReceiver), 0, "investor vault should still be empty");

        // release should work from 1 second after lock expires
        vm.warp(startTime + lockDuration + 2);
        timeLock.release(address(token));
        assertEq(token.balanceOf(tokenReceiver), tokenAmount, "investor vault should have tokens");
    }
}
