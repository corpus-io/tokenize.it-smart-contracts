// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.23;

import "../lib/forge-std/src/Test.sol";
import "../contracts/TokenProxyFactory.sol";
import "../contracts/PrivateOffer.sol";
import "../contracts/PrivateOfferFactory.sol";
import "../contracts/VestingWalletFactory.sol";
import "../contracts/FeeSettings.sol";
import "./resources/FakePaymentToken.sol";
import "../node_modules/@openzeppelin/contracts/finance/VestingWallet.sol";

contract PrivateOfferTimeLockTest is Test {
    PrivateOfferFactory privateOfferFactory;
    VestingWalletFactory vestingWalletFactory;

    AllowList list;
    FeeSettings feeSettings;
    Token token;
    FakePaymentToken currency;

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
        privateOfferFactory = new PrivateOfferFactory();
        vestingWalletFactory = new VestingWalletFactory();
        list = new AllowList();

        list.set(tokenReceiver, requirements);

        Fees memory fees = Fees(1, 100, 1, 100, 1, 100, 0);
        feeSettings = new FeeSettings(fees, admin, admin, admin);

        Token implementation = new Token(trustedForwarder);
        TokenProxyFactory tokenCloneFactory = new TokenProxyFactory(address(implementation));
        token = Token(
            tokenCloneFactory.createTokenProxy(
                0,
                trustedForwarder,
                feeSettings,
                admin,
                list,
                requirements,
                "token",
                "TOK"
            )
        );

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
        vm.warp(block.timestamp + lockDuration + 2); // +2 to account for block time, which starts at 1 in these tests

        // release tokens
        timeLock.release(address(token));

        // check that tokens were released
        assertEq(token.balanceOf(tokenReceiver), tokenAmount, "wrong token amount released");
    }

    /**
     *
     * @param salt can be used to generate different addresses
     * @param releaseStartTime when to start releasing tokens
     * @param attemptTime try to release tokens after this amount of time
     * @param releaseDuration how long the releasing of tokens should take
     */
    function testPrivateOfferWithTimeLock(
        bytes32 salt,
        uint64 releaseStartTime,
        uint64 releaseDuration,
        uint64 attemptTime
    ) public {
        vm.assume(releaseStartTime > attemptTime);
        vm.assume(releaseDuration < 20 * 365 * 24 * 60 * 60); // 20 years
        vm.assume(type(uint64).max - releaseDuration - 1 - block.timestamp > releaseStartTime);
        vm.assume(attemptTime < releaseStartTime + releaseDuration);
        vm.assume(attemptTime > 1);
        vm.assume(releaseStartTime > 1);

        // reference all times to current time. Important for when testing with mainnet forks.
        uint64 testStartTime = uint64(block.timestamp);
        attemptTime += testStartTime;
        releaseStartTime += testStartTime;
        assertTrue(testStartTime < releaseStartTime, "testStartTime >= releaseStartTime");

        // get future vestingWallet address.
        address expectedTimeLockAddress = vestingWalletFactory.getAddress(
            0,
            tokenReceiver,
            releaseStartTime,
            releaseDuration
        );

        // add time lock and token receiver to the allow list
        list.set(expectedTimeLockAddress, requirements);

        //bytes memory creationCode = type(PrivateOffer).creationCode;
        uint256 tokenAmount = 20000000000000;
        uint256 expiration = block.timestamp + 1000;
        uint256 tokenDecimals = token.decimals();
        uint256 currencyAmount = (tokenAmount * price) / 10 ** tokenDecimals;

        address expectedInviteAddress = privateOfferFactory.getAddress(
            salt,
            currencyPayer,
            expectedTimeLockAddress,
            currencyReceiver,
            tokenAmount,
            price,
            expiration,
            currency,
            IERC20(address(token))
        );

        vm.prank(admin);
        token.increaseMintingAllowance(expectedInviteAddress, tokenAmount);

        vm.prank(paymentTokenProvider);
        currency.mint(currencyPayer, currencyAmount);

        vm.prank(currencyPayer);
        currency.approve(expectedInviteAddress, currencyAmount);

        // make sure balances are as expected before deployment

        assertEq(currency.balanceOf(currencyPayer), currencyAmount, "currencyPayer wrong balance before deployment");
        assertEq(currency.balanceOf(currencyReceiver), 0, "currencyReceiver wrong balance before deployment");
        assertEq(currency.balanceOf(expectedTimeLockAddress), 0, "timeLock wrong currency balance before deployment");
        assertEq(token.balanceOf(expectedTimeLockAddress), 0, "timeLock wrong token balance before deployment");

        console.log(
            "feeCollector currency balance before deployment: %s",
            currency.balanceOf(token.feeSettings().privateOfferFeeCollector())
        );

        // create vesting wallet as token receiver
        VestingWallet timeLock = VestingWallet(
            payable(vestingWalletFactory.deploy(0, tokenReceiver, releaseStartTime, releaseDuration))
        );

        // make sure addresses match
        assertEq(address(timeLock), expectedTimeLockAddress, "timeLock address is not correct");

        // deploy private offer
        address inviteAddress = privateOfferFactory.deploy(
            salt,
            currencyPayer,
            expectedTimeLockAddress,
            currencyReceiver,
            tokenAmount,
            price,
            expiration,
            currency,
            IERC20(address(token))
        );

        assertEq(inviteAddress, expectedInviteAddress, "deployed contract address is not correct");

        console.log("payer balance: %s", currency.balanceOf(currencyPayer));
        console.log("receiver balance: %s", currency.balanceOf(currencyReceiver));
        console.log("timeLock token balance: %s", token.balanceOf(address(timeLock)));

        assertEq(currency.balanceOf(currencyPayer), 0, "currencyPayer wrong balance after deployment");

        assertEq(
            currency.balanceOf(currencyReceiver),
            currencyAmount - token.feeSettings().privateOfferFee(currencyAmount),
            "currencyReceiver wrong balance after deployment"
        );

        assertEq(
            currency.balanceOf(token.feeSettings().privateOfferFeeCollector()),
            token.feeSettings().privateOfferFee(currencyAmount),
            "feeCollector currency balance is not correct"
        );

        assertEq(token.balanceOf(address(timeLock)), tokenAmount, "timeLock wrong token balance after deployment");

        assertEq(
            token.balanceOf(token.feeSettings().privateOfferFeeCollector()),
            token.feeSettings().tokenFee(tokenAmount),
            "feeCollector token balance is not correct"
        );

        /*
         * PrivateOffer worked properly, now test the time lock
         */
        // immediate release should not work
        assertEq(token.balanceOf(tokenReceiver), 0, "investor vault should have no tokens");
        timeLock.release(address(token));
        assertEq(token.balanceOf(tokenReceiver), 0, "investor vault should still have no tokens");

        // too early release should not work
        vm.warp(attemptTime);
        timeLock.release(address(token));
        assertEq(token.balanceOf(tokenReceiver), 0, "investor vault should still be empty");

        // not testing the linear release time here because it's already tested in the vesting wallet tests

        // release all tokens after release duration has passed
        vm.warp(releaseStartTime + releaseDuration + 1);
        timeLock.release(address(token));
        assertEq(token.balanceOf(tokenReceiver), tokenAmount, "investor vault should have all tokens");
    }
}
