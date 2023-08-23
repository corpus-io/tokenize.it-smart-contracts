// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.13;

import "../lib/forge-std/src/Test.sol";
import "../contracts/TokenCloneFactory.sol";
import "../contracts/ContinuousFundraising.sol";
import "../contracts/FeeSettings.sol";
import "./resources/FakePaymentToken.sol";
import "./resources/ERC2771Helper.sol";
import "@opengsn/contracts/src/forwarder/Forwarder.sol"; // chose specific version to avoid import error: yarn add @opengsn/contracts@2.2.5

contract ContinuousFundraisingTest is Test {
    using ECDSA for bytes32; // for verify with var.recover()

    ContinuousFundraising raise;
    AllowList list;
    FeeSettings feeSettings;

    Token token;
    FakePaymentToken paymentToken;
    //Forwarder trustedForwarder;
    ERC2771Helper ERC2771helper;

    // copied from openGSN IForwarder
    struct ForwardRequest {
        address from;
        address to;
        uint256 value;
        uint256 gas;
        uint256 nonce;
        bytes data;
        uint256 validUntil;
    }

    address public constant trustedForwarder = 0x9109709EcFA91A80626FF3989D68f67F5B1dD129;
    address public constant admin = 0x0109709eCFa91a80626FF3989D68f67f5b1dD120;
    address public constant mintAllower = 0x2109709EcFa91a80626Ff3989d68F67F5B1Dd122;
    address public constant minter = 0x3109709ECfA91A80626fF3989D68f67F5B1Dd123;
    address public constant owner = 0x6109709EcFA91A80626FF3989d68f67F5b1dd126;
    address public constant receiver = 0x7109709eCfa91A80626Ff3989D68f67f5b1dD127;
    address public constant paymentTokenProvider = 0x8109709ecfa91a80626fF3989d68f67F5B1dD128;
    address public constant sender = 0x9109709EcFA91A80626FF3989D68f67F5B1dD129;

    // DO NOT USE IN PRODUCTION! Key was generated online for testing only.
    uint256 public constant buyerPrivateKey = 0x3c69254ad72222e3ddf37667b8173dd773bdbdfd93d4af1d192815ff0662de5f;
    address public buyer; // = 0x38d6703d37988C644D6d31551e9af6dcB762E618;

    uint8 public constant paymentTokenDecimals = 6;
    uint256 public constant paymentTokenAmount = 1000 * 10 ** paymentTokenDecimals;

    uint256 public constant price = 7 * 10 ** paymentTokenDecimals; // 7 payment tokens per token

    uint256 public constant maxAmountOfTokenToBeSold = 20 * 10 ** 18; // 20 token
    uint256 public constant maxAmountPerBuyer = maxAmountOfTokenToBeSold / 2; // 10 token
    uint256 public constant minAmountPerBuyer = maxAmountOfTokenToBeSold / 200; // 0.1 token

    uint256 tokenBuyAmount;
    uint256 costInPaymentToken;

    uint256 tokenFeeDenominator = 100;
    uint256 paymentTokenFeeDenominator = 50;

    function setUp() public {
        list = new AllowList();
        Fees memory fees = Fees(tokenFeeDenominator, paymentTokenFeeDenominator, paymentTokenFeeDenominator, 0);
        feeSettings = new FeeSettings(fees, admin);

        Token implementation = new Token(trustedForwarder);
        TokenCloneFactory factory = new TokenCloneFactory(address(implementation));
        token = Token(
            factory.createTokenClone(0, trustedForwarder, feeSettings, admin, list, 0x0, "TESTTOKEN", "TEST")
        );

        ERC2771helper = new ERC2771Helper();

        buyer = vm.addr(buyerPrivateKey);

        // set up currency
        vm.prank(paymentTokenProvider);
        paymentToken = new FakePaymentToken(paymentTokenAmount, paymentTokenDecimals); // 1000 tokens with 6 decimals
        // transfer currency to buyer
        vm.prank(paymentTokenProvider);
        paymentToken.transfer(buyer, paymentTokenAmount);
        assertTrue(paymentToken.balanceOf(buyer) == paymentTokenAmount);

        tokenBuyAmount = 5 * 10 ** token.decimals();
        costInPaymentToken = (tokenBuyAmount * price) / 10 ** 18;
    }

    function buyWithERC2771(Forwarder forwarder) public {
        vm.prank(owner);
        raise = new ContinuousFundraising(
            address(forwarder),
            payable(receiver),
            minAmountPerBuyer,
            maxAmountPerBuyer,
            price,
            maxAmountOfTokenToBeSold,
            paymentToken,
            token
        );

        // allow raise contract to mint
        bytes32 roleMintAllower = token.MINTALLOWER_ROLE();

        vm.prank(admin);
        token.grantRole(roleMintAllower, mintAllower);
        vm.prank(mintAllower);
        token.increaseMintingAllowance(address(raise), maxAmountOfTokenToBeSold);

        // give raise contract allowance
        vm.prank(buyer);
        paymentToken.approve(address(raise), paymentTokenAmount);

        assert(costInPaymentToken == 35 * 10 ** paymentTokenDecimals); // 35 payment tokens, manually calculated

        // register domain and request type
        bytes32 domainSeparator = ERC2771helper.registerDomain(
            forwarder,
            Strings.toHexString(uint256(uint160(address(raise))), 20),
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
        bytes memory payload = abi.encodeWithSelector(raise.buy.selector, tokenBuyAmount, buyer);

        IForwarder.ForwardRequest memory request = IForwarder.ForwardRequest({
            from: buyer,
            to: address(raise),
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
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(buyerPrivateKey, digest);
        bytes memory signature = abi.encodePacked(r, s, v); // https://docs.openzeppelin.com/contracts/2.x/utilities

        require(digest.recover(signature) == request.from, "FWD: signature mismatch");

        // // encode buy call and sign it https://book.getfoundry.sh/cheatcodes/sign
        // bytes memory buyCallData = abi.encodeWithSignature("buy(uint256)", tokenBuyAmount);

        /*
            execute request and check results
        */
        vm.prank(buyer);
        assertEq(token.balanceOf(buyer), 0);
        assertEq(paymentToken.balanceOf(receiver), 0);
        assertEq(paymentToken.balanceOf(address(raise)), 0);
        assertEq(token.balanceOf(address(raise)), 0);
        assertEq(token.balanceOf(receiver), 0);
        assertEq(token.balanceOf(address(forwarder)), 0);
        assertTrue(raise.tokensSold() == 0);
        assertTrue(raise.tokensBought(buyer) == 0);
        //assertTrue(vm.getNonce(buyer) == 0); // it seems forge does not increase nonces with prank

        console.log("Token balance of buyer before: ", token.balanceOf(buyer));
        console.log("eth balance of buyer ", buyer.balance);

        // send call through forwarder contract
        uint256 gasBefore = gasleft();
        forwarder.execute(request, domainSeparator, requestType, suffixData, signature);
        // vm.prank(buyer);
        // raise.buy(tokenBuyAmount);
        console.log("Gas used: ", gasBefore - gasleft());

        // investor receives as many tokens as they paid for
        assertTrue(token.balanceOf(buyer) == tokenBuyAmount);
        // but fee collector receives additional tokens
        assertTrue(token.balanceOf(feeSettings.feeCollector()) == tokenBuyAmount / tokenFeeDenominator);

        // receiver receives payment tokens after fee has been deducted
        assertEq(
            paymentToken.balanceOf(receiver),
            costInPaymentToken - costInPaymentToken / paymentTokenFeeDenominator
        );
        // fee collector receives fee in payment tokens
        assertEq(paymentToken.balanceOf(feeSettings.feeCollector()), costInPaymentToken / paymentTokenFeeDenominator);

        assertEq(paymentToken.balanceOf(address(raise)), 0);
        assertEq(token.balanceOf(address(raise)), 0);
        assertEq(token.balanceOf(receiver), 0);
        assertEq(token.balanceOf(address(forwarder)), 0);
        assertTrue(raise.tokensSold() == tokenBuyAmount);
        assertTrue(raise.tokensBought(buyer) == tokenBuyAmount);
        //assertTrue(vm.getNonce(buyer) == 0);

        console.log("paymentToken balance of receiver after: ", paymentToken.balanceOf(receiver));
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
