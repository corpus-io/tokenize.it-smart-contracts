// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.23;

import "../lib/forge-std/src/Test.sol";
import "../lib/forge-std/src/console.sol";
import "../contracts/factories/TokenProxyFactory.sol";
import "./resources/CloneCreators.sol";
import "./resources/FakePaymentToken.sol";
import "./resources/ERC2771Helper.sol";
import "../contracts/factories/CrowdinvestingCloneFactory.sol";

import "@opengsn/contracts/src/forwarder/Forwarder.sol"; // chose specific version to avoid import error: yarn add @opengsn/contracts@2.2.5

contract TokenERC2771Test is Test {
    using ECDSA for bytes32; // for verify with var.recover()

    Forwarder forwarder = new Forwarder();

    AllowList allowList;
    FeeSettings feeSettings;
    TokenProxyFactory factory;
    Token token;
    FakePaymentToken paymentToken;
    //Forwarder TRUSTED_FORWARDER;
    ERC2771Helper ERC2771helper;

    address public constant TRUSTED_FORWARDER = 0x9109709EcFA91A80626FF3989D68f67F5B1dD129;

    // DO NOT USE IN PRODUCTION! Key was generated online for testing only.
    uint256 public constant COMPANY_ADMIN_PRIVATE_KEY = 0x3c69254ad72222e3ddf37667b8173dd773bdbdfd93d4af1d192815ff0662de5f;
    address public companyAdmin; // = 0x38d6703d37988C644D6d31551e9af6dcB762E618;

    uint256 public constant MINTER_PRIVATE_KEY = 0x1111254ad72222e3ddf37667b8173dd773bdbdfd93d4af1d192815ff06621111;
    address public minter;

    address public constant INVESTOR = 0x6109709EcFA91A80626FF3989d68f67F5b1dd126;

    address public constant RECEIVER = 0x7109709eCfa91A80626Ff3989D68f67f5b1dD127;
    address public constant PLATFORM_HOT_WALLET = 0x8109709ecfa91a80626fF3989d68f67F5B1dD128;
    address public constant SENDER = 0x9109709EcFA91A80626FF3989D68f67F5B1dD129;

    address public constant PLATFORM_ADMIN = 0x3109709ECfA91A80626fF3989D68f67F5B1Dd123;
    address public constant FEE_COLLECTOR = 0x0109709eCFa91a80626FF3989D68f67f5b1dD120;

    uint32 public constant TOKEN_FEE_NUMERATOR = 100;
    uint32 public constant CROWDINVESTING_FEE_NUMERATOR = 200;
    uint32 public constant PRIVATE_OFFER_FEE_NUMERATOR = 150;

    bytes32 domainSeparator;
    bytes32 requestType;

    function setUp() public {
        // calculate address
        companyAdmin = vm.addr(COMPANY_ADMIN_PRIVATE_KEY);
        minter = vm.addr(MINTER_PRIVATE_KEY);

        // deploy allow list
        allowList = createAllowList(TRUSTED_FORWARDER, PLATFORM_ADMIN);

        // deploy fee settings
        vm.prank(PLATFORM_ADMIN);
        feeSettings = createFeeSettings(
            TRUSTED_FORWARDER,
            PLATFORM_ADMIN,
            buildFeeTypes(
                TOKEN_FEE_NUMERATOR,
                CROWDINVESTING_FEE_NUMERATOR,
                PRIVATE_OFFER_FEE_NUMERATOR,
                FEE_COLLECTOR,
                FEE_COLLECTOR,
                FEE_COLLECTOR
            )
        );

        Token implementation = new Token(address(forwarder));
        factory = new TokenProxyFactory(address(implementation));

        // deploy helper functions (only for testing with foundry)
        ERC2771helper = new ERC2771Helper();
    }

    /**
     * this test executes several EIP-2771 transactions on several contracts with the same domainSeparator
     * and on several functions with different signatures but using the same requestTypeHash
     */
    function testSeveralContractsOneDomainSeparator() public {
        uint256 _tokenMintAmount = 1000 * 10 ** 18;

        // deploy company token
        token = Token(
            factory.createTokenProxy(
                0,
                address(forwarder),
                feeSettings,
                companyAdmin,
                allowList,
                0x0,
                "TESTTOKEN",
                "TEST"
            )
        );

        // deploy fundraising
        paymentToken = new FakePaymentToken(6 * 10 ** 18, 18);
        CrowdinvestingCloneFactory fundraisingFactory = new CrowdinvestingCloneFactory(
            address(new Crowdinvesting(address(forwarder)))
        );

        // add payment token to allow list
        vm.prank(PLATFORM_ADMIN);
        allowList.set(address(paymentToken), TRUSTED_CURRENCY);

        CrowdinvestingInitializerArguments memory arguments = CrowdinvestingInitializerArguments({
            owner: companyAdmin,
            currencyReceiver: RECEIVER,
            minAmountPerBuyer: 1000 * 10 ** 18,
            maxAmountPerBuyer: 2000 * 10 ** 18,
            tokenPrice: 688,
            priceMin: 688,
            priceMax: 688,
            maxAmountOfTokenToBeSold: 10 * 1000 * 10 ** 18,
            currency: paymentToken,
            token: token,
            lastBuyDate: 0,
            priceOracle: address(0),
            tokenHolder: address(0)
        });
        Crowdinvesting crowdinvesting = Crowdinvesting(
            fundraisingFactory.createCrowdinvestingClone(0, address(forwarder), arguments)
        );

        // register domainSeparator with forwarder
        domainSeparator = ERC2771helper.registerDomain(forwarder, "some_string", "some_version_string");

        // register request type with forwarder
        requestType = ERC2771helper.registerRequestType(forwarder, "some_function_name", "no_real_parameters");

        /*
         * increase minting allowance
         */
        //vm.prank(companyAdmin);
        //token.increaseMintingAllowance(minter, tokenMintAmount);

        // 1. build request
        bytes memory payload = abi.encodeWithSelector(
            token.increaseMintingAllowance.selector,
            minter,
            _tokenMintAmount
        );

        IForwarder.ForwardRequest memory request = IForwarder.ForwardRequest({
            from: companyAdmin,
            to: address(token),
            value: 0,
            gas: 1000000,
            nonce: forwarder.getNonce(companyAdmin),
            data: payload,
            validUntil: 0
        });

        bytes memory suffixData = "0";

        // 2. pack and hash request
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                domainSeparator,
                keccak256(forwarder._getEncoded(request, requestType, suffixData))
            )
        );

        // 3. sign request
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(COMPANY_ADMIN_PRIVATE_KEY, digest);
        bytes memory signature = abi.encodePacked(r, s, v); // https://docs.openzeppelin.com/contracts/2.x/utilities

        require(digest.recover(signature) == request.from, "FWD: signature mismatch");

        assertEq(token.mintingAllowance(minter), 0, "Minting allowance is not 0");

        // 4.  execute request
        vm.prank(PLATFORM_HOT_WALLET);
        forwarder.execute(request, domainSeparator, requestType, suffixData, signature);

        assertEq(token.mintingAllowance(minter), _tokenMintAmount, "Minting allowance is not tokenMintAmount");

        /*
         * mint tokens
         */

        // 1. build request
        payload = abi.encodeWithSelector(token.mint.selector, INVESTOR, _tokenMintAmount);

        request = IForwarder.ForwardRequest({
            from: minter,
            to: address(token),
            value: 0,
            gas: 1000000,
            nonce: forwarder.getNonce(minter),
            data: payload,
            validUntil: 0
        });

        // 2. pack and hash request
        digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                domainSeparator,
                keccak256(forwarder._getEncoded(request, requestType, suffixData))
            )
        );

        // 3. sign request
        (v, r, s) = vm.sign(MINTER_PRIVATE_KEY, digest);
        signature = abi.encodePacked(r, s, v); // https://docs.openzeppelin.com/contracts/2.x/utilities

        require(digest.recover(signature) == request.from, "FWD: signature mismatch");

        // 4.  execute request
        assertEq(token.mintingAllowance(minter), _tokenMintAmount, "Minting allowance is wrong");
        assertEq(token.balanceOf(INVESTOR), 0, "Investor has tokens before mint");
        assertEq(token.balanceOf(FEE_COLLECTOR), 0, "FeeCollector has tokens before mint");

        // send call through forwarder contract
        vm.prank(PLATFORM_HOT_WALLET);
        forwarder.execute(request, domainSeparator, requestType, suffixData, signature);

        assertEq(token.balanceOf(INVESTOR), _tokenMintAmount, "Investor received wrong token amount");
        assertEq(token.mintingAllowance(minter), 0, "Minting allowance is not 0 after mint");
        assertEq(
            token.balanceOf(FEE_COLLECTOR),
            feeSettings.tokenFee(_tokenMintAmount),
            "FeeCollector received wrong token amount"
        );

        /*
         * update settings on crowdinvesting
         */

        // build request
        payload = abi.encodeWithSelector(crowdinvesting.pause.selector);

        request = IForwarder.ForwardRequest({
            from: companyAdmin,
            to: address(crowdinvesting),
            value: 0,
            gas: 1000000,
            nonce: forwarder.getNonce(companyAdmin),
            data: payload,
            validUntil: 0
        });

        suffixData = "0";

        // pack and hash request
        digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                domainSeparator,
                keccak256(forwarder._getEncoded(request, requestType, suffixData))
            )
        );

        // sign request
        //bytes memory signature
        (v, r, s) = vm.sign(COMPANY_ADMIN_PRIVATE_KEY, digest);
        signature = abi.encodePacked(r, s, v); // https://docs.openzeppelin.com/contracts/2.x/utilities

        require(digest.recover(signature) == request.from, "FWD: signature mismatch");

        // // encode buy call and sign it https://book.getfoundry.sh/cheatcodes/sign
        // bytes memory buyCallData = abi.encodeWithSignature("buy(uint256)", type(uint256).max, tokenBuyAmount);

        /*
            execute request and check results
        */
        assertEq(crowdinvesting.paused(), false);

        // send call through forwarder contract
        forwarder.execute(request, domainSeparator, requestType, suffixData, signature);
        assertEq(crowdinvesting.paused(), true);
    }
}
