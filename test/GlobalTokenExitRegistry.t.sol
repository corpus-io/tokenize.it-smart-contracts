// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import "../lib/forge-std/src/Test.sol";

import "../contracts/factories/TokenProxyFactory.sol";
import "../contracts/factories/ExitCloneFactory.sol";
import "../contracts/GlobalTokenExitRegistry.sol";
import "../contracts/Exit.sol";
import "../contracts/Token.sol";
import "./resources/CloneCreators.sol";
import "./resources/FakePaymentToken.sol";
import "./resources/FixedPayoutExit.sol";

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
    address public constant ADMIN = 0x0109709eCFa91a80626FF3989D68f67f5b1dD120;
    address public constant NON_ADMIN = 0x1109709ecFA91a80626ff3989D68f67F5B1Dd121;
    address public constant TRUSTED_FORWARDER = 0xa109709ecfA91A80626ff3989D68F67F5b1dD12a;

    AllowList allowList;
    IFeeSettingsV2 feeSettings;
    Token token;
    TokenProxyFactory tokenFactory;
    FakePaymentToken currency;
    ExitCloneFactory exitFactory;
    GlobalTokenExitRegistry registry;

    function setUp() public {
        allowList = createAllowList(TRUSTED_FORWARDER, ADMIN);
        feeSettings = createFeeSettings(TRUSTED_FORWARDER, ADMIN, buildFeeTypes(0, 0, 0, ADMIN, ADMIN, ADMIN));

        address tokenLogic = address(new Token(TRUSTED_FORWARDER));
        tokenFactory = new TokenProxyFactory(tokenLogic);
        token = Token(
            tokenFactory.createTokenProxy(0, TRUSTED_FORWARDER, feeSettings, ADMIN, allowList, 0, "TestToken", "TTK")
        );

        currency = new FakePaymentToken(0, 6);
        vm.prank(ADMIN);
        allowList.set(address(currency), TRUSTED_CURRENCY);

        exitFactory = new ExitCloneFactory(address(new Exit(TRUSTED_FORWARDER)));

        registry = new GlobalTokenExitRegistry(TRUSTED_FORWARDER);
    }

    /// @dev Deploys a real Exit clone for `_exitToken` using a zero initial funding amount.
    function _createExit(Token _exitToken, bytes32 salt) internal returns (Exit) {
        ExitInitializerArguments memory args = ExitInitializerArguments({
            owner: ADMIN,
            token: _exitToken,
            currency: IERC20(address(currency)),
            pricePerToken: 2e6,
            lockedUntil: uint64(block.timestamp + 30 days),
            referenceCurrencies: new IERC20[](0),
            referenceToExitRates: new uint256[](0)
        });
        return Exit(exitFactory.createExitClone(salt, TRUSTED_FORWARDER, address(this), args, 0));
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
                TRUSTED_FORWARDER,
                feeSettings,
                ADMIN,
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
        Exit realExit = _createExit(token, 0);

        vm.prank(ADMIN);
        vm.expectEmit(true, true, false, false, address(registry));
        emit GlobalTokenExitRegistry.ExitSet(token, realExit);
        registry.setExit(token, realExit);

        assertEq(address(registry.exits(token)), address(realExit), "exit not set correctly");
    }

    function testSetExitRevertsIfCallerIsNotTokenAdmin() public {
        address fakeExit = makeAddr("fakeExit");

        vm.prank(NON_ADMIN);
        vm.expectRevert(GlobalTokenExitRegistry.NotTokenAdminOrOwner.selector);
        registry.setExit(token, Exit(address(fakeExit)));
    }

    function testSetExitRevertsIfTokenIsZeroAddress() public {
        address fakeExit = makeAddr("fakeExit");

        vm.prank(ADMIN);
        vm.expectRevert(ZeroTokenAddress.selector);
        registry.setExit(Token(address(0)), Exit(address(fakeExit)));
    }

    function testSetExitRevertsIfExitIsZeroAddress() public {
        vm.prank(ADMIN);
        vm.expectRevert(GlobalTokenExitRegistry.ZeroExitAddress.selector);
        registry.setExit(token, Exit(address(0)));
    }

    function testSetExitRevertsIfAlreadySet() public {
        Exit realExit = _createExit(token, 0);
        address fakeExit2 = makeAddr("fakeExit2");

        vm.prank(ADMIN);
        registry.setExit(token, realExit);

        vm.prank(ADMIN);
        vm.expectRevert(GlobalTokenExitRegistry.ExitAlreadySet.selector);
        registry.setExit(token, Exit(address(fakeExit2)));
    }

    function testSetExitOnlyCallableByRoleHolder() public {
        Exit realExit = _createExit(token, 0);

        // Grant DEFAULT_ADMIN_ROLE to NON_ADMIN
        bytes32 defaultAdminRole = token.DEFAULT_ADMIN_ROLE();
        vm.prank(ADMIN);
        token.grantRole(defaultAdminRole, NON_ADMIN);

        // Now NON_ADMIN can set exit
        vm.prank(NON_ADMIN);
        registry.setExit(token, realExit);

        assertEq(address(registry.exits(token)), address(realExit), "exit not set by new ADMIN");
    }

    function testSetExitViaTokenOwner() public {
        FakeOwnableToken ownableToken = new FakeOwnableToken(ADMIN);
        FixedPayoutExit exitStub = new FixedPayoutExit(address(ownableToken), IERC20(address(currency)), 0);

        vm.prank(ADMIN);
        registry.setExit(Token(address(ownableToken)), Exit(address(exitStub)));

        assertEq(address(registry.exits(Token(address(ownableToken)))), address(exitStub), "exit not set via owner()");
    }

    function testSetExitRevertsForNonOwnerOfOwnableToken() public {
        FakeOwnableToken ownableToken = new FakeOwnableToken(ADMIN);
        FixedPayoutExit exitStub = new FixedPayoutExit(address(ownableToken), IERC20(address(currency)), 0);

        vm.prank(NON_ADMIN);
        vm.expectRevert(GlobalTokenExitRegistry.NotTokenAdminOrOwner.selector);
        registry.setExit(Token(address(ownableToken)), Exit(address(exitStub)));
    }

    function testSetExitIndependentPerToken() public {
        Token token2 = Token(
            tokenFactory.createTokenProxy(
                bytes32(uint256(2)),
                TRUSTED_FORWARDER,
                feeSettings,
                ADMIN,
                allowList,
                0,
                "Token2",
                "TT2"
            )
        );
        Exit exit1 = _createExit(token, 0);
        Exit exit2 = _createExit(token2, 0);

        vm.prank(ADMIN);
        registry.setExit(token, exit1);

        vm.prank(ADMIN);
        registry.setExit(token2, exit2);

        assertEq(address(registry.exits(token)), address(exit1), "token1 exit wrong");
        assertEq(address(registry.exits(token2)), address(exit2), "token2 exit wrong");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // ── Token mismatch validation ─────────────────────────────────────────────
    // ─────────────────────────────────────────────────────────────────────────

    function testSetExitRevertsIfExitTokenMismatch() public {
        Token otherToken = Token(
            tokenFactory.createTokenProxy(
                bytes32(uint256(1)),
                TRUSTED_FORWARDER,
                feeSettings,
                ADMIN,
                allowList,
                0,
                "OtherToken",
                "OTK"
            )
        );
        // Exit is initialized for otherToken, not for `token`
        Exit exitForOtherToken = _createExit(otherToken, 0);

        vm.prank(ADMIN);
        vm.expectRevert(GlobalTokenExitRegistry.ExitTokenMismatch.selector);
        registry.setExit(token, exitForOtherToken);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // ── Fuzz: only token ADMIN can setExit ────────────────────────────────────
    // ─────────────────────────────────────────────────────────────────────────

    /// Any address that does not hold DEFAULT_ADMIN_ROLE on the token must be rejected.
    function testFuzz_SetExitRevertsForNonAdmin(address caller) public {
        vm.assume(!token.hasRole(token.DEFAULT_ADMIN_ROLE(), caller));
        address fakeExit = makeAddr("fakeExit");
        vm.prank(caller);
        vm.expectRevert(GlobalTokenExitRegistry.NotTokenAdminOrOwner.selector);
        registry.setExit(token, Exit(address(fakeExit)));
    }

    // ─────────────────────────────────────────────────────────────────────────
    // ── ERC2771 ───────────────────────────────────────────────────────────────
    // ─────────────────────────────────────────────────────────────────────────

    /// Admin calling setExit through the trusted forwarder (ADMIN address appended to calldata)
    /// must succeed: _msgSender() resolves to ADMIN, not the forwarder.
    function testSetExitViaERC2771TrustedForwarder() public {
        Exit realExit = _createExit(token, 0);
        bytes memory callData = abi.encodePacked(
            abi.encodeWithSelector(GlobalTokenExitRegistry.setExit.selector, token, realExit),
            ADMIN
        );
        vm.prank(TRUSTED_FORWARDER);
        (bool success, ) = address(registry).call(callData);
        assertTrue(success, "setExit via trusted forwarder failed");
        assertEq(address(registry.exits(token)), address(realExit), "exit not set via ERC2771");
    }

    /// An untrusted forwarder appending ADMIN's address must NOT be treated as ADMIN:
    /// _msgSender() returns msg.sender (the untrusted address), so the call reverts.
    function testSetExitUntrustedForwarderCannotSpoofAdmin() public {
        address fakeExit = makeAddr("fakeExit");
        address untrusted = address(0xDEAD);
        bytes memory callData = abi.encodePacked(
            abi.encodeWithSelector(GlobalTokenExitRegistry.setExit.selector, token, Exit(address(fakeExit))),
            ADMIN
        );
        vm.prank(untrusted);
        (bool success, ) = address(registry).call(callData);
        assertFalse(success, "untrusted forwarder should not be able to spoof ADMIN");
        assertEq(address(registry.exits(token)), address(0), "exit must not be set");
    }
}
