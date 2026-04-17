// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import "../lib/forge-std/src/Test.sol";
import "../lib/forge-std/src/console.sol";
import "../contracts/factories/TokenProxyFactory.sol";
import "../contracts/FeeSettings.sol";
import "./resources/CloneCreators.sol";

import "@openzeppelin/contracts/utils/Strings.sol";

contract tokenTest is Test {
    Token token;
    AllowList allowList;
    FeeSettings feeSettings;
    address public constant TRUSTED_FORWARDER = 0x9109709EcFA91A80626FF3989D68f67F5B1dD129;
    address public constant ADMIN = 0x0109709eCFa91a80626FF3989D68f67f5b1dD120;
    address public constant SNAPSHOT_CREATOR = 0x1109709ecFA91a80626ff3989D68f67F5B1Dd121;
    address public constant MINT_ALLOWER = 0x2109709EcFa91a80626Ff3989d68F67F5B1Dd122;
    address public constant MINTER = 0x3109709ECfA91A80626fF3989D68f67F5B1Dd123;
    address public constant BURNER = 0x4109709eCFa91A80626ff3989d68F67f5b1DD124;
    address public constant TRANSFERER_ADMIN = 0x5109709EcFA91a80626ff3989d68f67F5B1dD125;
    address public constant TRANSFERER = 0x6109709EcFA91A80626FF3989d68f67F5b1dd126;
    address public constant PAUSER = 0x7109709eCfa91A80626Ff3989D68f67f5b1dD127;
    address public constant FEE_SETTINGS_AND_ALLOW_LIST_OWNER = 0x8109709ecfa91a80626fF3989d68f67F5B1dD128;

    event RequirementsChanged(uint256 newRequirements);

    function setUp() public {
        allowList = createAllowList(TRUSTED_FORWARDER, FEE_SETTINGS_AND_ALLOW_LIST_OWNER);
        feeSettings = createFeeSettings(
            TRUSTED_FORWARDER,
            FEE_SETTINGS_AND_ALLOW_LIST_OWNER,
            buildFeeTypes(
                0,
                0,
                0,
                FEE_SETTINGS_AND_ALLOW_LIST_OWNER,
                FEE_SETTINGS_AND_ALLOW_LIST_OWNER,
                FEE_SETTINGS_AND_ALLOW_LIST_OWNER
            )
        );

        address tokenHolder = address(this);

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
                0,
                "testToken",
                "TEST"
            )
        );

        // set up roles
        vm.startPrank(ADMIN);
        token.grantRole(token.MINTALLOWER_ROLE(), MINT_ALLOWER);
        token.increaseMintingAllowance(MINTER, 200);
        token.grantRole(token.SNAPSHOTCREATOR_ROLE(), SNAPSHOT_CREATOR);
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

    function testOneSnapshot() public {
        uint256 totalSupply = token.totalSupply();
        vm.prank(ADMIN);
        uint256 snapshotId = token.createSnapshot();
        assertEq(snapshotId, 1, "snapshotId is wrong");

        assertTrue(token.totalSupplyAt(snapshotId) == totalSupply, "totalSupplyAt is wrong");

        vm.prank(PAUSER);
        token.transfer(TRANSFERER, 100);

        // balances must have changed
        assertTrue(token.balanceOf(PAUSER) == 0, "PAUSER balance is wrong");
        assertTrue(token.balanceOf(TRANSFERER) == 100, "TRANSFERER balance is wrong");

        // but snapshot balances must not have changed
        assertTrue(token.balanceOfAt(PAUSER, snapshotId) == 100, "PAUSER balanceAt is wrong");
        assertTrue(token.balanceOfAt(TRANSFERER, snapshotId) == 0, "TRANSFERER balanceAt is wrong");
    }

    function testMultipleSnapshots(uint256 amount1, address rando1, uint256 amount2, address rando2) public {
        vm.assume(rando1 != rando2);
        vm.assume(amount2 < (type(uint256).max) - 1000);
        vm.assume(amount1 < (type(uint256).max - amount2) - 1000);
        vm.assume(rando1 != address(0));
        vm.assume(rando2 != address(0));
        vm.assume(rando1 != TRUSTED_FORWARDER);
        vm.assume(rando2 != TRUSTED_FORWARDER);
        vm.assume(token.balanceOf(rando1) == 0);
        vm.assume(token.balanceOf(rando2) == 0);

        uint256 snapshotId;

        vm.prank(SNAPSHOT_CREATOR);
        snapshotId = token.createSnapshot();
        console.log("snapshotId: %s", snapshotId);

        vm.prank(MINT_ALLOWER);
        token.mint(rando1, amount1);

        vm.prank(SNAPSHOT_CREATOR);
        token.createSnapshot();

        vm.prank(MINT_ALLOWER);
        token.mint(rando2, amount2);

        vm.prank(SNAPSHOT_CREATOR);
        token.createSnapshot();

        vm.prank(rando1);
        token.transfer(rando2, amount1);

        vm.prank(SNAPSHOT_CREATOR);
        token.createSnapshot();

        // verify all snapshots are correct
        assertTrue(token.balanceOfAt(rando1, 1) == 0, "rando1 balanceAt 0 is wrong");
        assertTrue(token.balanceOfAt(rando1, 2) == amount1, "rando1 balanceAt is wrong");
        assertTrue(token.balanceOfAt(rando1, 3) == amount1, "rando1 balanceAt is wrong");
        assertTrue(token.balanceOfAt(rando1, 4) == 0, "rando1 balanceAt is wrong");

        assertTrue(token.balanceOfAt(rando2, 1) == 0, "rando2 balanceAt is wrong");
        assertTrue(token.balanceOfAt(rando2, 2) == 0, "rando2 balanceAt is wrong");
        assertTrue(token.balanceOfAt(rando2, 3) == amount2, "rando2 balanceAt is wrong");
        assertTrue(token.balanceOfAt(rando2, 4) == amount1 + amount2, "rando2 balanceAt is wrong");

        // verify current balances are correct
        assertTrue(token.balanceOf(rando1) == 0, "rando1 balance is wrong");
        assertTrue(token.balanceOf(rando2) == amount1 + amount2, "rando2 balance is wrong");
    }

    function testOnlySnapshotCreatorCanSnapshot(address rando) public {
        vm.assume(rando != address(0));
        vm.assume(!token.hasRole(token.SNAPSHOTCREATOR_ROLE(), rando));
        string memory randoString = Strings.toHexString(uint256(uint160(rando)), 20);
        console.log("randoString: %s", randoString);
        string memory error = string.concat("AccessControl: account ", randoString);
        console.log("error: %s", error);
        error = string.concat(
            error,
            " is missing role 0x0f808695ed46dfe84975e0868729f72470bdaab0e6414a139300622caf1a5940"
        );
        console.log("error: %s", error);
        vm.prank(rando);
        vm.expectRevert(bytes(error));
        token.createSnapshot();

        // make rando snapshot creator and create snapshot
        vm.startPrank(ADMIN);
        token.grantRole(token.SNAPSHOTCREATOR_ROLE(), rando);
        vm.stopPrank();
        vm.prank(rando);
        token.createSnapshot();
    }

    function testAdminIsRoleAdminForSnapshotCreator(address rando) public {
        vm.assume(rando != address(0));
        vm.assume(!token.hasRole(token.SNAPSHOTCREATOR_ROLE(), rando));

        // make rando snapshot creator and create snapshot
        bytes32 snapshotCreatorRole = token.SNAPSHOTCREATOR_ROLE();
        vm.prank(ADMIN);
        token.grantRole(snapshotCreatorRole, rando);
        require(token.hasRole(token.SNAPSHOTCREATOR_ROLE(), rando), "rando is not snapshot creator");
    }
}
