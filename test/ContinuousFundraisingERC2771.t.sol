// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "../lib/forge-std/src/Test.sol";
import "../contracts/CorpusToken.sol";
import "../contracts/ContinuousFundraising.sol";
import "./FakePaymentToken.sol";
import "./MaliciousPaymentToken.sol";
import "@opengsn/contracts/src/forwarder/Forwarder.sol"; // chose specific version to avoid import error: yarn add @opengsn/contracts@2.2.5


contract ContinuousFundraisingTest is Test {
    ContinuousFundraising raise;
    AllowList list;
    CorpusToken token;
    FakePaymentToken paymentToken;
    Forwarder trustedForwarder;


    address public constant admin = 0x0109709eCFa91a80626FF3989D68f67f5b1dD120;
    address public constant buyer = 0x1109709ecFA91a80626ff3989D68f67F5B1Dd121;
    address public constant minterAdmin = 0x2109709EcFa91a80626Ff3989d68F67F5B1Dd122;
    address public constant minter = 0x3109709ECfA91A80626fF3989D68f67F5B1Dd123;
    address public constant owner = 0x6109709EcFA91A80626FF3989d68f67F5b1dd126;
    address public constant receiver = 0x7109709eCfa91A80626Ff3989D68f67f5b1dD127;
    address public constant paymentTokenProvider = 0x8109709ecfa91a80626fF3989d68f67F5B1dD128;
    address public constant sender = 0x9109709EcFA91A80626FF3989D68f67F5B1dD129;



    uint8 public constant paymentTokenDecimals = 6;
    uint256 public constant paymentTokenAmount = 1000 * 10**paymentTokenDecimals;
    
    uint256 public constant price = 7 * 10**paymentTokenDecimals; // 7 payment tokens per token
    
    uint256 public constant maxAmountOfTokenToBeSold = 20 * 10**18; // 20 token
    uint256 public constant maxAmountPerBuyer = maxAmountOfTokenToBeSold / 2; // 10 token
    uint256 public constant minAmountPerBuyer = maxAmountOfTokenToBeSold / 200; // 0.1 token



    function setUp() public {
        list = new AllowList();
        token = new CorpusToken(admin, list, 0x0, "TESTTOKEN", "TEST");
        trustedForwarder = new Forwarder();

        // set up currency
        vm.prank(paymentTokenProvider);
        paymentToken = new FakePaymentToken(paymentTokenAmount, paymentTokenDecimals); // 1000 tokens with 6 decimals
        // transfer currency to buyer
        vm.prank(paymentTokenProvider);
        paymentToken.transfer(buyer, paymentTokenAmount);
        assertTrue(paymentToken.balanceOf(buyer) == paymentTokenAmount);

        vm.prank(owner);
        raise = new ContinuousFundraising(address(trustedForwarder), payable(receiver), minAmountPerBuyer, maxAmountPerBuyer, price, maxAmountOfTokenToBeSold, paymentToken, MintableERC20(address(token)));

        // allow raise contract to mint
        bytes32 roleMinterAdmin = token.MINTERADMIN_ROLE();

        vm.prank(admin);
        token.grantRole(roleMinterAdmin, minterAdmin);
        vm.prank(minterAdmin);
        token.setUpMinter(address(raise), maxAmountOfTokenToBeSold);

        // give raise contract allowance
        vm.prank(buyer);
        paymentToken.approve(address(raise), paymentTokenAmount);
    }

    function testBuyWithERC2771() public {
        uint256 tokenBuyAmount = 5 * 10**token.decimals();
        uint256 costInPaymentToken = tokenBuyAmount * price / 10**18;

        assert(costInPaymentToken == 35 * 10**paymentTokenDecimals); // 35 payment tokens, manually calculated

        uint256 paymentTokenBalanceBefore = paymentToken.balanceOf(buyer);

        vm.prank(sender);

        /*
         register domain separator - does not work yet
         encodes which contract to call
        */
        string memory name = "ContinuousFundraising"; // 
        // https://eips.ethereum.org/EIPS/eip-712#definition-of-domainseparator
        // use chainId, address, name for proper implementation. 
        uint version = 1; 
        bytes32 domainSeparatorName = keccak256(abi.encode(
            keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
            keccak256(bytes(name)),
            keccak256(bytes("1")),
            1,
            address(raise)
        ));

        vm.recordLogs();
        trustedForwarder.registerDomainSeparator("test", "1");

        Vm.Log[] memory logs = vm.getRecordedLogs();

        bytes32 domainSeparator = logs[0].topics[1]; // internally, the forwarder calls this domainHash in registerDomainSeparator. But expects is as domainSeparator in execute().
        //bytes32 domainHash = keccak256(abi.encodePacked(domainValue));
        console.log("domainHash", vm.toString(domainSeparator));
        console.log("Hash registered: ", trustedForwarder.domains(domainSeparator));
        

        // for (uint i = 0; i < logs.length; i++) {
        //     Vm.Log memory log = logs[i];
        //     // if (log.sig == "DomainSeparatorRegistered(bytes32)") {
        //     //     bytes32 domainSeparator = abi.decode(log.data, (bytes32));
        //     //     raise.setDomainSeparator(domainSeparator);
        //     // }
        //     //console.log(vm.toString(log.sig));
        //     console.log("Number %i", i);
        //     console.log(vm.toString(log.data));
        //     console.log(vm.toString(log.topics.length));
        //     console.log(vm.toString(log.topics[0]));
        //     console.log(vm.toString(log.topics[1]));
        //     bytes32 hash = keccak256(abi.encodePacked(log.topics[1]));
        //     console.log("Hashed: %s", vm.toString(hash));
        //     //console.log(vm.toString(log.topics[2]));
        //     console.log("Hash registered: ", trustedForwarder.domains(log.topics[1]));
        // }

        // string memory log = vm.toString(logs[0].data);

        // console.log(log);

        // use expectEmit to get domain separator

        /* 
         register request type - does not work yet
         Might encode which function to call and which parameters to pass
        */
        vm.recordLogs();
        trustedForwarder.registerRequestType("buy", "address buyer,uint256 amount");
        logs = vm.getRecordedLogs();
        bytes32 requestType = logs[0].topics[1]; // internally, the forwarder calls this domainHash in registerDomainSeparator. But expects is as domainSeparator in execute().
        //bytes32 domainHash = keccak256(abi.encodePacked(domainValue));
        console.log("requestType", vm.toString(requestType));
        console.log("requestType registered: ", trustedForwarder.typeHashes(requestType));


        /*
            create data and signature for execution - does not work yet
        */
        // // https://github.com/foundry-rs/foundry/issues/3330
        // // https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/utils/cryptography/ECDSA.sol
        // bytes32 digest = ECDSA.toTypedDataHash(domainSeparator, keccak256(payload));
        // (uint8 v, bytes32 r, bytes32 s) = vm.sign(privKey, digest);

        // // encode buy call and sign it https://book.getfoundry.sh/cheatcodes/sign
        // bytes memory buyCallData = abi.encodeWithSignature("buy(uint256)", tokenBuyAmount);

        // address _buyer = vm.addr(1);
        // bytes32 hash = keccak256(buyCallData);
        // (uint8 v, bytes32 r, bytes32 s) = vm.sign(1, hash);

        // address signer = ecrecover(hash, v, r, s);
        // assertEq(alice, signer); // [PASS]

        // // send call through forwarder contract
        // raise.buy(tokenBuyAmount); // this test fails if 5 * 10**18 is replaced with 5 * 10**token.decimals() for this argument, even though they should be equal


        // assertTrue(paymentToken.balanceOf(buyer) == paymentTokenBalanceBefore - costInPaymentToken);
        // assertTrue(token.balanceOf(buyer) == tokenBuyAmount);
        // assertTrue(paymentToken.balanceOf(receiver) == costInPaymentToken);
        // assertTrue(raise.tokensSold() == tokenBuyAmount);
        // assertTrue(raise.tokensBought(buyer) == tokenBuyAmount);
    }

}