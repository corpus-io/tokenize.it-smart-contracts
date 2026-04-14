// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.23;

import "../lib/forge-std/src/Test.sol";

import "../contracts/factories/TokenProxyFactory.sol";
import "../contracts/GlobalTokenExitRegistry.sol";
import "../contracts/Exit.sol";
import "../contracts/Token.sol";
import "./resources/CloneCreators.sol";
import "./resources/FakePaymentToken.sol";

/// @dev Minimal Ownable token stub — has owner() but no AccessControl
contract FakeOwnableToken {
    address private _owner;

    constructor(address tokenOwner) {
        _owner = tokenOwner;
    }

    function owner() external view returns (address) {
        return _owner;
    }
}

/**
 * @title GlobalTokenExitRegistryTest
 * @notice Tests for GlobalTokenExitRegistry.
 */
contract GlobalTokenExitRegistryTest is Test {
    address public constant admin = 0x0109709eCFa91a80626FF3989D68f67f5b1dD120;
    address public constant nonAdmin = 0x1109709ecFA91a80626ff3989D68f67F5B1Dd121;
    address public constant trustedForwarder = 0xa109709ecfA91A80626ff3989D68F67F5b1dD12a;

    AllowList allowList;
    IFeeSettingsV2 feeSettings;
    Token token;
    TokenProxyFactory tokenFactory;
    GlobalTokenExitRegistry registry;

    function setUp() public {
        allowList = createAllowList(trustedForwarder, admin);
        feeSettings = createFeeSettings(trustedForwarder, admin, buildFeeTypes(0, 0, 0, admin, admin, admin));

        address tokenLogic = address(new Token(trustedForwarder));
        tokenFactory = new TokenProxyFactory(tokenLogic);
        token = Token(
            tokenFactory.createTokenProxy(0, trustedForwarder, feeSettings, admin, allowList, 0, "TestToken", "TTK")
        );

        registry = new GlobalTokenExitRegistry(trustedForwarder);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // ── Initial state ─────────────────────────────────────────────────────────
    // ─────────────────────────────────────────────────────────────────────────

    function testExitIsZeroInitially() public view {
        assertEq(address(registry.exits(token)), address(0), "exit should be zero initially");
    }

    function testExitIsZeroForUnknownToken() public {
        Token otherToken = Token(
            tokenFactory.createTokenProxy(
                bytes32(uint256(1)),
                trustedForwarder,
                feeSettings,
                admin,
                allowList,
                0,
                "OtherToken",
                "OTK"
            )
        );
        assertEq(address(registry.exits(otherToken)), address(0), "exit for unknown token should be zero");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // ── setExit ───────────────────────────────────────────────────────────────
    // ─────────────────────────────────────────────────────────────────────────

    function testSetExitHappyPath() public {
        address fakeExit = makeAddr("fakeExit");

        vm.prank(admin);
        vm.expectEmit(true, true, false, false, address(registry));
        emit GlobalTokenExitRegistry.ExitSet(token, Exit(address(fakeExit)));
        registry.setExit(token, Exit(address(fakeExit)));

        assertEq(address(registry.exits(token)), address(fakeExit), "exit not set correctly");
    }

    function testSetExitRevertsIfCallerIsNotTokenAdmin() public {
        address fakeExit = makeAddr("fakeExit");

        vm.prank(nonAdmin);
        vm.expectRevert("caller is not token admin or owner");
        registry.setExit(token, Exit(address(fakeExit)));
    }

    function testSetExitRevertsIfTokenIsZeroAddress() public {
        address fakeExit = makeAddr("fakeExit");

        vm.prank(admin);
        vm.expectRevert("token can not be zero address");
        registry.setExit(Token(address(0)), Exit(address(fakeExit)));
    }

    function testSetExitRevertsIfExitIsZeroAddress() public {
        vm.prank(admin);
        vm.expectRevert("exit can not be zero address");
        registry.setExit(token, Exit(address(0)));
    }

    function testSetExitRevertsIfAlreadySet() public {
        address fakeExit1 = makeAddr("fakeExit1");
        address fakeExit2 = makeAddr("fakeExit2");

        vm.prank(admin);
        registry.setExit(token, Exit(address(fakeExit1)));

        vm.prank(admin);
        vm.expectRevert("exit has already been set");
        registry.setExit(token, Exit(address(fakeExit2)));
    }

    function testSetExitOnlyCallableByRoleHolder() public {
        address fakeExit = makeAddr("fakeExit");

        // Grant DEFAULT_ADMIN_ROLE to nonAdmin
        bytes32 defaultAdminRole = token.DEFAULT_ADMIN_ROLE();
        vm.prank(admin);
        token.grantRole(defaultAdminRole, nonAdmin);

        // Now nonAdmin can set exit
        vm.prank(nonAdmin);
        registry.setExit(token, Exit(address(fakeExit)));

        assertEq(address(registry.exits(token)), address(fakeExit), "exit not set by new admin");
    }

    function testSetExitViaTokenOwner() public {
        FakeOwnableToken ownableToken = new FakeOwnableToken(admin);
        address fakeExit = makeAddr("fakeExit");

        // admin is the owner() of ownableToken — should be allowed
        vm.prank(admin);
        registry.setExit(Token(address(ownableToken)), Exit(address(fakeExit)));

        assertEq(address(registry.exits(Token(address(ownableToken)))), address(fakeExit), "exit not set via owner()");
    }

    function testSetExitRevertsForNonOwnerOfOwnableToken() public {
        FakeOwnableToken ownableToken = new FakeOwnableToken(admin);
        address fakeExit = makeAddr("fakeExit");

        vm.prank(nonAdmin);
        vm.expectRevert("caller is not token admin or owner");
        registry.setExit(Token(address(ownableToken)), Exit(address(fakeExit)));
    }

    function testSetExitIndependentPerToken() public {
        Token token2 = Token(
            tokenFactory.createTokenProxy(
                bytes32(uint256(2)),
                trustedForwarder,
                feeSettings,
                admin,
                allowList,
                0,
                "Token2",
                "TT2"
            )
        );
        address fakeExit1 = makeAddr("fakeExit1");
        address fakeExit2 = makeAddr("fakeExit2");

        vm.prank(admin);
        registry.setExit(token, Exit(address(fakeExit1)));

        vm.prank(admin);
        registry.setExit(token2, Exit(address(fakeExit2)));

        assertEq(address(registry.exits(token)), address(fakeExit1), "token1 exit wrong");
        assertEq(address(registry.exits(token2)), address(fakeExit2), "token2 exit wrong");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // ── Fuzz: only token admin can setExit ────────────────────────────────────
    // ─────────────────────────────────────────────────────────────────────────

    /// Any address that does not hold DEFAULT_ADMIN_ROLE on the token must be rejected.
    function testFuzz_SetExitRevertsForNonAdmin(address caller) public {
        vm.assume(!token.hasRole(token.DEFAULT_ADMIN_ROLE(), caller));
        address fakeExit = makeAddr("fakeExit");
        vm.prank(caller);
        vm.expectRevert("caller is not token admin or owner");
        registry.setExit(token, Exit(address(fakeExit)));
    }

    // ─────────────────────────────────────────────────────────────────────────
    // ── ERC2771 ───────────────────────────────────────────────────────────────
    // ─────────────────────────────────────────────────────────────────────────

    /// Admin calling setExit through the trusted forwarder (admin address appended to calldata)
    /// must succeed: _msgSender() resolves to admin, not the forwarder.
    function testSetExitViaERC2771TrustedForwarder() public {
        address fakeExit = makeAddr("fakeExit");
        bytes memory callData = abi.encodePacked(
            abi.encodeWithSelector(GlobalTokenExitRegistry.setExit.selector, token, Exit(address(fakeExit))),
            admin
        );
        vm.prank(trustedForwarder);
        (bool success, ) = address(registry).call(callData);
        assertTrue(success, "setExit via trusted forwarder failed");
        assertEq(address(registry.exits(token)), address(fakeExit), "exit not set via ERC2771");
    }

    /// An untrusted forwarder appending admin's address must NOT be treated as admin:
    /// _msgSender() returns msg.sender (the untrusted address), so the call reverts.
    function testSetExitUntrustedForwarderCannotSpoofAdmin() public {
        address fakeExit = makeAddr("fakeExit");
        address untrusted = address(0xDEAD);
        bytes memory callData = abi.encodePacked(
            abi.encodeWithSelector(GlobalTokenExitRegistry.setExit.selector, token, Exit(address(fakeExit))),
            admin
        );
        vm.prank(untrusted);
        (bool success, ) = address(registry).call(callData);
        assertFalse(success, "untrusted forwarder should not be able to spoof admin");
        assertEq(address(registry.exits(token)), address(0), "exit must not be set");
    }
}
