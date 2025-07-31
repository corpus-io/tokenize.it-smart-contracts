// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.23;

import "../lib/forge-std/src/Test.sol";
import "../lib/forge-std/src/console.sol";
import "../contracts/factories/TokenProxyFactory.sol";
import "../contracts/factories/VestingCloneFactory.sol";
import "./resources/CloneCreators.sol";
import "./resources/FakePaymentToken.sol";

contract PrivateOfferOffchainPaymentTimeLockTest is Test {
    AllowList list;
    FeeSettings feeSettings;
    Token token;
    FakePaymentToken currency;
    VestingCloneFactory vestingCloneFactory;

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
        Vesting vestingImplementation = new Vesting(trustedForwarder);
        vestingCloneFactory = new VestingCloneFactory(address(vestingImplementation));

        vm.prank(paymentTokenProvider);
        currency = new FakePaymentToken(0, 18);

        list = createAllowList(trustedForwarder, address(this));
        list.set(tokenReceiver, requirements);
        list.set(address(currency), TRUSTED_CURRENCY);

        Fees memory fees = Fees(100, 100, 100, 0);
        feeSettings = createFeeSettings(trustedForwarder, address(this), fees, admin, admin, admin);

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
    }

    /**
     *
     * @param salt can be used to generate different addresses
     * @param releaseStartTime when to start releasing tokens
     * @param attemptTime try to release tokens after this amount of time
     * @param releaseDuration how long the releasing of tokens should take
     */
    function testPrivateOfferOffchainPaymentTimeLock(
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

        uint256 tokenAmount = 20000000000000;

        // as the payment happens off-chain, we just assume it happened

        // predict addresses
        address expectedTimeLockAddress = vestingCloneFactory.predictCloneAddressWithLockupPlan(
            salt,
            trustedForwarder,
            address(0), // no owner
            address(token),
            releaseStartTime,
            releaseDuration,
            releaseDuration
        );

        // add time lock and token receiver to the allow list
        list.set(expectedTimeLockAddress, requirements);
        list.set(tokenReceiver, requirements);

        // make sure balances are as expected before deployment
        assertEq(token.balanceOf(expectedTimeLockAddress), 0, "timeLock wrong token balance before deployment");

        // create vesting contract and mint tokens
        Vesting timeLock = Vesting(
            vestingCloneFactory.createVestingCloneWithLockupPlan(
                salt,
                trustedForwarder,
                address(0), // no owner
                address(token),
                tokenAmount,
                tokenReceiver,
                releaseStartTime,
                releaseDuration,
                releaseDuration
            )
        );
        vm.prank(admin);
        token.mint(address(timeLock), tokenAmount);

        // check vesting contract
        console.log("timeLock token balance: %s", token.balanceOf(address(timeLock)));

        assertEq(token.balanceOf(address(timeLock)), tokenAmount, "timeLock wrong token balance after deployment");

        assertEq(
            token.balanceOf(token.feeSettings().privateOfferFeeCollector(address(token))),
            token.feeSettings().tokenFee(tokenAmount, address(token)),
            "feeCollector token balance is not correct"
        );

        /*
         * PrivateOffer worked properly, now test the time lock
         */
        // immediate release should not work
        assertEq(token.balanceOf(tokenReceiver), 0, "investor vault should have no tokens");
        vm.prank(tokenReceiver);
        timeLock.release(uint64(1));
        assertEq(token.balanceOf(tokenReceiver), 0, "investor vault should still have no tokens");

        // too early release should not work
        vm.warp(attemptTime);
        vm.prank(tokenReceiver);
        timeLock.release(uint64(1));
        assertEq(token.balanceOf(tokenReceiver), 0, "investor vault should still be empty");

        // not testing the linear release time here because it's already tested in the vesting wallet tests

        // release all tokens after release duration has passed
        vm.warp(releaseStartTime + releaseDuration + 1);
        vm.prank(tokenReceiver);
        timeLock.release(uint64(1));
        assertEq(token.balanceOf(tokenReceiver), tokenAmount, "investor vault should have all tokens");
    }
}
