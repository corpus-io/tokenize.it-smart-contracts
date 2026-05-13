// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import "../lib/forge-std/src/Test.sol";
import "../lib/forge-std/src/console.sol";
import "../contracts/factories/TokenProxyFactory.sol";
import "../contracts/factories/CrowdinvestingCloneFactory.sol";
import "../contracts/FeeSettings.sol";
import "./resources/FakePaymentToken.sol";
import "./resources/ERC2771Helper.sol";
import "./resources/CloneCreators.sol";
import "@opengsn/contracts/src/forwarder/Forwarder.sol"; // chose specific version to avoid import error: yarn add @opengsn/contracts@2.2.5

contract CrowdinvestingTest is Test {
    using ECDSA for bytes32; // for verify with var.recover()

    CrowdinvestingCloneFactory fundraisingFactory;
    Crowdinvesting crowdinvesting;
    AllowList list;
    FeeSettings feeSettings;

    Token token;
    FakePaymentToken paymentToken;
    //Forwarder TRUSTED_FORWARDER;
    ERC2771Helper ERC2771helper;

    CrowdinvestingInitializerArguments arguments;

    address public constant TRUSTED_FORWARDER = 0x9109709EcFA91A80626FF3989D68f67F5B1dD129;
    address public constant ADMIN = 0x0109709eCFa91a80626FF3989D68f67f5b1dD120;
    address public constant MINT_ALLOWER = 0x2109709EcFa91a80626Ff3989d68F67F5B1Dd122;
    address public constant MINTER = 0x3109709ECfA91A80626fF3989D68f67F5B1Dd123;
    address public constant OWNER = 0x6109709EcFA91A80626FF3989d68f67F5b1dd126;
    address public constant RECEIVER = 0x7109709eCfa91A80626Ff3989D68f67f5b1dD127;
    address public constant PAYMENT_TOKEN_PROVIDER = 0x8109709ecfa91a80626fF3989d68f67F5B1dD128;
    address public constant SENDER = 0x9109709EcFA91A80626FF3989D68f67F5B1dD129;

    // DO NOT USE IN PRODUCTION! Key was generated online for testing only.
    uint256 public constant BUYER_PRIVATE_KEY = 0x3c69254ad72222e3ddf37667b8173dd773bdbdfd93d4af1d192815ff0662de5f;
    address public buyer; // = 0x38d6703d37988C644D6d31551e9af6dcB762E618;

    uint8 public constant PAYMENT_TOKEN_DECIMALS = 6;
    uint256 public constant PAYMENT_TOKEN_AMOUNT = 1000 * 10 ** PAYMENT_TOKEN_DECIMALS;

    uint256 public constant PRICE = 7 * 10 ** PAYMENT_TOKEN_DECIMALS; // 7 payment tokens per token

    uint256 public constant MAX_AMOUNT_OF_TOKEN_TO_BE_SOLD = 20 * 10 ** 18; // 20 token
    uint256 public constant MAX_AMOUNT_PER_RECEIVER = MAX_AMOUNT_OF_TOKEN_TO_BE_SOLD / 2; // 10 token
    uint256 public constant MIN_AMOUNT_PER_RECEIVER = MAX_AMOUNT_OF_TOKEN_TO_BE_SOLD / 200; // 0.1 token

    uint256 tokenBuyAmount;
    uint256 costInPaymentToken;

    uint32 tokenFeeNumerator = 100;
    uint32 paymentTokenFeeNumerator = 200;

    function setUp() public {
        buyer = vm.addr(BUYER_PRIVATE_KEY);
        // set up currency
        vm.prank(PAYMENT_TOKEN_PROVIDER);
        paymentToken = new FakePaymentToken(PAYMENT_TOKEN_AMOUNT, PAYMENT_TOKEN_DECIMALS); // 1000 tokens with 6 decimals
        // transfer currency to buyer
        vm.prank(PAYMENT_TOKEN_PROVIDER);
        paymentToken.transfer(buyer, PAYMENT_TOKEN_AMOUNT);
        assertTrue(paymentToken.balanceOf(buyer) == PAYMENT_TOKEN_AMOUNT);

        list = createAllowList(TRUSTED_FORWARDER, OWNER);
        vm.prank(OWNER);
        list.set(address(paymentToken), TRUSTED_CURRENCY);

        feeSettings = createFeeSettings(
            TRUSTED_FORWARDER,
            address(this),
            buildFeeTypes(tokenFeeNumerator, paymentTokenFeeNumerator, paymentTokenFeeNumerator, ADMIN, ADMIN, ADMIN)
        );

        Token implementation = new Token(TRUSTED_FORWARDER);
        TokenProxyFactory tokenFactory = new TokenProxyFactory(address(implementation));
        token = Token(
            tokenFactory.createTokenProxy(0, TRUSTED_FORWARDER, feeSettings, ADMIN, list, 0x0, "TESTTOKEN", "TEST")
        );

        ERC2771helper = new ERC2771Helper();

        tokenBuyAmount = 5 * 10 ** token.decimals();
        costInPaymentToken = (tokenBuyAmount * PRICE) / 10 ** 18;

        arguments = CrowdinvestingInitializerArguments(
            OWNER,
            payable(RECEIVER),
            MIN_AMOUNT_PER_RECEIVER,
            MAX_AMOUNT_PER_RECEIVER,
            PRICE,
            PRICE,
            PRICE,
            MAX_AMOUNT_OF_TOKEN_TO_BE_SOLD,
            paymentToken,
            token,
            0,
            address(0),
            address(0)
        );
    }

    function buyWithERC2771(Forwarder forwarder) public {
        vm.prank(OWNER);
        fundraisingFactory = new CrowdinvestingCloneFactory(address(new Crowdinvesting(address(forwarder))));

        crowdinvesting = Crowdinvesting(fundraisingFactory.createCrowdinvestingClone(0, address(forwarder), arguments));

        // allow crowdinvesting contract to mint
        bytes32 roleMintAllower = token.MINTALLOWER_ROLE();

        vm.prank(ADMIN);
        token.grantRole(roleMintAllower, MINT_ALLOWER);
        vm.prank(MINT_ALLOWER);
        token.increaseMintingAllowance(address(crowdinvesting), MAX_AMOUNT_OF_TOKEN_TO_BE_SOLD);

        // give crowdinvesting contract allowance
        vm.prank(buyer);
        paymentToken.approve(address(crowdinvesting), PAYMENT_TOKEN_AMOUNT);

        assert(costInPaymentToken == 35 * 10 ** PAYMENT_TOKEN_DECIMALS); // 35 payment tokens, manually calculated

        // register domain and request type
        bytes32 domainSeparator = ERC2771helper.registerDomain(
            forwarder,
            Strings.toHexString(uint256(uint160(address(crowdinvesting))), 20),
            "1"
        );
        bytes32 requestType = ERC2771helper.registerRequestType(forwarder, "buy", "address buyer,uint256 amount");

        /*
            create data and signature for execution 
        */
        // // https://github.com/foundry-rs/foundry/issues/3330
        // // https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/utils/cryptography/ECDSA.sol
        // bytes32 digest = ECDSA.toTypedDataHash(domainSeparator, keccak256(payload));
        // (uint8 v, bytes32 r, bytes32 s) = vm.sign(privKey, digest);

        // todo: get nonce from forwarder

        // build request
        bytes memory payload = abi.encodeWithSelector(
            crowdinvesting.buy.selector,
            tokenBuyAmount,
            type(uint256).max,
            buyer
        );

        IForwarder.ForwardRequest memory request = IForwarder.ForwardRequest({
            from: buyer,
            to: address(crowdinvesting),
            value: 0,
            gas: 1000000,
            nonce: forwarder.getNonce(buyer),
            data: payload,
            validUntil: 0
        });

        bytes memory suffixData = "0";

        // pack and hash request
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                domainSeparator,
                keccak256(forwarder._getEncoded(request, requestType, suffixData))
            )
        );

        // sign request
        //bytes memory signature
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(BUYER_PRIVATE_KEY, digest);
        bytes memory signature = abi.encodePacked(r, s, v); // https://docs.openzeppelin.com/contracts/2.x/utilities

        require(digest.recover(signature) == request.from, "FWD: signature mismatch");

        // // encode buy call and sign it https://book.getfoundry.sh/cheatcodes/sign
        // bytes memory buyCallData = abi.encodeWithSignature("buy(uint256)", type(uint256).max, tokenBuyAmount);

        /*
            execute request and check results
        */
        vm.prank(buyer);
        assertEq(token.balanceOf(buyer), 0, "buyer has tokens before");
        assertEq(paymentToken.balanceOf(RECEIVER), 0, "RECEIVER has payment tokens before");
        assertEq(paymentToken.balanceOf(address(crowdinvesting)), 0, "crowdinvesting has payment tokens before");
        assertEq(token.balanceOf(address(crowdinvesting)), 0, "crowdinvesting has tokens before");
        assertEq(token.balanceOf(RECEIVER), 0, "RECEIVER has tokens before");
        assertEq(token.balanceOf(address(forwarder)), 0, "forwarder has tokens before");
        assertTrue(crowdinvesting.tokensSold() == 0, "tokens sold before");
        assertTrue(crowdinvesting.tokensBoughtByReceiver(buyer) == 0, "tokens bought before");
        //assertTrue(vm.getNonce(buyer) == 0); // it seems forge does not increase nonces with prank

        console.log("Token balance of buyer before: ", token.balanceOf(buyer));
        console.log("eth balance of buyer ", buyer.balance);

        // send call through forwarder contract
        uint256 gasBefore = gasleft();
        forwarder.execute(request, domainSeparator, requestType, suffixData, signature);
        // vm.prank(buyer);
        // crowdinvesting.buy(tokenBuyAmount);
        console.log("Gas used: ", gasBefore - gasleft());

        // investor receives as many tokens as they paid for
        assertTrue(token.balanceOf(buyer) == tokenBuyAmount, "buyer has tokens after");
        // but fee collector receives additional tokens
        assertTrue(
            token.balanceOf(feeSettings.feeCollector()) == tokenBuyAmount / tokenFeeNumerator,
            "fee collector has tokens after"
        );

        // RECEIVER receives payment tokens after fee has been deducted
        assertEq(
            paymentToken.balanceOf(RECEIVER),
            costInPaymentToken - (costInPaymentToken * paymentTokenFeeNumerator) / feeSettings.FEE_DENOMINATOR(),
            "RECEIVER has payment tokens after"
        );
        // fee collector receives fee in payment tokens
        assertEq(
            paymentToken.balanceOf(feeSettings.feeCollector()),
            (costInPaymentToken * paymentTokenFeeNumerator) / feeSettings.FEE_DENOMINATOR(),
            "fee collector has payment tokens after"
        );

        assertEq(paymentToken.balanceOf(address(crowdinvesting)), 0, "crowdinvesting has payment tokens after");
        assertEq(token.balanceOf(address(crowdinvesting)), 0, "crowdinvesting has tokens after");
        assertEq(token.balanceOf(RECEIVER), 0, "RECEIVER has tokens after");
        assertEq(token.balanceOf(address(forwarder)), 0, "forwarder has tokens after");
        assertTrue(crowdinvesting.tokensSold() == tokenBuyAmount, "tokens sold after");
        assertTrue(crowdinvesting.tokensBoughtByReceiver(buyer) == tokenBuyAmount, "tokens bought after");
        //assertTrue(vm.getNonce(buyer) == 0);

        console.log("paymentToken balance of RECEIVER after: ", paymentToken.balanceOf(RECEIVER));
        console.log("Token balance of buyer after: ", token.balanceOf(buyer));

        /*
            try to execute request again (must fail)
        */
        vm.expectRevert("FWD: nonce mismatch");
        forwarder.execute(request, domainSeparator, requestType, suffixData, signature);
    }

    function testBuyWithLocalForwarder() public {
        buyWithERC2771(new Forwarder());
    }

    function testBuyWithMainnetGSNForwarder() public {
        // uses deployed forwarder on mainnet with fork. https://docs-v2.opengsn.org/networks/ethereum/mainnet.html
        buyWithERC2771(Forwarder(payable(0xAa3E82b4c4093b4bA13Cb5714382C99ADBf750cA)));
    }
}
