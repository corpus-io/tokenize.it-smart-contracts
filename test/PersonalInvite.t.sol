// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "../lib/forge-std/src/Test.sol";
import "../contracts/Token.sol";
import "../contracts/PersonalInvite.sol";
import "../contracts/PersonalInviteFactory.sol";

contract PersonalInviteTest is Test {
    PersonalInviteFactory factory;

    AllowList list;
    FeeSettings feeSettings;
    Token token;
    Token currency; // todo: add different ERC20 token as currency!

    uint256 MAX_INT =
        115792089237316195423570985008687907853269984665640564039457584007913129639935;

    address public constant admin = 0x0109709eCFa91a80626FF3989D68f67f5b1dD120;
    address public constant buyer = 0x1109709ecFA91a80626ff3989D68f67F5B1Dd121;
    address public constant mintAllower =
        0x2109709EcFa91a80626Ff3989d68F67F5B1Dd122;
    address public constant minter = 0x3109709ECfA91A80626fF3989D68f67F5B1Dd123;
    address public constant owner = 0x6109709EcFA91A80626FF3989d68f67F5b1dd126;
    address public constant receiver =
        0x7109709eCfa91A80626Ff3989D68f67f5b1dD127;
    address public constant paymentTokenProvider =
        0x8109709ecfa91a80626fF3989d68f67F5B1dD128;
    address public constant trustedForwarder =
        0x9109709EcFA91A80626FF3989D68f67F5B1dD129;

    uint256 public constant price = 10000000;

    function setUp() public {
        factory = new PersonalInviteFactory();
        list = new AllowList();

        Fees memory fees = Fees(100, 100, 100, 0);
        feeSettings = new FeeSettings(fees, admin);

        token = new Token(
            trustedForwarder,
            feeSettings,
            admin,
            list,
            0x0,
            "token",
            "TOK"
        );
        currency = new Token(
            trustedForwarder,
            feeSettings,
            admin,
            list,
            0x0,
            "currency",
            "CUR"
        );
    }

    function testAcceptDeal(uint256 rawSalt) public {
        console.log(
            "feeCollector currency balance: %s",
            currency.balanceOf(token.feeSettings().feeCollector())
        );

        //uint rawSalt = 0;
        bytes32 salt = bytes32(rawSalt);

        //bytes memory creationCode = type(PersonalInvite).creationCode;
        uint256 amount = 20000000000000;
        uint256 expiration = block.timestamp + 1000;

        address expectedAddress = factory.getAddress(
            salt,
            payable(buyer),
            payable(receiver),
            amount,
            price,
            expiration,
            currency,
            token
        );

        vm.prank(admin);
        token.increaseMintingAllowance(expectedAddress, amount);

        vm.prank(admin);
        currency.increaseMintingAllowance(admin, amount * price);

        uint256 tokenDecimals = token.decimals();
        vm.prank(admin);
        currency.mint(buyer, (amount * price) / 10 ** tokenDecimals); // during this call, the feeCollector gets 1% of the amount

        vm.prank(buyer);
        currency.approve(
            expectedAddress,
            (amount * price) / 10 ** tokenDecimals
        );

        // make sure balances are as expected before deployment

        console.log(
            "feeCollector currency balance: %s",
            currency.balanceOf(token.feeSettings().feeCollector())
        );

        uint currencyAmount = (amount * price) / 10 ** tokenDecimals;
        assertEq(currency.balanceOf(buyer), currencyAmount);
        assertEq(currency.balanceOf(receiver), 0);
        assertEq(token.balanceOf(buyer), 0);

        console.log(
            "feeCollector currency balance before deployment: %s",
            currency.balanceOf(token.feeSettings().feeCollector())
        );
        // make sure balances are as expected after deployment
        uint256 feeCollectorCurrencyBalanceBefore = currency.balanceOf(
            token.feeSettings().feeCollector()
        );

        address inviteAddress = factory.deploy(
            salt,
            payable(buyer),
            payable(receiver),
            amount,
            price,
            expiration,
            currency,
            token
        );

        console.log(
            "feeCollector currency balance after deployment: %s",
            currency.balanceOf(token.feeSettings().feeCollector())
        );

        assertEq(
            inviteAddress,
            expectedAddress,
            "deployed contract address is not correct"
        );

        console.log("buyer balance: %s", currency.balanceOf(buyer));
        console.log("receiver balance: %s", currency.balanceOf(receiver));
        console.log("buyer token balance: %s", token.balanceOf(buyer));
        uint256 len;
        assembly {
            len := extcodesize(expectedAddress)
        }
        console.log("Deployed contract size: %s", len);
        assertEq(currency.balanceOf(buyer), 0);

        assertEq(
            currency.balanceOf(receiver),
            currencyAmount -
                currencyAmount /
                token.feeSettings().personalInviteFeeDenominator()
        );

        console.log(
            "feeCollector currency balance: %s",
            currency.balanceOf(token.feeSettings().feeCollector())
        );

        assertEq(
            currency.balanceOf(token.feeSettings().feeCollector()),
            feeCollectorCurrencyBalanceBefore +
                currencyAmount /
                token.feeSettings().personalInviteFeeDenominator(),
            "feeCollector currency balance is not correct"
        );

        assertEq(token.balanceOf(buyer), amount);

        assertEq(
            token.balanceOf(token.feeSettings().feeCollector()),
            amount / token.feeSettings().tokenFeeDenominator()
        );
    }

    function ensureCostIsRoundedUp(
        uint256 _tokenBuyAmount,
        uint256 _nominalPrice
    ) public {
        console.log(
            "feeCollector currency balance: %s",
            currency.balanceOf(token.feeSettings().feeCollector())
        );

        //uint rawSalt = 0;
        bytes32 salt = bytes32(uint256(8));

        //bytes memory creationCode = type(PersonalInvite).creationCode;
        uint256 expiration = block.timestamp + 1000;

        address expectedAddress = factory.getAddress(
            salt,
            payable(buyer),
            payable(receiver),
            _tokenBuyAmount,
            _nominalPrice,
            expiration,
            currency,
            token
        );

        // set fees to 0, otherwise extra currency is minted which causes an overflow
        Fees memory fees = Fees(0, 0, 0, 0);
        currency.feeSettings().planFeeChange(fees);
        currency.feeSettings().executeFeeChange();
        token.feeSettings().planFeeChange(fees);
        token.feeSettings().executeFeeChange();

        vm.prank(admin);
        token.increaseMintingAllowance(expectedAddress, _tokenBuyAmount);

        vm.prank(admin);
        currency.increaseMintingAllowance(
            admin,
            _tokenBuyAmount * _nominalPrice + 1
        );

        uint minCurrencyAmount = (_tokenBuyAmount * _nominalPrice) /
            10 ** token.decimals();
        console.log("minCurrencyAmount: %s", minCurrencyAmount);
        uint maxCurrencyAmount = minCurrencyAmount + 1;
        console.log("maxCurrencyAmount: %s", maxCurrencyAmount);

        vm.startPrank(admin);
        currency.mint(buyer, maxCurrencyAmount); // during this call, the feeCollector gets 1% of the amount
        // burn the feeCollector balance to simplify accounting
        currency.burn(
            token.feeSettings().feeCollector(),
            currency.balanceOf(token.feeSettings().feeCollector())
        ); // burn 1 wei to make sure the feeCollector balance is not rounded up
        vm.stopPrank();

        vm.prank(buyer);
        currency.approve(expectedAddress, maxCurrencyAmount);

        // make sure balances are as expected before deployment

        console.log(
            "feeCollector currency balance: %s",
            currency.balanceOf(token.feeSettings().feeCollector())
        );

        assertEq(currency.balanceOf(buyer), maxCurrencyAmount);
        assertEq(currency.balanceOf(receiver), 0);
        assertEq(token.balanceOf(token.feeSettings().feeCollector()), 0);
        assertEq(token.balanceOf(buyer), 0);

        console.log(
            "feeCollector currency balance before deployment: %s",
            currency.balanceOf(token.feeSettings().feeCollector())
        );
        // make sure balances are as expected after deployment
        uint256 currencyReceiverBalanceBefore = currency.balanceOf(receiver);

        address inviteAddress = factory.deploy(
            salt,
            payable(buyer),
            payable(receiver),
            _tokenBuyAmount,
            _nominalPrice,
            expiration,
            currency,
            token
        );

        console.log(
            "feeCollector currency balance after deployment: %s",
            currency.balanceOf(token.feeSettings().feeCollector())
        );

        assertEq(
            inviteAddress,
            expectedAddress,
            "deployed contract address is not correct"
        );

        console.log("buyer balance: %s", currency.balanceOf(buyer));
        console.log("receiver balance: %s", currency.balanceOf(receiver));
        console.log("buyer token balance: %s", token.balanceOf(buyer));
        uint256 len;
        assembly {
            len := extcodesize(expectedAddress)
        }
        console.log("Deployed contract size: %s", len);
        assertTrue(
            currency.balanceOf(buyer) <= 1,
            "Buyer has too much currency left"
        );

        assertTrue(
            currency.balanceOf(receiver) > currencyReceiverBalanceBefore,
            "receiver received no payment"
        );

        console.log(
            "feeCollector currency balance: %s",
            currency.balanceOf(token.feeSettings().feeCollector())
        );

        assertTrue(
            maxCurrencyAmount - currency.balanceOf(buyer) >= 1,
            "Buyer paid nothing"
        );
        uint totalCurrencyReceived = currency.balanceOf(receiver) +
            currency.balanceOf(token.feeSettings().feeCollector());
        console.log("totalCurrencyReceived: %s", totalCurrencyReceived);
        assertTrue(
            totalCurrencyReceived >= minCurrencyAmount,
            "Receiver and feeCollector received less than expected"
        );

        assertTrue(
            totalCurrencyReceived <= maxCurrencyAmount,
            "Receiver and feeCollector received more than expected"
        );

        assertEq(
            token.balanceOf(buyer),
            _tokenBuyAmount,
            "buyer received no tokens"
        );
    }

    function testRoundUp0() public {
        // buy one token bit with price 1 currency bit per full token
        // -> would have to pay 10^-18 currency bits, which is not possible
        // we expect to round up to 1 currency bit
        ensureCostIsRoundedUp(1, 1);
    }

    function testRoundFixedExample0() public {
        ensureCostIsRoundedUp(583 * 10 ** token.decimals(), 82742);
    }

    function testRoundFixedExample1() public {
        ensureCostIsRoundedUp(583 * 10 ** token.decimals(), 82742);
    }

    function testRoundUpAnything(
        uint256 _tokenBuyAmount,
        uint256 _tokenPrice
    ) public {
        vm.assume(_tokenBuyAmount > 0);
        vm.assume(_tokenPrice > 0);
        vm.assume(UINT256_MAX / _tokenPrice > _tokenBuyAmount);
        // vm.assume(UINT256_MAX / _tokenPrice > 10 ** token.decimals());
        // vm.assume(
        //     UINT256_MAX / _tokenBuyAmount > _tokenPrice * 10 ** token.decimals()
        // ); // amount * price *10**18 < UINT256_MAX
        //vm.assume(_tokenPrice < UINT256_MAX / (100 * 10 ** token.decimals()));
        ensureCostIsRoundedUp(_tokenBuyAmount, _tokenPrice);
    }

    function ensureReverts(
        uint256 _tokenBuyAmount,
        uint256 _nominalPrice
    ) public {
        //uint rawSalt = 0;
        bytes32 salt = bytes32(uint256(8));

        //bytes memory creationCode = type(PersonalInvite).creationCode;
        uint256 expiration = block.timestamp + 1000;

        address expectedAddress = factory.getAddress(
            salt,
            payable(buyer),
            payable(receiver),
            _tokenBuyAmount,
            _nominalPrice,
            expiration,
            currency,
            token
        );

        vm.startPrank(admin);
        console.log(
            "expectedAddress: %s",
            token.mintingAllowance(expectedAddress)
        );
        token.increaseMintingAllowance(expectedAddress, _tokenBuyAmount);

        currency.increaseMintingAllowance(admin, UINT256_MAX);
        vm.stopPrank();

        uint maxCurrencyAmount = UINT256_MAX;

        // set fees to 0, otherwise extra currency is minted which causes an overflow
        Fees memory fees = Fees(0, 0, 0, 0);
        currency.feeSettings().planFeeChange(fees);
        currency.feeSettings().executeFeeChange();

        vm.startPrank(admin);
        currency.mint(buyer, maxCurrencyAmount); // during this call, the feeCollector gets 1% of the amount
        // burn the feeCollector balance to simplify accounting
        currency.burn(
            token.feeSettings().feeCollector(),
            currency.balanceOf(token.feeSettings().feeCollector())
        ); // burn 1 wei to make sure the feeCollector balance is not rounded up
        vm.stopPrank();

        vm.prank(buyer);
        currency.approve(expectedAddress, maxCurrencyAmount);

        // make sure balances are as expected before deployment
        vm.expectRevert("Create2: Failed on deploy");
        factory.deploy(
            salt,
            buyer,
            receiver,
            _tokenBuyAmount,
            _nominalPrice,
            expiration,
            currency,
            token
        );
    }

    function testRevertOnOverflow(
        uint256 _tokenBuyAmount,
        uint256 _tokenPrice
    ) public {
        vm.assume(_tokenBuyAmount > 0);
        vm.assume(_tokenPrice > 0);

        vm.assume(UINT256_MAX / _tokenPrice < _tokenBuyAmount);
        //vm.assume(UINT256_MAX / _tokenBuyAmount > _tokenPrice);
        ensureReverts(_tokenBuyAmount, _tokenPrice);
    }
}
