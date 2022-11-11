// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "../lib/forge-std/src/Test.sol";
import "../contracts/Token.sol";

contract tokenTest is Test {
    Token token;
    AllowList allowList;
    address public constant trustedForwarder =
        0x9109709EcFA91A80626FF3989D68f67F5B1dD129;
    address public constant admin = 0x0109709eCFa91a80626FF3989D68f67f5b1dD120;
    address public constant requirer =
        0x1109709ecFA91a80626ff3989D68f67F5B1Dd121;
    address public constant minterAdmin =
        0x2109709EcFa91a80626Ff3989d68F67F5B1Dd122;
    address public constant minter = 0x3109709ECfA91A80626fF3989D68f67F5B1Dd123;
    address public constant burner = 0x4109709eCFa91A80626ff3989d68F67f5b1DD124;
    address public constant transfererAdmin =
        0x5109709EcFA91a80626ff3989d68f67F5B1dD125;
    address public constant transferer =
        0x6109709EcFA91A80626FF3989d68f67F5b1dd126;
    address public constant pauser = 0x7109709eCfa91A80626Ff3989D68f67f5b1dD127;

    event RequirementsChanged(uint256 newRequirements);

    function setUp() public {
        vm.prank(admin);
        allowList = new AllowList();
        token = new Token(
            trustedForwarder,
            admin,
            allowList,
            0x0,
            "testToken",
            "TEST"
        );
        console.log(msg.sender);

        // set up roles
        vm.startPrank(admin);
        token.grantRole(token.MINTER_ROLE(), minter);
        token.grantRole(token.BURNER_ROLE(), burner);
        token.grantRole(token.TRANSFERER_ROLE(), transferer);
        token.grantRole(token.PAUSER_ROLE(), pauser);
        token.grantRole(token.REQUIREMENT_ROLE(), requirer);
        token.grantRole(token.MINTERADMIN_ROLE(), minterAdmin);
        token.grantRole(token.TRANSFERERADMIN_ROLE(), transfererAdmin);

        // revoke roles from admin
        token.revokeRole(token.MINTER_ROLE(), admin);
        token.revokeRole(token.BURNER_ROLE(), admin);
        token.revokeRole(token.TRANSFERER_ROLE(), admin);
        token.revokeRole(token.PAUSER_ROLE(), admin);
        token.revokeRole(token.REQUIREMENT_ROLE(), admin);
        token.revokeRole(token.MINTERADMIN_ROLE(), admin);
        token.revokeRole(token.TRANSFERERADMIN_ROLE(), admin);

        vm.stopPrank();
    }

    function testSetUp() public {
        assertTrue(
            token.hasRole(token.getRoleAdmin(token.REQUIREMENT_ROLE()), admin)
        );
        assertTrue(token.allowList() == allowList);
        assertTrue(
            keccak256(bytes(token.name())) == keccak256(bytes("testToken"))
        );
        assertTrue(
            keccak256(bytes(token.symbol())) == keccak256(bytes("TEST"))
        );
    }

    function testFailAdmin() public {
        assertTrue(
            token.hasRole(
                token.getRoleAdmin(token.MINTER_ROLE()),
                address(this)
            )
        );
    }

    function testFailAdmin2() public {
        assertTrue(
            token.hasRole(token.getRoleAdmin(token.MINTER_ROLE()), msg.sender)
        );
    }

    /**
    @notice test that addresses that are not the admin cannot perform the minter admin tasks
     */
    function testFailAdminX(address x) public {
        // test would fail (to fail) if x = admin. This has actually happened! Abort test in that case.
        vm.assume(x != admin);
        assertTrue(token.hasRole(token.getRoleAdmin(token.MINTER_ROLE()), x));
    }

    function testAdmin() public {
        assertTrue(
            token.hasRole(token.getRoleAdmin(token.REQUIREMENT_ROLE()), admin)
        );
    }

    function testMinterAdmin() public {
        assertTrue(
            token.hasRole(token.getRoleAdmin(token.MINTER_ROLE()), minterAdmin)
        );
    }

    function testMinterAdmin(address x) public {
        vm.assume(x != admin);
        assertFalse(token.hasRole(token.getRoleAdmin(token.MINTER_ROLE()), x));
    }

    function testFailSetRequirements() public {
        token.setRequirements(3);
    }

    function testDecimals() public {
        assertTrue(token.decimals() == 18);
    }

    function testFailSetRequirementsAdmin() public {
        // admin has not the Requirements role, only the right to grant this role
        vm.prank(admin);
        token.setRequirements(3);
    }

    function testFailSetRequirementsX(address X) public {
        // this contract has not the Requirements role
        vm.prank(X);
        token.setRequirements(3);
    }

    function testSetRoleRequirements() public {
        bytes32 role = token.REQUIREMENT_ROLE();
        vm.prank(admin);
        token.grantRole(role, requirer);
        assertTrue(token.hasRole(role, requirer));
    }

    function testSetRoleMinter() public {
        bytes32 roleMinterAdmin = token.MINTERADMIN_ROLE();
        bytes32 roleMinter = token.MINTER_ROLE();

        vm.prank(admin);
        token.grantRole(roleMinterAdmin, minterAdmin);
        vm.prank(minterAdmin);
        token.grantRole(roleMinter, minter);
        assertTrue(token.hasRole(roleMinter, minter));
    }

    function testSetRoleBurner() public {
        bytes32 role = token.BURNER_ROLE();
        vm.prank(admin);
        token.grantRole(role, burner);
        assertTrue(token.hasRole(role, burner));
    }

    function testSetRoleTransferer() public {
        bytes32 roleTransfererAdmin = token.TRANSFERERADMIN_ROLE();
        bytes32 roleTransferer = token.TRANSFERER_ROLE();

        vm.prank(admin);
        token.grantRole(roleTransfererAdmin, transfererAdmin);
        vm.prank(transfererAdmin);
        token.grantRole(roleTransferer, transferer);
        assertTrue(token.hasRole(roleTransferer, transferer));
    }

    function testSetRolePauser() public {
        bytes32 role = token.PAUSER_ROLE();
        vm.prank(admin);
        token.grantRole(role, pauser);
        assertTrue(token.hasRole(role, pauser));
    }

    function testSetRoleDefaultAdmin() public {
        bytes32 role = token.DEFAULT_ADMIN_ROLE();
        vm.prank(admin);
        token.grantRole(role, pauser);
        assertTrue(token.hasRole(role, pauser));
    }

    // function testFailRemoveLastDefaultAdmin() public {
    //     bytes32 role = token.DEFAULT_ADMIN_ROLE();
    //     vm.prank(admin);
    //     token.revokeRole(role, admin);
    // }

    function testSetRequirements() public {
        bytes32 role = token.REQUIREMENT_ROLE();
        vm.prank(admin);
        token.grantRole(role, requirer);
        vm.prank(requirer);
        token.setRequirements(3);
        assertTrue(token.requirements() == 3);
    }

    function testFailSetRequirementsWrongRole() public {
        vm.prank(pauser);
        token.setRequirements(3);
        assertTrue(token.requirements() == 3);
    }

    function testUpdateAllowList() public {
        AllowList newAllowList = new AllowList(); // deploy new AllowList
        assertTrue(token.allowList() != newAllowList);
        vm.prank(admin);
        token.setAllowList(newAllowList);
        assertTrue(token.allowList() == newAllowList);
    }

    function testSetUpMinter() public {
        bytes32 roleMinterAdmin = token.MINTERADMIN_ROLE();

        vm.prank(admin);
        token.grantRole(roleMinterAdmin, minterAdmin);
        vm.prank(minterAdmin);
        token.setUpMinter(minter, 2);
        assertTrue(token.mintingAllowance(minter) == 2);

        vm.prank(minter);
        token.mint(pauser, 1);
        assertTrue(token.balanceOf(pauser) == 1);
        assertTrue(token.mintingAllowance(minter) == 1);
    }

    function testMint(uint256 x) public {
        bytes32 roleMinterAdmin = token.MINTERADMIN_ROLE();

        vm.prank(admin);
        token.grantRole(roleMinterAdmin, minterAdmin);
        vm.prank(minterAdmin);
        token.setUpMinter(minter, x);
        assertTrue(token.mintingAllowance(minter) == x);

        vm.prank(minter);
        token.mint(pauser, x);
        assertTrue(token.balanceOf(pauser) == x);
        assertTrue(token.mintingAllowance(minter) == 0);
    }

    function testFailMintAllowanceUsed(uint256 x) public {
        vm.prank(admin);
        token.setUpMinter(minter, x);
        assertTrue(token.mintingAllowance(minter) == x);

        vm.prank(minter);
        token.mint(pauser, x);
        assertTrue(token.balanceOf(pauser) == x);
        assertTrue(token.mintingAllowance(minter) == 0);

        vm.prank(minter);
        token.mint(pauser, 1);
    }

    /**
    @notice test if the minter can mint exactly the amount of tokens that is allowed, but in multiple steps
    */
    function testMintAgain(uint256 totalMintAmount, uint256 steps) public {
        //vm.assume(steps < 200);

        steps = steps % 100; // don't be ridiculous

        vm.prank(minterAdmin);
        token.setUpMinter(minter, totalMintAmount);
        assertTrue(token.mintingAllowance(minter) == totalMintAmount);

        // mint in steps
        uint256 minted = 0;
        for (uint256 i = 0; i < steps; i++) {
            uint256 mintAmount = totalMintAmount / steps;
            vm.prank(minter);
            token.mint(pauser, mintAmount);
            minted += mintAmount;
            assertTrue(token.balanceOf(pauser) == minted);
            assertTrue(
                token.mintingAllowance(minter) == totalMintAmount - minted
            );
        }

        // mint the rest
        if (totalMintAmount - minted > 0) {
            vm.prank(minter);
            token.mint(pauser, totalMintAmount - minted);
            assertTrue(token.balanceOf(pauser) == totalMintAmount);
            assertTrue(token.mintingAllowance(minter) == 0);
        }
    }

    function testFailZeroAllowanceMint(uint256 x) public {
        vm.assume(x > 0);

        vm.prank(admin);
        token.setUpMinter(minter, 0); // set allowance to 0
        assertTrue(token.mintingAllowance(minter) == 0); // check allowance is 0

        vm.prank(minter);
        token.mint(pauser, x); // try to mint -> must fail!
    }

    function testBurn(uint256 x) public {
        bytes32 roleMinterAdmin = token.MINTERADMIN_ROLE();
        bytes32 role = token.BURNER_ROLE();

        vm.prank(admin);
        token.grantRole(roleMinterAdmin, minterAdmin);
        vm.prank(minterAdmin);
        token.setUpMinter(minter, x);
        assertTrue(token.mintingAllowance(minter) == x);

        vm.prank(minter);
        token.mint(pauser, x);
        assertTrue(token.balanceOf(pauser) == x);
        vm.prank(admin);
        token.grantRole(role, burner);
        vm.prank(burner);
        token.burn(pauser, x);
        assertTrue(token.balanceOf(pauser) == 0);
    }

    /*
    Burn with requirements
     */
    function testBurnWithRequirements(uint256 x) public {
        vm.prank(minterAdmin);
        token.setUpMinter(minter, x);
        assertTrue(token.mintingAllowance(minter) == x);

        vm.prank(minter);
        token.mint(pauser, x);
        assertTrue(token.balanceOf(pauser) == x);

        // set requirements
        vm.prank(requirer);
        token.setRequirements(3);

        vm.prank(burner);
        token.burn(pauser, x);
        assertTrue(token.balanceOf(pauser) == 0);
    }

    function testBurn0() public {
        vm.prank(minterAdmin);
        token.setUpMinter(minter, 0);
        assertTrue(token.mintingAllowance(minter) == 0);

        vm.prank(minter);
        token.mint(pauser, 0);
        assertTrue(token.balanceOf(pauser) == 0);

        vm.prank(burner);
        token.burn(pauser, 0);
        assertTrue(token.balanceOf(pauser) == 0);
    }

    function testFailBurn0() public {
        bytes32 roleMinterAdmin = token.MINTERADMIN_ROLE();
        bytes32 role = token.BURNER_ROLE();

        vm.prank(admin);
        token.grantRole(roleMinterAdmin, minterAdmin);
        vm.prank(minterAdmin);
        token.setUpMinter(minter, 0);
        assertTrue(token.mintingAllowance(minter) == 0);

        vm.prank(minter);
        token.mint(pauser, 0);
        assertTrue(token.balanceOf(pauser) == 0);
        vm.prank(admin);
        token.grantRole(role, burner);
        vm.prank(burner);
        token.burn(pauser, 1);
        assertTrue(token.balanceOf(pauser) == 0);
    }

    function testBeforeTokenTransfer() public {
        // create tokens
        bytes32 roleMinterAdmin = token.MINTERADMIN_ROLE();

        vm.prank(admin);
        token.grantRole(roleMinterAdmin, minterAdmin);
        vm.prank(minterAdmin);
        token.setUpMinter(minter, 100);
        assertTrue(token.mintingAllowance(minter) == 100);

        vm.prank(minter);
        token.mint(pauser, 50);
        assertTrue(token.balanceOf(pauser) == 50);

        // create transferer
        bytes32 roleTransfererAdmin = token.TRANSFERERADMIN_ROLE();
        bytes32 roleTransferer = token.TRANSFERER_ROLE();

        vm.prank(admin);
        token.grantRole(roleTransfererAdmin, transfererAdmin);

        vm.prank(transfererAdmin);
        token.grantRole(roleTransferer, transferer);
        assertTrue(token.hasRole(roleTransferer, transferer));

        vm.prank(transfererAdmin);
        token.grantRole(roleTransferer, burner);
        assertTrue(token.hasRole(roleTransferer, burner));

        // move tokens around
        vm.prank(pauser);
        token.transfer(burner, 50);
        assertTrue(token.balanceOf(burner) == 50);
    }

    function testFailBeforeTokenTransferRequirements1() public {
        // create tokens
        bytes32 roleMinterAdmin = token.MINTERADMIN_ROLE();

        vm.prank(admin);
        token.grantRole(roleMinterAdmin, minterAdmin);
        vm.prank(minterAdmin);
        token.setUpMinter(minter, 100);
        assertTrue(token.mintingAllowance(minter) == 100);

        //testSetRequirements

        bytes32 role = token.REQUIREMENT_ROLE();
        vm.prank(admin);
        token.grantRole(role, requirer);
        vm.prank(requirer);
        token.setRequirements(3);
        assertTrue(token.requirements() == 3);

        vm.prank(minter);
        token.mint(pauser, 50);

        assertTrue(token.balanceOf(pauser) == 50);

        // create transferer
        bytes32 roleTransfererAdmin = token.TRANSFERERADMIN_ROLE();
        bytes32 roleTransferer = token.TRANSFERER_ROLE();

        vm.prank(admin);
        token.grantRole(roleTransfererAdmin, transfererAdmin);

        vm.prank(transfererAdmin);
        token.grantRole(roleTransferer, transferer);
        assertTrue(token.hasRole(roleTransferer, transferer));

        vm.prank(transfererAdmin);
        token.grantRole(roleTransferer, burner);
        assertTrue(token.hasRole(roleTransferer, burner));

        // move tokens around
        vm.prank(pauser);
        token.transfer(burner, 50);
        assertTrue(token.balanceOf(burner) == 50);
    }

    function testBeforeTokenTransferRequirementsOverfulfilled() public {
        // create tokens
        bytes32 roleMinterAdmin = token.MINTERADMIN_ROLE();

        vm.prank(admin);
        token.grantRole(roleMinterAdmin, minterAdmin);
        vm.prank(minterAdmin);
        token.setUpMinter(minter, 100);
        assertTrue(token.mintingAllowance(minter) == 100);

        //testSetRequirements

        bytes32 role = token.REQUIREMENT_ROLE();
        vm.prank(admin);
        token.grantRole(role, requirer);
        vm.prank(requirer);
        token.setRequirements(3);
        assertTrue(token.requirements() == 3);

        vm.prank(admin);
        allowList.set(pauser, 7);
        vm.prank(minter);
        token.mint(pauser, 50);

        assertTrue(token.balanceOf(pauser) == 50);
    }

    function testFailBeforeTokenTransferRequirementsNotfulfilled() public {
        // create tokens
        bytes32 roleMinterAdmin = token.MINTERADMIN_ROLE();

        vm.prank(admin);
        token.grantRole(roleMinterAdmin, minterAdmin);
        vm.prank(minterAdmin);
        token.setUpMinter(minter, 100);
        assertTrue(token.mintingAllowance(minter) == 100);

        //testSetRequirements

        bytes32 role = token.REQUIREMENT_ROLE();
        vm.prank(admin);
        token.grantRole(role, requirer);
        vm.prank(requirer);
        token.setRequirements(3);
        assertTrue(token.requirements() == 3);

        vm.prank(admin);
        allowList.set(pauser, 4); // onle on bit set, but bit 1 and 2 (=3) should be set
        vm.prank(minter);
        token.mint(pauser, 50);

        assertTrue(token.balanceOf(pauser) == 50);
    }

    function testBeforeTokenTransferRequirements2() public {
        // create tokens
        bytes32 roleMinterAdmin = token.MINTERADMIN_ROLE();

        vm.prank(admin);
        token.grantRole(roleMinterAdmin, minterAdmin);
        vm.prank(minterAdmin);
        token.setUpMinter(minter, 100);
        assertTrue(token.mintingAllowance(minter) == 100);

        //testSetRequirements

        bytes32 role = token.REQUIREMENT_ROLE();
        vm.prank(admin);
        token.grantRole(role, requirer);
        vm.prank(requirer);
        token.setRequirements(3);
        assertTrue(token.requirements() == 3); // 0x0011

        vm.prank(admin);
        allowList.set(pauser, 7); // 0x0111 -> includes required 0x0011
        vm.prank(minter);
        token.mint(pauser, 50);

        assertTrue(token.balanceOf(pauser) == 50);

        // create transferer
        bytes32 roleTransfererAdmin = token.TRANSFERERADMIN_ROLE();
        bytes32 roleTransferer = token.TRANSFERER_ROLE();

        vm.prank(admin);
        token.grantRole(roleTransfererAdmin, transfererAdmin);

        vm.prank(transfererAdmin);
        token.grantRole(roleTransferer, transferer);
        assertTrue(token.hasRole(roleTransferer, transferer));

        vm.prank(transfererAdmin);
        token.grantRole(roleTransferer, burner);
        assertTrue(token.hasRole(roleTransferer, burner));

        // move tokens around
        vm.prank(pauser);
        token.transfer(burner, 20);
        assertTrue(token.balanceOf(burner) == 20);
        assertTrue(token.balanceOf(pauser) == 30);
    }

    function testFailTransferPause() public {
        // create tokens
        bytes32 roleMinterAdmin = token.MINTERADMIN_ROLE();

        vm.prank(admin);
        token.grantRole(roleMinterAdmin, minterAdmin);
        vm.prank(minterAdmin);
        token.setUpMinter(minter, 100);
        assertTrue(token.mintingAllowance(minter) == 100);

        //testSetRequirements

        bytes32 role = token.REQUIREMENT_ROLE();
        vm.prank(admin);
        token.grantRole(role, requirer);
        vm.prank(requirer);
        token.setRequirements(3);
        assertTrue(token.requirements() == 3);

        vm.prank(admin);
        allowList.set(minter, 3);
        vm.prank(admin);
        allowList.set(pauser, 3);
        vm.prank(minter);
        token.mint(pauser, 50);

        assertTrue(token.balanceOf(pauser) == 50);

        // create transferer
        bytes32 roleTransfererAdmin = token.TRANSFERERADMIN_ROLE();
        bytes32 roleTransferer = token.TRANSFERER_ROLE();

        vm.prank(admin);
        token.grantRole(roleTransfererAdmin, transfererAdmin);

        vm.prank(transfererAdmin);
        token.grantRole(roleTransferer, transferer);
        assertTrue(token.hasRole(roleTransferer, transferer));

        vm.prank(transfererAdmin);
        token.grantRole(roleTransferer, burner);
        assertTrue(token.hasRole(roleTransferer, burner));

        // move tokens around
        vm.prank(pauser);
        token.transfer(burner, 20);
        assertTrue(token.balanceOf(burner) == 20);

        //pause
        bytes32 rolePauser = token.PAUSER_ROLE();
        vm.prank(admin);
        token.grantRole(rolePauser, pauser);
        assertTrue(token.hasRole(rolePauser, pauser));

        vm.prank(pauser);
        token.pause();

        // move tokens around with pause
        vm.prank(pauser);
        token.transfer(burner, 20);
        assertTrue(token.balanceOf(burner) == 20);
    }

    function testTransferUnpaused() public {
        // create tokens
        bytes32 roleMinterAdmin = token.MINTERADMIN_ROLE();

        vm.prank(admin);
        token.grantRole(roleMinterAdmin, minterAdmin);
        vm.prank(minterAdmin);
        token.setUpMinter(minter, 100);
        assertTrue(token.mintingAllowance(minter) == 100);

        //testSetRequirements

        bytes32 role = token.REQUIREMENT_ROLE();
        vm.prank(admin);
        token.grantRole(role, requirer);
        vm.prank(requirer);
        token.setRequirements(3);
        assertTrue(token.requirements() == 3);

        vm.prank(admin);
        allowList.set(minter, 3);
        vm.prank(admin);
        allowList.set(pauser, 3);
        vm.prank(minter);
        token.mint(pauser, 50);

        assertTrue(token.balanceOf(pauser) == 50);

        // create transferer
        bytes32 roleTransfererAdmin = token.TRANSFERERADMIN_ROLE();
        bytes32 roleTransferer = token.TRANSFERER_ROLE();

        vm.prank(admin);
        token.grantRole(roleTransfererAdmin, transfererAdmin);

        vm.prank(transfererAdmin);
        token.grantRole(roleTransferer, transferer);
        assertTrue(token.hasRole(roleTransferer, transferer));

        vm.prank(transfererAdmin);
        token.grantRole(roleTransferer, burner);
        assertTrue(token.hasRole(roleTransferer, burner));

        // move tokens around
        vm.prank(pauser);
        token.transfer(burner, 20);
        assertTrue(token.balanceOf(burner) == 20);

        //pause
        bytes32 rolePauser = token.PAUSER_ROLE();
        vm.prank(admin);
        token.grantRole(rolePauser, pauser);
        assertTrue(token.hasRole(rolePauser, pauser));

        vm.prank(pauser);
        token.pause();

        assertTrue(token.paused());

        vm.prank(pauser);
        token.unpause();

        assertFalse(token.paused());

        // move tokens around with pause
        vm.prank(pauser);
        token.transfer(burner, 20);
        assertTrue(token.balanceOf(burner) == 40);
    }

    function testLoseAndGainRequirements() public {
        address person1 = vm.addr(1);
        address person2 = vm.addr(2);

        vm.prank(minterAdmin);
        token.setUpMinter(minter, 100);
        assertTrue(token.mintingAllowance(minter) == 100);

        // //testSetRequirements
        vm.prank(requirer);
        token.setRequirements(11);
        assertTrue(token.requirements() == 11); // 0x1011

        vm.prank(admin);
        allowList.set(person1, 27); // 0x0111 -> includes required 0x0011
        vm.prank(admin);
        allowList.set(person2, 11); // 0x1011

        vm.prank(minter);
        token.mint(person1, 50);
        assertTrue(token.balanceOf(person1) == 50);

        vm.prank(person1);
        token.transfer(person2, 20);
        assertTrue(token.balanceOf(person2) == 20);
        assertTrue(token.balanceOf(person1) == 30);

        // person1 loses requirements
        vm.prank(admin);
        allowList.set(person1, 3); // 0x0011 -> does not include required 0x1011

        vm.prank(person1);
        vm.expectRevert(
            "Sender is not allowed to transact. Either locally issue the role as a TRANSFERER or they must meet requirements as defined in the allowList"
        );
        token.transfer(person2, 20);
        assertTrue(token.balanceOf(person2) == 20);
        assertTrue(token.balanceOf(person1) == 30);

        vm.prank(person2);
        vm.expectRevert(
            "Receiver is not allowed to transact. Either locally issue the role as a TRANSFERER or they must meet requirements as defined in the allowList"
        );
        token.transfer(person1, 10);
        assertTrue(token.balanceOf(person2) == 20);
        assertTrue(token.balanceOf(person1) == 30);

        // requirements are lowered to 3
        vm.prank(requirer);
        token.setRequirements(3); // 0x0011
        assertTrue(token.requirements() == 3);

        // now transfers should work again between person 1 and 2
        vm.prank(person1);
        token.transfer(person2, 20);
        assertTrue(token.balanceOf(person2) == 40);
        assertTrue(token.balanceOf(person1) == 10);

        vm.prank(person2);
        token.transfer(person1, 10);
        assertTrue(token.balanceOf(person2) == 30);
        assertTrue(token.balanceOf(person1) == 20);
    }

    /*
        mint more than mintingAllowance
        behavior of mintingAllowance is to not take into account tokens
        already minted once a new allowance is set
    */
    function testExceedMintingAllowance() public {
        address person1 = vm.addr(1);
        address person2 = vm.addr(2);

        vm.prank(minterAdmin);
        token.setUpMinter(minter, 100);
        assertTrue(token.mintingAllowance(minter) == 100);

        // //testSetRequirements
        vm.prank(requirer);
        token.setRequirements(11);
        assertTrue(token.requirements() == 11); // 0x1011

        vm.prank(admin);
        allowList.set(person1, 27); // 0x0111 -> includes required 0x0011
        vm.prank(admin);
        allowList.set(person2, 11); // 0x1011

        vm.prank(minter);
        token.mint(person1, 50);
        assertTrue(token.balanceOf(person1) == 50);

        vm.prank(minterAdmin);
        token.setUpMinter(minter, 0);
        vm.prank(minterAdmin);
        token.setUpMinter(minter, 10);
        assertTrue(token.mintingAllowance(minter) == 10);

        vm.prank(minter);
        //vm.expectRevert("Minting allowance exceeded");
        token.mint(person2, 3);
        assertTrue(token.balanceOf(person2) == 3);
    }

    function testFailSetAllowanceTo0BeforeResetting() public {
        address person1 = vm.addr(1);
        address person2 = vm.addr(2);

        vm.prank(minterAdmin);
        token.setUpMinter(minter, 100);
        assertTrue(token.mintingAllowance(minter) == 100);

        // //testSetRequirements
        vm.prank(requirer);
        token.setRequirements(11);
        assertTrue(token.requirements() == 11); // 0x1011

        vm.prank(admin);
        allowList.set(person1, 27); // 0x0111 -> includes required 0x0011
        vm.prank(admin);
        allowList.set(person2, 11); // 0x1011

        vm.prank(minter);
        token.mint(person1, 50);
        assertTrue(token.balanceOf(person1) == 50);

        vm.prank(minterAdmin);
        token.setUpMinter(minter, 10);
        assertTrue(token.mintingAllowance(minter) == 10);

        vm.prank(minter);
        //vm.expectRevert("Minting allowance exceeded");
        token.mint(person2, 3);
        assertTrue(token.balanceOf(person2) == 3);
    }

    function testDeployerDoesNotGetRole() public {
        Token localToken = new Token(
            trustedForwarder,
            admin,
            allowList,
            0x0,
            "testToken",
            "TEST"
        );
        address deployer = msg.sender;
        assertFalse(
            localToken.hasRole(localToken.REQUIREMENT_ROLE(), deployer)
        );
        assertFalse(
            localToken.hasRole(localToken.MINTERADMIN_ROLE(), deployer)
        );
        assertFalse(localToken.hasRole(localToken.MINTER_ROLE(), deployer));
        assertFalse(localToken.hasRole(localToken.BURNER_ROLE(), deployer));
        assertFalse(
            localToken.hasRole(localToken.TRANSFERERADMIN_ROLE(), deployer)
        );
        assertFalse(localToken.hasRole(localToken.TRANSFERER_ROLE(), deployer));
        assertFalse(localToken.hasRole(localToken.PAUSER_ROLE(), deployer));
    }
}