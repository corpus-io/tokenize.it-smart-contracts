// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "../lib/forge-std/src/Test.sol";
import "../contracts/Token.sol";
import "../contracts/FeeSettings.sol";
import "./resources/FakePaymentToken.sol";
import "./resources/ERC2771Helper.sol";
import "@opengsn/contracts/src/forwarder/Forwarder.sol"; // chose specific version to avoid import error: yarn add @opengsn/contracts@2.2.5

contract TokenERC2771Test is Test {
    using ECDSA for bytes32; // for verify with var.recover()

    AllowList allowList;
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

    address public constant trustedForwarder =
        0x9109709EcFA91A80626FF3989D68f67F5B1dD129;

    // DO NOT USE IN PRODUCTION! Key was generated online for testing only.
    uint256 public constant companyAdminPrivateKey =
        0x3c69254ad72222e3ddf37667b8173dd773bdbdfd93d4af1d192815ff0662de5f;
    address public companyAdmin; // = 0x38d6703d37988C644D6d31551e9af6dcB762E618;

    address public constant mintAllower =
        0x2109709EcFa91a80626Ff3989d68F67F5B1Dd122;
    address public constant investor =
        0x6109709EcFA91A80626FF3989d68f67F5b1dd126;

    address public constant receiver =
        0x7109709eCfa91A80626Ff3989D68f67f5b1dD127;
    address public constant platformHotWallet =
        0x8109709ecfa91a80626fF3989d68f67F5B1dD128;
    address public constant sender = 0x9109709EcFA91A80626FF3989D68f67F5B1dD129;

    address public constant platformAdmin =
        0x3109709ECfA91A80626fF3989D68f67F5B1Dd123;
    address public constant feeCollector =
        0x0109709eCFa91a80626FF3989D68f67f5b1dD120;

    uint256 public constant tokenFeeDenominator = 100;
    uint256 public constant continuousFundraisingFeeDenominator = 50;
    uint256 public constant personalInviteFeeDenominator = 70;

    function setUp() public {
        // calculate address
        companyAdmin = vm.addr(companyAdminPrivateKey);

        // deploy allow list
        vm.prank(platformAdmin);
        allowList = new AllowList();

        // deploy fee settings
        Fees memory fees = Fees(
            tokenFeeDenominator,
            continuousFundraisingFeeDenominator,
            personalInviteFeeDenominator,
            0
        );
        vm.prank(platformAdmin);
        feeSettings = new FeeSettings(fees, feeCollector);

        // deploy helper functions (only for testing with foundry)
        ERC2771helper = new ERC2771Helper();
    }

    function mintWithERC2771(Forwarder forwarder) public {
        uint256 tokenMintAmount = 837 * 10 ** 18;

        // deploy company token
        token = new Token(
            address(forwarder),
            feeSettings,
            companyAdmin,
            allowList,
            0x0,
            "TESTTOKEN",
            "TEST"
        );

        // allow raise contract to mint
        bytes32 roleMintAllower = token.MINTALLOWER_ROLE();

        // todo: this, too, should be meta txs!
        vm.prank(companyAdmin);
        token.grantRole(roleMintAllower, companyAdmin);
        vm.prank(companyAdmin);
        token.increaseMintingAllowance(companyAdmin, tokenMintAmount);

        // register domain and request type
        bytes32 domainSeparator = ERC2771helper.registerDomain(
            forwarder,
            Strings.toHexString(uint256(uint160(address(token))), 20),
            "1"
        );
        bytes32 requestType = ERC2771helper.registerRequestType(
            forwarder,
            "mint",
            "address _to,uint256 _amount"
        );

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
            token.mint.selector,
            investor,
            tokenMintAmount
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

        // pack and hash request
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                domainSeparator,
                keccak256(
                    forwarder._getEncoded(request, requestType, suffixData)
                )
            )
        );

        // sign request
        //bytes memory signature
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            companyAdminPrivateKey,
            digest
        );
        bytes memory signature = abi.encodePacked(r, s, v); // https://docs.openzeppelin.com/contracts/2.x/utilities

        require(
            digest.recover(signature) == request.from,
            "FWD: signature mismatch"
        );

        // // encode buy call and sign it https://book.getfoundry.sh/cheatcodes/sign
        // bytes memory buyCallData = abi.encodeWithSignature("buy(uint256)", tokenBuyAmount);

        /*
            execute request and check results
        */
        assertEq(
            token.mintingAllowance(companyAdmin),
            tokenMintAmount,
            "Minting allowance is wrong"
        );
        assertEq(
            token.balanceOf(investor),
            0,
            "Investor has tokens before mint"
        );

        // send call through forwarder contract
        vm.prank(platformHotWallet);
        forwarder.execute(
            request,
            domainSeparator,
            requestType,
            suffixData,
            signature
        );

        assertEq(
            token.balanceOf(investor),
            tokenMintAmount,
            "Investor received wrong token amount"
        );

        // /*
        //     try to execute request again (must fail)
        // */
        // vm.expectRevert("FWD: nonce mismatch");
        // forwarder.execute(
        //     request,
        //     domainSeparator,
        //     requestType,
        //     suffixData,
        //     signature
        // );
    }

    function testMintWithLocalForwarder() public {
        mintWithERC2771(new Forwarder());
    }

    function testBuyWithMainnetGSNForwarder() public {
        // uses deployed forwarder on mainnet with fork. https://docs-v2.opengsn.org/networks/ethereum/mainnet.html
        mintWithERC2771(
            Forwarder(payable(0xAa3E82b4c4093b4bA13Cb5714382C99ADBf750cA))
        );
    }
}
