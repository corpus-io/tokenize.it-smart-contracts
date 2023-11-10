// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.22;

import "../lib/forge-std/src/Test.sol";
import "../contracts/TokenCloneFactory.sol";
import "../contracts/PrivateOffer.sol";
import "../contracts/PrivateOfferFactory.sol";
import "../contracts/FeeSettings.sol";

contract PrivateOfferFactoryTest is Test {
    event Deploy(address indexed addr);

    PrivateOfferFactory factory;

    AllowList list;
    FeeSettings feeSettings;

    Token token;
    Token currency; // todo: add different ERC20 token as currency!

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

    function setUp() public {
        factory = new PrivateOfferFactory();
        list = new AllowList();
        Fees memory fees = Fees(1, 100, 1, 100, 1, 100, 0);
        feeSettings = new FeeSettings(fees, admin, admin, admin);

        Token implementation = new Token(trustedForwarder);
        TokenCloneFactory tokenCloneFactory = new TokenCloneFactory(address(implementation));
        token = Token(
            tokenCloneFactory.createTokenClone(0, trustedForwarder, feeSettings, admin, list, 0x0, "token", "TOK")
        );
        currency = Token(
            tokenCloneFactory.createTokenClone(0, trustedForwarder, feeSettings, admin, list, 0x0, "currency", "CUR")
        );
    }

    function testDeployContract(uint256 rawSalt) public {
        //uint256 rawSalt = 0;
        bytes32 salt = bytes32(rawSalt);

        //bytes memory creationCode = type(PrivateOffer).creationCode;
        uint256 amount = 20000000000000;
        uint256 expiration = block.timestamp + 1000;

        address expectedAddress = factory.getAddress(
            salt,
            buyer,
            buyer,
            receiver,
            amount,
            price,
            expiration,
            IERC20(address(currency)),
            IERC20(address(token))
        );

        // make sure no contract lives here yet
        uint256 len;
        assembly {
            len := extcodesize(expectedAddress)
        }
        assert(len == 0);

        vm.prank(admin);
        token.increaseMintingAllowance(expectedAddress, amount);

        vm.prank(admin);
        currency.increaseMintingAllowance(admin, amount * price);

        vm.prank(admin);
        currency.mint(buyer, amount * price);
        vm.prank(buyer);
        currency.approve(expectedAddress, amount * price);

        vm.expectEmit(true, true, true, true, address(factory));
        emit Deploy(expectedAddress);
        factory.deploy(
            salt,
            buyer,
            buyer,
            receiver,
            amount,
            price,
            expiration,
            IERC20(address(currency)),
            IERC20(address(token))
        );

        // make sure contract lives here now
        assembly {
            len := extcodesize(expectedAddress)
        }
        assert(len != 0);
    }
}
