// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.23;

import "../lib/forge-std/src/Test.sol";

import "../contracts/factories/TokenProxyFactory.sol";
import "../contracts/factories/CoinvestedPositionCloneFactory.sol";
import "../contracts/factories/ExitCloneFactory.sol";
import "../contracts/CoinvestedPosition.sol";
import "../contracts/Exit.sol";
import "../contracts/FeeSettings.sol";
import "../contracts/GlobalTokenExitRegistry.sol";
import "./resources/FakePaymentToken.sol";
import "./resources/CloneCreators.sol";
import "./resources/FixedPayoutExit.sol";

/// @dev Minimal IExit stub: claim() does nothing. Currency is configurable at construction.
contract NoOpExit {
    IERC20 private _currency;

    constructor(IERC20 currency_) {
        _currency = currency_;
    }

    function claim(address, uint256) external {}

    function currency() external view returns (IERC20) {
        return _currency;
    }

    function referenceToExitRate(IERC20) external pure returns (uint256) {
        return 0;
    }
}

/**
 * @title CoinvestedPositionExitTest
 * @notice Integration tests for CoinvestedPosition.claimExit() against a real Exit contract.
 * Covers: basic sanity, decimal scaling, multi-investor carry, fee scenarios,
 * pre-existing balance isolation, funding edge cases, token approval, fuzz, and
 * buy() + claimExit() interaction ordering.
 */
contract CoinvestedPositionExitTest is Test {
    // ── Well-known addresses ──────────────────────────────────────────────────
    address public constant admin = 0x0109709eCFa91a80626FF3989D68f67f5b1dD120;
    address public constant owner = 0x6109709EcFA91A80626FF3989d68f67F5b1dd126;
    address public constant receiver = 0x7109709eCfa91A80626Ff3989D68f67f5b1dD127;
    address public constant buyer = 0x1109709ecFA91a80626ff3989D68f67F5B1Dd121;
    address public constant leadA = 0x2109709EcFa91a80626Ff3989d68F67F5B1Dd122;
    address public constant leadB = 0x3109709ECfA91A80626fF3989D68f67F5B1Dd123;
    address public constant leadC = 0x4109709eCFa91A80626ff3989d68F67f5b1DD124;
    address public constant currencyProvider = 0x5109709EcFA91a80626ff3989d68f67F5B1dD125;
    address public constant trustedForwarder = 0xa109709ecfA91A80626ff3989D68F67F5b1dD12a;
    address public constant feeCollector = 0xB109709ECfa91A80626ff3989d68f67f5B1Dd12B;

    // ── Carry constants ───────────────────────────────────────────────────────
    // 10% of uint64.max
    uint64 public constant CARRY_10PCT = type(uint64).max / 10;
    // 5% of uint64.max
    uint64 public constant CARRY_5PCT = type(uint64).max / 20;

    // ── Token setup ───────────────────────────────────────────────────────────
    uint256 public constant TOKEN_SUPPLY = 1000e18;
    uint256 public constant CP_TOKEN_AMOUNT = 200e18;
    uint256 public constant BASE_PRICE_EURC = 100e6; // 100 EURc (6 dec) per token

    // ── Claim window ──────────────────────────────────────────────────────────
    uint64 public claimStart;
    uint64 public lockedUntil;

    // ── Contracts ─────────────────────────────────────────────────────────────
    AllowList allowList;
    IFeeSettingsV2 feeSettings;
    Token token;
    TokenProxyFactory tokenFactory;

    // EURc: 6 decimals (base currency)
    FakePaymentToken eurc;
    // EURe: 18 decimals (cross-currency tests)
    FakePaymentToken eure;
    // Non-EURO trusted token (for negative test)
    FakePaymentToken trustedNonEuro;

    GlobalTokenExitRegistry tokenExitRegistry;
    CoinvestedPosition coinvestedPositionLogic;
    CoinvestedPositionCloneFactory coinvestedPositionFactory;
    Exit exitLogic;
    ExitCloneFactory exitFactory;

    // Default clone: basePrice = 100e6 EURc, leadA=10%, leadB=5%
    CoinvestedPosition coinvestedPosition;

    // ── setUp ──────────────────────────────────────────────────────────────────
    function setUp() public {
        claimStart = uint64(block.timestamp + 1 days);
        lockedUntil = uint64(block.timestamp + 30 days);

        // Infrastructure
        allowList = createAllowList(trustedForwarder, admin);
        feeSettings = createFeeSettings(
            trustedForwarder,
            admin,
            buildFeeTypes(0, 0, 0, feeCollector, feeCollector, feeCollector)
        );

        // Currencies
        eurc = new FakePaymentToken(0, 6);
        eure = new FakePaymentToken(0, 18);
        trustedNonEuro = new FakePaymentToken(0, 6);

        vm.startPrank(admin);
        allowList.set(address(eurc), TRUSTED_CURRENCY);
        allowList.set(address(eure), TRUSTED_CURRENCY);
        allowList.set(address(trustedNonEuro), TRUSTED_CURRENCY);
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
        exitLogic = new Exit(trustedForwarder);
        exitFactory = new ExitCloneFactory(address(exitLogic));

        // GlobalTokenExitRegistry
        tokenExitRegistry = new GlobalTokenExitRegistry(trustedForwarder);

        // Deploy default CoinvestedPosition
        coinvestedPosition = _deployCoinvestedPosition(bytes32(0), BASE_PRICE_EURC, eurc, _defaultLeadInvestors());

        // Mint 200 tokens directly to cp
        vm.prank(admin);
        token.mint(address(coinvestedPosition), CP_TOKEN_AMOUNT);
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

    /// @dev Deploy a funded Exit clone for the given currency and price, funding for `tokenAmount` tokens
    function _deployExit(
        bytes32 salt,
        FakePaymentToken exitCurrency,
        uint256 pricePerToken,
        uint256 tokenAmount
    ) internal returns (Exit) {
        uint256 totalCurrency = (tokenAmount * pricePerToken) / (10 ** token.decimals());
        ExitInitializerArguments memory args = ExitInitializerArguments({
            owner: owner,
            token: token,
            currency: IERC20(address(exitCurrency)),
            pricePerToken: pricePerToken,
            claimStart: claimStart,
            lockedUntil: lockedUntil,
            referenceCurrencies: new IERC20[](0),
            referenceToExitRates: new uint256[](0)
        });
        address cloneAddr = exitFactory.predictCloneAddress(salt, trustedForwarder, args);
        exitCurrency.mint(currencyProvider, totalCurrency);
        vm.prank(currencyProvider);
        exitCurrency.approve(cloneAddr, totalCurrency);
        return Exit(exitFactory.createExitClone(salt, trustedForwarder, currencyProvider, args, totalCurrency));
    }

    /// @dev Deploy Exit with explicit initialFundingAmount (may differ from price * amount)
    function _deployExitWithFunding(
        bytes32 salt,
        FakePaymentToken exitCurrency,
        uint256 pricePerToken,
        uint256 initialFundingAmount
    ) internal returns (Exit) {
        ExitInitializerArguments memory args = ExitInitializerArguments({
            owner: owner,
            token: token,
            currency: IERC20(address(exitCurrency)),
            pricePerToken: pricePerToken,
            claimStart: claimStart,
            lockedUntil: lockedUntil,
            referenceCurrencies: new IERC20[](0),
            referenceToExitRates: new uint256[](0)
        });
        address cloneAddr = exitFactory.predictCloneAddress(salt, trustedForwarder, args);
        exitCurrency.mint(currencyProvider, initialFundingAmount);
        vm.prank(currencyProvider);
        exitCurrency.approve(cloneAddr, initialFundingAmount);
        return Exit(exitFactory.createExitClone(salt, trustedForwarder, currencyProvider, args, initialFundingAmount));
    }

    /// @dev Invariant helper: assert sum of payouts equals received and token balance is 0
    function _assertInvariant(
        uint256 received,
        uint256 receiverPayout,
        uint256[] memory leadPayouts,
        address _coinvestedPosition
    ) internal view {
        uint256 sum = receiverPayout;
        for (uint256 i = 0; i < leadPayouts.length; i++) {
            sum += leadPayouts[i];
        }
        assertEq(sum, received, "invariant: sum of payouts != received");
        assertEq(token.balanceOf(_coinvestedPosition), 0, "invariant: cp still holds tokens");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // ── I. Basic Sanity ───────────────────────────────────────────────────────
    // ─────────────────────────────────────────────────────────────────────────

    function testDistributeExitRevertsBeforeClaimStart() public {
        // Deploy an exit with price 200e6, funded for 200 tokens
        Exit exitContract = _deployExit(bytes32("i1"), eurc, 200e6, CP_TOKEN_AMOUNT);

        vm.prank(admin);
        tokenExitRegistry.setExit(token, IExit(address(exitContract)));
        // Do NOT warp — still before claimStart
        vm.expectRevert("exit not yet started");
        vm.prank(owner);
        coinvestedPosition.claimExit(1, 0);
    }

    function testDistributeExitSucceedsAfterDrainStart() public {
        Exit exitContract = _deployExit(bytes32("i2"), eurc, 200e6, CP_TOKEN_AMOUNT);

        vm.warp(lockedUntil + 1);
        vm.prank(admin);
        tokenExitRegistry.setExit(token, IExit(address(exitContract)));
        vm.prank(owner);
        coinvestedPosition.claimExit(1, 0);
    }

    function testDistributeExitRevertsWhenZeroTokens() public {
        Exit exitContract = _deployExit(bytes32("i3"), eurc, 200e6, CP_TOKEN_AMOUNT);

        // Deploy a fresh cp with no tokens minted
        CoinvestedPosition coinvestedPositionEmpty = _deployCoinvestedPosition(
            bytes32("i3empty"),
            BASE_PRICE_EURC,
            eurc,
            _defaultLeadInvestors()
        );

        vm.prank(admin);
        tokenExitRegistry.setExit(token, IExit(address(exitContract)));
        vm.warp(claimStart);
        vm.expectRevert("no tokens to claim");
        vm.prank(owner);
        coinvestedPositionEmpty.claimExit(1, 0);
    }

    function testDistributeExitOnlyOwner() public {
        vm.expectRevert("Ownable: caller is not the owner");
        // called by address(this) which is not owner
        coinvestedPosition.claimExit(1, 0);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // ── II. Same Currency, Same Decimals — Concrete Examples ─────────────────
    // ─────────────────────────────────────────────────────────────────────────

    /// II-A: Exit price above base (carry > 0)
    // 200 tokens × 200e6 EURc/token = 40,000e6; base = 20,000e6; carry = 20,000e6
    // A(10%) = 2,000e6; B(5%) = 1,000e6; receiver = 37,000e6
    function testIIA_ExitAboveBase() public {
        uint256 pricePerToken = 200e6;
        Exit exitContract = _deployExit(bytes32("iia"), eurc, pricePerToken, CP_TOKEN_AMOUNT);

        uint256 beforeA = eurc.balanceOf(leadA);
        uint256 beforeB = eurc.balanceOf(leadB);
        uint256 beforeR = eurc.balanceOf(receiver);

        vm.warp(claimStart);
        vm.prank(admin);
        tokenExitRegistry.setExit(token, IExit(address(exitContract)));
        vm.prank(owner);
        coinvestedPosition.claimExit(1, 0);

        uint256 received = 40_000e6;
        uint256 carry = 20_000e6; // received - basePayout(20,000e6)
        uint256 aGot = eurc.balanceOf(leadA) - beforeA;
        uint256 bGot = eurc.balanceOf(leadB) - beforeB;
        uint256 rGot = eurc.balanceOf(receiver) - beforeR;

        uint256 expectedA = (uint256(CARRY_10PCT) * carry) / type(uint64).max;
        uint256 expectedB = (uint256(CARRY_5PCT) * carry) / type(uint64).max;
        assertEq(aGot, expectedA, "IIA: wrong A payout");
        assertEq(bGot, expectedB, "IIA: wrong B payout");
        // receiver gets full sweep: basePayout + dust from carry
        assertEq(rGot, received - expectedA - expectedB, "IIA: wrong receiver payout");

        // Exit holds tokens
        assertEq(token.balanceOf(address(exitContract)), CP_TOKEN_AMOUNT, "IIA: wrong exit token balance");

        // Invariants
        uint256[] memory payouts = new uint256[](2);
        payouts[0] = aGot;
        payouts[1] = bGot;
        _assertInvariant(received, rGot, payouts, address(coinvestedPosition));
    }

    /// II-B: Exit price equals base (carry = 0)
    function testIIB_ExitAtBase() public {
        uint256 pricePerToken = 100e6; // equals base price
        Exit exitContract = _deployExit(bytes32("iib"), eurc, pricePerToken, CP_TOKEN_AMOUNT);

        uint256 beforeA = eurc.balanceOf(leadA);
        uint256 beforeB = eurc.balanceOf(leadB);
        uint256 beforeR = eurc.balanceOf(receiver);

        vm.warp(claimStart);
        vm.prank(admin);
        tokenExitRegistry.setExit(token, IExit(address(exitContract)));
        vm.prank(owner);
        coinvestedPosition.claimExit(1, 0);

        uint256 received = 20_000e6;
        uint256 aGot = eurc.balanceOf(leadA) - beforeA;
        uint256 bGot = eurc.balanceOf(leadB) - beforeB;
        uint256 rGot = eurc.balanceOf(receiver) - beforeR;

        assertEq(aGot, 0, "IIB: A got non-zero at base price");
        assertEq(bGot, 0, "IIB: B got non-zero at base price");
        assertEq(rGot, 20_000e6, "IIB: wrong receiver payout");

        uint256[] memory payouts = new uint256[](2);
        payouts[0] = aGot;
        payouts[1] = bGot;
        _assertInvariant(received, rGot, payouts, address(coinvestedPosition));
    }

    /// II-C: Exit price below base (carry = 0, shortfall)
    function testIIC_ExitBelowBase() public {
        uint256 pricePerToken = 60e6;
        Exit exitContract = _deployExit(bytes32("iic"), eurc, pricePerToken, CP_TOKEN_AMOUNT);

        uint256 beforeA = eurc.balanceOf(leadA);
        uint256 beforeB = eurc.balanceOf(leadB);
        uint256 beforeR = eurc.balanceOf(receiver);

        vm.warp(claimStart);
        vm.prank(admin);
        tokenExitRegistry.setExit(token, IExit(address(exitContract)));
        vm.prank(owner);
        coinvestedPosition.claimExit(1, 0);

        uint256 received = 12_000e6; // 200 * 60e6 / 1e18 * 1e18 = 12,000e6
        uint256 aGot = eurc.balanceOf(leadA) - beforeA;
        uint256 bGot = eurc.balanceOf(leadB) - beforeB;
        uint256 rGot = eurc.balanceOf(receiver) - beforeR;

        assertEq(aGot, 0, "IIC: A got non-zero below base price");
        assertEq(bGot, 0, "IIC: B got non-zero below base price");
        assertEq(rGot, 12_000e6, "IIC: wrong receiver payout below base price");

        uint256[] memory payouts = new uint256[](2);
        payouts[0] = aGot;
        payouts[1] = bGot;
        _assertInvariant(received, rGot, payouts, address(coinvestedPosition));
    }

    // ─────────────────────────────────────────────────────────────────────────
    // ── III. Cross-Currency Decimal Scaling ───────────────────────────────────
    // ─────────────────────────────────────────────────────────────────────────

    /// III-A: Upscaling — basePrice in EURc (6 dec), exit in EURe (18 dec)
    function testIIIA_UpscalingEURcToEURe() public {
        uint256 pricePerToken = 200e18; // 200 EURe per token
        Exit exitContract = _deployExit(bytes32("iiia"), eure, pricePerToken, CP_TOKEN_AMOUNT);

        uint256 beforeA = eure.balanceOf(leadA);
        uint256 beforeB = eure.balanceOf(leadB);
        uint256 beforeR = eure.balanceOf(receiver);
        uint256 beforeEurc = eurc.balanceOf(address(coinvestedPosition));

        vm.warp(claimStart);
        vm.prank(admin);
        tokenExitRegistry.setExit(token, IExit(address(exitContract)));
        vm.prank(owner);
        coinvestedPosition.claimExit(1, 100e18);

        // received: 200e18 * 200e18 / 1e18 = 40,000e18 EURe
        // basePayout: scaleToDecimals(20,000e6, 18) = 20,000e18 EURe
        // carry = 20,000e18
        uint256 received = 40_000e18;
        uint256 carry = 20_000e18;
        uint256 aGot = eure.balanceOf(leadA) - beforeA;
        uint256 bGot = eure.balanceOf(leadB) - beforeB;
        uint256 rGot = eure.balanceOf(receiver) - beforeR;

        uint256 expectedA = (uint256(CARRY_10PCT) * carry) / type(uint64).max;
        uint256 expectedB = (uint256(CARRY_5PCT) * carry) / type(uint64).max;
        assertEq(aGot, expectedA, "IIIA: wrong A payout in EURe");
        assertEq(bGot, expectedB, "IIIA: wrong B payout in EURe");
        assertEq(rGot, received - expectedA - expectedB, "IIIA: wrong receiver payout in EURe");

        // EURc balance on cp untouched
        assertEq(eurc.balanceOf(address(coinvestedPosition)), beforeEurc, "IIIA: EURc balance changed");

        uint256[] memory payouts = new uint256[](2);
        payouts[0] = aGot;
        payouts[1] = bGot;
        _assertInvariant(received, rGot, payouts, address(coinvestedPosition));
    }

    function _deployEureCp() internal returns (CoinvestedPosition) {
        LeadInvestor[] memory leadInvestors = _defaultLeadInvestors();
        CoinvestedPosition coinvestedPositionEure = _deployCoinvestedPosition(
            bytes32("iiib"),
            100e18,
            eure,
            leadInvestors
        );
        vm.prank(admin);
        token.mint(address(coinvestedPositionEure), CP_TOKEN_AMOUNT);
        return coinvestedPositionEure;
    }

    /// III-B: Downscaling — basePrice in EURe (18 dec), exit in EURc (6 dec)
    function testIIIB_DownscalingEUReToEURc() public {
        CoinvestedPosition coinvestedPositionEure = _deployEureCp();
        Exit exitContract = _deployExit(bytes32("iiib_exit"), eurc, 200e6, CP_TOKEN_AMOUNT);

        uint256 beforeA = eurc.balanceOf(leadA);
        uint256 beforeB = eurc.balanceOf(leadB);
        uint256 beforeR = eurc.balanceOf(receiver);

        vm.warp(claimStart);
        vm.prank(admin);
        tokenExitRegistry.setExit(token, IExit(address(exitContract)));
        vm.prank(owner);
        coinvestedPositionEure.claimExit(1, 100e6);

        // received: 200e18 * 200e6 / 1e18 = 40,000e6 EURc
        // basePayout: scaleToDecimals(20,000e18, 6) = 20,000e6 EURc; carry = 20,000e6
        _checkIIIB(beforeA, beforeB, beforeR, address(coinvestedPositionEure));
    }

    function _checkIIIB(uint256 beforeA, uint256 beforeB, uint256 beforeR, address cpAddr) internal view {
        uint256 received = 40_000e6;
        uint256 carry = 20_000e6;
        uint256 aGot = eurc.balanceOf(leadA) - beforeA;
        uint256 bGot = eurc.balanceOf(leadB) - beforeB;
        uint256 rGot = eurc.balanceOf(receiver) - beforeR;
        uint256 expectedA = (uint256(CARRY_10PCT) * carry) / type(uint64).max;
        uint256 expectedB = (uint256(CARRY_5PCT) * carry) / type(uint64).max;
        assertEq(aGot, expectedA, "IIIB: wrong A payout downscaled");
        assertEq(bGot, expectedB, "IIIB: wrong B payout downscaled");
        assertEq(rGot, received - expectedA - expectedB, "IIIB: wrong receiver payout downscaled");
        uint256[] memory payouts = new uint256[](2);
        payouts[0] = aGot;
        payouts[1] = bGot;
        _assertInvariant(received, rGot, payouts, cpAddr);
    }

    /// III-C: Equal decimals — scaleToDecimals returns unchanged amount
    /// (same as II-A but confirms no rounding artifacts when decimals match)
    function testIIIC_EqualDecimalsNoScaling() public {
        // baseCurrency = EURc (6 dec), exit currency = EURc (6 dec)
        uint256 pricePerToken = 200e6;
        Exit exitContract = _deployExit(bytes32("iiic"), eurc, pricePerToken, CP_TOKEN_AMOUNT);

        vm.warp(claimStart);
        vm.prank(admin);
        tokenExitRegistry.setExit(token, IExit(address(exitContract)));
        vm.prank(owner);
        coinvestedPosition.claimExit(1, 0);

        // Same as II-A — using formula-based expected values to confirm no double-scaling
        uint256 carryIIIC = 20_000e6;
        assertEq(eurc.balanceOf(leadA), (uint256(CARRY_10PCT) * carryIIIC) / type(uint64).max, "IIIC: wrong A payout");
        assertEq(eurc.balanceOf(leadB), (uint256(CARRY_5PCT) * carryIIIC) / type(uint64).max, "IIIC: wrong B payout");
        assertEq(token.balanceOf(address(coinvestedPosition)), 0, "IIIC: cp still holds tokens");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // ── IV. Multiple Lead Investors and Carry Fraction Precision ──────────────
    // ─────────────────────────────────────────────────────────────────────────

    /// IV-A: Three lead investors, non-round fractions
    /// A=17%, B=11%, C=3%; pricePerToken=600e6 so received=120,000e6; base=20,000e6; carry=100,000e6
    // carry fractions for IV-A test (constants to avoid stack pressure)
    uint64 internal constant IVA_FRAC_A = uint64((uint256(type(uint64).max) * 17) / 100);
    uint64 internal constant IVA_FRAC_B = uint64((uint256(type(uint64).max) * 11) / 100);
    uint64 internal constant IVA_FRAC_C = uint64((uint256(type(uint64).max) * 3) / 100);

    function _deployThreeInvestorCp() internal returns (CoinvestedPosition) {
        LeadInvestor[] memory leadInvestors = new LeadInvestor[](3);
        leadInvestors[0] = LeadInvestor({account: leadA, carryFraction: IVA_FRAC_A});
        leadInvestors[1] = LeadInvestor({account: leadB, carryFraction: IVA_FRAC_B});
        leadInvestors[2] = LeadInvestor({account: leadC, carryFraction: IVA_FRAC_C});
        CoinvestedPosition coinvestedPosition3 = _deployCoinvestedPosition(
            bytes32("iva"),
            BASE_PRICE_EURC,
            eurc,
            leadInvestors
        );
        vm.prank(admin);
        token.mint(address(coinvestedPosition3), CP_TOKEN_AMOUNT);
        return coinvestedPosition3;
    }

    /// IV-A: Three lead investors, non-round fractions
    /// A=17%, B=11%, C=3%; pricePerToken=600e6 so received=120,000e6; base=20,000e6; carry=100,000e6
    function testIVA_ThreeLeadInvestors() public {
        CoinvestedPosition coinvestedPosition3 = _deployThreeInvestorCp();
        Exit exitContract = _deployExit(bytes32("iva_exit"), eurc, 600e6, CP_TOKEN_AMOUNT);

        uint256 beforeA = eurc.balanceOf(leadA);
        uint256 beforeB = eurc.balanceOf(leadB);
        uint256 beforeC = eurc.balanceOf(leadC);
        uint256 beforeR = eurc.balanceOf(receiver);

        vm.warp(claimStart);
        vm.prank(admin);
        tokenExitRegistry.setExit(token, IExit(address(exitContract)));
        vm.prank(owner);
        coinvestedPosition3.claimExit(1, 0);

        _checkIVA(beforeA, beforeB, beforeC, beforeR, eurc.balanceOf(receiver) - beforeR, address(coinvestedPosition3));
    }

    function _checkIVA(
        // view helper
        uint256 beforeA,
        uint256 beforeB,
        uint256 beforeC,
        uint256 /* beforeR */,
        uint256 rGot,
        address coinvestedPosition3Addr
    ) internal view {
        uint256 carry = 100_000e6;
        uint256 received = 120_000e6;
        uint256 aGot = eurc.balanceOf(leadA) - beforeA;
        uint256 bGot = eurc.balanceOf(leadB) - beforeB;
        uint256 cGot = eurc.balanceOf(leadC) - beforeC;

        assertEq(aGot, (uint256(IVA_FRAC_A) * carry) / type(uint64).max, "IVA: wrong A payout");
        assertEq(bGot, (uint256(IVA_FRAC_B) * carry) / type(uint64).max, "IVA: wrong B payout");
        assertEq(cGot, (uint256(IVA_FRAC_C) * carry) / type(uint64).max, "IVA: wrong C payout");

        uint256[] memory payouts = new uint256[](3);
        payouts[0] = aGot;
        payouts[1] = bGot;
        payouts[2] = cGot;
        _assertInvariant(received, rGot, payouts, coinvestedPosition3Addr);
    }

    /// IV-B: Single lead investor with ~99.9% carry
    function testIVB_SingleLeadNearMaxCarry() public {
        // carryFraction = type(uint64).max - 1  (≈ 100%, just below the max limit)
        uint64 fracNearMax = type(uint64).max - 1;
        LeadInvestor[] memory leadInvestors = new LeadInvestor[](1);
        leadInvestors[0] = LeadInvestor({account: leadA, carryFraction: fracNearMax});

        CoinvestedPosition coinvestedPositionSingle = _deployCoinvestedPosition(
            bytes32("ivb"),
            BASE_PRICE_EURC,
            eurc,
            leadInvestors
        );
        vm.prank(admin);
        token.mint(address(coinvestedPositionSingle), CP_TOKEN_AMOUNT);

        uint256 pricePerToken = 200e6;
        Exit exitContract = _deployExit(bytes32("ivb_exit"), eurc, pricePerToken, CP_TOKEN_AMOUNT);

        uint256 beforeA = eurc.balanceOf(leadA);
        uint256 beforeR = eurc.balanceOf(receiver);

        vm.warp(claimStart);
        vm.prank(admin);
        tokenExitRegistry.setExit(token, IExit(address(exitContract)));
        vm.prank(owner);
        coinvestedPositionSingle.claimExit(1, 0);

        uint256 received = 40_000e6;
        uint256 carry = 20_000e6; // received - basePayout
        uint256 aGot = eurc.balanceOf(leadA) - beforeA;
        uint256 rGot = eurc.balanceOf(receiver) - beforeR;

        uint256 expectedA = (uint256(fracNearMax) * carry) / type(uint64).max;
        assertEq(aGot, expectedA, "IVB: wrong A near-max carry payout");

        uint256[] memory payouts = new uint256[](1);
        payouts[0] = aGot;
        _assertInvariant(received, rGot, payouts, address(coinvestedPositionSingle));
    }

    // ─────────────────────────────────────────────────────────────────────────
    // ── V. Fee Scenarios ──────────────────────────────────────────────────────
    // ─────────────────────────────────────────────────────────────────────────

    /// @dev Deploys a Token with 0.1% fee setting + a CoinvestedPosition for it,
    ///      mints CP_TOKEN_AMOUNT tokens to that coinvestedPosition, returns (token, cp).
    function _deployFeeTokenAndCp() internal returns (Token, CoinvestedPosition) {
        IFeeSettingsV2 fsWithFee = createFeeSettings(
            trustedForwarder,
            admin,
            buildFeeTypes(0, 10, 0, feeCollector, feeCollector, feeCollector)
        );
        Token tokenWithFee = Token(
            tokenFactory.createTokenProxy(
                bytes32("fee_token"),
                trustedForwarder,
                fsWithFee,
                admin,
                allowList,
                0,
                "FeeToken",
                "FTK"
            )
        );
        vm.startPrank(admin);
        tokenWithFee.grantRole(tokenWithFee.MINTALLOWER_ROLE(), admin);
        vm.stopPrank();

        CoinvestedPositionInitializerArguments memory coinvestedPositionArgs = CoinvestedPositionInitializerArguments({
            owner: owner,
            receiver: receiver,
            leadInvestors: _defaultLeadInvestors(),
            basePrice: BASE_PRICE_EURC,
            baseCurrency: IERC20(address(eurc)),
            token: tokenWithFee,
            lockedUntil: 0,
            tokenExitRegistry: tokenExitRegistry
        });
        CoinvestedPosition coinvestedPositionFee = CoinvestedPosition(
            coinvestedPositionFactory.createCoinvestedPositionClone(
                bytes32("v_cp"),
                trustedForwarder,
                coinvestedPositionArgs
            )
        );
        vm.prank(admin);
        tokenWithFee.mint(address(coinvestedPositionFee), CP_TOKEN_AMOUNT);
        return (tokenWithFee, coinvestedPositionFee);
    }

    /// @dev Deploys an Exit for `_token` using eurc at 200e6 price for CP_TOKEN_AMOUNT tokens
    function _deployFeeExit(Token _token) internal returns (Exit) {
        uint256 totalCurrency = (CP_TOKEN_AMOUNT * 200e6) / (10 ** _token.decimals());
        ExitInitializerArguments memory exitArgs = ExitInitializerArguments({
            owner: owner,
            token: _token,
            currency: IERC20(address(eurc)),
            pricePerToken: 200e6,
            claimStart: claimStart,
            lockedUntil: lockedUntil,
            referenceCurrencies: new IERC20[](0),
            referenceToExitRates: new uint256[](0)
        });
        address cloneAddr = exitFactory.predictCloneAddress(bytes32("v_exit"), trustedForwarder, exitArgs);
        eurc.mint(currencyProvider, totalCurrency);
        vm.prank(currencyProvider);
        eurc.approve(cloneAddr, totalCurrency);
        return
            Exit(
                exitFactory.createExitClone(
                    bytes32("v_exit"),
                    trustedForwarder,
                    currencyProvider,
                    exitArgs,
                    totalCurrency
                )
            );
    }

    /// V: claimExit does NOT apply fees — full received amount is distributed
    function testV_NoFeeDeductedInDistributeExit() public {
        (Token tokenWithFee, CoinvestedPosition coinvestedPositionFee) = _deployFeeTokenAndCp();
        Exit exitContract = _deployFeeExit(tokenWithFee);

        uint256 beforeA = eurc.balanceOf(leadA);
        uint256 beforeB = eurc.balanceOf(leadB);
        uint256 beforeR = eurc.balanceOf(receiver);

        vm.warp(claimStart);
        vm.prank(admin);
        tokenExitRegistry.setExit(tokenWithFee, IExit(address(exitContract)));
        vm.prank(owner);
        coinvestedPositionFee.claimExit(1, 0);

        // Full 40,000e6 distributed; no fee deducted
        uint256 received = 40_000e6;
        uint256 aGot = eurc.balanceOf(leadA) - beforeA;
        uint256 bGot = eurc.balanceOf(leadB) - beforeB;
        uint256 rGot = eurc.balanceOf(receiver) - beforeR;

        // If fees were wrongly applied, A+B+receiver would be < received
        uint256[] memory payouts = new uint256[](2);
        payouts[0] = aGot;
        payouts[1] = bGot;
        _assertInvariant(received, rGot, payouts, address(coinvestedPositionFee));
    }

    // ─────────────────────────────────────────────────────────────────────────
    // ── VI. Pre-existing Currency Balance ────────────────────────────────────
    // ─────────────────────────────────────────────────────────────────────────

    /// VI-A: CoinvestedPosition already holds exitCurrency before claimExit()
    /// Pre-existing 500e6 EURc should NOT inflate carry; receiver sweeps it too
    function testVIA_PreExistingExitCurrencyBalance() public {
        uint256 pricePerToken = 200e6;
        Exit exitContract = _deployExit(bytes32("via"), eurc, pricePerToken, CP_TOKEN_AMOUNT);

        // Send 500e6 EURc directly to cp before the call
        uint256 preExisting = 500e6;
        eurc.mint(address(coinvestedPosition), preExisting);

        uint256 beforeA = eurc.balanceOf(leadA);
        uint256 beforeB = eurc.balanceOf(leadB);
        uint256 beforeR = eurc.balanceOf(receiver);

        vm.warp(claimStart);
        vm.prank(admin);
        tokenExitRegistry.setExit(token, IExit(address(exitContract)));
        vm.prank(owner);
        coinvestedPosition.claimExit(1, 0);

        // received computed via before-snapshot excludes the 500e6 pre-existing
        // => received = 40,000e6; carry = 20,000e6; A=2,000; B=1,000; receiver gets 37,000 + 500 = 37,500
        uint256 aGot = eurc.balanceOf(leadA) - beforeA;
        uint256 bGot = eurc.balanceOf(leadB) - beforeB;
        uint256 rGot = eurc.balanceOf(receiver) - beforeR;

        uint256 carry = 20_000e6;
        uint256 expectedA = (uint256(CARRY_10PCT) * carry) / type(uint64).max;
        uint256 expectedB = (uint256(CARRY_5PCT) * carry) / type(uint64).max;
        assertEq(aGot, expectedA, "VIA: A was inflated by pre-existing");
        assertEq(bGot, expectedB, "VIA: B was inflated by pre-existing");
        // receiver gets: (received - A - B) + preExisting (via sweep)
        assertEq(rGot, (40_000e6 - expectedA - expectedB) + preExisting, "VIA: wrong receiver payout");

        // Sum = A + B + receiver = received + preExisting
        uint256 totalOut = aGot + bGot + rGot;
        assertEq(totalOut, 40_000e6 + preExisting, "VIA: total does not equal received + pre-existing");
        assertEq(token.balanceOf(address(coinvestedPosition)), 0, "VIA: cp still holds tokens");
    }

    /// VI-B: CoinvestedPosition holds a different currency; that currency is untouched
    function testVIB_DifferentCurrencyUntouched() public {
        uint256 pricePerToken = 200e6;
        Exit exitContract = _deployExit(bytes32("vib"), eurc, pricePerToken, CP_TOKEN_AMOUNT);

        // Send 1000e18 EURe to cp
        uint256 eureAmount = 1_000e18;
        eure.mint(address(coinvestedPosition), eureAmount);

        uint256 eureBalanceBefore = eure.balanceOf(address(coinvestedPosition));

        vm.warp(claimStart);
        vm.prank(admin);
        tokenExitRegistry.setExit(token, IExit(address(exitContract)));
        vm.prank(owner);
        coinvestedPosition.claimExit(1, 0);

        // EURe balance on cp is unchanged
        assertEq(eure.balanceOf(address(coinvestedPosition)), eureBalanceBefore, "VIB: EURe balance changed");
        assertEq(token.balanceOf(address(coinvestedPosition)), 0, "VIB: cp still holds tokens");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // ── VII. Exit Contract Funding Edge Cases ─────────────────────────────────
    // ─────────────────────────────────────────────────────────────────────────

    /// VII-A: Exit underfunded — third party drains most, cp can't claim
    function testVIIA_ExitUnderfunded() public {
        uint256 pricePerToken = 200e6;
        // Fund only for 50 tokens (not enough for cp's 200)
        uint256 onlyFifty = (50e18 * pricePerToken) / (10 ** token.decimals()); // 10,000e6
        Exit exitContract = _deployExitWithFunding(bytes32("viia"), eurc, pricePerToken, onlyFifty);

        uint256 cpTokensBefore = token.balanceOf(address(coinvestedPosition));

        vm.prank(admin);
        tokenExitRegistry.setExit(token, IExit(address(exitContract)));
        vm.warp(claimStart);
        vm.expectRevert("ERC20: transfer amount exceeds balance");
        vm.prank(owner);
        coinvestedPosition.claimExit(1, 0);

        // cp retains its tokens
        assertEq(token.balanceOf(address(coinvestedPosition)), cpTokensBefore, "VIIA: cp lost tokens despite revert");
    }

    /// VII-B: Exit funded for exactly the right amount
    function testVIIB_ExitExactlyFunded() public {
        uint256 pricePerToken = 200e6;
        // Exact: 200 tokens × 200e6 = 40,000e6
        Exit exitContract = _deployExit(bytes32("viib"), eurc, pricePerToken, CP_TOKEN_AMOUNT);

        vm.warp(claimStart);
        vm.prank(admin);
        tokenExitRegistry.setExit(token, IExit(address(exitContract)));
        vm.prank(owner);
        coinvestedPosition.claimExit(1, 0);

        // Exit currency balance = 0 after full claim
        assertEq(eurc.balanceOf(address(exitContract)), 0, "VIIB: exit EURc not fully exhausted");
        assertEq(token.balanceOf(address(coinvestedPosition)), 0, "VIIB: cp still holds tokens");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // ── VIII. Token Approval ──────────────────────────────────────────────────
    // ─────────────────────────────────────────────────────────────────────────

    /// VIII: claimExit approves and transfers exactly tokenBalance; cp holds 0 tokens after
    function testVIII_TokenApprovalAndTransfer() public {
        uint256 pricePerToken = 200e6;
        Exit exitContract = _deployExit(bytes32("viii"), eurc, pricePerToken, CP_TOKEN_AMOUNT);

        assertEq(token.balanceOf(address(coinvestedPosition)), CP_TOKEN_AMOUNT, "VIII: wrong cp token balance before");

        vm.warp(claimStart);
        vm.prank(admin);
        tokenExitRegistry.setExit(token, IExit(address(exitContract)));
        vm.prank(owner);
        coinvestedPosition.claimExit(1, 0);

        assertEq(token.balanceOf(address(coinvestedPosition)), 0, "VIII: cp still holds tokens after");
        assertEq(token.balanceOf(address(exitContract)), CP_TOKEN_AMOUNT, "VIII: exit does not hold tokens");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // ── IX. Fuzz Tests ────────────────────────────────────────────────────────
    // ─────────────────────────────────────────────────────────────────────────

    /// IX-A: Fuzz over tokenBalance, pricePerToken, basePrice; verify sum invariant
    function testFuzz_SumInvariantSingleCurrency(uint128 tokenBalance, uint64 pricePerToken, uint64 basePrice) public {
        vm.assume(tokenBalance > 0 && tokenBalance <= 1000e18);
        vm.assume(pricePerToken > 0);
        vm.assume(basePrice > 0);

        // Deploy cp with fuzzed basePrice using EURc (6 dec)
        LeadInvestor[] memory leadInvestors = _defaultLeadInvestors();
        CoinvestedPosition coinvestedPositionFuzz = _deployCoinvestedPosition(
            bytes32("fuzz_a"),
            uint256(basePrice),
            eurc,
            leadInvestors
        );
        vm.prank(admin);
        token.mint(address(coinvestedPositionFuzz), tokenBalance);

        uint256 totalCurrency = (uint256(tokenBalance) * uint256(pricePerToken)) / (10 ** token.decimals());
        vm.assume(totalCurrency > 0); // skip dust amounts

        // Deploy exit
        ExitInitializerArguments memory exitArgs = ExitInitializerArguments({
            owner: owner,
            token: token,
            currency: IERC20(address(eurc)),
            pricePerToken: uint256(pricePerToken),
            claimStart: claimStart,
            lockedUntil: lockedUntil,
            referenceCurrencies: new IERC20[](0),
            referenceToExitRates: new uint256[](0)
        });
        address cloneAddr = exitFactory.predictCloneAddress(bytes32("fuzz_a_exit"), trustedForwarder, exitArgs);
        eurc.mint(currencyProvider, totalCurrency);
        vm.prank(currencyProvider);
        eurc.approve(cloneAddr, totalCurrency);
        Exit exitContract = Exit(
            exitFactory.createExitClone(
                bytes32("fuzz_a_exit"),
                trustedForwarder,
                currencyProvider,
                exitArgs,
                totalCurrency
            )
        );

        uint256 beforeA = eurc.balanceOf(leadA);
        uint256 beforeB = eurc.balanceOf(leadB);
        uint256 beforeR = eurc.balanceOf(receiver);

        vm.warp(claimStart);
        vm.prank(admin);
        tokenExitRegistry.setExit(token, IExit(address(exitContract)));
        vm.prank(owner);
        coinvestedPositionFuzz.claimExit(1, 0);

        uint256 aGot = eurc.balanceOf(leadA) - beforeA;
        uint256 bGot = eurc.balanceOf(leadB) - beforeB;
        uint256 rGot = eurc.balanceOf(receiver) - beforeR;

        uint256[] memory payouts = new uint256[](2);
        payouts[0] = aGot;
        payouts[1] = bGot;
        _assertInvariant(totalCurrency, rGot, payouts, address(coinvestedPositionFuzz));
    }

    /// IX-B: Fuzz pre-existing exitCurrency balance; carry unaffected; receiver sweeps all
    function testFuzz_PreExistingBalance(uint64 preExisting) public {
        vm.assume(preExisting > 0);

        uint256 pricePerToken = 200e6;
        Exit exitContract = _deployExit(bytes32("fuzz_b"), eurc, pricePerToken, CP_TOKEN_AMOUNT);

        // Send pre-existing EURc to cp
        eurc.mint(address(coinvestedPosition), preExisting);

        uint256 beforeA = eurc.balanceOf(leadA);
        uint256 beforeB = eurc.balanceOf(leadB);
        uint256 beforeR = eurc.balanceOf(receiver);

        vm.warp(claimStart);
        vm.prank(admin);
        tokenExitRegistry.setExit(token, IExit(address(exitContract)));
        vm.prank(owner);
        coinvestedPosition.claimExit(1, 0);

        uint256 received = 40_000e6; // snapshot-based, excludes preExisting
        uint256 carry = 20_000e6;
        uint256 aGot = eurc.balanceOf(leadA) - beforeA;
        uint256 bGot = eurc.balanceOf(leadB) - beforeB;
        uint256 rGot = eurc.balanceOf(receiver) - beforeR;

        // A and B should be based only on received carry
        uint256 expectedA = (uint256(CARRY_10PCT) * carry) / type(uint64).max;
        uint256 expectedB = (uint256(CARRY_5PCT) * carry) / type(uint64).max;
        assertEq(aGot, expectedA, "IX-B: A carry was affected by preExisting");
        assertEq(bGot, expectedB, "IX-B: B carry was affected by preExisting");

        // Sum check: A + B + receiver = received + preExisting (receiver sweeps all)
        assertEq(aGot + bGot + rGot, received + uint256(preExisting), "IX-B: wrong total sum");
        assertEq(token.balanceOf(address(coinvestedPosition)), 0, "IX-B: cp still holds tokens");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // ── X. Interaction Ordering: buy() then claimExit() ─────────────────
    // ─────────────────────────────────────────────────────────────────────────

    /// X: buy() sells 50 tokens first, then claimExit() uses remaining 150 tokens
    function testX_BuyThenDistributeExit() public {
        // Setup: cp holds 200 tokens (from setUp)
        // Set token price and unpause so buy() works
        uint256 tokenPriceForBuy = 150e6; // 150 EURc per token
        vm.prank(owner);
        coinvestedPosition.setTokenPrice(tokenPriceForBuy);
        vm.prank(owner);
        coinvestedPosition.unpause();

        // Fund buyer and buy 50 tokens
        uint256 buyAmount = 50e18;
        // Use ceilDiv like the contract
        uint256 buyCostCeil = (buyAmount * tokenPriceForBuy + (10 ** token.decimals()) - 1) / (10 ** token.decimals());
        eurc.mint(buyer, buyCostCeil);
        vm.prank(buyer);
        eurc.approve(address(coinvestedPosition), buyCostCeil);

        vm.prank(buyer);
        coinvestedPosition.buy(buyAmount, buyCostCeil, buyer);

        // cp now holds 150 tokens
        uint256 remainingTokens = 150e18;
        assertEq(token.balanceOf(address(coinvestedPosition)), remainingTokens, "X: wrong cp token balance after buy");

        // Deploy exit for remaining 150 tokens at 200e6
        uint256 pricePerToken = 200e6;
        uint256 totalCurrency = (remainingTokens * pricePerToken) / (10 ** token.decimals()); // 30,000e6
        ExitInitializerArguments memory exitArgs = ExitInitializerArguments({
            owner: owner,
            token: token,
            currency: IERC20(address(eurc)),
            pricePerToken: pricePerToken,
            claimStart: claimStart,
            lockedUntil: lockedUntil,
            referenceCurrencies: new IERC20[](0),
            referenceToExitRates: new uint256[](0)
        });
        address cloneAddr = exitFactory.predictCloneAddress(bytes32("x_exit"), trustedForwarder, exitArgs);
        eurc.mint(currencyProvider, totalCurrency);
        vm.prank(currencyProvider);
        eurc.approve(cloneAddr, totalCurrency);
        Exit exitContract = Exit(
            exitFactory.createExitClone(bytes32("x_exit"), trustedForwarder, currencyProvider, exitArgs, totalCurrency)
        );

        // Snapshot balances before exit (cp may have EURc from buy() proceeds — receiver already got them via settle)
        uint256 beforeA = eurc.balanceOf(leadA);
        uint256 beforeB = eurc.balanceOf(leadB);
        uint256 beforeR = eurc.balanceOf(receiver);

        vm.warp(claimStart);
        vm.prank(admin);
        tokenExitRegistry.setExit(token, IExit(address(exitContract)));
        vm.prank(owner);
        coinvestedPosition.claimExit(1, 0);

        // received = 150e18 * 200e6 / 1e18 = 30,000e6
        // basePayout = scaleToDecimals((100e6 * 150e18) / 1e18, 6) = 15,000e6
        // carry = 15,000e6
        // A(10%) = 1,500e6; B(5%) = 750e6; receiver = 27,750e6
        uint256 received = 30_000e6;
        uint256 carry = 15_000e6;
        uint256 expectedA = (uint256(CARRY_10PCT) * carry) / type(uint64).max;
        uint256 expectedB = (uint256(CARRY_5PCT) * carry) / type(uint64).max;

        uint256 aGot = eurc.balanceOf(leadA) - beforeA;
        uint256 bGot = eurc.balanceOf(leadB) - beforeB;
        uint256 rGot = eurc.balanceOf(receiver) - beforeR;

        assertEq(aGot, expectedA, "X: wrong A payout for 150 tokens");
        assertEq(bGot, expectedB, "X: wrong B payout for 150 tokens");

        uint256[] memory payouts = new uint256[](2);
        payouts[0] = aGot;
        payouts[1] = bGot;
        _assertInvariant(received, rGot, payouts, address(coinvestedPosition));
    }

    // ─────────────────────────────────────────────────────────────────────────
    // ── Key Invariant: No tokens remain in cp after any successful exit ───────
    // ─────────────────────────────────────────────────────────────────────────

    function testKeyInvariant_TokenBalanceZeroAfterExit() public {
        Exit exitContract = _deployExit(bytes32("ki"), eurc, 200e6, CP_TOKEN_AMOUNT);

        vm.warp(claimStart);
        vm.prank(admin);
        tokenExitRegistry.setExit(token, IExit(address(exitContract)));
        vm.prank(owner);
        coinvestedPosition.claimExit(1, 0);

        assertEq(token.balanceOf(address(coinvestedPosition)), 0, "KI: cp still holds tokens after exit");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // ── XI. _minCurrencyAmount enforcement ───────────────────────────────────
    // ─────────────────────────────────────────────────────────────────────────

    /// XI-A: reverts when received < _minCurrencyAmount
    function testXIA_MinCurrencyAmountReverts() public {
        uint256 pricePerToken = 200e6;
        uint256 totalCurrency = (CP_TOKEN_AMOUNT * pricePerToken) / (10 ** token.decimals()); // 40,000e6
        Exit exitContract = _deployExit(bytes32("xia"), eurc, pricePerToken, CP_TOKEN_AMOUNT);

        vm.prank(admin);
        tokenExitRegistry.setExit(token, IExit(address(exitContract)));
        vm.warp(claimStart);
        vm.prank(owner);
        vm.expectRevert("payout below minimum");
        coinvestedPosition.claimExit(totalCurrency + 1, 0);
    }

    /// XI-B: succeeds when received == _minCurrencyAmount (exact boundary)
    function testXIB_MinCurrencyAmountExactBoundarySucceeds() public {
        uint256 pricePerToken = 200e6;
        uint256 totalCurrency = (CP_TOKEN_AMOUNT * pricePerToken) / (10 ** token.decimals()); // 40,000e6
        Exit exitContract = _deployExit(bytes32("xib"), eurc, pricePerToken, CP_TOKEN_AMOUNT);

        vm.warp(claimStart);
        vm.prank(admin);
        tokenExitRegistry.setExit(token, IExit(address(exitContract)));
        vm.prank(owner);
        coinvestedPosition.claimExit(totalCurrency, 0);

        assertEq(token.balanceOf(address(coinvestedPosition)), 0, "XIB: cp still holds tokens after exit");
    }

    /// XI-C: zero _minCurrencyAmount always passes (backwards-compatible floor)
    function testXIC_ZeroMinCurrencyAmountAlwaysPasses() public {
        uint256 pricePerToken = 200e6;
        Exit exitContract = _deployExit(bytes32("xic"), eurc, pricePerToken, CP_TOKEN_AMOUNT);

        vm.warp(claimStart);
        vm.prank(admin);
        tokenExitRegistry.setExit(token, IExit(address(exitContract)));
        vm.prank(owner);
        coinvestedPosition.claimExit(0, 0);

        assertEq(token.balanceOf(address(coinvestedPosition)), 0, "XIC: cp still holds tokens after exit");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // ── XII. _settle rejects currency == held token ───────────────────────────
    // ─────────────────────────────────────────────────────────────────────────

    /// XII: claimExit reverts when exitCurrency is the held token.
    /// Uses a no-op Exit stub so received == 0 (>= _minCurrencyAmount 0), reaching _settle.
    function testXII_DistributeExitRevertsWhenCurrencyIsHeldToken() public {
        // Give the equity token TRUSTED_CURRENCY to pass the exit currency check
        vm.prank(admin);
        allowList.set(address(token), TRUSTED_CURRENCY);

        NoOpExit noOpExit = new NoOpExit(IERC20(address(token)));

        vm.prank(admin);
        tokenExitRegistry.setExit(token, IExit(address(noOpExit)));
        vm.expectRevert("currency cannot be the held token");
        vm.prank(owner);
        coinvestedPosition.claimExit(0, 1);
    }

    /// XI-D: fuzz — reverts iff _minCurrencyAmount > received; succeeds otherwise
    function testFuzz_MinCurrencyAmountEnforcement(uint64 minCurrencyAmount) public {
        uint256 pricePerToken = 200e6;
        uint256 received = (CP_TOKEN_AMOUNT * pricePerToken) / (10 ** token.decimals()); // 40,000e6

        LeadInvestor[] memory leadInvestors = _defaultLeadInvestors();
        CoinvestedPosition coinvestedPositionFuzz = _deployCoinvestedPosition(
            bytes32("xid"),
            uint256(100e6),
            eurc,
            leadInvestors
        );
        vm.prank(admin);
        token.mint(address(coinvestedPositionFuzz), CP_TOKEN_AMOUNT);

        Exit exitContract = _deployExit(bytes32("xid_exit"), eurc, pricePerToken, CP_TOKEN_AMOUNT);

        vm.prank(admin);
        tokenExitRegistry.setExit(token, IExit(address(exitContract)));
        vm.warp(claimStart);
        vm.prank(owner);
        if (uint256(minCurrencyAmount) > received) {
            vm.expectRevert("payout below minimum");
        }
        coinvestedPositionFuzz.claimExit(uint256(minCurrencyAmount), 0);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // ── XIII. minPayout passthrough ──────────────────────────────────────────
    // ─────────────────────────────────────────────────────────────────────────

    /// XIII-B: FixedPayoutExit pays exactly _minCurrencyAmount → succeeds
    function testXIII_BalanceDiffAcceptsExactMinimum() public {
        uint256 minCurrencyAmount = 1e6;
        eurc.mint(address(this), minCurrencyAmount);
        FixedPayoutExit stub = new FixedPayoutExit(IERC20(address(eurc)), minCurrencyAmount);
        IERC20(address(eurc)).transfer(address(stub), minCurrencyAmount);
        vm.prank(admin);
        tokenExitRegistry.setExit(token, IExit(address(stub)));

        vm.prank(owner);
        coinvestedPosition.claimExit(minCurrencyAmount, 0);
        assertEq(eurc.balanceOf(address(coinvestedPosition)), 0, "cp should hold no eurc after settle");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // ── XV. Full cross-currency carry scenario ────────────────────────────────
    // ─────────────────────────────────────────────────────────────────────────

    /// Cross-currency carry: CP in EURe, exit in USDC, conversion stored in Exit.
    ///
    /// Setup:
    ///   10 tokens, base price 10 EURe/token (total 100 EURe invested)
    ///   Exit price: 300 USDC/token → received = 3000 USDC
    ///   Conversion: 1 EURe = 5 USDC  (referenceToExitRate[EURe] = 5e6)
    ///
    /// Derivation:
    ///   effectiveBasePrice = 10e18 EURe/tok × 5e6 USDC/EURe / 1e18 = 50e6 USDC/tok
    ///   basePayout  = 50e6 × 10 tokens = 500 USDC  (= 100 EURe × 5)
    ///   carry       = 3000 − 500       = 2500 USDC  (≡ 500 EURe at 5 USDC/EURe)
    ///   investor A (10%) → 250 USDC    (≡ 50 EURe in value)
    ///   investor B  (5%) → 125 USDC    (≡ 25 EURe in value)
    function testXV_CrossCurrencyCarryScenario() public {
        // 10 tokens, base price 10 EURe/token (100 EURe total)
        // Exit: 300 USDC/token, 1 EURe = 5 USDC stored in exit
        // received = 3000 USDC, basePayout = 500 USDC (100 EURe × 5)
        // carry = 2500 USDC (= 500 EURe equiv); investor A (10%) → 250 USDC (= 50 EURe)
        CoinvestedPosition coinvestedPositionEure = _deployCoinvestedPosition(
            bytes32("xv"),
            10e18,
            eure,
            _defaultLeadInvestors()
        );
        vm.prank(admin);
        token.mint(address(coinvestedPositionEure), 10e18);

        // trustedNonEuro (6 dec) serves as USDC stand-in; rate = 5e6 USDC bits per 10^18 EURe bits
        Exit exitContract = _deployExitWithReferenceRate(
            bytes32("xv_exit"),
            trustedNonEuro,
            300e6,
            10e18,
            IERC20(address(eure)),
            5e6
        );

        uint256 beforeA = trustedNonEuro.balanceOf(leadA);
        uint256 beforeB = trustedNonEuro.balanceOf(leadB);
        uint256 beforeR = trustedNonEuro.balanceOf(receiver);

        vm.warp(claimStart);
        vm.prank(admin);
        tokenExitRegistry.setExit(token, IExit(address(exitContract)));
        vm.prank(owner);
        coinvestedPositionEure.claimExit(1, 0); // _basePrice=0: rate is auto-looked up from exit

        // 3000e6 received − 500e6 basePayout
        // carry = 2500e6
        uint256 aGot = trustedNonEuro.balanceOf(leadA) - beforeA;
        uint256 bGot = trustedNonEuro.balanceOf(leadB) - beforeB;
        uint256 rGot = trustedNonEuro.balanceOf(receiver) - beforeR;

        assertEq(aGot, 250e6 - 1, "XV: wrong investor A payout");
        assertEq(bGot, 125e6 - 1, "XV: wrong investor B payout");
        assertEq(rGot, 2625e6 + 2, "wrong coinvestor payout");
        uint256[] memory payouts = new uint256[](2);
        payouts[0] = aGot;
        payouts[1] = bGot;
        _assertInvariant(3000e6, rGot, payouts, address(coinvestedPositionEure));
    }

    // ─────────────────────────────────────────────────────────────────────────
    // ── XIV. Reference Currency Rate Auto-Lookup ─────────────────────────────
    // ─────────────────────────────────────────────────────────────────────────

    /// @dev Deploy an Exit with a single reference currency rate set
    function _deployExitWithReferenceRate(
        bytes32 salt,
        FakePaymentToken exitCurrency,
        uint256 pricePerToken,
        uint256 tokenAmount,
        IERC20 referenceCurrency,
        uint256 referenceRate
    ) internal returns (Exit) {
        uint256 totalCurrency = (tokenAmount * pricePerToken) / (10 ** token.decimals());
        IERC20[] memory referenceCurrencies = new IERC20[](1);
        referenceCurrencies[0] = referenceCurrency;
        uint256[] memory rates = new uint256[](1);
        rates[0] = referenceRate;
        ExitInitializerArguments memory args = ExitInitializerArguments({
            owner: owner,
            token: token,
            currency: IERC20(address(exitCurrency)),
            pricePerToken: pricePerToken,
            claimStart: claimStart,
            lockedUntil: lockedUntil,
            referenceCurrencies: referenceCurrencies,
            referenceToExitRates: rates
        });
        address cloneAddr = exitFactory.predictCloneAddress(salt, trustedForwarder, args);
        exitCurrency.mint(currencyProvider, totalCurrency);
        vm.prank(currencyProvider);
        exitCurrency.approve(cloneAddr, totalCurrency);
        return Exit(exitFactory.createExitClone(salt, trustedForwarder, currencyProvider, args, totalCurrency));
    }

    /// XIV-A: Auto-lookup upscaling — CP in EURc (6 dec), exit in EURe (18 dec), 1:1 rate stored in Exit
    ///        Carry matches IIIA but _basePrice parameter is not needed (caller passes 0)
    function testXIVA_AutoLookupUpscalingEURcToEURe() public {
        // referenceToExitRate[EURc] = 1e18: 10^6 EURc bits (1 EURc) = 1e18 EURe bits (1 EURe)
        uint256 rate = 1e18; // EURe bits per 10^6 EURc bits, 1:1 value
        Exit exitContract = _deployExitWithReferenceRate(
            bytes32("xiva"),
            eure,
            200e18,
            CP_TOKEN_AMOUNT,
            IERC20(address(eurc)),
            rate
        );

        uint256 beforeA = eure.balanceOf(leadA);
        uint256 beforeB = eure.balanceOf(leadB);
        uint256 beforeR = eure.balanceOf(receiver);

        vm.warp(claimStart);
        vm.prank(admin);
        tokenExitRegistry.setExit(token, IExit(address(exitContract)));
        vm.prank(owner);
        // _basePrice=0: auto-lookup from exit because EURc rate is set
        coinvestedPosition.claimExit(1, 0);

        // received = 200 tokens * 200e18 / 1e18 = 40,000e18 EURe
        // effectiveBasePrice = 100e6 * 1e18 / 1e6 = 100e18 EURe per token
        // basePayout = 100e18 * 200e18 / 1e18 = 20,000e18 EURe; carry = 20,000e18
        uint256 received = 40_000e18;
        uint256 carry = 20_000e18;
        uint256 aGot = eure.balanceOf(leadA) - beforeA;
        uint256 bGot = eure.balanceOf(leadB) - beforeB;
        uint256 rGot = eure.balanceOf(receiver) - beforeR;

        uint256 expectedA = (uint256(CARRY_10PCT) * carry) / type(uint64).max;
        uint256 expectedB = (uint256(CARRY_5PCT) * carry) / type(uint64).max;
        assertEq(aGot, expectedA, "XIVA: wrong A payout");
        assertEq(bGot, expectedB, "XIVA: wrong B payout");
        assertEq(rGot, received - expectedA - expectedB, "XIVA: wrong receiver payout");
        uint256[] memory payouts = new uint256[](2);
        payouts[0] = aGot;
        payouts[1] = bGot;
        _assertInvariant(received, rGot, payouts, address(coinvestedPosition));
    }

    /// XIV-B: Auto-lookup downscaling — CP in EURe (18 dec), exit in EURc (6 dec), 1:1 rate stored in Exit
    function testXIVB_AutoLookupDownscalingEUReToEURc() public {
        CoinvestedPosition coinvestedPositionEure = _deployEureCp();
        // referenceToExitRate[EURe] = 1e6: 10^18 EURe bits (1 EURe) = 1e6 EURc bits (1 EURc)
        uint256 rate = 1e6; // EURc bits per 10^18 EURe bits, 1:1 value
        Exit exitContract = _deployExitWithReferenceRate(
            bytes32("xivb"),
            eurc,
            200e6,
            CP_TOKEN_AMOUNT,
            IERC20(address(eure)),
            rate
        );

        uint256 beforeA = eurc.balanceOf(leadA);
        uint256 beforeB = eurc.balanceOf(leadB);
        uint256 beforeR = eurc.balanceOf(receiver);

        vm.warp(claimStart);
        vm.prank(admin);
        tokenExitRegistry.setExit(token, IExit(address(exitContract)));
        vm.prank(owner);
        // _basePrice=0: auto-lookup from exit because EURe rate is set
        coinvestedPositionEure.claimExit(1, 0);

        // effectiveBasePrice = 100e18 * 1e6 / 1e18 = 100e6 EURc per token; carry = 20,000e6
        _checkIIIB(beforeA, beforeB, beforeR, address(coinvestedPositionEure));
    }

    /// XIV-C: Multiple reference currencies — two CPs with different base currencies both auto-resolve
    function testXIVC_MultipleReferenceCurrencies() public {
        // Deploy an exit with rates for both EURc and EURe
        IERC20[] memory referenceCurrencies = new IERC20[](2);
        referenceCurrencies[0] = IERC20(address(eurc)); // EURc (6 dec) → EURe (18 dec)
        referenceCurrencies[1] = IERC20(address(trustedNonEuro)); // trustedNonEuro (6 dec) → EURe (18 dec)
        uint256[] memory rates = new uint256[](2);
        rates[0] = 1e18; // 1 EURc = 1 EURe
        rates[1] = 2e18; // 1 trustedNonEuro = 2 EURe (hypothetical)

        uint256 totalCurrency = (CP_TOKEN_AMOUNT * 200e18) / (10 ** token.decimals());
        ExitInitializerArguments memory args = ExitInitializerArguments({
            owner: owner,
            token: token,
            currency: IERC20(address(eure)),
            pricePerToken: 200e18,
            claimStart: claimStart,
            lockedUntil: lockedUntil,
            referenceCurrencies: referenceCurrencies,
            referenceToExitRates: rates
        });
        address cloneAddr = exitFactory.predictCloneAddress(bytes32("xivc"), trustedForwarder, args);
        eure.mint(currencyProvider, totalCurrency);
        vm.prank(currencyProvider);
        eure.approve(cloneAddr, totalCurrency);
        Exit exitContract = Exit(
            exitFactory.createExitClone(bytes32("xivc"), trustedForwarder, currencyProvider, args, totalCurrency)
        );

        // Verify both rates are stored
        assertEq(exitContract.referenceToExitRate(IERC20(address(eurc))), 1e18, "XIVC: EURc rate");
        assertEq(exitContract.referenceToExitRate(IERC20(address(trustedNonEuro))), 2e18, "XIVC: trustedNonEuro rate");

        // CP in EURc auto-resolves using rate[EURc]
        vm.warp(claimStart);
        vm.prank(admin);
        tokenExitRegistry.setExit(token, IExit(address(exitContract)));
        vm.prank(owner);
        coinvestedPosition.claimExit(1, 0); // _basePrice=0, auto-lookup used
    }

    /// XIV-D: No rate for CP's currency → fallback to caller-provided _basePrice
    function testXIVD_NoRateFallsBackToCallerBasePrice() public {
        // Exit in EURe with no reference rate for EURc
        Exit exitContract = _deployExit(bytes32("xivd"), eure, 200e18, CP_TOKEN_AMOUNT);

        vm.warp(claimStart);
        vm.prank(admin);
        tokenExitRegistry.setExit(token, IExit(address(exitContract)));

        // _basePrice=0 and no rate in exit → must revert
        vm.expectRevert("altBasePrice must be > 0");
        vm.prank(owner);
        coinvestedPosition.claimExit(1, 0);

        // Providing _basePrice explicitly still works
        vm.prank(owner);
        coinvestedPosition.claimExit(1, 100e18);
    }

    /// XIV-E: Exit initialization reverts when reference currency arrays have mismatched lengths
    function testXIVE_MismatchedArrayLengthsReverts() public {
        IERC20[] memory referenceCurrencies = new IERC20[](1);
        referenceCurrencies[0] = IERC20(address(eurc));
        uint256[] memory rates = new uint256[](0); // length mismatch

        ExitInitializerArguments memory args = ExitInitializerArguments({
            owner: owner,
            token: token,
            currency: IERC20(address(eure)),
            pricePerToken: 200e18,
            claimStart: claimStart,
            lockedUntil: lockedUntil,
            referenceCurrencies: referenceCurrencies,
            referenceToExitRates: rates
        });
        vm.expectRevert("referenceCurrencies and referenceToExitRates must have the same length");
        exitFactory.createExitClone(bytes32("xive"), trustedForwarder, currencyProvider, args, 0);
    }

    /// XIV-F: Exit initialization reverts when a referenceToExitRate is zero
    function testXIVF_ZeroRateReverts() public {
        IERC20[] memory referenceCurrencies = new IERC20[](1);
        referenceCurrencies[0] = IERC20(address(eurc));
        uint256[] memory rates = new uint256[](1);
        rates[0] = 0; // invalid

        uint256 totalCurrency = (CP_TOKEN_AMOUNT * 200e18) / (10 ** token.decimals());
        ExitInitializerArguments memory args = ExitInitializerArguments({
            owner: owner,
            token: token,
            currency: IERC20(address(eure)),
            pricePerToken: 200e18,
            claimStart: claimStart,
            lockedUntil: lockedUntil,
            referenceCurrencies: referenceCurrencies,
            referenceToExitRates: rates
        });
        address cloneAddr = exitFactory.predictCloneAddress(bytes32("xivf"), trustedForwarder, args);
        eure.mint(currencyProvider, totalCurrency);
        vm.prank(currencyProvider);
        eure.approve(cloneAddr, totalCurrency);
        vm.expectRevert("referenceToExitRate must be positive");
        exitFactory.createExitClone(bytes32("xivf"), trustedForwarder, currencyProvider, args, totalCurrency);
    }

    /// XIV-G: setCurrency is blocked before lockedUntil expires
    function testXIVG_SetCurrencyBlockedDuringLocktime() public {
        uint64 lockUntil = uint64(block.timestamp + 7 days);
        LeadInvestor[] memory leadInvestors = _defaultLeadInvestors();
        CoinvestedPositionInitializerArguments memory args = CoinvestedPositionInitializerArguments({
            owner: owner,
            receiver: receiver,
            leadInvestors: leadInvestors,
            basePrice: BASE_PRICE_EURC,
            baseCurrency: IERC20(address(eurc)),
            token: token,
            lockedUntil: lockUntil,
            tokenExitRegistry: tokenExitRegistry
        });
        CoinvestedPosition lockedCp = CoinvestedPosition(
            coinvestedPositionFactory.createCoinvestedPositionClone(bytes32("xivg"), trustedForwarder, args)
        );

        // Before lock expires: setCurrency must revert
        vm.expectRevert("timelock has not expired");
        vm.prank(owner);
        lockedCp.setCurrency(IERC20(address(eure)), 100e18);

        // After lock expires: setCurrency succeeds
        vm.warp(lockUntil);
        vm.prank(owner);
        lockedCp.setCurrency(IERC20(address(eure)), 100e18);
        assertEq(address(lockedCp.currency()), address(eure), "XIVG: currency not updated");
        assertEq(lockedCp.basePrice(), 100e18, "XIVG: basePrice not updated");
    }
}
