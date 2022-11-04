// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "../lib/forge-std/src/Test.sol";
import "../contracts/CorpusToken.sol";
import "../contracts/PrivateInvite.sol";
import "../contracts/DeterministicDeployFactory.sol";



contract PrivateInviteTest is Test {
    DeterministicDeployFactory factory;

    AllowList list;
    CorpusToken token;
    CorpusToken currency; // todo: add different ERC20 token as currency!

    uint256 MAX_INT = 115792089237316195423570985008687907853269984665640564039457584007913129639935;

    address public constant admin = 0x0109709eCFa91a80626FF3989D68f67f5b1dD120;
    address public constant buyer = 0x1109709ecFA91a80626ff3989D68f67F5B1Dd121;
    address public constant minterAdmin = 0x2109709EcFa91a80626Ff3989d68F67F5B1Dd122;
    address public constant minter = 0x3109709ECfA91A80626fF3989D68f67F5B1Dd123;
    address public constant owner = 0x6109709EcFA91A80626FF3989d68f67F5b1dd126;
    address public constant receiver = 0x7109709eCfa91A80626Ff3989D68f67f5b1dD127;
    address public constant paymentTokenProvider = 0x8109709ecfa91a80626fF3989d68f67F5B1dD128;
    address public constant trustedForwarder = 0x9109709EcFA91A80626FF3989D68f67F5B1dD129;


    uint256 public constant price = 10000000;
 

    function setUp() public {
        factory = new DeterministicDeployFactory();
        list = new AllowList();
        token = new CorpusToken(admin, list, 0x0, "token", "TOK");
        currency = new CorpusToken(admin, list, 0x0, "currency", "CUR");
    }

    function testAcceptDeal() public {
        uint rawSalt = 0;
        bytes32 salt = bytes32(rawSalt);

        //bytes memory creationCode = type(PrivateInvite).creationCode;
        uint amount = 20000000000000;
        uint expiration = block.timestamp + 1000;

        address expectedAddress = factory.getAddress(salt, payable(buyer), payable(receiver), amount, price, expiration, currency, MintableERC20(address(token)));

        vm.prank(admin);
        token.setUpMinter(expectedAddress, amount);

        vm.prank(admin);
        currency.setUpMinter(admin, amount*price);

        uint tokenDecimals = token.decimals();

        vm.prank(admin);
        currency.mint(buyer, amount*price / 10**tokenDecimals);
        vm.prank(buyer);
        currency.approve(expectedAddress, amount*price / 10**tokenDecimals);

        // make sure balances are as expected before deployment
        assertEq(currency.balanceOf(buyer), amount*price / 10**tokenDecimals);
        assertEq(currency.balanceOf(receiver), 0);
        assertEq(token.balanceOf(buyer), 0);

        address inviteAddress = factory.deploy(salt, payable(buyer), payable(receiver), amount, price, expiration, currency, MintableERC20(address(token)));

        assertEq(inviteAddress, expectedAddress, "deployed contract address is not correct");

        // make sure balances are as expected after deployment
        console.log("buyer balance: %s", currency.balanceOf(buyer));
        console.log("receiver balance: %s", currency.balanceOf(receiver));
        console.log("buyer token balance: %s", token.balanceOf(buyer));
        assertEq(currency.balanceOf(buyer), 0);
        assertEq(currency.balanceOf(receiver), amount*price / 10**tokenDecimals);
        assertEq(token.balanceOf(buyer), amount);
    }
}