// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import "../lib/forge-std/src/Test.sol";
import "../contracts/factories/TokenProxyFactory.sol";
import "../contracts/factories/DistributionCloneFactory.sol";
import "../contracts/Distribution.sol";
import "./resources/FakePaymentToken.sol";
import "./resources/CloneCreators.sol";
import "./resources/MaliciousDistributionCurrency.sol";

contract DistributionTest is Test {
    address public constant ADMIN = 0x0109709eCFa91a80626FF3989D68f67f5b1dD120;
    address public constant OWNER = 0x1109709ecFA91a80626ff3989D68f67F5B1Dd121;
    address public constant HOLDER_A = 0x2109709EcFa91a80626Ff3989d68F67F5B1Dd122;
    address public constant HOLDER_B = 0x3109709ECfA91A80626fF3989D68f67F5B1Dd123;
    address public constant HOLDER_C = 0x4109709eCFa91A80626ff3989d68F67f5b1DD124;
    address public constant RECIPIENT = 0x5109709EcFA91a80626ff3989d68f67F5B1dD125;
    address public constant CURRENCY_PROVIDER = 0x6109709EcFA91A80626FF3989d68f67F5b1dd126;
    address public constant FEE_COLLECTOR = 0x7109709eCfa91A80626Ff3989D68f67f5b1dD127;
    address public constant TRUSTED_FORWARDER = 0x9109709EcFA91A80626FF3989D68f67F5B1dD129;

    uint8 public constant CURRENCY_DECIMALS = 6;
    // Total supply: 1000 tokens.  A=600, B=300, C=100.
    uint256 public constant SUPPLY_A = 600e18;
    uint256 public constant SUPPLY_B = 300e18;
    uint256 public constant SUPPLY_C = 100e18;
    uint256 public constant TOTAL_SUPPLY = SUPPLY_A + SUPPLY_B + SUPPLY_C;
    // 200 USDC total distribution
    uint256 public constant TOTAL_CURRENCY = 200e6;
    // pricePerToken: 200e6 currency for 1000e18 tokens → 200e6 * 1e18 / 1000e18 = 200_000
    uint256 public constant PRICE_PER_TOKEN = 200_000;

    uint64 public lockedUntil;

    AllowList allowList;
    FakePaymentToken currency;
    Token token;
    Distribution distLogic;
    DistributionCloneFactory factory;
    Distribution dist;
    TokenProxyFactory tokenFactory;
    uint256 public snapshotId;

    function setUp() public {
        lockedUntil = uint64(block.timestamp + 31 days);

        allowList = createAllowList(TRUSTED_FORWARDER, ADMIN);
        currency = new FakePaymentToken(0, CURRENCY_DECIMALS);
        vm.prank(ADMIN);
        allowList.set(address(currency), TRUSTED_CURRENCY);

        address tokenLogic = address(new Token(TRUSTED_FORWARDER));
        tokenFactory = new TokenProxyFactory(tokenLogic);
        IFeeSettingsV2 feeSettings = createFeeSettings(
            TRUSTED_FORWARDER,
            ADMIN,
            buildFeeTypes(0, 0, 0, ADMIN, ADMIN, ADMIN)
        );
        token = Token(
            tokenFactory.createTokenProxy(0, TRUSTED_FORWARDER, feeSettings, ADMIN, allowList, 0, "DistToken", "DST")
        );

        vm.startPrank(ADMIN);
        token.grantRole(token.MINTALLOWER_ROLE(), ADMIN);
        token.mint(HOLDER_A, SUPPLY_A);
        token.mint(HOLDER_B, SUPPLY_B);
        token.mint(HOLDER_C, SUPPLY_C);
        vm.stopPrank();

        vm.prank(ADMIN);
        snapshotId = token.createSnapshot();

        distLogic = new Distribution(TRUSTED_FORWARDER);
        factory = new DistributionCloneFactory(address(distLogic));
        dist = _deployDist(bytes32(0), TOTAL_CURRENCY, lockedUntil);
    }

    /// @dev Helper: predict address, fund, and deploy a Distribution clone
    function _deployDist(bytes32 salt, uint256 initialFunding, uint64 _lockedUntil) internal returns (Distribution) {
        DistributionInitializerArguments memory args = DistributionInitializerArguments({
            owner: OWNER,
            token: token,
            snapshotId: snapshotId,
            currency: IERC20(address(currency)),
            pricePerToken: PRICE_PER_TOKEN,
            lockedUntil: _lockedUntil,
            initialReassignments: new Reassignment[](0)
        });
        address cloneAddr = factory.predictCloneAddress(salt, TRUSTED_FORWARDER, args);
        if (initialFunding > 0) {
            currency.mint(CURRENCY_PROVIDER, initialFunding);
            vm.prank(CURRENCY_PROVIDER);
            currency.approve(cloneAddr, initialFunding);
        }
        return
            Distribution(
                factory.createDistributionClone(salt, TRUSTED_FORWARDER, CURRENCY_PROVIDER, args, initialFunding)
            );
    }

    // ========== D1. Constructor / Logic Contract ==========

    function testLogicContractInitializeReverts() public {
        DistributionInitializerArguments memory args = DistributionInitializerArguments({
            owner: OWNER,
            token: token,
            snapshotId: snapshotId,
            currency: IERC20(address(currency)),
            pricePerToken: PRICE_PER_TOKEN,
            lockedUntil: lockedUntil,
            initialReassignments: new Reassignment[](0)
        });
        vm.expectRevert("Initializable: contract is already initialized");
        distLogic.initialize(args, CURRENCY_PROVIDER, 0);
    }

    function testSecondInitializeReverts() public {
        DistributionInitializerArguments memory args = DistributionInitializerArguments({
            owner: OWNER,
            token: token,
            snapshotId: snapshotId,
            currency: IERC20(address(currency)),
            pricePerToken: PRICE_PER_TOKEN,
            lockedUntil: lockedUntil,
            initialReassignments: new Reassignment[](0)
        });
        vm.expectRevert("Initializable: contract is already initialized");
        dist.initialize(args, CURRENCY_PROVIDER, 0);
    }

    // ========== D2. initialize() — Validation & State ==========

    function testInitializeNonTrustedCurrencyReverts() public {
        FakePaymentToken badCurrency = new FakePaymentToken(0, 6);
        DistributionInitializerArguments memory args = DistributionInitializerArguments({
            owner: OWNER,
            token: token,
            snapshotId: snapshotId,
            currency: IERC20(address(badCurrency)),
            pricePerToken: PRICE_PER_TOKEN,
            lockedUntil: lockedUntil,
            initialReassignments: new Reassignment[](0)
        });
        vm.expectRevert(UntrustedCurrency.selector);
        factory.createDistributionClone(bytes32(0), TRUSTED_FORWARDER, CURRENCY_PROVIDER, args, 0);
    }

    function testInitializeInsufficientAllowanceReverts() public {
        DistributionInitializerArguments memory args = DistributionInitializerArguments({
            owner: OWNER,
            token: token,
            snapshotId: snapshotId,
            currency: IERC20(address(currency)),
            pricePerToken: PRICE_PER_TOKEN,
            lockedUntil: lockedUntil,
            initialReassignments: new Reassignment[](0)
        });
        address cloneAddr = factory.predictCloneAddress(bytes32("2"), TRUSTED_FORWARDER, args);
        currency.mint(CURRENCY_PROVIDER, 500e6);
        vm.prank(CURRENCY_PROVIDER);
        currency.approve(cloneAddr, 499e6); // one short
        vm.expectRevert("ERC20: insufficient allowance");
        factory.createDistributionClone(bytes32("2"), TRUSTED_FORWARDER, CURRENCY_PROVIDER, args, 500e6);
    }

    function testInitializeZeroPriceReverts() public {
        DistributionInitializerArguments memory args = DistributionInitializerArguments({
            owner: OWNER,
            token: token,
            snapshotId: snapshotId,
            currency: IERC20(address(currency)),
            pricePerToken: 0,
            lockedUntil: lockedUntil,
            initialReassignments: new Reassignment[](0)
        });
        vm.expectRevert(ZeroPrice.selector);
        factory.createDistributionClone(bytes32(0), TRUSTED_FORWARDER, CURRENCY_PROVIDER, args, 0);
    }

    function testInitializeZeroOwnerReverts() public {
        DistributionInitializerArguments memory args = DistributionInitializerArguments({
            owner: address(0),
            token: token,
            snapshotId: snapshotId,
            currency: IERC20(address(currency)),
            pricePerToken: PRICE_PER_TOKEN,
            lockedUntil: lockedUntil,
            initialReassignments: new Reassignment[](0)
        });
        vm.expectRevert(ZeroOwnerAddress.selector);
        factory.createDistributionClone(bytes32("1"), TRUSTED_FORWARDER, CURRENCY_PROVIDER, args, 0);
    }

    function testInitializeStateVariables() public view {
        assertEq(address(dist.token()), address(token), "unexpected token address");
        assertEq(dist.snapshotId(), snapshotId, "unexpected snapshotId");
        assertEq(address(dist.currency()), address(currency), "unexpected currency address");
        assertEq(dist.pricePerToken(), PRICE_PER_TOKEN, "unexpected pricePerToken");
        assertEq(dist.lockedUntil(), lockedUntil, "unexpected lockedUntil");
        assertEq(dist.owner(), OWNER, "unexpected OWNER");
        assertEq(currency.balanceOf(address(dist)), TOTAL_CURRENCY, "dist not fully funded");
    }

    function testInitializeZeroTotalSupplyReverts() public {
        // Take a snapshot before any tokens are minted on a fresh token
        IFeeSettingsV2 feeSettings = createFeeSettings(
            TRUSTED_FORWARDER,
            ADMIN,
            buildFeeTypes(0, 0, 0, ADMIN, ADMIN, ADMIN)
        );
        Token emptyToken = Token(
            tokenFactory.createTokenProxy(
                bytes32(0),
                TRUSTED_FORWARDER,
                feeSettings,
                ADMIN,
                allowList,
                0,
                "EmptyToken",
                "EMP"
            )
        );
        vm.prank(ADMIN);
        uint256 emptySnap = emptyToken.createSnapshot(); // total supply = 0

        DistributionInitializerArguments memory args = DistributionInitializerArguments({
            owner: OWNER,
            token: emptyToken,
            snapshotId: emptySnap,
            currency: IERC20(address(currency)),
            pricePerToken: PRICE_PER_TOKEN,
            lockedUntil: lockedUntil,
            initialReassignments: new Reassignment[](0)
        });
        vm.expectRevert(Distribution.EmptySnapshot.selector);
        factory.createDistributionClone(bytes32(0), TRUSTED_FORWARDER, CURRENCY_PROVIDER, args, 0);
    }

    function testInitializeWithZeroFunding() public {
        Distribution unfunded = _deployDist(bytes32("1"), 0, lockedUntil);
        assertEq(currency.balanceOf(address(unfunded)), 0, "unfunded dist should have zero balance");
        assertEq(unfunded.pricePerToken(), PRICE_PER_TOKEN, "pricePerToken should be set even without funding");
        // eligible is based on price, not balance
        assertEq(unfunded.eligible(HOLDER_A), 120e6, "HOLDER_A eligible should be based on price");
    }

    // ========== D3. eligible() — Math ==========

    function testEligibleConcreteExample() public view {
        // A: 600e18 * 200_000 / 1e18 = 120e6
        assertEq(dist.eligible(HOLDER_A), 120e6, "HOLDER_A eligible amount wrong");
        // B: 300e18 * 200_000 / 1e18 = 60e6
        assertEq(dist.eligible(HOLDER_B), 60e6, "HOLDER_B eligible amount wrong");
        // C: 100e18 * 200_000 / 1e18 = 20e6
        assertEq(dist.eligible(HOLDER_C), 20e6, "HOLDER_C eligible amount wrong");
    }

    function testEligibleZeroBalanceIsZero() public view {
        assertEq(dist.eligible(address(42)), 0, "holder with zero balance should have zero eligible");
    }

    function testEligibleSumEqTotalCurrencyLimitedDust() public view {
        uint256 sumEligible = dist.eligible(HOLDER_A) + dist.eligible(HOLDER_B) + dist.eligible(HOLDER_C);
        uint256 maxPayout = (TOTAL_SUPPLY * PRICE_PER_TOKEN) / (10 ** token.decimals());
        assertLe(sumEligible, maxPayout, "sum of eligible exceeds max payout");
        // max dust = number of holders
        assertGe(sumEligible + 3, maxPayout, "sum of eligible less than max payout minus dust");
    }

    function testFuzzEligibleSumNeverExceedsTotal(uint128 pricePerTokenFuzz, uint128 balA, uint128 balB) public {
        vm.assume(pricePerTokenFuzz > 0);
        vm.assume(uint256(balA) + balB < type(uint128).max);
        uint256 balC = uint256(balA) + balB > 0 ? uint256(balA) + balB : 1;
        // Ensure balance * pricePerToken fits in uint256 (each balance ≤ 2*type(uint128).max)
        uint256 maxBalance = 2 * uint256(type(uint128).max);
        vm.assume(uint256(pricePerTokenFuzz) <= type(uint256).max / (maxBalance > 0 ? maxBalance : 1));

        // Deploy a fresh token with three holders
        IFeeSettingsV2 feeSettings = createFeeSettings(
            TRUSTED_FORWARDER,
            ADMIN,
            buildFeeTypes(0, 0, 0, ADMIN, ADMIN, ADMIN)
        );
        Token fuzzToken = Token(
            tokenFactory.createTokenProxy(
                bytes32(0),
                TRUSTED_FORWARDER,
                feeSettings,
                ADMIN,
                allowList,
                0,
                "FuzzToken",
                "FZT"
            )
        );
        vm.startPrank(ADMIN);
        fuzzToken.grantRole(fuzzToken.MINTALLOWER_ROLE(), ADMIN);
        if (balA > 0) fuzzToken.mint(HOLDER_A, balA);
        if (balB > 0) fuzzToken.mint(HOLDER_B, balB);
        fuzzToken.mint(HOLDER_C, balC);
        vm.stopPrank();
        vm.prank(ADMIN);
        uint256 snap = fuzzToken.createSnapshot();

        uint256 totalSupply = uint256(balA) + uint256(balB) + balC;
        uint256 maxPayout = (totalSupply * uint256(pricePerTokenFuzz)) / (10 ** fuzzToken.decimals());

        DistributionInitializerArguments memory args = DistributionInitializerArguments({
            owner: OWNER,
            token: fuzzToken,
            snapshotId: snap,
            currency: IERC20(address(currency)),
            pricePerToken: pricePerTokenFuzz,
            lockedUntil: lockedUntil,
            initialReassignments: new Reassignment[](0)
        });
        Distribution fuzzDistribution = Distribution(
            factory.createDistributionClone(bytes32(0), TRUSTED_FORWARDER, CURRENCY_PROVIDER, args, 0)
        );

        uint256 sumE = fuzzDistribution.eligible(HOLDER_A) +
            fuzzDistribution.eligible(HOLDER_B) +
            fuzzDistribution.eligible(HOLDER_C);
        assertLe(sumE, maxPayout, "sum of eligible exceeds max payout");
        // Each eligible() truncates balance * pricePerToken / 10^decimals, losing up to (10^decimals - 1) per holder
        uint256 maxDust = 3 * (10 ** fuzzToken.decimals());
        assertGe(sumE + maxDust, maxPayout, "dust exceeds bound");
    }

    // ========== D4. claim(address) — Direct Claim ==========

    function testClaimCorrectAmount() public {
        assertEq(currency.balanceOf(RECIPIENT), 0, "RECIPIENT already holds currency");
        vm.prank(HOLDER_A);
        dist.claim(RECIPIENT, 0);
        assertEq(currency.balanceOf(RECIPIENT), 120e6, "RECIPIENT did not receive HOLDER_A's share");
    }

    function testClaimZeroEligibleReverts() public {
        vm.expectRevert(NothingToClaim.selector);
        dist.claim(RECIPIENT, 0); // address(this) has 0 snapshot balance
    }

    function testClaimUpdatesPayedOut() public {
        vm.prank(HOLDER_A);
        dist.claim(HOLDER_A, 0);
        assertEq(dist.eligible(HOLDER_A), 0, "eligible should be zero after claim");
        assertEq(dist.paidOut(HOLDER_A), 120e6, "paidOut not updated after claim");
    }

    function testSecondClaimReverts() public {
        vm.prank(HOLDER_A);
        dist.claim(HOLDER_A, 0);
        vm.prank(HOLDER_A);
        vm.expectRevert(NothingToClaim.selector);
        dist.claim(HOLDER_A, 0);
    }

    function testClaimRecipientDiffersFromSender() public {
        vm.prank(HOLDER_A);
        dist.claim(RECIPIENT, 0);
        assertEq(currency.balanceOf(HOLDER_A), 0, "sender should not receive currency when RECIPIENT differs");
        assertEq(currency.balanceOf(RECIPIENT), 120e6, "RECIPIENT did not receive HOLDER_A's share");
    }

    function testMultipleHoldersClaimIndependently() public {
        vm.prank(HOLDER_A);
        dist.claim(HOLDER_A, 0);
        vm.prank(HOLDER_B);
        dist.claim(HOLDER_B, 0);
        vm.prank(HOLDER_C);
        dist.claim(HOLDER_C, 0);
        assertEq(currency.balanceOf(HOLDER_A), 120e6, "HOLDER_A received wrong amount");
        assertEq(currency.balanceOf(HOLDER_B), 60e6, "HOLDER_B received wrong amount");
        assertEq(currency.balanceOf(HOLDER_C), 20e6, "HOLDER_C received wrong amount");
    }

    function testERC2771ClaimIdentifiesHolder() public {
        uint256 expected = 120e6;
        bytes memory callData = abi.encodePacked(
            abi.encodeWithSelector(bytes4(keccak256("claim(address,uint256)")), RECIPIENT, uint256(0)),
            HOLDER_A
        );
        vm.prank(TRUSTED_FORWARDER);
        (bool success, ) = address(dist).call(callData);
        assertTrue(success, "ERC2771 claim call failed");
        assertEq(currency.balanceOf(RECIPIENT), expected, "RECIPIENT did not receive HOLDER_A's share via ERC2771");
    }

    /// @dev Helper to deploy a Distribution against a specific snapshot
    function _deployDistWithSnapshot(
        bytes32 salt,
        uint256 snap,
        uint256 initialFunding
    ) internal returns (Distribution) {
        DistributionInitializerArguments memory args = DistributionInitializerArguments({
            owner: OWNER,
            token: token,
            snapshotId: snap,
            currency: IERC20(address(currency)),
            pricePerToken: PRICE_PER_TOKEN,
            lockedUntil: lockedUntil,
            initialReassignments: new Reassignment[](0)
        });
        address cloneAddr = factory.predictCloneAddress(salt, TRUSTED_FORWARDER, args);
        if (initialFunding > 0) {
            currency.mint(CURRENCY_PROVIDER, initialFunding);
            vm.prank(CURRENCY_PROVIDER);
            currency.approve(cloneAddr, initialFunding);
        }
        return
            Distribution(
                factory.createDistributionClone(salt, TRUSTED_FORWARDER, CURRENCY_PROVIDER, args, initialFunding)
            );
    }

    // ========== D5. drain() ==========

    function testDrainNonOwnerReverts() public {
        vm.warp(lockedUntil);
        vm.expectRevert("Ownable: caller is not the owner");
        vm.prank(HOLDER_A);
        dist.drain(HOLDER_A, currency);
    }

    function testDrainBeforeDeadlineReverts() public {
        vm.expectRevert(DrainNotYetAvailable.selector);
        vm.prank(OWNER);
        dist.drain(OWNER, currency);
    }

    function testDrainAtExactDeadlineSucceeds() public {
        vm.warp(lockedUntil);
        vm.prank(OWNER);
        dist.drain(OWNER, currency);
        assertEq(currency.balanceOf(OWNER), TOTAL_CURRENCY, "OWNER should receive full balance after drain");
        assertEq(currency.balanceOf(address(dist)), 0, "dist should be empty after drain");
    }

    function testDrainAfterPartialClaims() public {
        vm.prank(HOLDER_A);
        dist.claim(HOLDER_A, 0);
        uint256 remaining = currency.balanceOf(address(dist));
        assertEq(remaining, TOTAL_CURRENCY - 120e6, "remaining balance wrong after HOLDER_A claim");

        vm.warp(lockedUntil);
        vm.prank(OWNER);
        dist.drain(OWNER, currency);
        assertEq(currency.balanceOf(OWNER), remaining, "OWNER should receive remaining balance after drain");
        assertEq(currency.balanceOf(address(dist)), 0, "dist should be empty after drain");
    }

    function testFuzzDrainTiming(uint64 warpTo) public {
        vm.assume(warpTo >= block.timestamp);
        vm.warp(warpTo);
        if (warpTo < lockedUntil) {
            vm.expectRevert(DrainNotYetAvailable.selector);
            vm.prank(OWNER);
            dist.drain(OWNER, currency);
        } else {
            vm.prank(OWNER);
            dist.drain(OWNER, currency);
            assertEq(currency.balanceOf(address(dist)), 0, "dist should be empty after drain");
        }
    }

    // ========== D7. reassign() ==========

    function testReassignNonOwnerReverts() public {
        vm.warp(lockedUntil);
        uint256 amount = dist.eligible(HOLDER_A);
        vm.expectRevert("Ownable: caller is not the owner");
        vm.prank(HOLDER_A);
        dist.reassign(HOLDER_A, HOLDER_B, amount);
    }

    function testReassignBeforeDeadlineReverts() public {
        uint256 amount = dist.eligible(HOLDER_A);
        vm.expectRevert(Distribution.ReassignmentNotYetAvailable.selector);
        vm.prank(OWNER);
        dist.reassign(HOLDER_A, HOLDER_B, amount);
    }

    function testReassignAtExactDeadlineSucceeds() public {
        vm.warp(lockedUntil);
        uint256 amount = dist.eligible(HOLDER_A);
        vm.prank(OWNER);
        dist.reassign(HOLDER_A, HOLDER_B, amount);
    }

    function testFuzzReassignDeadline(uint64 warpTo) public {
        vm.assume(warpTo >= block.timestamp); // avoid warping to the past
        uint256 amount = dist.eligible(HOLDER_A);
        vm.warp(warpTo);
        assertEq(dist.eligible(HOLDER_A), amount, "HOLDER_A eligible should be non-zero before reassign");
        assertEq(dist.eligible(HOLDER_B), 60e6, "HOLDER_B eligible should be own share before reassign");
        if (warpTo < lockedUntil) {
            vm.expectRevert(Distribution.ReassignmentNotYetAvailable.selector);
            vm.prank(OWNER);
            dist.reassign(HOLDER_A, HOLDER_B, amount);
            assertEq(dist.eligible(HOLDER_A), amount, "HOLDER_A eligible should be non-zero after revert");
            assertEq(dist.eligible(HOLDER_B), 60e6, "HOLDER_B eligible should be own share after revert");
        } else {
            vm.prank(OWNER);
            dist.reassign(HOLDER_A, HOLDER_B, amount);
            assertEq(dist.eligible(HOLDER_A), 0, "HOLDER_A eligible should be zero after reassign");
            assertEq(dist.eligible(HOLDER_B), 60e6 + amount, "HOLDER_B eligible should include reassigned amount");
        }
    }

    function testReassignToZeroAddressReverts() public {
        vm.warp(lockedUntil);
        uint256 amount = dist.eligible(HOLDER_A);
        vm.expectRevert(ZeroReceiverAddress.selector);
        vm.prank(OWNER);
        dist.reassign(HOLDER_A, address(0), amount);
    }

    function testReassignZeroAmountReverts() public {
        vm.warp(lockedUntil);
        vm.expectRevert(ZeroAmount.selector);
        vm.prank(OWNER);
        dist.reassign(HOLDER_A, HOLDER_B, 0);
    }

    function testReassignExceedsEligibleReverts() public {
        vm.warp(lockedUntil);
        vm.expectRevert(Distribution.ReassignmentExceedsEligible.selector);
        vm.prank(OWNER);
        dist.reassign(address(42), HOLDER_B, 1); // address(42) has no balance
    }

    function testReassignEffect() public {
        vm.warp(lockedUntil);
        assertEq(dist.eligible(HOLDER_A), 120e6, "HOLDER_A eligible should be 120e6 before reassign");
        assertEq(dist.eligible(HOLDER_B), 60e6, "HOLDER_B eligible should be 60e6 before reassign");
        uint256 amountA = dist.eligible(HOLDER_A);
        vm.prank(OWNER);
        dist.reassign(HOLDER_A, HOLDER_B, amountA);

        assertEq(dist.eligible(HOLDER_A), 0, "HOLDER_A eligible should be zero after full reassign");
        assertEq(dist.paidOut(HOLDER_A), 120e6, "HOLDER_A paidOut not updated after reassign");
        // HOLDER_B gets own share + reassigned
        assertEq(dist.eligible(HOLDER_B), 60e6 + 120e6, "HOLDER_B eligible should include reassigned amount");
    }

    function testReassignEmitsEvent() public {
        vm.warp(lockedUntil);
        vm.expectEmit(true, true, false, true, address(dist));
        emit Distribution.Reassigned(HOLDER_A, HOLDER_B, 120e6);
        vm.prank(OWNER);
        dist.reassign(HOLDER_A, HOLDER_B, 120e6);
    }

    function testReassignStackingMultipleToSameRecipient() public {
        vm.warp(lockedUntil);
        uint256 amountB = dist.eligible(HOLDER_B);
        vm.prank(OWNER);
        dist.reassign(HOLDER_B, HOLDER_A, amountB); // A gets B's 60e6
        uint256 amountC = dist.eligible(HOLDER_C);
        vm.prank(OWNER);
        dist.reassign(HOLDER_C, HOLDER_A, amountC); // A gets C's 20e6

        assertEq(
            dist.eligible(HOLDER_A),
            120e6 + 60e6 + 20e6,
            "HOLDER_A eligible should include all reassigned amounts"
        );
        assertEq(dist.eligible(HOLDER_B), 0, "HOLDER_B eligible should be zero after full reassign");
        assertEq(dist.eligible(HOLDER_C), 0, "HOLDER_C eligible should be zero after full reassign");

        vm.prank(HOLDER_A);
        dist.claim(HOLDER_A, 0);
        assertEq(
            currency.balanceOf(HOLDER_A),
            200e6,
            "HOLDER_A should receive full distribution after stacked reassigns"
        );
    }

    function testReassignSelfReverts() public {
        vm.warp(lockedUntil);
        vm.expectRevert(Distribution.SelfReassignmentNotAllowed.selector);
        vm.prank(OWNER);
        dist.reassign(HOLDER_A, HOLDER_A, 1);
    }

    function testReassignAfterClaimReverts() public {
        vm.prank(HOLDER_A);
        dist.claim(HOLDER_A, 0); // eligible drops to 0
        vm.warp(lockedUntil);
        vm.expectRevert(Distribution.ReassignmentExceedsEligible.selector);
        vm.prank(OWNER);
        dist.reassign(HOLDER_A, HOLDER_B, 1);
    }

    function testSecondReassignFromSameAddressReverts() public {
        vm.warp(lockedUntil);
        uint256 amountA = dist.eligible(HOLDER_A);
        vm.prank(OWNER);
        dist.reassign(HOLDER_A, HOLDER_B, amountA);
        vm.expectRevert(Distribution.ReassignmentExceedsEligible.selector);
        vm.prank(OWNER);
        dist.reassign(HOLDER_A, HOLDER_C, 1); // eligible = 0 after first reassign
    }

    function testPartialReassign() public {
        vm.warp(lockedUntil);
        uint256 aliceEligible = dist.eligible(HOLDER_A); // 120e6

        vm.prank(OWNER);
        dist.reassign(HOLDER_A, HOLDER_B, aliceEligible / 2); // 60e6 to B
        assertEq(
            dist.eligible(HOLDER_A),
            aliceEligible / 2,
            "HOLDER_A eligible should be halved after partial reassign"
        );
        assertEq(dist.eligible(HOLDER_B), 60e6 + aliceEligible / 2, "HOLDER_B eligible should include reassigned half");

        uint256 aliceRemaining = dist.eligible(HOLDER_A);
        vm.prank(OWNER);
        dist.reassign(HOLDER_A, HOLDER_C, aliceRemaining); // remaining 60e6 to C
        assertEq(dist.eligible(HOLDER_A), 0, "HOLDER_A eligible should be zero after second partial reassign");
        assertEq(
            dist.eligible(HOLDER_C),
            20e6 + aliceEligible / 2,
            "HOLDER_C eligible should include reassigned remainder"
        );
    }

    function testChainedReassignAToB() public {
        // A → B → C (B has no snapshot balance)
        Distribution chainDist = _deployDist(bytes32("1"), TOTAL_CURRENCY, lockedUntil);

        // initial state
        assertEq(chainDist.eligible(HOLDER_A), 120e6, "HOLDER_A initial eligible");
        assertEq(chainDist.eligible(HOLDER_B), 60e6, "HOLDER_B initial eligible");
        assertEq(chainDist.eligible(HOLDER_C), 20e6, "HOLDER_C initial eligible");

        vm.warp(lockedUntil);
        uint256 amountA = chainDist.eligible(HOLDER_A);
        vm.prank(OWNER);
        chainDist.reassign(HOLDER_A, HOLDER_B, amountA); // B now has 120+60=180e6

        // after A → B
        assertEq(chainDist.eligible(HOLDER_A), 0, "HOLDER_A eligible should be zero after first reassign");
        assertEq(chainDist.eligible(HOLDER_B), 180e6, "HOLDER_B eligible should be 180e6 after receiving A's share");
        assertEq(chainDist.eligible(HOLDER_C), 20e6, "HOLDER_C eligible should be unchanged after first reassign");

        uint256 amountB = chainDist.eligible(HOLDER_B);
        vm.prank(OWNER);
        chainDist.reassign(HOLDER_B, HOLDER_C, amountB); // C now has 20+180=200e6

        // after B → C
        assertEq(chainDist.eligible(HOLDER_A), 0, "HOLDER_A eligible should be zero after chained reassign");
        assertEq(chainDist.eligible(HOLDER_B), 0, "HOLDER_B eligible should be zero after chained reassign");
        assertEq(
            chainDist.eligible(HOLDER_C),
            TOTAL_CURRENCY,
            "HOLDER_C eligible should be full amount after chained reassign"
        );

        vm.prank(HOLDER_C);
        chainDist.claim(HOLDER_C, 0);
        assertEq(
            currency.balanceOf(HOLDER_C),
            TOTAL_CURRENCY,
            "HOLDER_C should receive full distribution after chained reassign"
        );
    }

    function testChainedReassignSumOfEligibleInvariant() public {
        // After each reassign, sum of all eligible must remain constant
        uint256 sumBefore = dist.eligible(HOLDER_A) + dist.eligible(HOLDER_B) + dist.eligible(HOLDER_C);

        vm.warp(lockedUntil);
        uint256 amountA = dist.eligible(HOLDER_A);
        vm.prank(OWNER);
        dist.reassign(HOLDER_A, HOLDER_B, amountA);

        uint256 sumAfter = dist.eligible(HOLDER_A) + dist.eligible(HOLDER_B) + dist.eligible(HOLDER_C);
        assertEq(sumBefore, sumAfter, "sum of eligible should be unchanged after reassign");
    }

    // ========== D8. Interaction: claim then reassign ==========

    function testClaimThenReassignReverts() public {
        vm.prank(HOLDER_A);
        dist.claim(HOLDER_A, 0); // eligible(A) = 0
        vm.warp(lockedUntil);
        vm.expectRevert(Distribution.ReassignmentExceedsEligible.selector);
        vm.prank(OWNER);
        dist.reassign(HOLDER_A, HOLDER_B, 1);
    }

    // ========== D9. Interaction: reassign then claim by RECIPIENT ==========

    function testReassignThenClaimByRecipient() public {
        vm.warp(lockedUntil);
        uint256 amountA = dist.eligible(HOLDER_A);
        vm.prank(OWNER);
        dist.reassign(HOLDER_A, HOLDER_B, amountA); // B gets 60 + 120 = 180e6

        vm.prank(HOLDER_B);
        dist.claim(HOLDER_B, 0);
        assertEq(currency.balanceOf(HOLDER_B), 180e6, "HOLDER_B should receive own share plus reassigned amount");

        // A's paidOut covers their share: A claims 0
        vm.prank(HOLDER_A);
        vm.expectRevert(NothingToClaim.selector);
        dist.claim(HOLDER_A, 0);
        assertEq(currency.balanceOf(HOLDER_A), 0, "HOLDER_A should receive nothing after full reassign");

        // total paid out ≤ funded amount
        assertLe(
            currency.balanceOf(HOLDER_B) + currency.balanceOf(HOLDER_A),
            TOTAL_CURRENCY,
            "total paid out exceeds funded amount"
        );
    }

    // ========== D10. Fuzz / Property-Based Tests ==========

    function testFuzzClaimNoDoublePay(uint8 claimOrder) public {
        // Any order of A, B, C claiming → sum of payouts ≤ funded amount
        address[3] memory holders = [HOLDER_A, HOLDER_B, HOLDER_C];
        // claimOrder low bits determine which subset claims
        for (uint256 i = 0; i < 3; i++) {
            if ((claimOrder >> i) & 1 == 1) {
                vm.prank(holders[i]);
                dist.claim(holders[i], 0);
            }
        }
        uint256 totalPaid = currency.balanceOf(HOLDER_A) + currency.balanceOf(HOLDER_B) + currency.balanceOf(HOLDER_C);
        assertLe(totalPaid, TOTAL_CURRENCY, "total paid out exceeds funded amount");
    }

    function testFuzzReassignSumInvariant(address reassignTo) public {
        vm.assume(reassignTo != address(0));
        vm.assume(reassignTo != HOLDER_A);
        vm.assume(reassignTo != HOLDER_B);
        vm.assume(reassignTo != HOLDER_C);
        uint256 sumBefore = dist.eligible(HOLDER_A) +
            dist.eligible(HOLDER_B) +
            dist.eligible(HOLDER_C) +
            dist.eligible(reassignTo);

        vm.warp(lockedUntil);
        uint256 amountA = dist.eligible(HOLDER_A);
        vm.prank(OWNER);
        dist.reassign(HOLDER_A, reassignTo, amountA);

        uint256 sumAfter = dist.eligible(HOLDER_A) +
            dist.eligible(HOLDER_B) +
            dist.eligible(HOLDER_C) +
            dist.eligible(reassignTo);
        assertEq(sumBefore, sumAfter, "sum of eligible should be unchanged after reassign");
    }

    // ========== D11. Underfunding ==========

    function testClaimRevertsWhenUnderfunded() public {
        Distribution unfunded = _deployDist(bytes32("1"), 0, lockedUntil);
        // HOLDER_A is eligible for 120e6 but contract has 0 balance
        vm.prank(HOLDER_A);
        vm.expectRevert("ERC20: transfer amount exceeds balance");
        unfunded.claim(HOLDER_A, 0);
    }

    function testClaimSucceedsAfterLaterFunding() public {
        Distribution unfunded = _deployDist(bytes32("1"), 0, lockedUntil);
        // Fund later
        currency.mint(address(unfunded), TOTAL_CURRENCY);
        vm.prank(HOLDER_A);
        unfunded.claim(HOLDER_A, 0);
        assertEq(currency.balanceOf(HOLDER_A), 120e6, "HOLDER_A should receive share after late funding");
    }

    function testPartialFundingAllowsSomeClaims() public {
        // Fund only enough for HOLDER_C (20e6)
        Distribution partialDist = _deployDist(bytes32("1"), 20e6, lockedUntil);
        vm.prank(HOLDER_C);
        partialDist.claim(HOLDER_C, 0);
        assertEq(currency.balanceOf(HOLDER_C), 20e6, "HOLDER_C should claim from partial funding");

        // HOLDER_A cannot claim (not enough balance)
        vm.prank(HOLDER_A);
        vm.expectRevert("ERC20: transfer amount exceeds balance");
        partialDist.claim(HOLDER_A, 0);
    }

    // ========== D_Fee. Fee Collection at Claim Time ==========

    /// @dev Deploy a Distribution backed by a token with 1% private offer fee.
    function _deployDistWithNonZeroFee() internal returns (Distribution d) {
        IFeeSettingsV2 feeSettingsWithFee = createFeeSettings(
            TRUSTED_FORWARDER,
            ADMIN,
            buildFeeTypes(0, 0, 100, ADMIN, ADMIN, FEE_COLLECTOR)
        );
        Token feeToken = Token(
            tokenFactory.createTokenProxy(
                bytes32(0),
                TRUSTED_FORWARDER,
                feeSettingsWithFee,
                ADMIN,
                allowList,
                0,
                "FeeToken",
                "FTK"
            )
        );
        vm.startPrank(ADMIN);
        feeToken.grantRole(feeToken.MINTALLOWER_ROLE(), ADMIN);
        feeToken.mint(HOLDER_A, SUPPLY_A);
        feeToken.mint(HOLDER_B, SUPPLY_B);
        feeToken.mint(HOLDER_C, SUPPLY_C);
        vm.stopPrank();
        vm.prank(ADMIN);
        uint256 snap = feeToken.createSnapshot();

        DistributionInitializerArguments memory args = DistributionInitializerArguments({
            owner: OWNER,
            token: feeToken,
            snapshotId: snap,
            currency: IERC20(address(currency)),
            pricePerToken: PRICE_PER_TOKEN,
            lockedUntil: lockedUntil,
            initialReassignments: new Reassignment[](0)
        });
        address cloneAddr = factory.predictCloneAddress(bytes32(0), TRUSTED_FORWARDER, args);
        currency.mint(CURRENCY_PROVIDER, TOTAL_CURRENCY);
        vm.prank(CURRENCY_PROVIDER);
        currency.approve(cloneAddr, TOTAL_CURRENCY);
        d = Distribution(
            factory.createDistributionClone(bytes32(0), TRUSTED_FORWARDER, CURRENCY_PROVIDER, args, TOTAL_CURRENCY)
        );
    }

    function testNoFeeAtInitialization() public {
        assertEq(currency.balanceOf(FEE_COLLECTOR), 0, "FEE_COLLECTOR should have no currency before deployment");
        _deployDistWithNonZeroFee();
        assertEq(currency.balanceOf(FEE_COLLECTOR), 0, "FEE_COLLECTOR should have no currency after deployment");
    }

    function testFeeDeductedAtClaimTime() public {
        Distribution d = _deployDistWithNonZeroFee();
        uint256 grossA = (SUPPLY_A * PRICE_PER_TOKEN) / 1e18; // 120e6
        uint256 expectedFee = grossA / 100; // 1% of gross
        uint256 expectedNet = grossA - expectedFee; // 118.8e6

        vm.prank(HOLDER_A);
        d.claim(HOLDER_A, 0);

        assertEq(currency.balanceOf(FEE_COLLECTOR), expectedFee, "FEE_COLLECTOR did not receive correct fee");
        assertEq(currency.balanceOf(HOLDER_A), expectedNet, "HOLDER_A did not receive net amount after fee");
    }

    function testFeeSentToFeeCollectorPerClaim() public {
        Distribution d = _deployDistWithNonZeroFee();

        vm.prank(HOLDER_A);
        d.claim(HOLDER_A, 0);
        uint256 feeAfterA = currency.balanceOf(FEE_COLLECTOR);
        assertGt(feeAfterA, 0, "FEE_COLLECTOR should have received fee from HOLDER_A claim");

        vm.prank(HOLDER_B);
        d.claim(HOLDER_B, 0);
        uint256 feeAfterB = currency.balanceOf(FEE_COLLECTOR);
        assertGt(feeAfterB, feeAfterA, "FEE_COLLECTOR should have received additional fee from HOLDER_B claim");
    }

    function testEligibleDeductsFee() public {
        Distribution d = _deployDistWithNonZeroFee();
        // eligible() deducts the 1% fee, returning net payout amount
        uint256 grossA = (SUPPLY_A * PRICE_PER_TOKEN) / 1e18; // 120e6
        uint256 grossB = (SUPPLY_B * PRICE_PER_TOKEN) / 1e18; // 60e6
        uint256 grossC = (SUPPLY_C * PRICE_PER_TOKEN) / 1e18; // 20e6
        assertEq(d.eligible(HOLDER_A), grossA - grossA / 100, "HOLDER_A eligible should be net after fee");
        assertEq(d.eligible(HOLDER_B), grossB - grossB / 100, "HOLDER_B eligible should be net after fee");
        assertEq(d.eligible(HOLDER_C), grossC - grossC / 100, "HOLDER_C eligible should be net after fee");
    }

    // ========== D_MinPayout. minPayout guard ==========

    /// minPayout == 0 always passes (no minimum)
    function testClaimMinPayoutZeroAlwaysPasses() public {
        vm.prank(HOLDER_A);
        dist.claim(HOLDER_A, 0);
        assertGt(currency.balanceOf(HOLDER_A), 0, "HOLDER_A should receive currency");
    }

    /// minPayout exactly equal to eligible (no fees) succeeds
    function testClaimMinPayoutExactEligibleSucceeds() public {
        uint256 expectedNet = dist.eligible(HOLDER_A); // 120e6
        vm.prank(HOLDER_A);
        dist.claim(HOLDER_A, expectedNet);
        assertEq(currency.balanceOf(HOLDER_A), expectedNet, "HOLDER_A should receive exactly eligible");
    }

    /// minPayout one above eligible reverts
    function testClaimMinPayoutAboveEligibleReverts() public {
        uint256 expectedNet = dist.eligible(HOLDER_A);
        vm.prank(HOLDER_A);
        vm.expectRevert(PayoutBelowMinimum.selector);
        dist.claim(HOLDER_A, expectedNet + 1);
    }

    /// With a fee, minPayout exactly equal to eligible() succeeds because eligible() already deducts the fee
    function testClaimMinPayoutEligibleWithFeeSucceeds() public {
        Distribution d = _deployDistWithNonZeroFee();
        uint256 expectedNet = d.eligible(HOLDER_A); // eligible() returns net after fee
        vm.prank(HOLDER_A);
        d.claim(HOLDER_A, expectedNet);
        assertEq(currency.balanceOf(HOLDER_A), expectedNet, "HOLDER_A should receive exactly eligible");
    }

    /// With a fee, minPayout above eligible() (i.e. the gross amount) reverts
    function testClaimMinPayoutAboveEligibleWithFeeReverts() public {
        Distribution d = _deployDistWithNonZeroFee();
        uint256 gross = (SUPPLY_A * PRICE_PER_TOKEN) / 1e18; // 120e6, before fee
        vm.prank(HOLDER_A);
        vm.expectRevert(PayoutBelowMinimum.selector);
        d.claim(HOLDER_A, gross); // gross > eligible() (net)
    }

    /// Fuzz: claim always succeeds when minPayout <= net, reverts when minPayout > net (no fees)
    function testFuzzClaimMinPayoutBoundary(uint256 minPayout) public {
        uint256 net = dist.eligible(HOLDER_A); // 120e6, no fee
        vm.prank(HOLDER_A);
        if (minPayout <= net) {
            dist.claim(HOLDER_A, minPayout);
            assertEq(currency.balanceOf(HOLDER_A), net, "HOLDER_A should receive eligible");
        } else {
            vm.expectRevert(PayoutBelowMinimum.selector);
            dist.claim(HOLDER_A, minPayout);
        }
    }

    function testFuzzReassignAndClaimWithFee(uint256 amount) public {
        Distribution d = _deployDistWithNonZeroFee();
        uint256 grossA = (SUPPLY_A * PRICE_PER_TOKEN) / 1e18; // 120e6
        uint256 grossB = (SUPPLY_B * PRICE_PER_TOKEN) / 1e18; // 60e6
        uint256 grossC = (SUPPLY_C * PRICE_PER_TOKEN) / 1e18; // 20e6

        amount = bound(amount, 1, grossA); // can reassign up to full gross allocation

        vm.warp(lockedUntil);
        vm.prank(OWNER);
        d.reassign(HOLDER_A, HOLDER_B, amount);

        uint256 grossANew = grossA - amount;
        uint256 grossBNew = grossB + amount;
        // eligible() returns net after 1% fee
        assertEq(d.eligible(HOLDER_A), grossANew - grossANew / 100, "HOLDER_A eligible wrong after reassign");
        assertEq(d.eligible(HOLDER_B), grossBNew - grossBNew / 100, "HOLDER_B eligible wrong after reassign");
        assertEq(d.eligible(HOLDER_C), grossC - grossC / 100, "HOLDER_C eligible unchanged after reassign");

        // Store expected balances (net = gross - fee) before claims consume eligible
        uint256 expectedBalanceA = grossANew - grossANew / 100;
        uint256 expectedBalanceB = grossBNew - grossBNew / 100;
        uint256 expectedBalanceC = grossC - grossC / 100;

        if (grossANew > 0) {
            vm.prank(HOLDER_A);
            d.claim(HOLDER_A, 0);
        }
        vm.prank(HOLDER_B);
        d.claim(HOLDER_B, 0);
        vm.prank(HOLDER_C);
        d.claim(HOLDER_C, 0);

        // Each holder receives net (gross - fee)
        if (grossANew > 0) {
            assertEq(currency.balanceOf(HOLDER_A), expectedBalanceA, "HOLDER_A balance wrong");
        }
        assertEq(currency.balanceOf(HOLDER_B), expectedBalanceB, "HOLDER_B balance wrong");
        assertEq(currency.balanceOf(HOLDER_C), expectedBalanceC, "HOLDER_C balance wrong");
    }

    // ========== D_Reentrancy. Reentrancy protection ==========

    /// @dev Deploy a distribution whose currency is a MaliciousDistributionCurrency.
    function _deployDistWithMaliciousCurrency(
        MaliciousDistributionCurrency maliciousCurrency,
        uint256 funding
    ) internal returns (Distribution) {
        vm.prank(ADMIN);
        allowList.set(address(maliciousCurrency), TRUSTED_CURRENCY);

        DistributionInitializerArguments memory args = DistributionInitializerArguments({
            owner: OWNER,
            token: token,
            snapshotId: snapshotId,
            currency: IERC20(address(maliciousCurrency)),
            pricePerToken: PRICE_PER_TOKEN,
            lockedUntil: lockedUntil,
            initialReassignments: new Reassignment[](0)
        });
        address cloneAddr = factory.predictCloneAddress(bytes32(0), TRUSTED_FORWARDER, args);
        maliciousCurrency.mint(CURRENCY_PROVIDER, funding);
        vm.prank(CURRENCY_PROVIDER);
        maliciousCurrency.approve(cloneAddr, funding);
        return
            Distribution(
                factory.createDistributionClone(bytes32(0), TRUSTED_FORWARDER, CURRENCY_PROVIDER, args, funding)
            );
    }

    /// claim() reverts when the currency reenters claim() during the payout transfer
    function testReentrancyOnClaim() public {
        MaliciousDistributionCurrency maliciousCurrency = new MaliciousDistributionCurrency();
        Distribution distribution = _deployDistWithMaliciousCurrency(maliciousCurrency, TOTAL_CURRENCY);
        maliciousCurrency.setExploitTarget(address(distribution), RECIPIENT);

        vm.prank(HOLDER_A);
        vm.expectRevert("ReentrancyGuard: reentrant call");
        distribution.claim(RECIPIENT, 0);
    }

    /// drain() reverts when the currency reenters claim() during the drain transfer
    function testReentrancyOnDrain() public {
        MaliciousDistributionCurrency maliciousCurrency = new MaliciousDistributionCurrency();
        Distribution distribution = _deployDistWithMaliciousCurrency(maliciousCurrency, TOTAL_CURRENCY);
        maliciousCurrency.setExploitTarget(address(distribution), RECIPIENT);

        vm.warp(lockedUntil);
        vm.prank(OWNER);
        vm.expectRevert("ReentrancyGuard: reentrant call");
        distribution.drain(OWNER, IERC20(address(maliciousCurrency)));
    }

    function testInitializeWithInitialReassignments() public {
        // HOLDER_A reassigns part of their currency-denominated share to RECIPIENT at init time
        // grossEligible(HOLDER_A) = SUPPLY_A * PRICE_PER_TOKEN / 1e18 = 600e18 * 200_000 / 1e18 = 120e6
        uint256 reassignAmount = 10e6; // 10 USDC — well within HOLDER_A's eligible share

        Reassignment[] memory reassignments = new Reassignment[](1);
        reassignments[0] = Reassignment({from: HOLDER_A, to: RECIPIENT, amount: reassignAmount});

        DistributionInitializerArguments memory args = DistributionInitializerArguments({
            owner: OWNER,
            token: token,
            snapshotId: snapshotId,
            currency: IERC20(address(currency)),
            pricePerToken: PRICE_PER_TOKEN,
            lockedUntil: lockedUntil,
            initialReassignments: reassignments
        });

        address cloneAddr = factory.predictCloneAddress(bytes32("reassign"), TRUSTED_FORWARDER, args);
        currency.mint(CURRENCY_PROVIDER, TOTAL_CURRENCY);
        vm.prank(CURRENCY_PROVIDER);
        currency.approve(cloneAddr, TOTAL_CURRENCY);

        Distribution distWithReassignment = Distribution(
            factory.createDistributionClone(
                bytes32("reassign"),
                TRUSTED_FORWARDER,
                CURRENCY_PROVIDER,
                args,
                TOTAL_CURRENCY
            )
        );

        // RECIPIENT can now claim the reassigned currency amount directly
        uint256 expectedRecipientCurrency = reassignAmount;
        vm.warp(lockedUntil);
        vm.prank(RECIPIENT);
        distWithReassignment.claim(RECIPIENT, 0);

        assertEq(currency.balanceOf(RECIPIENT), expectedRecipientCurrency, "RECIPIENT got wrong currency amount");

        // ensure recipient cannot claim from original dist without reassignment
        vm.prank(RECIPIENT);
        vm.expectRevert(NothingToClaim.selector);
        dist.claim(RECIPIENT, 0);

        assertEq(currency.balanceOf(RECIPIENT), expectedRecipientCurrency, "RECIPIENT balance changed");
    }
}
