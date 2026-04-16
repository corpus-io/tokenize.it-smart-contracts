// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.23;

import "../lib/forge-std/src/Test.sol";

import "../contracts/factories/TokenProxyFactory.sol";
import "../contracts/factories/TimeLockCloneFactory.sol";
import "../contracts/factories/ExitCloneFactory.sol";
import "../contracts/TimeLock.sol";
import "../contracts/GlobalTokenExitRegistry.sol";
import "../contracts/Exit.sol";
import "../contracts/Token.sol";
import "../contracts/Distribution.sol";
import "./resources/CloneCreators.sol";
import "./resources/FakePaymentToken.sol";
import "./resources/FixedPayoutExit.sol";

/// @dev Stub IDistribution: claim() pays a fixed amount to _recipient, ignoring _minPayout.
contract FixedPayoutDistribution {
    IERC20 public currency;
    uint256 public payout;

    constructor(IERC20 _currency, uint256 _payout) {
        currency = _currency;
        payout = _payout;
    }

    function claim(address _recipient, uint256) external {
        if (payout > 0) currency.transfer(_recipient, payout);
    }
}

/**
 * @title TimeLockDistributeExitTest
 * @notice Tests for TimeLock.claimExit(, 0), which claims exit proceeds bypassing lockedUntil.
 */
contract TimeLockDistributeExitTest is Test {
    address public constant ADMIN = 0x0109709eCFa91a80626FF3989D68f67f5b1dD120;
    address public constant OWNER = 0x6109709EcFA91A80626FF3989d68f67F5b1dd126;
    address public constant RECIPIENT = 0x7109709eCfa91A80626Ff3989D68f67f5b1dD127;
    address public constant CURRENCY_PROVIDER = 0x5109709EcFA91a80626ff3989d68f67F5B1dD125;
    address public constant TRUSTED_FORWARDER = 0xa109709ecfA91A80626ff3989D68F67F5b1dD12a;

    uint256 public constant TOKEN_AMOUNT = 200e18;

    uint64 public lockedUntil;
    uint64 public timeLockExpiry;

    AllowList allowList;
    IFeeSettingsV2 feeSettings;
    Token token;
    FakePaymentToken eurc;

    GlobalTokenExitRegistry tokenExitRegistry;
    TimeLock timeLock;
    Exit exitLogic;
    ExitCloneFactory exitFactory;

    function setUp() public {
        lockedUntil = uint64(block.timestamp + 30 days);
        timeLockExpiry = uint64(block.timestamp + 365 days);

        // Infrastructure
        allowList = createAllowList(TRUSTED_FORWARDER, ADMIN);
        feeSettings = createFeeSettings(TRUSTED_FORWARDER, ADMIN, buildFeeTypes(0, 0, 0, ADMIN, ADMIN, ADMIN));

        eurc = new FakePaymentToken(0, 6);

        vm.prank(ADMIN);
        allowList.set(address(eurc), TRUSTED_CURRENCY);

        // Token (requirements=0 so timeLock can freely transfer tokens)
        address tokenLogic = address(new Token(TRUSTED_FORWARDER));
        TokenProxyFactory tokenFactory = new TokenProxyFactory(tokenLogic);
        token = Token(
            tokenFactory.createTokenProxy(0, TRUSTED_FORWARDER, feeSettings, ADMIN, allowList, 0, "TestToken", "TTK")
        );
        vm.startPrank(ADMIN);
        token.grantRole(token.MINTALLOWER_ROLE(), ADMIN);
        vm.stopPrank();

        // GlobalTokenExitRegistry
        tokenExitRegistry = new GlobalTokenExitRegistry(TRUSTED_FORWARDER);

        // TimeLock (locked for 1 year)
        TimeLock timeLockLogic = new TimeLock(TRUSTED_FORWARDER);
        TimeLockCloneFactory timeLockFactory = new TimeLockCloneFactory(address(timeLockLogic));
        timeLock = TimeLock(
            timeLockFactory.createTimeLockClone(bytes32(0), TRUSTED_FORWARDER, OWNER, timeLockExpiry, tokenExitRegistry)
        );

        // Mint tokens directly to timeLock
        vm.prank(ADMIN);
        token.mint(address(timeLock), TOKEN_AMOUNT);

        // Exit factory
        exitLogic = new Exit(TRUSTED_FORWARDER);
        exitFactory = new ExitCloneFactory(address(exitLogic));
    }

    function _deployExit(
        uint256 pricePerToken,
        IERC20[] memory referenceCurrencies,
        uint256[] memory rates
    ) internal returns (Exit) {
        uint256 totalCurrency = (TOKEN_AMOUNT * pricePerToken) / (10 ** token.decimals());
        ExitInitializerArguments memory args = ExitInitializerArguments({
            owner: OWNER,
            token: token,
            currency: IERC20(address(eurc)),
            pricePerToken: pricePerToken,

            lockedUntil: lockedUntil,
            referenceCurrencies: referenceCurrencies,
            referenceToExitRates: rates
        });
        address cloneAddr = exitFactory.predictCloneAddress(bytes32(0), TRUSTED_FORWARDER, args);
        eurc.mint(CURRENCY_PROVIDER, totalCurrency);
        vm.prank(CURRENCY_PROVIDER);
        eurc.approve(cloneAddr, totalCurrency);
        return Exit(exitFactory.createExitClone(bytes32(0), TRUSTED_FORWARDER, CURRENCY_PROVIDER, args, totalCurrency));
    }

    function _deployExit(uint256 pricePerToken) internal returns (Exit) {
        return _deployExit(pricePerToken, new IERC20[](0), new uint256[](0));
    }

    // ── claimExit bypasses lockedUntil ──────────────────────────────────

    /// claimExit works before lockedUntil has passed
    function testDistributeExitBeforeLockedUntil() public {
        Exit exitContract = _deployExit(200e6);

        vm.prank(ADMIN);
        tokenExitRegistry.setExit(token, Exit(address(exitContract)));

        // Still locked (timeLockExpiry = now + 365 days)
        assertLt(block.timestamp, timeLockExpiry, "should still be locked");


        vm.prank(OWNER);
        timeLock.claimExit(token, RECIPIENT, 0);

        assertEq(token.balanceOf(address(timeLock)), 0, "timeLock should have no tokens after exit");
        assertEq(
            eurc.balanceOf(RECIPIENT),
            (TOKEN_AMOUNT * 200e6) / (10 ** token.decimals()),
            "RECIPIENT got wrong amount"
        );
    }

    /// drain() still blocks before lockedUntil (when no exit is set)
    function testDrainStillBlockedBeforeLockedUntil() public {
        // No exit is set — drain must be blocked
        vm.prank(OWNER);
        vm.expectRevert("timelock has not expired");
        timeLock.drain(IERC20(address(token)), RECIPIENT);
    }

    /// drain() is still blocked before lockedUntil even after setExit is called
    function testDrainStillBlockedAfterExitSet() public {
        Exit exitContract = _deployExit(200e6);

        vm.prank(ADMIN);
        tokenExitRegistry.setExit(token, Exit(address(exitContract)));

        vm.prank(OWNER);
        vm.expectRevert("timelock has not expired");
        timeLock.drain(IERC20(address(token)), RECIPIENT);
    }

    // ── Revert cases ─────────────────────────────────────────────────────────

    /// Reverts when no exit is set in tokenExitRegistry
    function testDistributeExitRevertsIfNoExitRegistered() public {

        vm.prank(OWNER);
        vm.expectRevert("no exit set in tokenExitRegistry");
        timeLock.claimExit(token, RECIPIENT, 0);
    }

    /// Reverts when RECIPIENT is zero address
    function testDistributeExitRevertsIfRecipientZero() public {
        Exit exitContract = _deployExit(200e6);
        vm.prank(ADMIN);
        tokenExitRegistry.setExit(token, Exit(address(exitContract)));


        vm.prank(OWNER);
        vm.expectRevert("recipient can not be zero address");
        timeLock.claimExit(token, address(0), 0);
    }

    /// Only OWNER can call claimExit
    function testDistributeExitRevertsIfNotOwner() public {
        Exit exitContract = _deployExit(200e6);
        vm.prank(ADMIN);
        tokenExitRegistry.setExit(token, Exit(address(exitContract)));


        vm.expectRevert("Ownable: caller is not the owner");
        timeLock.claimExit(token, RECIPIENT, 0);
    }

    /// Reverts when timeLock holds no tokens (drain after lock expires, then try claimExit)
    function testDistributeExitRevertsIfNoTokens() public {
        Exit exitContract = _deployExit(200e6);

        // Drain all tokens after timeLockExpiry has passed
        vm.warp(timeLockExpiry);
        vm.prank(OWNER);
        timeLock.drain(IERC20(address(token)), RECIPIENT);

        assertEq(token.balanceOf(address(timeLock)), 0, "timeLock should have no tokens after drain");

        // Now set exit and try claimExit — should revert because no tokens remain
        vm.prank(ADMIN);
        tokenExitRegistry.setExit(token, Exit(address(exitContract)));

        vm.warp(timeLockExpiry + 1 days);
        vm.prank(OWNER);
        vm.expectRevert("no tokens to exit");
        timeLock.claimExit(token, RECIPIENT, 0);
    }

    // ── minPayout passthrough (stub-based) ───────────────────────────────────

    /// FixedPayoutExit pays exactly _minPayout: claimExit succeeds
    function testClaimExitSucceedsWhenReceivedEqualsMinPayout() public {
        uint256 minPayout = 1e6;
        eurc.mint(address(this), minPayout);
        FixedPayoutExit stub = new FixedPayoutExit(IERC20(address(eurc)), minPayout);
        IERC20(address(eurc)).transfer(address(stub), minPayout);
        vm.prank(ADMIN);
        tokenExitRegistry.setExit(token, Exit(address(stub)));

        vm.prank(OWNER);
        timeLock.claimExit(token, RECIPIENT, minPayout);
        assertEq(eurc.balanceOf(RECIPIENT), minPayout, "RECIPIENT should receive exactly minPayout");
    }

    /// FixedPayoutDistribution pays exactly _minPayout: claimDistribution succeeds
    function testClaimDistributionSucceedsWhenReceivedEqualsMinPayout() public {
        uint256 minPayout = 1e6;
        eurc.mint(address(this), minPayout);
        FixedPayoutDistribution stub = new FixedPayoutDistribution(IERC20(address(eurc)), minPayout);
        IERC20(address(eurc)).transfer(address(stub), minPayout);

        vm.prank(OWNER);
        timeLock.claimDistribution(Distribution(address(stub)), RECIPIENT, minPayout);
        assertEq(eurc.balanceOf(RECIPIENT), minPayout, "RECIPIENT should receive exactly minPayout");
    }

    // ── referenceToExitRate ──────────────────────────────────────────────────

    /// TimeLock receives the correct payout from an Exit that has reference rates set.
    /// The reference rates are irrelevant to TimeLock (no carry), so payout must be identical
    /// to an exit without reference rates.
    function testClaimExitPayoutUnaffectedByReferenceRates() public {
        FakePaymentToken eure = new FakePaymentToken(0, 18);
        vm.prank(ADMIN);
        allowList.set(address(eure), TRUSTED_CURRENCY);

        IERC20[] memory referenceCurrencies = new IERC20[](1);
        referenceCurrencies[0] = IERC20(address(eure));
        uint256[] memory rates = new uint256[](1);
        rates[0] = 1e6; // 1 EURe (18 dec) = 1 EURc (6 dec)

        Exit exitContract = _deployExit(200e6, referenceCurrencies, rates);

        assertEq(exitContract.referenceToExitRate(IERC20(address(eure))), 1e6, "rate not stored");

        vm.prank(ADMIN);
        tokenExitRegistry.setExit(token, Exit(address(exitContract)));


        vm.prank(OWNER);
        timeLock.claimExit(token, RECIPIENT, 0);

        uint256 expectedPayout = (TOKEN_AMOUNT * 200e6) / (10 ** token.decimals());
        assertEq(eurc.balanceOf(RECIPIENT), expectedPayout, "wrong payout");
        assertEq(token.balanceOf(address(timeLock)), 0, "timeLock should have no tokens");
    }

    // ── TimeLock initialize revert cases ─────────────────────────────────────

    function testInitializeRevertsIfOwnerZero() public {
        TimeLock logic = new TimeLock(TRUSTED_FORWARDER);
        TimeLockCloneFactory cloneFactory = new TimeLockCloneFactory(address(logic));
        vm.expectRevert("owner can not be zero address");
        cloneFactory.createTimeLockClone(bytes32(0), TRUSTED_FORWARDER, address(0), timeLockExpiry, tokenExitRegistry);
    }

    function testInitializeRevertsIfLockedUntilNotInFuture() public {
        TimeLock logic = new TimeLock(TRUSTED_FORWARDER);
        TimeLockCloneFactory cloneFactory = new TimeLockCloneFactory(address(logic));
        vm.expectRevert("lockedUntil must be in the future");
        cloneFactory.createTimeLockClone(
            bytes32(0),
            TRUSTED_FORWARDER,
            OWNER,
            uint64(block.timestamp),
            tokenExitRegistry
        );
    }

    function testInitializeRevertsIfRegistryZero() public {
        TimeLock logic = new TimeLock(TRUSTED_FORWARDER);
        TimeLockCloneFactory cloneFactory = new TimeLockCloneFactory(address(logic));
        vm.expectRevert("tokenExitRegistry can not be zero address");
        cloneFactory.createTimeLockClone(
            bytes32(0),
            TRUSTED_FORWARDER,
            OWNER,
            timeLockExpiry,
            GlobalTokenExitRegistry(address(0))
        );
    }

    function testTimeLockCloneFactoryWrongForwarderReverts() public {
        address wrongForwarder = address(99);
        TimeLock logic = new TimeLock(TRUSTED_FORWARDER);
        TimeLockCloneFactory cloneFactory = new TimeLockCloneFactory(address(logic));
        vm.expectRevert("TimeLockCloneFactory: Unexpected trustedForwarder");
        cloneFactory.createTimeLockClone(bytes32(0), wrongForwarder, OWNER, timeLockExpiry, tokenExitRegistry);
    }

    // ── drain() revert cases ─────────────────────────────────────────────────

    function testDrainRevertsIfRecipientZero() public {
        vm.warp(timeLockExpiry);
        vm.prank(OWNER);
        vm.expectRevert("recipient can not be zero address");
        timeLock.drain(IERC20(address(token)), address(0));
    }

    function testDrainRevertsIfNoTokens() public {
        vm.warp(timeLockExpiry);
        vm.prank(OWNER);
        timeLock.drain(IERC20(address(token)), RECIPIENT);

        vm.prank(OWNER);
        vm.expectRevert("no tokens to drain");
        timeLock.drain(IERC20(address(token)), RECIPIENT);
    }

    function testClaimDistributionRevertsIfRecipientZero() public {
        FixedPayoutDistribution stub = new FixedPayoutDistribution(IERC20(address(eurc)), 0);
        vm.prank(OWNER);
        vm.expectRevert("recipient can not be zero address");
        timeLock.claimDistribution(Distribution(address(stub)), address(0), 0);
    }
}
