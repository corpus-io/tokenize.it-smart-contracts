// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.23;

import "../lib/forge-std/src/Test.sol";

import "../contracts/factories/TokenProxyFactory.sol";
import "../contracts/factories/CoinvestedPositionCloneFactory.sol";
import "../contracts/factories/DistributionCloneFactory.sol";
import "../contracts/CoinvestedPosition.sol";
import "../contracts/Distribution.sol";
import "../contracts/FeeSettings.sol";
import "../contracts/GlobalTokenExitRegistry.sol";
import "./resources/FakePaymentToken.sol";
import "./resources/CloneCreators.sol";

/// @dev Stub IDistribution: on claim() transfers a fixed amount of a given token to the recipient.
/// Used to test _settle() with currency == held token, bypassing Distribution's own guard.
contract TokenTransferStub {
    IERC20 public currency;
    uint256 public amount;

    constructor(IERC20 _currency, uint256 _amount) {
        currency = _currency;
        amount = _amount;
    }

    function claim(address recipient, uint256) external {
        currency.transfer(recipient, amount);
    }
}

/**
 * @title CoinvestedPositionDistributionTest
 * @notice Integration tests for CoinvestedPosition.claimDistribution() against a real Distribution contract.
 * Covers: basic proportional claim, claim ordering, carry fractions, non-EURO currencies,
 * cross-currency isolation, zero-token snapshot, reassignment extra credit, multiple
 * sequential distributions, pre-existing balance isolation, post-snapshot buy(), and fuzz.
 */
contract CoinvestedPositionDistributionTest is Test {
    // ── Well-known addresses ──────────────────────────────────────────────────
    address public constant admin = 0x0109709eCFa91a80626FF3989D68f67f5b1dD120;
    address public constant owner = 0x6109709EcFA91A80626FF3989d68f67F5b1dd126;
    address public constant receiver = 0x7109709eCfa91A80626Ff3989D68f67f5b1dD127;
    address public constant buyer = 0x1109709ecFA91a80626ff3989D68f67F5B1Dd121;
    address public constant leadA = 0x2109709EcFa91a80626Ff3989d68F67F5B1Dd122;
    address public constant leadB = 0x3109709ECfA91A80626fF3989D68f67F5B1Dd123;
    address public constant leadC = 0x4109709eCFa91A80626ff3989d68F67f5b1DD124;
    address public constant holderX = 0x8109709ecfa91a80626fF3989d68f67F5B1dD128;
    address public constant currencyProvider = 0x5109709EcFA91a80626ff3989d68f67F5B1dD125;
    address public constant trustedForwarder = 0xa109709ecfA91A80626ff3989D68F67F5b1dD12a;
    address public constant feeCollector = 0xB109709ECfa91A80626ff3989d68f67f5B1Dd12B;

    // ── Carry constants ───────────────────────────────────────────────────────
    /// 10% of uint64.max
    uint64 public constant CARRY_10PCT = type(uint64).max / 10;
    /// 5% of uint64.max
    uint64 public constant CARRY_5PCT = type(uint64).max / 20;

    // ── Token/Distribution setup ──────────────────────────────────────────────
    uint256 public constant TOKEN_SUPPLY = 1000e18;
    uint256 public constant COINVESTED_POSITION_TOKEN_AMOUNT = 200e18; // 20% of supply
    uint256 public constant OTHER_TOKENS = 800e18; // remainder to holderX
    uint256 public constant BASE_PRICE_EURC = 100e6; // 100 EURc per token (6 dec)

    uint256 public constant TOTAL_USDC = 2000e6; // total distribution
    uint256 public constant COINVESTED_POSITION_ELIGIBLE_USDC = 400e6; // 20% of 2000e6

    uint256 public constant PRICE_PER_TOKEN_USDC = 2_000_000; // 2000e6 / 1000e18 * 1e18
    uint256 public constant PRICE_PER_TOKEN_EURE = 1e18; // 1000e18 / 1000e18 * 1e18

    // ── lockedUntil ─────────────────────────────────────────────────
    uint64 public lockedUntil;

    // ── Contracts ─────────────────────────────────────────────────────────────
    AllowList allowList;
    IFeeSettingsV2 feeSettings;
    Token token;
    TokenProxyFactory tokenFactory;

    /// EURc: 6 decimals — base currency for CoinvestedPosition
    FakePaymentToken eurc;
    /// USDC: 6 decimals — dividend currency (TRUSTED_CURRENCY only, no EURO)
    FakePaymentToken usdc;
    /// EURe: 18 decimals — alternative dividend currency (TRUSTED | EURO)
    FakePaymentToken eure;

    GlobalTokenExitRegistry tokenExitRegistry;
    CoinvestedPosition coinvestedPositionLogic;
    CoinvestedPositionCloneFactory coinvestedPositionFactory;

    Distribution distributionLogic;
    DistributionCloneFactory distributionFactory;

    /// Snapshot taken after minting COINVESTED_POSITION_TOKEN_AMOUNT to `cp` and OTHER_TOKENS to `holderX`
    uint256 public snapshotId;

    /// Default CoinvestedPosition: basePrice=100e6 EURc, leadA=10%, leadB=5%
    CoinvestedPosition coinvestedPosition;

    // ─────────────────────────────────────────────────────────────────────────
    // ── setUp ─────────────────────────────────────────────────────────────────
    // ─────────────────────────────────────────────────────────────────────────

    function setUp() public {
        lockedUntil = uint64(block.timestamp + 31 days);

        // Infrastructure
        allowList = createAllowList(trustedForwarder, admin);
        feeSettings = createFeeSettings(
            trustedForwarder,
            admin,
            buildFeeTypes(0, 0, 0, feeCollector, feeCollector, feeCollector)
        );

        // Currencies
        eurc = new FakePaymentToken(0, 6);
        usdc = new FakePaymentToken(0, 6);
        eure = new FakePaymentToken(0, 18);

        vm.startPrank(admin);
        allowList.set(address(eurc), TRUSTED_CURRENCY);
        allowList.set(address(usdc), TRUSTED_CURRENCY);
        allowList.set(address(eure), TRUSTED_CURRENCY);
        vm.stopPrank();

        // Token
        address tokenLogicAddr = address(new Token(trustedForwarder));
        tokenFactory = new TokenProxyFactory(tokenLogicAddr);
        token = Token(
            tokenFactory.createTokenProxy(0, trustedForwarder, feeSettings, admin, allowList, 0, "TestToken", "TTK")
        );
        vm.startPrank(admin);
        token.grantRole(token.MINTALLOWER_ROLE(), admin);
        vm.stopPrank();

        // Factories
        coinvestedPositionLogic = new CoinvestedPosition(trustedForwarder);
        coinvestedPositionFactory = new CoinvestedPositionCloneFactory(address(coinvestedPositionLogic));
        distributionLogic = new Distribution(trustedForwarder);
        distributionFactory = new DistributionCloneFactory(address(distributionLogic));

        // GlobalTokenExitRegistry
        tokenExitRegistry = new GlobalTokenExitRegistry(trustedForwarder);

        // Deploy default CoinvestedPosition (base currency = EURc, leadA=10%, leadB=5%)
        coinvestedPosition = _deployCoinvestedPosition(bytes32(0), BASE_PRICE_EURC, eurc, _defaultLeadInvestors());

        // Mint tokens: 200 to coinvestedPosition, 800 to holderX
        vm.startPrank(admin);
        token.mint(address(coinvestedPosition), COINVESTED_POSITION_TOKEN_AMOUNT);
        token.mint(holderX, OTHER_TOKENS);
        vm.stopPrank();

        // Take snapshot (admin has SNAPSHOTCREATOR_ROLE by default)
        vm.prank(admin);
        snapshotId = token.createSnapshot();
    }

    // ─────────────────────────────────────────────────────────────────────────
    // ── Internal helpers ──────────────────────────────────────────────────────
    // ─────────────────────────────────────────────────────────────────────────

    function _defaultLeadInvestors() internal pure returns (LeadInvestor[] memory) {
        LeadInvestor[] memory leadInvestors = new LeadInvestor[](2);
        leadInvestors[0] = LeadInvestor({account: leadA, carryFraction: CARRY_10PCT});
        leadInvestors[1] = LeadInvestor({account: leadB, carryFraction: CARRY_5PCT});
        return leadInvestors;
    }

    function _deployCoinvestedPosition(
        bytes32 salt,
        uint256 basePrice,
        FakePaymentToken baseCurrency,
        LeadInvestor[] memory leadInvestors
    ) internal returns (CoinvestedPosition) {
        CoinvestedPositionInitializerArguments memory args = CoinvestedPositionInitializerArguments({
            owner: owner,
            receiver: receiver,
            leadInvestors: leadInvestors,
            basePrice: basePrice,
            baseCurrency: IERC20(address(baseCurrency)),
            token: token,
            lockedUntil: 0,
            tokenExitRegistry: tokenExitRegistry
        });
        return
            CoinvestedPosition(coinvestedPositionFactory.createCoinvestedPositionClone(salt, trustedForwarder, args));
    }

    /// @dev Deploy a funded Distribution clone against the pre-created snapshotId
    function _deployDistribution(
        bytes32 salt,
        FakePaymentToken _currency,
        uint256 initialFunding,
        uint256 _pricePerToken
    ) internal returns (Distribution) {
        return _deployDistributionWithSnapshot(salt, _currency, initialFunding, _pricePerToken, snapshotId);
    }

    /// @dev Deploy a funded Distribution clone against an explicit snapshotId
    function _deployDistributionWithSnapshot(
        bytes32 salt,
        FakePaymentToken _currency,
        uint256 initialFunding,
        uint256 _pricePerToken,
        uint256 _snapshotId
    ) internal returns (Distribution) {
        DistributionInitializerArguments memory args = DistributionInitializerArguments({
            owner: owner,
            token: token,
            snapshotId: _snapshotId,
            currency: IERC20(address(_currency)),
            pricePerToken: _pricePerToken,
            lockedUntil: lockedUntil,
            initialReassignments: new Reassignment[](0)
        });
        address cloneAddr = distributionFactory.predictCloneAddress(salt, trustedForwarder, args);
        if (initialFunding > 0) {
            _currency.mint(currencyProvider, initialFunding);
            vm.prank(currencyProvider);
            _currency.approve(cloneAddr, initialFunding);
        }
        return
            Distribution(
                distributionFactory.createDistributionClone(
                    salt,
                    trustedForwarder,
                    currencyProvider,
                    args,
                    initialFunding
                )
            );
    }

    /// @dev Compute expected lead-investor payout: floor(carryFraction * received / uint64.max)
    function _leadShare(uint64 carryFraction, uint256 received) internal pure returns (uint256) {
        return (uint256(carryFraction) * received) / type(uint64).max;
    }

    /// @dev Assert key invariant: sum of all payouts equals received
    function _assertPayoutSum(uint256 received, uint256 receiverPayout, uint256[] memory leadPayouts) internal pure {
        uint256 sum = receiverPayout;
        for (uint256 i = 0; i < leadPayouts.length; i++) {
            sum += leadPayouts[i];
        }
        assertEq(sum, received, "invariant: sum of payouts != received");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // ── DI-I. Basic Proportional Claim ────────────────────────────────────────
    // ─────────────────────────────────────────────────────────────────────────

    function testDI_I_BasicProportionalClaim() public {
        Distribution distribution = _deployDistribution(bytes32("DI-I"), usdc, TOTAL_USDC, PRICE_PER_TOKEN_USDC);

        // Verify eligible before claim
        assertEq(
            distribution.eligible(address(coinvestedPosition)),
            COINVESTED_POSITION_ELIGIBLE_USDC,
            "DI-I: wrong eligible before claim"
        );

        uint256 beforeA = usdc.balanceOf(leadA);
        uint256 beforeB = usdc.balanceOf(leadB);
        uint256 beforeR = usdc.balanceOf(receiver);

        vm.prank(owner);
        coinvestedPosition.claimDistribution(IDistribution(address(distribution)), 0);

        uint256 aGot = usdc.balanceOf(leadA) - beforeA;
        uint256 bGot = usdc.balanceOf(leadB) - beforeB;
        uint256 rGot = usdc.balanceOf(receiver) - beforeR;

        // floor(10% * 200e6) and floor(5% * 200e6) using uint64 fractions
        uint256 expectedA = _leadShare(CARRY_10PCT, COINVESTED_POSITION_ELIGIBLE_USDC);
        uint256 expectedB = _leadShare(CARRY_5PCT, COINVESTED_POSITION_ELIGIBLE_USDC);
        uint256 expectedR = COINVESTED_POSITION_ELIGIBLE_USDC - expectedA - expectedB;

        // auto-check
        assertEq(aGot, expectedA, "DI-I: wrong leadA payout");
        assertEq(bGot, expectedB, "DI-I: wrong leadB payout");
        assertEq(rGot, expectedR, "DI-I: wrong receiver payout");

        // manual check
        assertEq(aGot, 40e6 - 1, "wrong payout A");
        assertEq(bGot, 20e6 - 1, "wrong payout B");
        assertEq(rGot, 340e6 + 2, "wrong payout Coinvestor");

        // Distribution state
        assertEq(
            distribution.paidOut(address(coinvestedPosition)),
            COINVESTED_POSITION_ELIGIBLE_USDC,
            "DI-I: wrong paidOut"
        );
        assertEq(distribution.eligible(address(coinvestedPosition)), 0, "DI-I: eligible not zero after claim");

        // Invariant: sum
        uint256[] memory payouts = new uint256[](2);
        payouts[0] = aGot;
        payouts[1] = bGot;
        _assertPayoutSum(COINVESTED_POSITION_ELIGIBLE_USDC, rGot, payouts);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // ── DI-II. CoinvestedPosition as Minority Holder (others claim first) ─────
    // ─────────────────────────────────────────────────────────────────────────

    function testDI_II_MinorityHolder_OthersClaimFirst() public {
        Distribution distribution = _deployDistribution(bytes32("DI-II"), usdc, TOTAL_USDC, PRICE_PER_TOKEN_USDC);

        // holderX (800 tokens = 80%) claims first
        vm.prank(holderX);
        distribution.claim(holderX, 0);

        uint256 expectedHolderX = (OTHER_TOKENS * PRICE_PER_TOKEN_USDC) / (10 ** token.decimals());
        assertEq(usdc.balanceOf(holderX), expectedHolderX, "DI-II: wrong holderX payout");
        assertEq(expectedHolderX, 1600e6, "wrong amount for X");

        // CoinvestedPosition still has its full eligible share
        assertEq(
            distribution.eligible(address(coinvestedPosition)),
            COINVESTED_POSITION_ELIGIBLE_USDC,
            "DI-II: coinvestedPosition eligible changed after holderX claim"
        );

        uint256 beforeR = usdc.balanceOf(receiver);
        uint256 beforeA = usdc.balanceOf(leadA);
        uint256 beforeB = usdc.balanceOf(leadB);

        vm.prank(owner);
        coinvestedPosition.claimDistribution(IDistribution(address(distribution)), 0);

        uint256 aGot = usdc.balanceOf(leadA) - beforeA;
        uint256 bGot = usdc.balanceOf(leadB) - beforeB;
        uint256 rGot = usdc.balanceOf(receiver) - beforeR;

        uint256 expectedA = _leadShare(CARRY_10PCT, COINVESTED_POSITION_ELIGIBLE_USDC);
        uint256 expectedB = _leadShare(CARRY_5PCT, COINVESTED_POSITION_ELIGIBLE_USDC);

        assertEq(aGot, expectedA, "DI-II: wrong leadA payout");
        assertEq(bGot, expectedB, "DI-II: wrong leadB payout");
        assertEq(rGot, COINVESTED_POSITION_ELIGIBLE_USDC - expectedA - expectedB, "DI-II: wrong receiver payout");

        // Distribution currency balance after all claims <= total (rounding dust may remain)
        assertLe(usdc.balanceOf(address(distribution)), TOTAL_USDC, "DI-II: dist balance exceeded total");

        uint256[] memory payouts = new uint256[](2);
        payouts[0] = aGot;
        payouts[1] = bGot;
        _assertPayoutSum(COINVESTED_POSITION_ELIGIBLE_USDC, rGot, payouts);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // ── DI-III. Various Carry Fractions × Various Currencies ──────────────────
    // ─────────────────────────────────────────────────────────────────────────

    /// @dev Deploy a CoinvestedPosition with 3 lead investors: A=7%, B=13%, C=3%
    function _threeLeadInvestors() internal pure returns (LeadInvestor[] memory) {
        LeadInvestor[] memory leadInvestors = new LeadInvestor[](3);
        // 7% ≈ type(uint64).max * 7 / 100
        leadInvestors[0] = LeadInvestor({account: leadA, carryFraction: uint64((type(uint64).max / 100) * 7)});
        // 13% ≈ type(uint64).max * 13 / 100
        leadInvestors[1] = LeadInvestor({account: leadB, carryFraction: uint64((type(uint64).max / 100) * 13)});
        // 3% ≈ type(uint64).max * 3 / 100
        leadInvestors[2] = LeadInvestor({account: leadC, carryFraction: uint64((type(uint64).max / 100) * 3)});
        return leadInvestors;
    }

    /// III-A: Non-round carry fractions, USDC (6 dec)
    function testDI_III_A_ThreeLeadInvestors_USDC() public {
        CoinvestedPosition coinvestedPosition3 = _deployCoinvestedPosition(
            bytes32("DI-III-A-cp"),
            BASE_PRICE_EURC,
            eurc,
            _threeLeadInvestors()
        );

        // Mint 200 tokens to the new coinvestedPosition (snapshot already taken — cp3 has 0 at snapshot)
        // We need cp3 to have tokens at snapshot time, so deploy fresh token state:
        // For this test, redeploy with a fresh snapshot.
        vm.prank(admin);
        token.mint(address(coinvestedPosition3), COINVESTED_POSITION_TOKEN_AMOUNT);

        vm.prank(admin);
        uint256 snap3 = token.createSnapshot();

        // Now cp3 holds 200 tokens in snap3.
        // Total supply at snap3 = original 1000e18 (coinvestedPosition, holderX) + 200e18 (cp3) = 1200e18
        // cp3 eligible = 200e18 * PRICE_PER_TOKEN_USDC / 1e18
        uint256 coinvestedPosition3Eligible = (COINVESTED_POSITION_TOKEN_AMOUNT * PRICE_PER_TOKEN_USDC) /
            (10 ** token.decimals());

        Distribution distribution = _deployDistributionWithSnapshot(
            bytes32("DI-III-A"),
            usdc,
            TOTAL_USDC,
            PRICE_PER_TOKEN_USDC,
            snap3
        );

        assertEq(
            distribution.eligible(address(coinvestedPosition3)),
            coinvestedPosition3Eligible,
            "DI-III-A: wrong eligible"
        );

        LeadInvestor[] memory leadInvestors = _threeLeadInvestors();
        uint256 expectedA = _leadShare(leadInvestors[0].carryFraction, coinvestedPosition3Eligible);
        uint256 expectedB = _leadShare(leadInvestors[1].carryFraction, coinvestedPosition3Eligible);
        uint256 expectedC = _leadShare(leadInvestors[2].carryFraction, coinvestedPosition3Eligible);

        uint256 beforeA = usdc.balanceOf(leadA);
        uint256 beforeB = usdc.balanceOf(leadB);
        uint256 beforeC = usdc.balanceOf(leadC);
        uint256 beforeR = usdc.balanceOf(receiver);

        vm.prank(owner);
        coinvestedPosition3.claimDistribution(IDistribution(address(distribution)), 0);

        assertEq(usdc.balanceOf(leadA) - beforeA, expectedA, "DI-III-A: wrong leadA payout");
        assertEq(usdc.balanceOf(leadB) - beforeB, expectedB, "DI-III-A: wrong leadB payout");
        assertEq(usdc.balanceOf(leadC) - beforeC, expectedC, "DI-III-A: wrong leadC payout");
        // receiver collects remainder via sweep
        uint256 rGot = usdc.balanceOf(receiver) - beforeR;
        assertEq(
            rGot,
            coinvestedPosition3Eligible - expectedA - expectedB - expectedC,
            "DI-III-A: wrong receiver payout"
        );

        uint256[] memory payouts = new uint256[](3);
        payouts[0] = expectedA;
        payouts[1] = expectedB;
        payouts[2] = expectedC;
        _assertPayoutSum(coinvestedPosition3Eligible, rGot, payouts);
    }

    /// III-B: Same fractions, EURe (18 dec)
    function testDI_III_B_ThreeLeadInvestors_EURe() public {
        CoinvestedPosition coinvestedPosition3 = _deployCoinvestedPosition(
            bytes32("DI-III-B-cp"),
            BASE_PRICE_EURC,
            eurc,
            _threeLeadInvestors()
        );

        vm.prank(admin);
        token.mint(address(coinvestedPosition3), COINVESTED_POSITION_TOKEN_AMOUNT);

        vm.prank(admin);
        uint256 snap3 = token.createSnapshot();

        uint256 totalEure = 1000e18;
        uint256 totalSupplyAtSnap3 = token.totalSupplyAt(snap3);
        uint256 pricePerTokenEure = (totalEure * (10 ** token.decimals())) / totalSupplyAtSnap3;
        uint256 coinvestedPosition3Eligible = (COINVESTED_POSITION_TOKEN_AMOUNT * pricePerTokenEure) /
            (10 ** token.decimals());

        Distribution distribution = _deployDistributionWithSnapshot(
            bytes32("DI-III-B"),
            eure,
            totalEure,
            pricePerTokenEure,
            snap3
        );

        assertEq(
            distribution.eligible(address(coinvestedPosition3)),
            coinvestedPosition3Eligible,
            "DI-III-B: wrong eligible"
        );

        LeadInvestor[] memory leadInvestors = _threeLeadInvestors();
        uint256 expectedA = _leadShare(leadInvestors[0].carryFraction, coinvestedPosition3Eligible);
        uint256 expectedB = _leadShare(leadInvestors[1].carryFraction, coinvestedPosition3Eligible);
        uint256 expectedC = _leadShare(leadInvestors[2].carryFraction, coinvestedPosition3Eligible);

        // total token amount = 1000 + 200 = 1200e18
        // our token amount = 200e18, pricePerToken = 1000e18 * 1e18 / 1200e18 = 833333333333333333
        // eligible = 200e18 * 833333333333333333 / 1e18 = 166666666666666666600
        // (double rounding from price-based formula loses ~66 wei vs proportional 1000e18/6)
        assertEq(coinvestedPosition3Eligible, 166666666666666666600, "total eligible wrong");
        // percentages calculated the same way as contracts do, to get the rounding error right
        assertEq(
            expectedA,
            ((coinvestedPosition3Eligible * (((type(uint64).max) / 100) * 7)) / type(uint64).max),
            "expectedA wrong"
        );
        assertEq(
            expectedB,
            ((coinvestedPosition3Eligible * (((type(uint64).max) / 100) * 13)) / type(uint64).max),
            "expectedB wrong"
        );
        assertEq(
            expectedC,
            ((coinvestedPosition3Eligible * (((type(uint64).max) / 100) * 3)) / type(uint64).max),
            "expectedC wrong"
        );

        uint256 beforeA = eure.balanceOf(leadA);
        uint256 beforeB = eure.balanceOf(leadB);
        uint256 beforeC = eure.balanceOf(leadC);
        uint256 beforeR = eure.balanceOf(receiver);

        vm.prank(owner);
        coinvestedPosition3.claimDistribution(IDistribution(address(distribution)), 0);

        assertEq(eure.balanceOf(leadA) - beforeA, expectedA, "DI-III-B: wrong leadA EURe payout");
        assertEq(eure.balanceOf(leadB) - beforeB, expectedB, "DI-III-B: wrong leadB EURe payout");
        assertEq(eure.balanceOf(leadC) - beforeC, expectedC, "DI-III-B: wrong leadC EURe payout");
        uint256 rGot = eure.balanceOf(receiver) - beforeR;
        assertEq(
            rGot,
            coinvestedPosition3Eligible - expectedA - expectedB - expectedC,
            "DI-III-B: wrong receiver EURe payout"
        );

        // No basePriceDecimals scaling — raw bits
        uint256[] memory payouts = new uint256[](3);
        payouts[0] = expectedA;
        payouts[1] = expectedB;
        payouts[2] = expectedC;
        _assertPayoutSum(coinvestedPosition3Eligible, rGot, payouts);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // ── DI-IV. Non-EURO Trusted Currency (USDC) ───────────────────────────────
    // ─────────────────────────────────────────────────────────────────────────

    function testDI_IV_NonEuroTrustedCurrency_Accepted() public {
        // USDC has TRUSTED_CURRENCY bit — must be accepted by claimDistribution
        Distribution distribution = _deployDistribution(bytes32("DI-IV"), usdc, TOTAL_USDC, PRICE_PER_TOKEN_USDC);

        uint256 beforeA = usdc.balanceOf(leadA);
        uint256 beforeB = usdc.balanceOf(leadB);
        uint256 beforeR = usdc.balanceOf(receiver);

        // Must not revert
        vm.prank(owner);
        coinvestedPosition.claimDistribution(IDistribution(address(distribution)), 0);

        uint256 aGot = usdc.balanceOf(leadA) - beforeA;
        uint256 bGot = usdc.balanceOf(leadB) - beforeB;
        uint256 rGot = usdc.balanceOf(receiver) - beforeR;

        uint256 expectedA = _leadShare(CARRY_10PCT, COINVESTED_POSITION_ELIGIBLE_USDC);
        uint256 expectedB = _leadShare(CARRY_5PCT, COINVESTED_POSITION_ELIGIBLE_USDC);

        assertEq(aGot, expectedA, "DI-IV: wrong leadA USDC payout");
        assertEq(bGot, expectedB, "DI-IV: wrong leadB USDC payout");
        assertEq(rGot, COINVESTED_POSITION_ELIGIBLE_USDC - expectedA - expectedB, "DI-IV: wrong receiver USDC payout");

        uint256[] memory payouts = new uint256[](2);
        payouts[0] = aGot;
        payouts[1] = bGot;
        _assertPayoutSum(COINVESTED_POSITION_ELIGIBLE_USDC, rGot, payouts);
    }

    function testDI_IV_UntrustedCurrency_Rejected() public {
        // A currency not on the allowlist should be rejected.
        // Use a stub Distribution that reports an untrusted token as its currency,
        // bypassing Distribution's own constructor guard.
        FakePaymentToken untrusted = new FakePaymentToken(0, 6);
        TokenTransferStub stub = new TokenTransferStub(IERC20(address(untrusted)), 0);
        IERC20 untrustedCurrency = IERC20(address(stub.currency()));

        vm.expectRevert("dividend currency must be a trusted currency");
        vm.prank(owner);
        coinvestedPosition.claimDistribution(IDistribution(address(stub)), 0);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // ── DI-V. Currency Different from baseCurrency ────────────────────────────
    // ─────────────────────────────────────────────────────────────────────────

    function testDI_V_DividendCurrencyDiffersFromBaseCurrency() public {
        // coinvestedPosition was initialised with EURc as baseCurrency; Distribution pays USDC
        Distribution distribution = _deployDistribution(bytes32("DI-V"), usdc, TOTAL_USDC, PRICE_PER_TOKEN_USDC);

        // Give coinvestedPosition some EURc to verify it is untouched
        eurc.mint(address(coinvestedPosition), 500e6);
        uint256 eurcBefore = eurc.balanceOf(address(coinvestedPosition));

        uint256 beforeA = usdc.balanceOf(leadA);
        uint256 beforeB = usdc.balanceOf(leadB);
        uint256 beforeR = usdc.balanceOf(receiver);

        vm.prank(owner);
        coinvestedPosition.claimDistribution(IDistribution(address(distribution)), 0);

        uint256 aGot = usdc.balanceOf(leadA) - beforeA;
        uint256 bGot = usdc.balanceOf(leadB) - beforeB;
        uint256 rGot = usdc.balanceOf(receiver) - beforeR;

        uint256 expectedA = _leadShare(CARRY_10PCT, COINVESTED_POSITION_ELIGIBLE_USDC);
        uint256 expectedB = _leadShare(CARRY_5PCT, COINVESTED_POSITION_ELIGIBLE_USDC);

        // No decimal conversion — raw 6-dec USDC bits used directly
        assertEq(aGot, expectedA, "DI-V: wrong leadA USDC payout");
        assertEq(bGot, expectedB, "DI-V: wrong leadB USDC payout");
        assertEq(rGot, COINVESTED_POSITION_ELIGIBLE_USDC - expectedA - expectedB, "DI-V: wrong receiver USDC payout");

        // EURc balance untouched
        assertEq(eurc.balanceOf(address(coinvestedPosition)), eurcBefore, "DI-V: EURc balance changed");

        uint256[] memory payouts = new uint256[](2);
        payouts[0] = aGot;
        payouts[1] = bGot;
        _assertPayoutSum(COINVESTED_POSITION_ELIGIBLE_USDC, rGot, payouts);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // ── DI-VI. CoinvestedPosition Has 0 Tokens in Snapshot ────────────────────
    // ─────────────────────────────────────────────────────────────────────────

    function testDI_VI_ZeroTokensAtSnapshot_Reverts() public {
        // Deploy a fresh CoinvestedPosition that had 0 tokens at snapshot time
        CoinvestedPosition coinvestedPositionZero = _deployCoinvestedPosition(
            bytes32("DI-VI-cp"),
            BASE_PRICE_EURC,
            eurc,
            _defaultLeadInvestors()
        );
        // Do NOT mint any tokens to coinvestedPositionZero before the snapshot (snapshotId taken in setUp)

        Distribution distribution = _deployDistribution(bytes32("DI-VI"), usdc, TOTAL_USDC, PRICE_PER_TOKEN_USDC);

        // eligible must be 0
        assertEq(distribution.eligible(address(coinvestedPositionZero)), 0, "DI-VI: eligible not zero");

        // claimDistribution must revert because eligible = 0
        vm.expectRevert("nothing to claim");
        vm.prank(owner);
        coinvestedPositionZero.claimDistribution(IDistribution(address(distribution)), 0);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // ── DI-VII. Extra Credit via Reassignment ─────────────────────────────────
    // ─────────────────────────────────────────────────────────────────────────

    address constant holderY = 0x9109709EcFA91A80626FF3989D68f67F5B1dD129;

    function testDI_VII_ExtraCreditViaReassignment() public {
        // Mint 100 tokens to holderY, retake snapshot
        vm.prank(admin);
        token.mint(holderY, 100e18);
        vm.prank(admin);
        uint256 snap7 = token.createSnapshot();

        uint256 coinvestedPositionEligible7 = (COINVESTED_POSITION_TOKEN_AMOUNT * PRICE_PER_TOKEN_USDC) /
            (10 ** token.decimals());
        uint256 holderYEligible = (100e18 * PRICE_PER_TOKEN_USDC) / (10 ** token.decimals());

        Distribution distribution = _deployDistributionWithSnapshot(
            bytes32("DI-VII"),
            usdc,
            TOTAL_USDC,
            PRICE_PER_TOKEN_USDC,
            snap7
        );
        assertEq(
            distribution.eligible(address(coinvestedPosition)),
            coinvestedPositionEligible7,
            "DI-VII: wrong coinvestedPosition eligible before reassign"
        );
        assertEq(distribution.eligible(holderY), holderYEligible, "DI-VII: wrong holderY eligible");

        vm.warp(lockedUntil);
        uint256 yEligible = distribution.eligible(holderY);
        vm.prank(owner);
        distribution.reassign(holderY, address(coinvestedPosition), yEligible);

        uint256 coinvestedPositionEligibleAfter = coinvestedPositionEligible7 + holderYEligible;
        assertEq(
            distribution.eligible(address(coinvestedPosition)),
            coinvestedPositionEligibleAfter,
            "DI-VII: wrong coinvestedPosition eligible after reassign"
        );
        assertEq(distribution.eligible(holderY), 0, "DI-VII: holderY eligible not zero after reassign");

        uint256 beforeA = usdc.balanceOf(leadA);
        uint256 beforeB = usdc.balanceOf(leadB);
        uint256 beforeR = usdc.balanceOf(receiver);

        vm.prank(owner);
        coinvestedPosition.claimDistribution(IDistribution(address(distribution)), 0);

        uint256 aGot = usdc.balanceOf(leadA) - beforeA;
        uint256 bGot = usdc.balanceOf(leadB) - beforeB;
        uint256 rGot = usdc.balanceOf(receiver) - beforeR;

        assertEq(
            aGot,
            _leadShare(CARRY_10PCT, coinvestedPositionEligibleAfter),
            "DI-VII: wrong leadA payout on combined eligible"
        );
        assertEq(
            bGot,
            _leadShare(CARRY_5PCT, coinvestedPositionEligibleAfter),
            "DI-VII: wrong leadB payout on combined eligible"
        );
        assertEq(rGot, coinvestedPositionEligibleAfter - aGot - bGot, "DI-VII: wrong receiver payout");

        // holderY cannot claim anything
        uint256 holderYBalBefore = usdc.balanceOf(holderY);
        // holderY's eligible is 0 after full reassign → claim reverts
        vm.prank(holderY);
        vm.expectRevert("nothing to claim");
        distribution.claim(holderY, 0);
        assertEq(usdc.balanceOf(holderY), holderYBalBefore, "DI-VII: holderY received non-zero after reassign");

        uint256[] memory payouts = new uint256[](2);
        payouts[0] = aGot;
        payouts[1] = bGot;
        _assertPayoutSum(coinvestedPositionEligibleAfter, rGot, payouts);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // ── DI-VIII. Multiple Distribution Contracts, Sequential Claims ────────────
    // ─────────────────────────────────────────────────────────────────────────

    function testDI_VIII_MultipleDistributions_Sequential() public {
        Distribution usdcDistribution = _deployDistribution(
            bytes32("DI-VIII-usdc"),
            usdc,
            TOTAL_USDC,
            PRICE_PER_TOKEN_USDC
        );
        Distribution eureDistribution = _deployDistribution(
            bytes32("DI-VIII-eure"),
            eure,
            1000e18,
            PRICE_PER_TOKEN_EURE
        );

        // --- Claim USDC distribution ---
        {
            uint256 beforeA = usdc.balanceOf(leadA);
            uint256 beforeB = usdc.balanceOf(leadB);
            uint256 beforeR = usdc.balanceOf(receiver);

            vm.prank(owner);
            coinvestedPosition.claimDistribution(IDistribution(address(usdcDistribution)), 0);

            uint256 aGot = usdc.balanceOf(leadA) - beforeA;
            uint256 bGot = usdc.balanceOf(leadB) - beforeB;
            uint256 rGot = usdc.balanceOf(receiver) - beforeR;

            assertEq(
                aGot,
                _leadShare(CARRY_10PCT, COINVESTED_POSITION_ELIGIBLE_USDC),
                "DI-VIII: wrong leadA USDC payout"
            );
            assertEq(
                bGot,
                _leadShare(CARRY_5PCT, COINVESTED_POSITION_ELIGIBLE_USDC),
                "DI-VIII: wrong leadB USDC payout"
            );
            assertEq(rGot, COINVESTED_POSITION_ELIGIBLE_USDC - aGot - bGot, "DI-VIII: wrong receiver USDC payout");

            uint256[] memory payouts = new uint256[](2);
            payouts[0] = aGot;
            payouts[1] = bGot;
            _assertPayoutSum(COINVESTED_POSITION_ELIGIBLE_USDC, rGot, payouts);
        }

        assertEq(
            usdc.balanceOf(address(coinvestedPosition)),
            0,
            "DI-VIII: coinvestedPosition USDC balance not zero after first claim"
        );

        // --- Claim EURe distribution ---
        uint256 coinvestedPositionEligibleEure = (1000e18 * COINVESTED_POSITION_TOKEN_AMOUNT) / TOKEN_SUPPLY;
        {
            uint256 beforeA = eure.balanceOf(leadA);
            uint256 beforeB = eure.balanceOf(leadB);
            uint256 beforeR = eure.balanceOf(receiver);

            vm.prank(owner);
            coinvestedPosition.claimDistribution(IDistribution(address(eureDistribution)), 0);

            uint256 aGot = eure.balanceOf(leadA) - beforeA;
            uint256 bGot = eure.balanceOf(leadB) - beforeB;
            uint256 rGot = eure.balanceOf(receiver) - beforeR;

            assertEq(aGot, _leadShare(CARRY_10PCT, coinvestedPositionEligibleEure), "DI-VIII: wrong leadA EURe payout");
            assertEq(bGot, _leadShare(CARRY_5PCT, coinvestedPositionEligibleEure), "DI-VIII: wrong leadB EURe payout");
            assertEq(rGot, coinvestedPositionEligibleEure - aGot - bGot, "DI-VIII: wrong receiver EURe payout");

            uint256[] memory payouts = new uint256[](2);
            payouts[0] = aGot;
            payouts[1] = bGot;
            _assertPayoutSum(coinvestedPositionEligibleEure, rGot, payouts);
        }

        assertEq(
            eure.balanceOf(address(coinvestedPosition)),
            0,
            "DI-VIII: coinvestedPosition EURe balance not zero after second claim"
        );
    }

    // ─────────────────────────────────────────────────────────────────────────
    // ── DI-IX. Pre-existing Dividend Currency Balance Isolation ──────────────
    // ─────────────────────────────────────────────────────────────────────────

    function testDI_IX_PreExistingBalance_Isolation() public {
        // 300e6 USDC already on coinvestedPosition before claimDistribution
        uint256 preExisting = 300e6;
        usdc.mint(address(coinvestedPosition), preExisting);

        Distribution distribution = _deployDistribution(bytes32("DI-IX"), usdc, TOTAL_USDC, PRICE_PER_TOKEN_USDC);

        // before snapshot is taken at call time — pre-existing is excluded from `received`
        uint256 beforeA = usdc.balanceOf(leadA);
        uint256 beforeB = usdc.balanceOf(leadB);
        uint256 beforeR = usdc.balanceOf(receiver);

        vm.prank(owner);
        coinvestedPosition.claimDistribution(IDistribution(address(distribution)), 0);

        uint256 aGot = usdc.balanceOf(leadA) - beforeA;
        uint256 bGot = usdc.balanceOf(leadB) - beforeB;
        uint256 rGot = usdc.balanceOf(receiver) - beforeR;

        // received = 200e6 (from distribution, not 300e6 pre-existing)
        uint256 received = COINVESTED_POSITION_ELIGIBLE_USDC;
        uint256 expectedA = _leadShare(CARRY_10PCT, received);
        uint256 expectedB = _leadShare(CARRY_5PCT, received);

        assertEq(aGot, expectedA, "DI-IX: wrong leadA carry");
        assertEq(bGot, expectedB, "DI-IX: wrong leadB carry");

        // receiver gets dividend share + 300e6 pre-existing via sweep
        uint256 expectedR = received - expectedA - expectedB + preExisting;
        assertEq(rGot, expectedR, "DI-IX: wrong receiver payout");

        // Total: A + B + receiver = 200e6 + 300e6 = 500e6
        assertEq(aGot + bGot + rGot, received + preExisting, "DI-IX: total sum mismatch");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // ── DI-X. buy() Between Snapshot and Dividend Claim ──────────────────────
    // ─────────────────────────────────────────────────────────────────────────

    function testDI_X_BuyBetweenSnapshotAndClaim() public {
        // Snapshot already taken in setUp with coinvestedPosition holding 200 tokens.
        // Deploy distribution — coinvestedPosition eligible = 200e6
        Distribution distribution = _deployDistribution(bytes32("DI-X"), usdc, TOTAL_USDC, PRICE_PER_TOKEN_USDC);
        assertEq(
            distribution.eligible(address(coinvestedPosition)),
            COINVESTED_POSITION_ELIGIBLE_USDC,
            "DI-X: wrong eligible at snapshot"
        );

        // Now simulate a buyer purchasing 50 tokens from coinvestedPosition after the snapshot
        // Need: set token price, flag buyer on allowList, unpause coinvestedPosition, buyer buys
        uint256 tokenPrice = 200e6; // 200 EURc per token
        vm.prank(owner);
        coinvestedPosition.setTokenPrice(tokenPrice);

        // Flag buyer
        vm.prank(admin);

        // Mint EURc for buyer
        uint256 buyAmount = 50e18;
        // ceilDiv(50e18 * 200e6 / 1e18) = 10_000e6
        uint256 costEurc = Math.ceilDiv(buyAmount * tokenPrice, 10 ** token.decimals());
        eurc.mint(buyer, costEurc);

        vm.prank(owner);
        coinvestedPosition.unpause();

        vm.startPrank(buyer);
        eurc.approve(address(coinvestedPosition), costEurc);
        coinvestedPosition.buy(buyAmount, costEurc, buyer);
        vm.stopPrank();

        // coinvestedPosition now holds 150 tokens, buyer holds 50
        assertEq(
            token.balanceOf(address(coinvestedPosition)),
            COINVESTED_POSITION_TOKEN_AMOUNT - buyAmount,
            "DI-X: wrong coinvestedPosition token balance after buy"
        );
        assertEq(token.balanceOf(buyer), buyAmount, "DI-X: wrong buyer token balance");

        // claimDistribution still claims full snapshot-eligible 200e6
        uint256 beforeA = usdc.balanceOf(leadA);
        uint256 beforeB = usdc.balanceOf(leadB);
        uint256 beforeR = usdc.balanceOf(receiver);

        vm.prank(owner);
        coinvestedPosition.claimDistribution(IDistribution(address(distribution)), 0);

        uint256 aGot = usdc.balanceOf(leadA) - beforeA;
        uint256 bGot = usdc.balanceOf(leadB) - beforeB;
        uint256 rGot = usdc.balanceOf(receiver) - beforeR;

        // received = 200e6 (snapshot-based, ignores the post-snapshot sell)
        uint256 received = COINVESTED_POSITION_ELIGIBLE_USDC;
        uint256 expectedA = _leadShare(CARRY_10PCT, received);
        uint256 expectedB = _leadShare(CARRY_5PCT, received);

        assertEq(aGot, expectedA, "DI-X: wrong leadA payout");
        assertEq(bGot, expectedB, "DI-X: wrong leadB payout");
        assertEq(rGot, received - expectedA - expectedB, "DI-X: wrong receiver payout");

        uint256[] memory payouts = new uint256[](2);
        payouts[0] = aGot;
        payouts[1] = bGot;
        _assertPayoutSum(received, rGot, payouts);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // ── DI-XI. Fuzz Tests ──────────────────────────────────────────────────────
    // ─────────────────────────────────────────────────────────────────────────

    // ─────────────────────────────────────────────────────────────────────────
    // ── DI-XII. _settle rejects currency == held token ────────────────────────
    // ─────────────────────────────────────────────────────────────────────────

    function testDI_XII_DistributionRevertsWhenCurrencyIsToken() public {
        // Give the equity token the TRUSTED_CURRENCY bit so the allowList check passes
        vm.prank(admin);
        allowList.set(address(token), TRUSTED_CURRENCY);

        DistributionInitializerArguments memory args = DistributionInitializerArguments({
            owner: owner,
            token: token,
            snapshotId: snapshotId,
            currency: IERC20(address(token)),
            pricePerToken: PRICE_PER_TOKEN_USDC,
            lockedUntil: lockedUntil,
            initialReassignments: new Reassignment[](0)
        });
        address cloneAddr = distributionFactory.predictCloneAddress(bytes32("DI-XII"), trustedForwarder, args);
        vm.prank(admin);
        token.mint(currencyProvider, 100e18);
        vm.prank(currencyProvider);
        token.approve(cloneAddr, 100e18);

        vm.expectRevert("currency and token must be different");
        distributionFactory.createDistributionClone(
            bytes32("DI-XII"),
            trustedForwarder,
            currencyProvider,
            args,
            100e18
        );
    }

    /// DI-XIII: _settle reverts when currency == held token, tested via a stub Distribution
    /// that bypasses Distribution's own guard and actually delivers the equity token to cp.
    function testDI_XIII_SettleRevertsWhenCurrencyIsHeldToken() public {
        // Give the equity token TRUSTED_CURRENCY so it passes claimDistribution' allowList check
        vm.prank(admin);
        allowList.set(address(token), TRUSTED_CURRENCY);

        // Seed the stub with equity tokens so claim() can transfer them to cp
        uint256 stubAmount = 10e18;
        vm.prank(admin);
        token.mint(address(this), stubAmount);
        TokenTransferStub stub = new TokenTransferStub(IERC20(address(token)), stubAmount);
        IERC20(address(token)).transfer(address(stub), stubAmount);
        IERC20 tokenCurrency = IERC20(address(stub.currency()));

        vm.expectRevert("currency cannot be the held token");
        vm.prank(owner);
        coinvestedPosition.claimDistribution(IDistribution(address(stub)), 0);
    }

    /**
     * @notice Fuzz: random CoinvestedPosition snapshot balance, pricePerToken, 1-3 lead investors.
     * Invariants:
     *   1. received == Distribution.eligible(coinvestedPosition) at claim time
     *   2. sum(lead investor payouts) + receiver_payout == received
     *   3. each lead investor payout == floor(carryFraction * received / uint64.max)
     *   4. no currency created or destroyed
     */
    function testDI_XI_Fuzz(
        uint64 coinvestedPositionTokenAmount,
        uint64 otherTokenAmount,
        uint96 fuzzPricePerToken,
        uint8 numLeads,
        uint64 carryA,
        uint64 carryB,
        uint64 carryC
    ) public {
        vm.assume(coinvestedPositionTokenAmount > 0);
        vm.assume(otherTokenAmount > 0);
        // uint64 * 1e18 + uint64 * 1e18 << uint256.max, so no overflow check needed
        vm.assume(numLeads >= 1 && numLeads <= 3);

        vm.assume(carryA >= 1 && carryA <= type(uint64).max / 10);
        if (numLeads >= 2) vm.assume(carryB >= 1 && carryB <= type(uint64).max / 10);
        else carryB = 0;
        if (numLeads >= 3) vm.assume(carryC >= 1 && carryC <= type(uint64).max / 10);
        else carryC = 0;
        vm.assume(uint256(carryA) + uint256(carryB) + uint256(carryC) < type(uint64).max);

        vm.assume(fuzzPricePerToken >= 1);

        // Scope leadInvestors, fuzzToken, snapFuzz so they're freed before the assertion phase.
        CoinvestedPosition coinvestedPositionFuzz;
        Distribution distributionFuzz;
        uint256 coinvestedPositionEligible;
        {
            LeadInvestor[] memory leadInvestors = new LeadInvestor[](numLeads);
            leadInvestors[0] = LeadInvestor({account: leadA, carryFraction: carryA});
            if (numLeads >= 2) leadInvestors[1] = LeadInvestor({account: leadB, carryFraction: carryB});
            if (numLeads >= 3) leadInvestors[2] = LeadInvestor({account: leadC, carryFraction: carryC});

            Token fuzzToken;
            uint256 snapFuzz;
            {
                uint256 coinvestedPositionTokens = uint256(coinvestedPositionTokenAmount) * 1e18;
                uint256 otherTokens = uint256(otherTokenAmount) * 1e18;

                bytes32 salt = bytes32(uint256(leadInvestors[0].carryFraction) ^ coinvestedPositionTokens);
                CoinvestedPosition tempCoinvestedPosition = _deployCoinvestedPosition(
                    salt,
                    BASE_PRICE_EURC,
                    eurc,
                    leadInvestors
                );

                fuzzToken = Token(
                    tokenFactory.createTokenProxy(
                        bytes32(uint256(uint160(address(tempCoinvestedPosition)))),
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
                fuzzToken.mint(address(tempCoinvestedPosition), coinvestedPositionTokens);
                if (otherTokens > 0) fuzzToken.mint(holderX, otherTokens);
                vm.stopPrank();

                CoinvestedPositionInitializerArguments
                    memory coinvestedPositionArgs = CoinvestedPositionInitializerArguments({
                        owner: owner,
                        receiver: receiver,
                        leadInvestors: leadInvestors,
                        basePrice: BASE_PRICE_EURC,
                        baseCurrency: IERC20(address(eurc)),
                        token: fuzzToken,
                        lockedUntil: 0,
                        tokenExitRegistry: tokenExitRegistry
                    });
                coinvestedPositionFuzz = CoinvestedPosition(
                    coinvestedPositionFactory.createCoinvestedPositionClone(
                        bytes32(uint256(uint160(address(tempCoinvestedPosition))) + 1),
                        trustedForwarder,
                        coinvestedPositionArgs
                    )
                );
                vm.prank(address(tempCoinvestedPosition));
                fuzzToken.transfer(address(coinvestedPositionFuzz), coinvestedPositionTokens);
                vm.prank(admin);
                snapFuzz = fuzzToken.createSnapshot();
            }

            coinvestedPositionEligible =
                (fuzzToken.balanceOfAt(address(coinvestedPositionFuzz), snapFuzz) * uint256(fuzzPricePerToken)) /
                (10 ** fuzzToken.decimals());

            // Compute initial funding: enough to cover all eligible claims
            uint256 totalSupplyFuzz = fuzzToken.totalSupplyAt(snapFuzz);
            uint256 initialFunding = (totalSupplyFuzz * uint256(fuzzPricePerToken)) / (10 ** fuzzToken.decimals());

            DistributionInitializerArguments memory distributionArgs = DistributionInitializerArguments({
                owner: owner,
                token: fuzzToken,
                snapshotId: snapFuzz,
                currency: IERC20(address(usdc)),
                pricePerToken: uint256(fuzzPricePerToken),
                lockedUntil: lockedUntil,
                initialReassignments: new Reassignment[](0)
            });
            address cloneAddr = distributionFactory.predictCloneAddress(
                bytes32("DI-XI-dist"),
                trustedForwarder,
                distributionArgs
            );
            usdc.mint(currencyProvider, initialFunding);
            vm.prank(currencyProvider);
            usdc.approve(cloneAddr, initialFunding);
            distributionFuzz = Distribution(
                distributionFactory.createDistributionClone(
                    bytes32("DI-XI-dist"),
                    trustedForwarder,
                    currencyProvider,
                    distributionArgs,
                    initialFunding
                )
            );
        }
        // leadInvestors, fuzzToken, snapFuzz released; stack: 6 params + coinvestedPositionFuzz + distributionFuzz + coinvestedPositionEligible

        assertEq(
            distributionFuzz.eligible(address(coinvestedPositionFuzz)),
            coinvestedPositionEligible,
            "DI-XI: wrong eligible"
        );

        if (coinvestedPositionEligible == 0) {
            vm.expectRevert("didn't receive expected currency from distribution");
            vm.prank(owner);
            coinvestedPositionFuzz.claimDistribution(IDistribution(address(distributionFuzz)), 0);
            return;
        }

        // Pack snap values into a memory array (1 stack slot) to stay under the stack limit.
        // Layout: [0]=leadA, [1]=leadB, [2]=leadC, [3]=receiver
        uint256[4] memory snaps;
        snaps[0] = usdc.balanceOf(leadA);
        snaps[1] = usdc.balanceOf(leadB);
        snaps[2] = usdc.balanceOf(leadC);
        snaps[3] = usdc.balanceOf(receiver);

        vm.prank(owner);
        coinvestedPositionFuzz.claimDistribution(IDistribution(address(distributionFuzz)), 0);

        uint256 totalGot = 0;
        {
            uint256 aGot = usdc.balanceOf(leadA) - snaps[0];
            assertEq(aGot, _leadShare(carryA, coinvestedPositionEligible), "DI-XI: wrong leadA payout");
            totalGot += aGot;
        }
        {
            uint256 bGot = usdc.balanceOf(leadB) - snaps[1];
            if (numLeads >= 2)
                assertEq(bGot, _leadShare(carryB, coinvestedPositionEligible), "DI-XI: wrong leadB payout");
            totalGot += bGot;
        }
        {
            uint256 cGot = usdc.balanceOf(leadC) - snaps[2];
            if (numLeads >= 3)
                assertEq(cGot, _leadShare(carryC, coinvestedPositionEligible), "DI-XI: wrong leadC payout");
            totalGot += cGot;
        }
        totalGot += usdc.balanceOf(receiver) - snaps[3];

        assertEq(totalGot, coinvestedPositionEligible, "DI-XI: sum of payouts != received");
        assertEq(distributionFuzz.eligible(address(coinvestedPositionFuzz)), 0, "DI-XI: eligible not zero after claim");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // ── DI-XIV. CoinvestedPosition balance-diff minPayout check ──────────────
    // ─────────────────────────────────────────────────────────────────────────

    /// DI-XIV-B: stub pays exactly _minPayout → succeeds
    function testDI_XIV_BalanceDiffAcceptsExactMinimum() public {
        uint256 minPayout = 1e6;
        usdc.mint(address(this), minPayout);
        TokenTransferStub stub = new TokenTransferStub(IERC20(address(usdc)), minPayout);
        IERC20(address(usdc)).transfer(address(stub), minPayout);

        vm.prank(owner);
        coinvestedPosition.claimDistribution(IDistribution(address(stub)), minPayout);
        assertEq(usdc.balanceOf(address(coinvestedPosition)), 0, "cp should hold no usdc after settle");
    }
}
