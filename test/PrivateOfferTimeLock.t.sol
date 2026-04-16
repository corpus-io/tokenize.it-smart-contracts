// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.23;

import "../lib/forge-std/src/Test.sol";
import "../lib/forge-std/src/console.sol";
import "../contracts/factories/TokenProxyFactory.sol";
import "../contracts/PrivateOffer.sol";
import "../contracts/factories/PrivateOfferFactory.sol";
import "../contracts/factories/TimeLockCloneFactory.sol";
import "../contracts/factories/CoinvestedPositionCloneFactory.sol";
import "../contracts/TimeLock.sol";
import "../contracts/GlobalTokenExitRegistry.sol";
import "./resources/CloneCreators.sol";
import "./resources/FakePaymentToken.sol";

contract PrivateOfferTimeLockTest is Test {
    PrivateOfferFactory privateOfferFactory;
    GlobalTokenExitRegistry tokenExitRegistry;

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
        TimeLock timeLockImplementation = new TimeLock(trustedForwarder);
        TimeLockCloneFactory timeLockCloneFactory = new TimeLockCloneFactory(address(timeLockImplementation));
        privateOfferFactory = new PrivateOfferFactory(timeLockCloneFactory, CoinvestedPositionCloneFactory(address(1)));

        vm.prank(paymentTokenProvider);
        currency = new FakePaymentToken(0, 18);

        list = createAllowList(trustedForwarder, address(this));
        list.set(tokenReceiver, requirements);
        list.set(address(currency), TRUSTED_CURRENCY);

        feeSettings = createFeeSettings(
            trustedForwarder,
            address(this),
            buildFeeTypes(100, 100, 100, admin, admin, admin)
        );

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

        tokenExitRegistry = new GlobalTokenExitRegistry(trustedForwarder);
    }

    /**
     * @param salt can be used to generate different addresses
     * @param lockedUntil unix timestamp before which drain() is blocked
     * @param attemptTime try to drain tokens at this timestamp (must be before lockedUntil)
     */
    function testPrivateOfferWithTimeLock(bytes32 salt, uint64 lockedUntil, uint64 attemptTime) public {
        vm.assume(lockedUntil > block.timestamp + 1);
        vm.assume(lockedUntil < type(uint64).max / 2);
        vm.assume(attemptTime > block.timestamp);
        vm.assume(attemptTime < lockedUntil);

        PrivateOfferArguments memory arguments = PrivateOfferArguments(
            currencyPayer,
            tokenReceiver,
            currencyReceiver,
            20000000000000,
            price,
            block.timestamp + 1000,
            currency,
            token,
            address(0)
        );

        uint256 currencyAmount = (arguments.tokenAmount * price) / 10 ** token.decimals();

        // predict addresses
        (address expectedInviteAddress, address expectedTimeLockAddress) = privateOfferFactory
            .predictPrivateOfferAndTimeLockAddress(
                salt,
                arguments,
                lockedUntil,
                admin,
                tokenExitRegistry,
                trustedForwarder
            );

        // add time lock and token receiver to the allow list
        list.set(expectedTimeLockAddress, requirements);
        list.set(tokenReceiver, requirements);

        // grant minting allowance to the invite address
        vm.prank(admin);
        token.increaseMintingAllowance(expectedInviteAddress, arguments.tokenAmount);

        // mint currency to the payer
        vm.prank(paymentTokenProvider);
        currency.mint(currencyPayer, currencyAmount);

        // approve the invite address to spend the currency
        vm.prank(currencyPayer);
        currency.approve(expectedInviteAddress, currencyAmount);

        // make sure balances are as expected before deployment
        assertEq(currency.balanceOf(currencyPayer), currencyAmount, "currencyPayer wrong balance before deployment");
        assertEq(currency.balanceOf(currencyReceiver), 0, "currencyReceiver wrong balance before deployment");
        assertEq(currency.balanceOf(expectedTimeLockAddress), 0, "timeLock wrong currency balance before deployment");
        assertEq(token.balanceOf(expectedTimeLockAddress), 0, "timeLock wrong token balance before deployment");

        console.log(
            "feeCollector currency balance before deployment: %s",
            currency.balanceOf(token.feeSettings().privateOfferFeeCollector(address(token)))
        );

        // measure and log gas
        uint256 gasBefore = gasleft();
        // deploy private offer and time lock
        TimeLock timeLock = TimeLock(
            privateOfferFactory.deployPrivateOfferWithTimeLock(
                salt,
                arguments,
                lockedUntil,
                admin,
                tokenExitRegistry,
                trustedForwarder
            )
        );
        uint256 gasAfter = gasleft();
        console.log("gas used: %s", gasBefore - gasAfter);

        console.log("payer balance: %s", currency.balanceOf(currencyPayer));
        console.log("receiver balance: %s", currency.balanceOf(currencyReceiver));
        console.log("timeLock token balance: %s", token.balanceOf(address(timeLock)));

        assertEq(currency.balanceOf(currencyPayer), 0, "currencyPayer wrong balance after deployment");

        assertEq(
            currency.balanceOf(currencyReceiver),
            currencyAmount - token.feeSettings().privateOfferFee(currencyAmount, address(token)),
            "currencyReceiver wrong balance after deployment"
        );

        assertEq(
            currency.balanceOf(token.feeSettings().privateOfferFeeCollector(address(token))),
            token.feeSettings().privateOfferFee(currencyAmount, address(token)),
            "feeCollector currency balance is not correct"
        );

        assertEq(
            token.balanceOf(address(timeLock)),
            arguments.tokenAmount,
            "timeLock wrong token balance after deployment"
        );

        assertEq(
            token.balanceOf(token.feeSettings().privateOfferFeeCollector(address(token))),
            token.feeSettings().tokenFee(arguments.tokenAmount, address(token)),
            "feeCollector token balance is not correct"
        );

        /*
         * PrivateOffer worked properly, now test the time lock
         */
        // drain before lock expires should revert
        assertEq(token.balanceOf(tokenReceiver), 0, "investor vault should have no tokens");
        vm.prank(admin);
        vm.expectRevert("timelock has not expired");
        timeLock.drain(IERC20(address(token)), tokenReceiver);

        // drain at attemptTime (still before lockedUntil) should also revert
        vm.warp(attemptTime);
        vm.prank(admin);
        vm.expectRevert("timelock has not expired");
        timeLock.drain(IERC20(address(token)), tokenReceiver);

        // drain after lock expires transfers all tokens to recipient
        vm.warp(lockedUntil);
        vm.prank(admin);
        timeLock.drain(IERC20(address(token)), tokenReceiver);
        assertEq(token.balanceOf(tokenReceiver), arguments.tokenAmount, "investor vault should have all tokens");
    }
}
