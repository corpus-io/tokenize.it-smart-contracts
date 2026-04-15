// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.23;

import "../lib/forge-std/src/Test.sol";
import "../contracts/factories/TokenProxyFactory.sol";
import "../contracts/factories/DistributionCloneFactory.sol";
import "../contracts/Distribution.sol";
import "./resources/FakePaymentToken.sol";
import "./resources/CloneCreators.sol";
import "./resources/MaliciousDistributionCurrency.sol";

contract DistributionTest is Test {
    address public constant admin = 0x0109709eCFa91a80626FF3989D68f67f5b1dD120;
    address public constant owner = 0x1109709ecFA91a80626ff3989D68f67F5B1Dd121;
    address public constant holderA = 0x2109709EcFa91a80626Ff3989d68F67F5B1Dd122;
    address public constant holderB = 0x3109709ECfA91A80626fF3989D68f67F5B1Dd123;
    address public constant holderC = 0x4109709eCFa91A80626ff3989d68F67f5b1DD124;
    address public constant recipient = 0x5109709EcFA91a80626ff3989d68f67F5B1dD125;
    address public constant currencyProvider = 0x6109709EcFA91A80626FF3989d68f67F5b1dd126;
    address public constant feeCollector = 0x7109709eCfa91A80626Ff3989D68f67f5b1dD127;
    address public constant trustedForwarder = 0x9109709EcFA91A80626FF3989D68f67F5B1dD129;

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

        allowList = createAllowList(trustedForwarder, admin);
        currency = new FakePaymentToken(0, CURRENCY_DECIMALS);
        vm.prank(admin);
        allowList.set(address(currency), TRUSTED_CURRENCY);

        address tokenLogic = address(new Token(trustedForwarder));
        tokenFactory = new TokenProxyFactory(tokenLogic);
        IFeeSettingsV2 feeSettings = createFeeSettings(
            trustedForwarder,
            admin,
            buildFeeTypes(0, 0, 0, admin, admin, admin)
        );
        token = Token(
            tokenFactory.createTokenProxy(0, trustedForwarder, feeSettings, admin, allowList, 0, "DistToken", "DST")
        );

        vm.startPrank(admin);
        token.grantRole(token.MINTALLOWER_ROLE(), admin);
        token.mint(holderA, SUPPLY_A);
        token.mint(holderB, SUPPLY_B);
        token.mint(holderC, SUPPLY_C);
        vm.stopPrank();

        vm.prank(admin);
        snapshotId = token.createSnapshot();

        distLogic = new Distribution(trustedForwarder);
        factory = new DistributionCloneFactory(address(distLogic));
        dist = _deployDist(bytes32(0), TOTAL_CURRENCY, lockedUntil);
    }

    /// @dev Helper: predict address, fund, and deploy a Distribution clone
    function _deployDist(bytes32 salt, uint256 initialFunding, uint64 _lockedUntil) internal returns (Distribution) {
        DistributionInitializerArguments memory args = DistributionInitializerArguments({
            owner: owner,
            token: token,
            snapshotId: snapshotId,
            currency: IERC20(address(currency)),
            pricePerToken: PRICE_PER_TOKEN,
            lockedUntil: _lockedUntil,
            initialReassignments: new Reassignment[](0)
        });
        address cloneAddr = factory.predictCloneAddress(salt, trustedForwarder, args);
        if (initialFunding > 0) {
            currency.mint(currencyProvider, initialFunding);
            vm.prank(currencyProvider);
            currency.approve(cloneAddr, initialFunding);
        }
        return
            Distribution(
                factory.createDistributionClone(salt, trustedForwarder, currencyProvider, args, initialFunding)
            );
    }

    // ========== D1. Constructor / Logic Contract ==========

    function testLogicContractInitializeReverts() public {
        DistributionInitializerArguments memory args = DistributionInitializerArguments({
            owner: owner,
            token: token,
            snapshotId: snapshotId,
            currency: IERC20(address(currency)),
            pricePerToken: PRICE_PER_TOKEN,
            lockedUntil: lockedUntil,
            initialReassignments: new Reassignment[](0)
        });
        vm.expectRevert("Initializable: contract is already initialized");
        distLogic.initialize(args, currencyProvider, 0);
    }

    function testSecondInitializeReverts() public {
        DistributionInitializerArguments memory args = DistributionInitializerArguments({
            owner: owner,
            token: token,
            snapshotId: snapshotId,
            currency: IERC20(address(currency)),
            pricePerToken: PRICE_PER_TOKEN,
            lockedUntil: lockedUntil,
            initialReassignments: new Reassignment[](0)
        });
        vm.expectRevert("Initializable: contract is already initialized");
        dist.initialize(args, currencyProvider, 0);
    }

    // ========== D2. initialize() — Validation & State ==========

    function testInitializeNonTrustedCurrencyReverts() public {
        FakePaymentToken badCurrency = new FakePaymentToken(0, 6);
        DistributionInitializerArguments memory args = DistributionInitializerArguments({
            owner: owner,
            token: token,
            snapshotId: snapshotId,
            currency: IERC20(address(badCurrency)),
            pricePerToken: PRICE_PER_TOKEN,
            lockedUntil: lockedUntil,
            initialReassignments: new Reassignment[](0)
        });
        vm.expectRevert("currency needs to be on the allowlist with TRUSTED_CURRENCY attribute");
        factory.createDistributionClone(bytes32(0), trustedForwarder, currencyProvider, args, 0);
    }

    function testInitializeInsufficientAllowanceReverts() public {
        DistributionInitializerArguments memory args = DistributionInitializerArguments({
            owner: owner,
            token: token,
            snapshotId: snapshotId,
            currency: IERC20(address(currency)),
            pricePerToken: PRICE_PER_TOKEN,
            lockedUntil: lockedUntil,
            initialReassignments: new Reassignment[](0)
        });
        address cloneAddr = factory.predictCloneAddress(bytes32("2"), trustedForwarder, args);
        currency.mint(currencyProvider, 500e6);
        vm.prank(currencyProvider);
        currency.approve(cloneAddr, 499e6); // one short
        vm.expectRevert("ERC20: insufficient allowance");
        factory.createDistributionClone(bytes32("2"), trustedForwarder, currencyProvider, args, 500e6);
    }

    function testInitializeZeroPriceReverts() public {
        DistributionInitializerArguments memory args = DistributionInitializerArguments({
            owner: owner,
            token: token,
            snapshotId: snapshotId,
            currency: IERC20(address(currency)),
            pricePerToken: 0,
            lockedUntil: lockedUntil,
            initialReassignments: new Reassignment[](0)
        });
        vm.expectRevert("price must be positive");
        factory.createDistributionClone(bytes32(0), trustedForwarder, currencyProvider, args, 0);
    }

    function testInitializeStateVariables() public view {
        assertEq(address(dist.token()), address(token), "unexpected token address");
        assertEq(dist.snapshotId(), snapshotId, "unexpected snapshotId");
        assertEq(address(dist.currency()), address(currency), "unexpected currency address");
        assertEq(dist.pricePerToken(), PRICE_PER_TOKEN, "unexpected pricePerToken");
        assertEq(dist.lockedUntil(), lockedUntil, "unexpected lockedUntil");
        assertEq(dist.owner(), owner, "unexpected owner");
        assertEq(currency.balanceOf(address(dist)), TOTAL_CURRENCY, "dist not fully funded");
    }

    function testInitializeZeroTotalSupplyReverts() public {
        // Take a snapshot before any tokens are minted on a fresh token
        IFeeSettingsV2 feeSettings = createFeeSettings(
            trustedForwarder,
            admin,
            buildFeeTypes(0, 0, 0, admin, admin, admin)
        );
        Token emptyToken = Token(
            tokenFactory.createTokenProxy(
                bytes32(0),
                trustedForwarder,
                feeSettings,
                admin,
                allowList,
                0,
                "EmptyToken",
                "EMP"
            )
        );
        vm.prank(admin);
        uint256 emptySnap = emptyToken.createSnapshot(); // total supply = 0

        DistributionInitializerArguments memory args = DistributionInitializerArguments({
            owner: owner,
            token: emptyToken,
            snapshotId: emptySnap,
            currency: IERC20(address(currency)),
            pricePerToken: PRICE_PER_TOKEN,
            lockedUntil: lockedUntil,
            initialReassignments: new Reassignment[](0)
        });
        vm.expectRevert("snapshot has no tokens");
        factory.createDistributionClone(bytes32(0), trustedForwarder, currencyProvider, args, 0);
    }

    function testInitializeWithZeroFunding() public {
        Distribution unfunded = _deployDist(bytes32("1"), 0, lockedUntil);
        assertEq(currency.balanceOf(address(unfunded)), 0, "unfunded dist should have zero balance");
        assertEq(unfunded.pricePerToken(), PRICE_PER_TOKEN, "pricePerToken should be set even without funding");
        // eligible is based on price, not balance
        assertEq(unfunded.eligible(holderA), 120e6, "holderA eligible should be based on price");
    }

    // ========== D3. eligible() — Math ==========

    function testEligibleConcreteExample() public view {
        // A: 600e18 * 200_000 / 1e18 = 120e6
        assertEq(dist.eligible(holderA), 120e6, "holderA eligible amount wrong");
        // B: 300e18 * 200_000 / 1e18 = 60e6
        assertEq(dist.eligible(holderB), 60e6, "holderB eligible amount wrong");
        // C: 100e18 * 200_000 / 1e18 = 20e6
        assertEq(dist.eligible(holderC), 20e6, "holderC eligible amount wrong");
    }

    function testEligibleZeroBalanceIsZero() public view {
        assertEq(dist.eligible(address(42)), 0, "holder with zero balance should have zero eligible");
    }

    function testEligibleSumEqTotalCurrencyLimitedDust() public view {
        uint256 sumEligible = dist.eligible(holderA) + dist.eligible(holderB) + dist.eligible(holderC);
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
            trustedForwarder,
            admin,
            buildFeeTypes(0, 0, 0, admin, admin, admin)
        );
        Token fuzzToken = Token(
            tokenFactory.createTokenProxy(
                bytes32(0),
                trustedForwarder,
                feeSettings,
                admin,
                allowList,
                0,
                "FuzzToken",
                "FZT"
            )
        );
        vm.startPrank(admin);
        fuzzToken.grantRole(fuzzToken.MINTALLOWER_ROLE(), admin);
        if (balA > 0) fuzzToken.mint(holderA, balA);
        if (balB > 0) fuzzToken.mint(holderB, balB);
        fuzzToken.mint(holderC, balC);
        vm.stopPrank();
        vm.prank(admin);
        uint256 snap = fuzzToken.createSnapshot();

        uint256 totalSupply = uint256(balA) + uint256(balB) + balC;
        uint256 maxPayout = (totalSupply * uint256(pricePerTokenFuzz)) / (10 ** fuzzToken.decimals());

        DistributionInitializerArguments memory args = DistributionInitializerArguments({
            owner: owner,
            token: fuzzToken,
            snapshotId: snap,
            currency: IERC20(address(currency)),
            pricePerToken: pricePerTokenFuzz,
            lockedUntil: lockedUntil,
            initialReassignments: new Reassignment[](0)
        });
        Distribution fuzzDistribution = Distribution(
            factory.createDistributionClone(bytes32(0), trustedForwarder, currencyProvider, args, 0)
        );

        uint256 sumE = fuzzDistribution.eligible(holderA) +
            fuzzDistribution.eligible(holderB) +
            fuzzDistribution.eligible(holderC);
        assertLe(sumE, maxPayout, "sum of eligible exceeds max payout");
        // Each eligible() truncates balance * pricePerToken / 10^decimals, losing up to (10^decimals - 1) per holder
        uint256 maxDust = 3 * (10 ** fuzzToken.decimals());
        assertGe(sumE + maxDust, maxPayout, "dust exceeds bound");
    }

    // ========== D4. claim(address) — Direct Claim ==========

    function testClaimCorrectAmount() public {
        assertEq(currency.balanceOf(recipient), 0, "recipient already holds currency");
        vm.prank(holderA);
        dist.claim(recipient, 0);
        assertEq(currency.balanceOf(recipient), 120e6, "recipient did not receive holderA's share");
    }

    function testClaimZeroEligibleReverts() public {
        vm.expectRevert("nothing to claim");
        dist.claim(recipient, 0); // address(this) has 0 snapshot balance
    }

    function testClaimUpdatesPayedOut() public {
        vm.prank(holderA);
        dist.claim(holderA, 0);
        assertEq(dist.eligible(holderA), 0, "eligible should be zero after claim");
        assertEq(dist.paidOut(holderA), 120e6, "paidOut not updated after claim");
    }

    function testSecondClaimReverts() public {
        vm.prank(holderA);
        dist.claim(holderA, 0);
        vm.prank(holderA);
        vm.expectRevert("nothing to claim");
        dist.claim(holderA, 0);
    }

    function testClaimRecipientDiffersFromSender() public {
        vm.prank(holderA);
        dist.claim(recipient, 0);
        assertEq(currency.balanceOf(holderA), 0, "sender should not receive currency when recipient differs");
        assertEq(currency.balanceOf(recipient), 120e6, "recipient did not receive holderA's share");
    }

    function testMultipleHoldersClaimIndependently() public {
        vm.prank(holderA);
        dist.claim(holderA, 0);
        vm.prank(holderB);
        dist.claim(holderB, 0);
        vm.prank(holderC);
        dist.claim(holderC, 0);
        assertEq(currency.balanceOf(holderA), 120e6, "holderA received wrong amount");
        assertEq(currency.balanceOf(holderB), 60e6, "holderB received wrong amount");
        assertEq(currency.balanceOf(holderC), 20e6, "holderC received wrong amount");
    }

    function testERC2771ClaimIdentifiesHolder() public {
        uint256 expected = 120e6;
        bytes memory callData = abi.encodePacked(
            abi.encodeWithSelector(bytes4(keccak256("claim(address,uint256)")), recipient, uint256(0)),
            holderA
        );
        vm.prank(trustedForwarder);
        (bool success, ) = address(dist).call(callData);
        assertTrue(success, "ERC2771 claim call failed");
        assertEq(currency.balanceOf(recipient), expected, "recipient did not receive holderA's share via ERC2771");
    }

    /// @dev Helper to deploy a Distribution against a specific snapshot
    function _deployDistWithSnapshot(
        bytes32 salt,
        uint256 snap,
        uint256 initialFunding
    ) internal returns (Distribution) {
        DistributionInitializerArguments memory args = DistributionInitializerArguments({
            owner: owner,
            token: token,
            snapshotId: snap,
            currency: IERC20(address(currency)),
            pricePerToken: PRICE_PER_TOKEN,
            lockedUntil: lockedUntil,
            initialReassignments: new Reassignment[](0)
        });
        address cloneAddr = factory.predictCloneAddress(salt, trustedForwarder, args);
        if (initialFunding > 0) {
            currency.mint(currencyProvider, initialFunding);
            vm.prank(currencyProvider);
            currency.approve(cloneAddr, initialFunding);
        }
        return
            Distribution(
                factory.createDistributionClone(salt, trustedForwarder, currencyProvider, args, initialFunding)
            );
    }

    // ========== D5. drain() ==========

    function testDrainNonOwnerReverts() public {
        vm.warp(lockedUntil);
        vm.expectRevert("Ownable: caller is not the owner");
        vm.prank(holderA);
        dist.drain(holderA, currency);
    }

    function testDrainBeforeDeadlineReverts() public {
        vm.expectRevert("drain not yet available");
        vm.prank(owner);
        dist.drain(owner, currency);
    }

    function testDrainAtExactDeadlineSucceeds() public {
        vm.warp(lockedUntil);
        vm.prank(owner);
        dist.drain(owner, currency);
        assertEq(currency.balanceOf(owner), TOTAL_CURRENCY, "owner should receive full balance after drain");
        assertEq(currency.balanceOf(address(dist)), 0, "dist should be empty after drain");
    }

    function testDrainAfterPartialClaims() public {
        vm.prank(holderA);
        dist.claim(holderA, 0);
        uint256 remaining = currency.balanceOf(address(dist));
        assertEq(remaining, TOTAL_CURRENCY - 120e6, "remaining balance wrong after holderA claim");

        vm.warp(lockedUntil);
        vm.prank(owner);
        dist.drain(owner, currency);
        assertEq(currency.balanceOf(owner), remaining, "owner should receive remaining balance after drain");
        assertEq(currency.balanceOf(address(dist)), 0, "dist should be empty after drain");
    }

    function testFuzzDrainTiming(uint64 warpTo) public {
        vm.assume(warpTo >= block.timestamp);
        vm.warp(warpTo);
        if (warpTo < lockedUntil) {
            vm.expectRevert("drain not yet available");
            vm.prank(owner);
            dist.drain(owner, currency);
        } else {
            vm.prank(owner);
            dist.drain(owner, currency);
            assertEq(currency.balanceOf(address(dist)), 0, "dist should be empty after drain");
        }
    }

    // ========== D7. reassign() ==========

    function testReassignNonOwnerReverts() public {
        vm.warp(lockedUntil);
        uint256 amount = dist.eligible(holderA);
        vm.expectRevert("Ownable: caller is not the owner");
        vm.prank(holderA);
        dist.reassign(holderA, holderB, amount);
    }

    function testReassignBeforeDeadlineReverts() public {
        uint256 amount = dist.eligible(holderA);
        vm.expectRevert("reassignment not yet available");
        vm.prank(owner);
        dist.reassign(holderA, holderB, amount);
    }

    function testReassignAtExactDeadlineSucceeds() public {
        vm.warp(lockedUntil);
        uint256 amount = dist.eligible(holderA);
        vm.prank(owner);
        dist.reassign(holderA, holderB, amount);
    }

    function testFuzzReassignDeadline(uint64 warpTo) public {
        vm.assume(warpTo >= block.timestamp); // avoid warping to the past
        uint256 amount = dist.eligible(holderA);
        vm.warp(warpTo);
        assertEq(dist.eligible(holderA), amount, "holderA eligible should be non-zero before reassign");
        assertEq(dist.eligible(holderB), 60e6, "holderB eligible should be own share before reassign");
        if (warpTo < lockedUntil) {
            vm.expectRevert("reassignment not yet available");
            vm.prank(owner);
            dist.reassign(holderA, holderB, amount);
            assertEq(dist.eligible(holderA), amount, "holderA eligible should be non-zero after revert");
            assertEq(dist.eligible(holderB), 60e6, "holderB eligible should be own share after revert");
        } else {
            vm.prank(owner);
            dist.reassign(holderA, holderB, amount);
            assertEq(dist.eligible(holderA), 0, "holderA eligible should be zero after reassign");
            assertEq(dist.eligible(holderB), 60e6 + amount, "holderB eligible should include reassigned amount");
        }
    }

    function testReassignToZeroAddressReverts() public {
        vm.warp(lockedUntil);
        uint256 amount = dist.eligible(holderA);
        vm.expectRevert("to can not be zero address");
        vm.prank(owner);
        dist.reassign(holderA, address(0), amount);
    }

    function testReassignZeroAmountReverts() public {
        vm.warp(lockedUntil);
        vm.expectRevert("amount must be positive");
        vm.prank(owner);
        dist.reassign(holderA, holderB, 0);
    }

    function testReassignExceedsEligibleReverts() public {
        vm.warp(lockedUntil);
        vm.expectRevert("amount exceeds eligible");
        vm.prank(owner);
        dist.reassign(address(42), holderB, 1); // address(42) has no balance
    }

    function testReassignEffect() public {
        vm.warp(lockedUntil);
        assertEq(dist.eligible(holderA), 120e6, "holderA eligible should be 120e6 before reassign");
        assertEq(dist.eligible(holderB), 60e6, "holderB eligible should be 60e6 before reassign");
        uint256 amountA = dist.eligible(holderA);
        vm.prank(owner);
        dist.reassign(holderA, holderB, amountA);

        assertEq(dist.eligible(holderA), 0, "holderA eligible should be zero after full reassign");
        assertEq(dist.paidOut(holderA), 120e6, "holderA paidOut not updated after reassign");
        // holderB gets own share + reassigned
        assertEq(dist.eligible(holderB), 60e6 + 120e6, "holderB eligible should include reassigned amount");
    }

    function testReassignEmitsEvent() public {
        vm.warp(lockedUntil);
        vm.expectEmit(true, true, false, true, address(dist));
        emit Distribution.Reassigned(holderA, holderB, 120e6);
        vm.prank(owner);
        dist.reassign(holderA, holderB, 120e6);
    }

    function testReassignStackingMultipleToSameRecipient() public {
        vm.warp(lockedUntil);
        uint256 amountB = dist.eligible(holderB);
        vm.prank(owner);
        dist.reassign(holderB, holderA, amountB); // A gets B's 60e6
        uint256 amountC = dist.eligible(holderC);
        vm.prank(owner);
        dist.reassign(holderC, holderA, amountC); // A gets C's 20e6

        assertEq(dist.eligible(holderA), 120e6 + 60e6 + 20e6, "holderA eligible should include all reassigned amounts");
        assertEq(dist.eligible(holderB), 0, "holderB eligible should be zero after full reassign");
        assertEq(dist.eligible(holderC), 0, "holderC eligible should be zero after full reassign");

        vm.prank(holderA);
        dist.claim(holderA, 0);
        assertEq(
            currency.balanceOf(holderA),
            200e6,
            "holderA should receive full distribution after stacked reassigns"
        );
    }

    function testReassignSelfIsNoOp() public {
        vm.warp(lockedUntil);
        uint256 eligibleBefore = dist.eligible(holderA);
        vm.prank(owner);
        dist.reassign(holderA, holderA, eligibleBefore); // self-reassign
        assertEq(dist.eligible(holderA), eligibleBefore, "self-reassign should leave eligible unchanged"); // unchanged
    }

    function testReassignAfterClaimReverts() public {
        vm.prank(holderA);
        dist.claim(holderA, 0); // eligible drops to 0
        vm.warp(lockedUntil);
        vm.expectRevert("amount exceeds eligible");
        vm.prank(owner);
        dist.reassign(holderA, holderB, 1);
    }

    function testSecondReassignFromSameAddressReverts() public {
        vm.warp(lockedUntil);
        uint256 amountA = dist.eligible(holderA);
        vm.prank(owner);
        dist.reassign(holderA, holderB, amountA);
        vm.expectRevert("amount exceeds eligible");
        vm.prank(owner);
        dist.reassign(holderA, holderC, 1); // eligible = 0 after first reassign
    }

    function testPartialReassign() public {
        vm.warp(lockedUntil);
        uint256 aliceEligible = dist.eligible(holderA); // 120e6

        vm.prank(owner);
        dist.reassign(holderA, holderB, aliceEligible / 2); // 60e6 to B
        assertEq(dist.eligible(holderA), aliceEligible / 2, "holderA eligible should be halved after partial reassign");
        assertEq(dist.eligible(holderB), 60e6 + aliceEligible / 2, "holderB eligible should include reassigned half");

        uint256 aliceRemaining = dist.eligible(holderA);
        vm.prank(owner);
        dist.reassign(holderA, holderC, aliceRemaining); // remaining 60e6 to C
        assertEq(dist.eligible(holderA), 0, "holderA eligible should be zero after second partial reassign");
        assertEq(
            dist.eligible(holderC),
            20e6 + aliceEligible / 2,
            "holderC eligible should include reassigned remainder"
        );
    }

    function testChainedReassignAToB() public {
        // A → B → C (B has no snapshot balance)
        Distribution chainDist = _deployDist(bytes32("1"), TOTAL_CURRENCY, lockedUntil);

        // initial state
        assertEq(chainDist.eligible(holderA), 120e6, "holderA initial eligible");
        assertEq(chainDist.eligible(holderB), 60e6, "holderB initial eligible");
        assertEq(chainDist.eligible(holderC), 20e6, "holderC initial eligible");

        vm.warp(lockedUntil);
        uint256 amountA = chainDist.eligible(holderA);
        vm.prank(owner);
        chainDist.reassign(holderA, holderB, amountA); // B now has 120+60=180e6

        // after A → B
        assertEq(chainDist.eligible(holderA), 0, "holderA eligible should be zero after first reassign");
        assertEq(chainDist.eligible(holderB), 180e6, "holderB eligible should be 180e6 after receiving A's share");
        assertEq(chainDist.eligible(holderC), 20e6, "holderC eligible should be unchanged after first reassign");

        uint256 amountB = chainDist.eligible(holderB);
        vm.prank(owner);
        chainDist.reassign(holderB, holderC, amountB); // C now has 20+180=200e6

        // after B → C
        assertEq(chainDist.eligible(holderA), 0, "holderA eligible should be zero after chained reassign");
        assertEq(chainDist.eligible(holderB), 0, "holderB eligible should be zero after chained reassign");
        assertEq(
            chainDist.eligible(holderC),
            TOTAL_CURRENCY,
            "holderC eligible should be full amount after chained reassign"
        );

        vm.prank(holderC);
        chainDist.claim(holderC, 0);
        assertEq(
            currency.balanceOf(holderC),
            TOTAL_CURRENCY,
            "holderC should receive full distribution after chained reassign"
        );
    }

    function testChainedReassignSumOfEligibleInvariant() public {
        // After each reassign, sum of all eligible must remain constant
        uint256 sumBefore = dist.eligible(holderA) + dist.eligible(holderB) + dist.eligible(holderC);

        vm.warp(lockedUntil);
        uint256 amountA = dist.eligible(holderA);
        vm.prank(owner);
        dist.reassign(holderA, holderB, amountA);

        uint256 sumAfter = dist.eligible(holderA) + dist.eligible(holderB) + dist.eligible(holderC);
        assertEq(sumBefore, sumAfter, "sum of eligible should be unchanged after reassign");
    }

    // ========== D8. Interaction: claim then reassign ==========

    function testClaimThenReassignReverts() public {
        vm.prank(holderA);
        dist.claim(holderA, 0); // eligible(A) = 0
        vm.warp(lockedUntil);
        vm.expectRevert("amount exceeds eligible");
        vm.prank(owner);
        dist.reassign(holderA, holderB, 1);
    }

    // ========== D9. Interaction: reassign then claim by recipient ==========

    function testReassignThenClaimByRecipient() public {
        vm.warp(lockedUntil);
        uint256 amountA = dist.eligible(holderA);
        vm.prank(owner);
        dist.reassign(holderA, holderB, amountA); // B gets 60 + 120 = 180e6

        vm.prank(holderB);
        dist.claim(holderB, 0);
        assertEq(currency.balanceOf(holderB), 180e6, "holderB should receive own share plus reassigned amount");

        // A's paidOut covers their share: A claims 0
        vm.prank(holderA);
        vm.expectRevert("nothing to claim");
        dist.claim(holderA, 0);
        assertEq(currency.balanceOf(holderA), 0, "holderA should receive nothing after full reassign");

        // total paid out ≤ funded amount
        assertLe(
            currency.balanceOf(holderB) + currency.balanceOf(holderA),
            TOTAL_CURRENCY,
            "total paid out exceeds funded amount"
        );
    }

    // ========== D10. Fuzz / Property-Based Tests ==========

    function testFuzzClaimNoDoublePay(uint8 claimOrder) public {
        // Any order of A, B, C claiming → sum of payouts ≤ funded amount
        address[3] memory holders = [holderA, holderB, holderC];
        // claimOrder low bits determine which subset claims
        for (uint256 i = 0; i < 3; i++) {
            if ((claimOrder >> i) & 1 == 1) {
                vm.prank(holders[i]);
                dist.claim(holders[i], 0);
            }
        }
        uint256 totalPaid = currency.balanceOf(holderA) + currency.balanceOf(holderB) + currency.balanceOf(holderC);
        assertLe(totalPaid, TOTAL_CURRENCY, "total paid out exceeds funded amount");
    }

    function testFuzzReassignSumInvariant(address reassignTo) public {
        vm.assume(reassignTo != address(0));
        vm.assume(reassignTo != holderA);
        vm.assume(reassignTo != holderB);
        vm.assume(reassignTo != holderC);
        uint256 sumBefore = dist.eligible(holderA) +
            dist.eligible(holderB) +
            dist.eligible(holderC) +
            dist.eligible(reassignTo);

        vm.warp(lockedUntil);
        uint256 amountA = dist.eligible(holderA);
        vm.prank(owner);
        dist.reassign(holderA, reassignTo, amountA);

        uint256 sumAfter = dist.eligible(holderA) +
            dist.eligible(holderB) +
            dist.eligible(holderC) +
            dist.eligible(reassignTo);
        assertEq(sumBefore, sumAfter, "sum of eligible should be unchanged after reassign");
    }

    // ========== D11. Underfunding ==========

    function testClaimRevertsWhenUnderfunded() public {
        Distribution unfunded = _deployDist(bytes32("1"), 0, lockedUntil);
        // holderA is eligible for 120e6 but contract has 0 balance
        vm.prank(holderA);
        vm.expectRevert("ERC20: transfer amount exceeds balance");
        unfunded.claim(holderA, 0);
    }

    function testClaimSucceedsAfterLaterFunding() public {
        Distribution unfunded = _deployDist(bytes32("1"), 0, lockedUntil);
        // Fund later
        currency.mint(address(unfunded), TOTAL_CURRENCY);
        vm.prank(holderA);
        unfunded.claim(holderA, 0);
        assertEq(currency.balanceOf(holderA), 120e6, "holderA should receive share after late funding");
    }

    function testPartialFundingAllowsSomeClaims() public {
        // Fund only enough for holderC (20e6)
        Distribution partialDist = _deployDist(bytes32("1"), 20e6, lockedUntil);
        vm.prank(holderC);
        partialDist.claim(holderC, 0);
        assertEq(currency.balanceOf(holderC), 20e6, "holderC should claim from partial funding");

        // holderA cannot claim (not enough balance)
        vm.prank(holderA);
        vm.expectRevert("ERC20: transfer amount exceeds balance");
        partialDist.claim(holderA, 0);
    }

    // ========== D_Fee. Fee Collection at Claim Time ==========

    /// @dev Deploy a Distribution backed by a token with 1% private offer fee.
    function _deployDistWithNonZeroFee() internal returns (Distribution d) {
        IFeeSettingsV2 feeSettingsWithFee = createFeeSettings(
            trustedForwarder,
            admin,
            buildFeeTypes(0, 0, 100, admin, admin, feeCollector)
        );
        Token feeToken = Token(
            tokenFactory.createTokenProxy(
                bytes32(0),
                trustedForwarder,
                feeSettingsWithFee,
                admin,
                allowList,
                0,
                "FeeToken",
                "FTK"
            )
        );
        vm.startPrank(admin);
        feeToken.grantRole(feeToken.MINTALLOWER_ROLE(), admin);
        feeToken.mint(holderA, SUPPLY_A);
        feeToken.mint(holderB, SUPPLY_B);
        feeToken.mint(holderC, SUPPLY_C);
        vm.stopPrank();
        vm.prank(admin);
        uint256 snap = feeToken.createSnapshot();

        DistributionInitializerArguments memory args = DistributionInitializerArguments({
            owner: owner,
            token: feeToken,
            snapshotId: snap,
            currency: IERC20(address(currency)),
            pricePerToken: PRICE_PER_TOKEN,
            lockedUntil: lockedUntil,
            initialReassignments: new Reassignment[](0)
        });
        address cloneAddr = factory.predictCloneAddress(bytes32(0), trustedForwarder, args);
        currency.mint(currencyProvider, TOTAL_CURRENCY);
        vm.prank(currencyProvider);
        currency.approve(cloneAddr, TOTAL_CURRENCY);
        d = Distribution(
            factory.createDistributionClone(bytes32(0), trustedForwarder, currencyProvider, args, TOTAL_CURRENCY)
        );
    }

    function testNoFeeAtInitialization() public {
        assertEq(currency.balanceOf(feeCollector), 0, "feeCollector should have no currency before deployment");
        _deployDistWithNonZeroFee();
        assertEq(currency.balanceOf(feeCollector), 0, "feeCollector should have no currency after deployment");
    }

    function testFeeDeductedAtClaimTime() public {
        Distribution d = _deployDistWithNonZeroFee();
        uint256 grossA = (SUPPLY_A * PRICE_PER_TOKEN) / 1e18; // 120e6
        uint256 expectedFee = grossA / 100; // 1% of gross
        uint256 expectedNet = grossA - expectedFee; // 118.8e6

        vm.prank(holderA);
        d.claim(holderA, 0);

        assertEq(currency.balanceOf(feeCollector), expectedFee, "feeCollector did not receive correct fee");
        assertEq(currency.balanceOf(holderA), expectedNet, "holderA did not receive net amount after fee");
    }

    function testFeeSentToFeeCollectorPerClaim() public {
        Distribution d = _deployDistWithNonZeroFee();

        vm.prank(holderA);
        d.claim(holderA, 0);
        uint256 feeAfterA = currency.balanceOf(feeCollector);
        assertGt(feeAfterA, 0, "feeCollector should have received fee from holderA claim");

        vm.prank(holderB);
        d.claim(holderB, 0);
        uint256 feeAfterB = currency.balanceOf(feeCollector);
        assertGt(feeAfterB, feeAfterA, "feeCollector should have received additional fee from holderB claim");
    }

    function testEligibleDeductsFee() public {
        Distribution d = _deployDistWithNonZeroFee();
        // eligible() deducts the 1% fee, returning net payout amount
        uint256 grossA = (SUPPLY_A * PRICE_PER_TOKEN) / 1e18; // 120e6
        uint256 grossB = (SUPPLY_B * PRICE_PER_TOKEN) / 1e18; // 60e6
        uint256 grossC = (SUPPLY_C * PRICE_PER_TOKEN) / 1e18; // 20e6
        assertEq(d.eligible(holderA), grossA - grossA / 100, "holderA eligible should be net after fee");
        assertEq(d.eligible(holderB), grossB - grossB / 100, "holderB eligible should be net after fee");
        assertEq(d.eligible(holderC), grossC - grossC / 100, "holderC eligible should be net after fee");
    }

    // ========== D_MinPayout. minPayout guard ==========

    /// minPayout == 0 always passes (no minimum)
    function testClaimMinPayoutZeroAlwaysPasses() public {
        vm.prank(holderA);
        dist.claim(holderA, 0);
        assertGt(currency.balanceOf(holderA), 0, "holderA should receive currency");
    }

    /// minPayout exactly equal to eligible (no fees) succeeds
    function testClaimMinPayoutExactEligibleSucceeds() public {
        uint256 expectedNet = dist.eligible(holderA); // 120e6
        vm.prank(holderA);
        dist.claim(holderA, expectedNet);
        assertEq(currency.balanceOf(holderA), expectedNet, "holderA should receive exactly eligible");
    }

    /// minPayout one above eligible reverts
    function testClaimMinPayoutAboveEligibleReverts() public {
        uint256 expectedNet = dist.eligible(holderA);
        vm.prank(holderA);
        vm.expectRevert("payout below minimum");
        dist.claim(holderA, expectedNet + 1);
    }

    /// With a fee, minPayout exactly equal to eligible() succeeds because eligible() already deducts the fee
    function testClaimMinPayoutEligibleWithFeeSucceeds() public {
        Distribution d = _deployDistWithNonZeroFee();
        uint256 expectedNet = d.eligible(holderA); // eligible() returns net after fee
        vm.prank(holderA);
        d.claim(holderA, expectedNet);
        assertEq(currency.balanceOf(holderA), expectedNet, "holderA should receive exactly eligible");
    }

    /// With a fee, minPayout above eligible() (i.e. the gross amount) reverts
    function testClaimMinPayoutAboveEligibleWithFeeReverts() public {
        Distribution d = _deployDistWithNonZeroFee();
        uint256 gross = (SUPPLY_A * PRICE_PER_TOKEN) / 1e18; // 120e6, before fee
        vm.prank(holderA);
        vm.expectRevert("payout below minimum");
        d.claim(holderA, gross); // gross > eligible() (net)
    }

    /// Fuzz: claim always succeeds when minPayout <= net, reverts when minPayout > net (no fees)
    function testFuzzClaimMinPayoutBoundary(uint256 minPayout) public {
        uint256 net = dist.eligible(holderA); // 120e6, no fee
        vm.prank(holderA);
        if (minPayout <= net) {
            dist.claim(holderA, minPayout);
            assertEq(currency.balanceOf(holderA), net, "holderA should receive eligible");
        } else {
            vm.expectRevert("payout below minimum");
            dist.claim(holderA, minPayout);
        }
    }

    function testFuzzReassignAndClaimWithFee(uint256 amount) public {
        Distribution d = _deployDistWithNonZeroFee();
        uint256 grossA = (SUPPLY_A * PRICE_PER_TOKEN) / 1e18; // 120e6
        uint256 grossB = (SUPPLY_B * PRICE_PER_TOKEN) / 1e18; // 60e6
        uint256 grossC = (SUPPLY_C * PRICE_PER_TOKEN) / 1e18; // 20e6

        amount = bound(amount, 1, grossA); // can reassign up to full gross allocation

        vm.warp(lockedUntil);
        vm.prank(owner);
        d.reassign(holderA, holderB, amount);

        uint256 grossANew = grossA - amount;
        uint256 grossBNew = grossB + amount;
        // eligible() returns net after 1% fee
        assertEq(d.eligible(holderA), grossANew - grossANew / 100, "holderA eligible wrong after reassign");
        assertEq(d.eligible(holderB), grossBNew - grossBNew / 100, "holderB eligible wrong after reassign");
        assertEq(d.eligible(holderC), grossC - grossC / 100, "holderC eligible unchanged after reassign");

        // Store expected balances (net = gross - fee) before claims consume eligible
        uint256 expectedBalanceA = grossANew - grossANew / 100;
        uint256 expectedBalanceB = grossBNew - grossBNew / 100;
        uint256 expectedBalanceC = grossC - grossC / 100;

        if (grossANew > 0) {
            vm.prank(holderA);
            d.claim(holderA, 0);
        }
        vm.prank(holderB);
        d.claim(holderB, 0);
        vm.prank(holderC);
        d.claim(holderC, 0);

        // Each holder receives net (gross - fee)
        if (grossANew > 0) {
            assertEq(currency.balanceOf(holderA), expectedBalanceA, "holderA balance wrong");
        }
        assertEq(currency.balanceOf(holderB), expectedBalanceB, "holderB balance wrong");
        assertEq(currency.balanceOf(holderC), expectedBalanceC, "holderC balance wrong");
    }

    // ========== D_Reentrancy. Reentrancy protection ==========

    /// @dev Deploy a distribution whose currency is a MaliciousDistributionCurrency.
    function _deployDistWithMaliciousCurrency(
        MaliciousDistributionCurrency maliciousCurrency,
        uint256 funding
    ) internal returns (Distribution) {
        vm.prank(admin);
        allowList.set(address(maliciousCurrency), TRUSTED_CURRENCY);

        DistributionInitializerArguments memory args = DistributionInitializerArguments({
            owner: owner,
            token: token,
            snapshotId: snapshotId,
            currency: IERC20(address(maliciousCurrency)),
            pricePerToken: PRICE_PER_TOKEN,
            lockedUntil: lockedUntil,
            initialReassignments: new Reassignment[](0)
        });
        address cloneAddr = factory.predictCloneAddress(bytes32(0), trustedForwarder, args);
        maliciousCurrency.mint(currencyProvider, funding);
        vm.prank(currencyProvider);
        maliciousCurrency.approve(cloneAddr, funding);
        return
            Distribution(
                factory.createDistributionClone(bytes32(0), trustedForwarder, currencyProvider, args, funding)
            );
    }

    /// claim() reverts when the currency reenters claim() during the payout transfer
    function testReentrancyOnClaim() public {
        MaliciousDistributionCurrency maliciousCurrency = new MaliciousDistributionCurrency();
        Distribution distribution = _deployDistWithMaliciousCurrency(maliciousCurrency, TOTAL_CURRENCY);
        maliciousCurrency.setExploitTarget(address(distribution), recipient);

        vm.prank(holderA);
        vm.expectRevert("ReentrancyGuard: reentrant call");
        distribution.claim(recipient, 0);
    }

    /// drain() reverts when the currency reenters claim() during the drain transfer
    function testReentrancyOnDrain() public {
        MaliciousDistributionCurrency maliciousCurrency = new MaliciousDistributionCurrency();
        Distribution distribution = _deployDistWithMaliciousCurrency(maliciousCurrency, TOTAL_CURRENCY);
        maliciousCurrency.setExploitTarget(address(distribution), recipient);

        vm.warp(lockedUntil);
        vm.prank(owner);
        vm.expectRevert("ReentrancyGuard: reentrant call");
        distribution.drain(owner, IERC20(address(maliciousCurrency)));
    }
}
