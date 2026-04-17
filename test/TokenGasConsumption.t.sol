// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import "../lib/forge-std/src/Test.sol";
import "../lib/forge-std/src/console.sol";
import "../contracts/factories/TokenProxyFactory.sol";
import "./resources/CloneCreators.sol";

contract tokenTest is Test {
    Token token;
    AllowList allowList;
    FeeSettings feeSettings;
    address public constant TRUSTED_FORWARDER = 0x9109709EcFA91A80626FF3989D68f67F5B1dD129;
    address public constant ADMIN = 0x0109709eCFa91a80626FF3989D68f67f5b1dD120;
    address public constant REQUIRER = 0x1109709ecFA91a80626ff3989D68f67F5B1Dd121;
    address public constant MINT_ALLOWER = 0x2109709EcFa91a80626Ff3989d68F67F5B1Dd122;
    address public constant MINTER = 0x3109709ECfA91A80626fF3989D68f67F5B1Dd123;
    address public constant BURNER = 0x4109709eCFa91A80626ff3989d68F67f5b1DD124;
    address public constant TRANSFERER_ADMIN = 0x5109709EcFA91a80626ff3989d68f67F5B1dD125;
    address public constant TRANSFERER = 0x6109709EcFA91A80626FF3989d68f67F5b1dd126;
    address public constant PAUSER = 0x7109709eCfa91A80626Ff3989D68f67f5b1dD127;
    address public constant FEE_SETTINGS_AND_ALLOW_LIST_OWNER = 0x8109709ecfa91a80626fF3989d68f67F5B1dD128;

    uint256 requirements = 934332;

    event RequirementsChanged(uint256 newRequirements);

    function setUp() public {
        allowList = createAllowList(TRUSTED_FORWARDER, FEE_SETTINGS_AND_ALLOW_LIST_OWNER);
        feeSettings = createFeeSettings(
            TRUSTED_FORWARDER,
            FEE_SETTINGS_AND_ALLOW_LIST_OWNER,
            buildFeeTypes(
                100,
                100,
                100,
                FEE_SETTINGS_AND_ALLOW_LIST_OWNER,
                FEE_SETTINGS_AND_ALLOW_LIST_OWNER,
                FEE_SETTINGS_AND_ALLOW_LIST_OWNER
            )
        );

        address tokenHolder = address(this);

        vm.startPrank(FEE_SETTINGS_AND_ALLOW_LIST_OWNER);
        allowList.set(PAUSER, requirements);
        allowList.set(TRANSFERER, requirements);
        allowList.set(tokenHolder, requirements);
        allowList.set(ADMIN, requirements);

        vm.stopPrank();

        Token implementation = new Token(TRUSTED_FORWARDER);
        TokenProxyFactory tokenCloneFactory = new TokenProxyFactory(address(implementation));

        token = Token(
            tokenCloneFactory.createTokenProxy(
                0,
                TRUSTED_FORWARDER,
                feeSettings,
                ADMIN,
                allowList,
                requirements,
                "testToken",
                "TEST"
            )
        );
        console.log(msg.sender);

        // set up roles
        vm.startPrank(ADMIN);
        token.grantRole(token.MINTALLOWER_ROLE(), MINT_ALLOWER);
        token.increaseMintingAllowance(MINTER, 200);
        vm.stopPrank();

        vm.prank(MINTER);
        token.mint(tokenHolder, 100);
        vm.prank(MINTER);
        token.mint(PAUSER, 100);
        vm.prank(PAUSER);
        token.approve(ADMIN, 100); // for transferFrom test case

        assertTrue(token.balanceOf(tokenHolder) == 100, "tokenHolder balance is wrong");
        assertTrue(token.balanceOf(PAUSER) == 100, "PAUSER balance is wrong");
    }

    function testSimpleTransfer() public {
        vm.prank(PAUSER);
        token.transfer(TRANSFERER, 100);
    }

    function test10Transfers() public {
        vm.startPrank(PAUSER);
        token.transfer(TRANSFERER, 10);
        token.transfer(TRANSFERER, 12);
        token.transfer(TRANSFERER, 13);
        token.transfer(TRANSFERER, 14);
        token.transfer(TRANSFERER, 15);
        vm.stopPrank();

        vm.startPrank(TRANSFERER);
        token.transfer(PAUSER, 10);
        token.transfer(PAUSER, 12);
        token.transfer(PAUSER, 13);
        token.transfer(PAUSER, 14);
        token.transfer(PAUSER, 15);
        vm.stopPrank();
    }

    function testGrantAllowance() public {
        vm.prank(PAUSER);
        token.approve(TRANSFERER, 100);
    }

    function testSimpleTransferFrom() public {
        vm.prank(ADMIN);
        token.transferFrom(PAUSER, ADMIN, 100);
    }
}
