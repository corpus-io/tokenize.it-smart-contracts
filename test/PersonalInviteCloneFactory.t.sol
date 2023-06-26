// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.13;

import "../lib/forge-std/src/Test.sol";
import "../contracts/Token.sol";
import "../contracts/PersonalInvite.sol";
import "../contracts/PersonalInviteCloneFactory.sol";
import "../contracts/FeeSettings.sol";
import "./resources/FakePaymentToken.sol";

contract PersonalInviteCloneFactoryyTest is Test {
    event Deploy(address indexed addr);

    PersonalInviteCloneFactory factory;

    AllowList list;
    FeeSettings feeSettings;

    Token token;
    FakePaymentToken currency; // todo: add different ERC20 token as currency!

    uint256 MAX_INT = type(uint256).max;

    address public constant admin = 0x0109709eCFa91a80626FF3989D68f67f5b1dD120;
    address public constant buyer = 0x1109709ecFA91a80626ff3989D68f67F5B1Dd121;
    address public constant mintAllower = 0x2109709EcFa91a80626Ff3989d68F67F5B1Dd122;
    address public constant minter = 0x3109709ECfA91A80626fF3989D68f67F5B1Dd123;
    address public constant owner = 0x6109709EcFA91A80626FF3989d68f67F5b1dd126;
    address public constant receiver = 0x7109709eCfa91A80626Ff3989D68f67f5b1dD127;
    address public constant paymentTokenProvider = 0x8109709ecfa91a80626fF3989d68f67F5B1dD128;
    address public constant trustedForwarder = 0x9109709EcFA91A80626FF3989D68f67F5B1dD129;

    uint256 public constant price = 10000000;

    // function calcAddress(bytes memory bytecode, uint salt, address sender) public pure returns (address) {
    //     bytes32 saltBytes = bytes32(salt);
    //     bytes32 hash = keccak256(abi.encodePacked(bytes1(0xff), sender, saltBytes, keccak256(bytecode)));
    //     return address(uint160(uint256(hash)));
    // }

    // function testCalcAddressWithExample() public view {
    //     // example taken from https://docs.ethers.io/v5/api/utils/address/#utils-getCreate2Address
    //     address sender = 0x8ba1f109551bD432803012645Ac136ddd64DBA72;
    //     uint salt = 0x7c5ea36004851c764c44143b1dcb59679b11c9a68e5f41497f6cf3d480715331;
    //     string memory hexString = "0x6394198df16000526103ff60206004601c335afa6040516060f3";
    //     bytes memory bytecode = bytes(hexString);

    //     address actual = calcAddress(bytecode, salt, sender);
    //     address expected = 0x533ae9d683B10C02EbDb05471642F85230071FC3;

    //     console.log("bytecode: %s", string(bytecode));

    //     console.log("actual: %s", actual);
    //     console.log("expected: %s", expected);
    //     //assertEq(actual, expected);

    //     // TODO: figure out why this fails

    // }

    function setUp() public {
        list = new AllowList();
        Fees memory fees = Fees(100, 100, 100, 0);
        feeSettings = new FeeSettings(fees, admin);

        token = new Token(trustedForwarder, feeSettings, admin, list, 0x0, "token", "TOK");
        vm.prank(paymentTokenProvider);
        currency = new FakePaymentToken(0, 18);
        // address dummyInvestor = address(0x42);
        // uint256 dummyAmount = 1;
        // vm.prank(paymentTokenProvider);
        // currency.mint(buyer, 1e20);
        // vm.prank(dummyInvestor);
        // currency.approve(expectedAddress, 1e20);
        // need to deploy a personalInvite first
        PersonalInviteCloneable inviteImplementation = new PersonalInviteCloneable();
        // dummyInvestor,
        // dummyInvestor,
        // dummyInvestor,
        // 1,
        // 1,
        // 1e28,
        // currency,
        // token

        factory = new PersonalInviteCloneFactory(address(inviteImplementation));
    }

    function testDeployContract() public {
        uint256 amount = 20000000000000;
        uint256 expiration = block.timestamp + 1000;

        bytes32 hash = keccak256(abi.encodePacked(buyer, buyer, receiver, amount, price, expiration, currency, token));

        address expectedAddress = factory.predictCloneAddress(hash);

        // make sure no contract lives here yet
        uint256 len;
        assembly {
            len := extcodesize(expectedAddress)
        }
        assert(len == 0);

        vm.prank(admin);
        token.increaseMintingAllowance(expectedAddress, amount);

        uint256 totalPrice = 1e20; //Math.ceilDiv(amount * price, 10 ** token.decimals());

        vm.prank(paymentTokenProvider);
        currency.mint(buyer, totalPrice);

        vm.prank(buyer);
        currency.approve(expectedAddress, totalPrice);

        uint256 gasBefore = gasleft();
        factory.createPersonalInvite(hash, buyer, buyer, receiver, amount, price, expiration, currency, token);
        uint256 gasAfter = gasleft();
        console.log("gas used: %s", gasBefore - gasAfter);

        // make sure contract lives here now
        assembly {
            len := extcodesize(expectedAddress)
        }
        assert(len != 0);
    }
}
