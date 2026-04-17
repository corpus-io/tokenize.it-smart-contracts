// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import "./resources/CoinvestedPositionTestBase.sol";

// ── Malicious currency that re-enters CoinvestedPosition.buy() ──────────────
contract MaliciousCoinvestedToken is FakePaymentToken {
    CoinvestedPosition public target;
    bool public attacking;

    constructor() FakePaymentToken(0, 6) {}

    function setTarget(address _target) external {
        target = CoinvestedPosition(_target);
    }

    function transferFrom(address sender, address recipient, uint256 amount) public override returns (bool) {
        if (attacking) return super.transferFrom(sender, recipient, amount);
        attacking = true;
        // Try to re-enter buy()
        target.buy(1e18, type(uint256).max, address(this));
        attacking = false;
        return super.transferFrom(sender, recipient, amount);
    }
}

// ─────────────────────────────────────────────────────────────────────────────

contract CoinvestedPositionTest is CoinvestedPositionTestBase {
    // ── Events ────────────────────────────────────────────────────────────────
    event TokensBought(address indexed BUYER, uint256 tokenAmount, uint256 currencyAmount);
    event ReceiverChanged(address indexed newReceiver);
    event TokenPriceChanged(uint256 newTokenPrice);

    // ── Well-known addresses ──────────────────────────────────────────────────
    address public constant BUYER = 0x1109709ecFA91a80626ff3989D68f67F5B1Dd121;
    address public constant LEAD_B = 0x3109709ECfA91A80626fF3989D68f67F5B1Dd123;
    address public constant FEE_COLLECTOR = 0x4109709eCFa91A80626ff3989d68F67f5b1DD124;

    // ── Test constants ────────────────────────────────────────────────────────
    // 5% of uint64.max (floor)
    uint64 public constant CARRY_5PCT = type(uint64).max / 20;
    // 2% of uint64.max (floor)
    uint64 public constant CARRY_2PCT = type(uint64).max / 50;

    // ── Shared state ──────────────────────────────────────────────────────────
    // EURe: 18 decimals (used for cross-currency tests)
    FakePaymentToken eure;

    CoinvestedPosition logic;
    CoinvestedPositionCloneFactory factory;

    // ── setUp ─────────────────────────────────────────────────────────────────
    function setUp() public {
        // Infrastructure
        allowList = createAllowList(TRUSTED_FORWARDER, ADMIN);
        feeSettings = createFeeSettings(TRUSTED_FORWARDER, ADMIN, buildFeeTypes(0, 0, 0, ADMIN, ADMIN, ADMIN));

        // EURc (6 dec) and EURe (18 dec)
        eurc = new FakePaymentToken(0, 6);
        eure = new FakePaymentToken(0, 18);

        // Register currencies on allowList
        vm.startPrank(ADMIN);
        allowList.set(address(eurc), TRUSTED_CURRENCY);
        allowList.set(address(eure), TRUSTED_CURRENCY);
        vm.stopPrank();

        // Token (18 dec)
        address tokenLogic = address(new Token(TRUSTED_FORWARDER));
        tokenFactory = new TokenProxyFactory(tokenLogic);
        token = Token(
            tokenFactory.createTokenProxy(0, TRUSTED_FORWARDER, feeSettings, ADMIN, allowList, 0, "TestToken", "TTK")
        );

        // Grant mint role so tests can mint tokens to coinvestedPosition
        vm.startPrank(ADMIN);
        token.grantRole(token.MINTALLOWER_ROLE(), ADMIN);
        vm.stopPrank();

        // Factory
        logic = new CoinvestedPosition(TRUSTED_FORWARDER);
        factory = new CoinvestedPositionCloneFactory(address(logic));

        // GlobalTokenExitRegistry
        tokenExitRegistry = new GlobalTokenExitRegistry(TRUSTED_FORWARDER);

        // Deploy default clone: basePrice=100e6 EURc, 10%+5% carry
        coinvestedPosition = _deployCoinvestedPosition(bytes32(0), 100e6, eurc, _defaultLeadInvestors());
    }

    // ─────────────────────────────────────────────────────────────────────────
    // ── Internal helpers ──────────────────────────────────────────────────────
    // ─────────────────────────────────────────────────────────────────────────

    function _defaultLeadInvestors() internal pure returns (LeadInvestor[] memory) {
        LeadInvestor[] memory leadInvestors = new LeadInvestor[](2);
        leadInvestors[0] = LeadInvestor({account: LEAD_A, profitFraction: CARRY_10PCT});
        leadInvestors[1] = LeadInvestor({account: LEAD_B, profitFraction: CARRY_5PCT});
        return leadInvestors;
    }

    function _deployCoinvestedPosition(
        bytes32 salt,
        uint256 basePrice,
        FakePaymentToken baseCurrency,
        LeadInvestor[] memory leadInvestors
    ) internal returns (CoinvestedPosition) {
        CoinvestedPositionInitializerArguments memory args = CoinvestedPositionInitializerArguments({
            owner: OWNER,
            receiver: RECEIVER,
            leadInvestors: leadInvestors,
            basePrice: basePrice,
            baseCurrency: IERC20(address(baseCurrency)),
            token: token,
            lockedUntil: 0,
            tokenExitRegistry: tokenExitRegistry
        });
        return CoinvestedPosition(factory.createCoinvestedPositionClone(salt, TRUSTED_FORWARDER, args));
    }

    /// Give BUYER currency and approve coinvestedPosition
    function _fundBuyer(FakePaymentToken currency, uint256 amount) internal {
        currency.mint(BUYER, amount);
        vm.prank(BUYER);
        currency.approve(address(coinvestedPosition), amount);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // ── Section 1: Constructor / Logic Contract ───────────────────────────────
    // ─────────────────────────────────────────────────────────────────────────

    function testLogicContractInitializeReverts() public {
        LeadInvestor[] memory leadInvestors = _defaultLeadInvestors();
        CoinvestedPositionInitializerArguments memory args = CoinvestedPositionInitializerArguments({
            owner: OWNER,
            receiver: RECEIVER,
            leadInvestors: leadInvestors,
            basePrice: 100e6,
            baseCurrency: IERC20(address(eurc)),
            token: token,
            lockedUntil: 0,
            tokenExitRegistry: tokenExitRegistry
        });

        CoinvestedPosition localLogic = new CoinvestedPosition(TRUSTED_FORWARDER);
        vm.expectRevert("Initializable: contract is already initialized");
        localLogic.initialize(args);
    }

    function testLogicContractStateIsZero() public view {
        assertEq(address(logic.token()), address(0), "token");
        assertEq(address(logic.currency()), address(0), "currency");
        assertEq(address(logic.receiver()), address(0), "RECEIVER");
        assertEq(logic.tokenPrice(), 0, "tokenPrice");
        assertEq(logic.basePrice(), 0, "basePrice");
        assertEq(logic.getLeadInvestorsCount(), 0, "leadInvestors length");
        assertEq(logic.owner(), address(0), "OWNER");
        // NOTE: logic contract starts unpaused (paused=false is the storage default).
        // Unlike initialized clones, _pause() is never called here, so buy() is NOT
        // blocked by whenNotPaused — only by token=address(0) causing a revert.
        assertFalse(logic.paused(), "paused");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // ── Section 2: initialize() — Validation ─────────────────────────────────
    // ─────────────────────────────────────────────────────────────────────────

    function testInitStateVarsCorrect() public view {
        assertEq(coinvestedPosition.owner(), OWNER, "OWNER");
        assertEq(coinvestedPosition.receiver(), RECEIVER, "RECEIVER");
        assertEq(address(coinvestedPosition.currency()), address(eurc), "currency");
        assertEq(address(coinvestedPosition.token()), address(token), "token");
        assertEq(coinvestedPosition.basePrice(), 100e6, "basePrice");
        assertEq(coinvestedPosition.getLeadInvestorsCount(), 2, "leadInvestors length");
        (address acc0, uint64 frac0) = coinvestedPosition.leadInvestors(0);
        assertEq(acc0, LEAD_A, "LEAD_A account");
        assertEq(frac0, CARRY_10PCT, "LEAD_A fraction");
        (address acc1, uint64 frac1) = coinvestedPosition.leadInvestors(1);
        assertEq(acc1, LEAD_B, "LEAD_B account");
        assertEq(frac1, CARRY_5PCT, "LEAD_B fraction");
    }

    function testFuzz_InitBasePriceDecimalsAndPriceStoredCorrectly(uint8 decimals, uint256 basePrice) public {
        vm.assume(basePrice > 0);
        vm.assume(decimals <= 30);

        FakePaymentToken fuzzCurrency = new FakePaymentToken(0, decimals);
        vm.prank(ADMIN);
        allowList.set(address(fuzzCurrency), TRUSTED_CURRENCY);

        bytes32 salt = keccak256(abi.encodePacked(decimals, basePrice));
        CoinvestedPositionInitializerArguments memory args = CoinvestedPositionInitializerArguments({
            owner: OWNER,
            receiver: RECEIVER,
            leadInvestors: _defaultLeadInvestors(),
            basePrice: basePrice,
            baseCurrency: IERC20(address(fuzzCurrency)),
            token: token,
            lockedUntil: 0,
            tokenExitRegistry: tokenExitRegistry
        });
        CoinvestedPosition fuzzPosition = CoinvestedPosition(
            factory.createCoinvestedPositionClone(salt, TRUSTED_FORWARDER, args)
        );

        assertEq(fuzzPosition.basePrice(), basePrice, "basePrice not stored as-is");
    }

    function testInitTokenPriceIsZero() public view {
        assertEq(coinvestedPosition.tokenPrice(), 0, "tokenPrice is not 0 at init");
    }

    function testInitContractStartsPaused() public view {
        assertTrue(coinvestedPosition.paused(), "contract is not paused at init");
    }

    function testInitNonTrustedCurrencyReverts() public {
        // Currency not on allowList → 0 attributes, no TRUSTED_CURRENCY bit
        FakePaymentToken nonTrusted = new FakePaymentToken(0, 6);

        LeadInvestor[] memory leadInvestors = _defaultLeadInvestors();
        CoinvestedPositionInitializerArguments memory args = CoinvestedPositionInitializerArguments({
            owner: OWNER,
            receiver: RECEIVER,
            leadInvestors: leadInvestors,
            basePrice: 100e6,
            baseCurrency: IERC20(address(nonTrusted)),
            token: token,
            lockedUntil: 0,
            tokenExitRegistry: tokenExitRegistry
        });
        vm.expectRevert(UntrustedCurrency.selector);
        factory.createCoinvestedPositionClone(bytes32(0), TRUSTED_FORWARDER, args);
    }

    function testInitCurrencyNotOnAllowListReverts() public {
        FakePaymentToken noBit = new FakePaymentToken(0, 6);
        // not set on allowList at all
        LeadInvestor[] memory leadInvestors = _defaultLeadInvestors();
        CoinvestedPositionInitializerArguments memory args = CoinvestedPositionInitializerArguments({
            owner: OWNER,
            receiver: RECEIVER,
            leadInvestors: leadInvestors,
            basePrice: 100e6,
            baseCurrency: IERC20(address(noBit)),
            token: token,
            lockedUntil: 0,
            tokenExitRegistry: tokenExitRegistry
        });
        vm.expectRevert();
        factory.createCoinvestedPositionClone(bytes32(0), TRUSTED_FORWARDER, args);

        // Adding the currency to the allowList with TRUSTED_CURRENCY bit makes creation succeed
        vm.prank(ADMIN);
        allowList.set(address(noBit), TRUSTED_CURRENCY);
        factory.createCoinvestedPositionClone(bytes32(0), TRUSTED_FORWARDER, args); // must not revert
    }

    function testInitEmptyLeadInvestorsReverts() public {
        LeadInvestor[] memory leadInvestors = new LeadInvestor[](0);
        CoinvestedPositionInitializerArguments memory args = CoinvestedPositionInitializerArguments({
            owner: OWNER,
            receiver: RECEIVER,
            leadInvestors: leadInvestors,
            basePrice: 100e6,
            baseCurrency: IERC20(address(eurc)),
            token: token,
            lockedUntil: 0,
            tokenExitRegistry: tokenExitRegistry
        });
        vm.expectRevert("There must be at least one lead investor");
        factory.createCoinvestedPositionClone(bytes32(0), TRUSTED_FORWARDER, args);
    }

    function testInitZeroAddressLeadInvestorReverts() public {
        LeadInvestor[] memory leadInvestors = new LeadInvestor[](1);
        leadInvestors[0] = LeadInvestor({account: address(0), profitFraction: CARRY_10PCT});
        CoinvestedPositionInitializerArguments memory args = CoinvestedPositionInitializerArguments({
            owner: OWNER,
            receiver: RECEIVER,
            leadInvestors: leadInvestors,
            basePrice: 100e6,
            baseCurrency: IERC20(address(eurc)),
            token: token,
            lockedUntil: 0,
            tokenExitRegistry: tokenExitRegistry
        });
        vm.expectRevert("lead investor can not be zero address");
        factory.createCoinvestedPositionClone(bytes32(0), TRUSTED_FORWARDER, args);
    }

    function testInitCarryFractionZeroReverts() public {
        LeadInvestor[] memory leadInvestors = new LeadInvestor[](1);
        leadInvestors[0] = LeadInvestor({account: LEAD_A, profitFraction: 0});
        CoinvestedPositionInitializerArguments memory args = CoinvestedPositionInitializerArguments({
            owner: OWNER,
            receiver: RECEIVER,
            leadInvestors: leadInvestors,
            basePrice: 100e6,
            baseCurrency: IERC20(address(eurc)),
            token: token,
            lockedUntil: 0,
            tokenExitRegistry: tokenExitRegistry
        });
        vm.expectRevert("lead investor profit fraction can not be zero");
        factory.createCoinvestedPositionClone(bytes32(0), TRUSTED_FORWARDER, args);
    }

    function testInitCarryFractionsSumOverflowReverts() public {
        // (max/2 + 1) + (max/2 + 1) = max + 1: sum overflows uint64 → arithmetic revert
        LeadInvestor[] memory leadInvestors = new LeadInvestor[](2);
        leadInvestors[0] = LeadInvestor({account: LEAD_A, profitFraction: type(uint64).max / 2 + 1});
        leadInvestors[1] = LeadInvestor({account: LEAD_B, profitFraction: type(uint64).max / 2 + 1});
        CoinvestedPositionInitializerArguments memory args = CoinvestedPositionInitializerArguments({
            owner: OWNER,
            receiver: RECEIVER,
            leadInvestors: leadInvestors,
            basePrice: 100e6,
            baseCurrency: IERC20(address(eurc)),
            token: token,
            lockedUntil: 0,
            tokenExitRegistry: tokenExitRegistry
        });
        vm.expectRevert("panic: arithmetic underflow or overflow (0x11)"); // arithmetic overflow
        factory.createCoinvestedPositionClone(bytes32(0), TRUSTED_FORWARDER, args);
    }

    function testInitCarryFractionsSumMaxAccepted() public {
        LeadInvestor[] memory leadInvestors = new LeadInvestor[](1);
        leadInvestors[0] = LeadInvestor({account: LEAD_A, profitFraction: type(uint64).max});
        CoinvestedPosition coinvestedPositionBoundary = _deployCoinvestedPosition(
            bytes32(0),
            100e6,
            eurc,
            leadInvestors
        );
        assertEq(coinvestedPositionBoundary.getLeadInvestorsCount(), 1);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // ── Section 3: setCurrency() ──────────────────────────────────────────────
    // ─────────────────────────────────────────────────────────────────────────

    function testSetCurrencyOnlyOwner() public {
        vm.prank(BUYER);
        vm.expectRevert("Ownable: caller is not the owner");
        coinvestedPosition.setCurrency(IERC20(address(eure)), 1);
    }

    function testFuzz_SetCurrencyOnlyOwner(address caller) public {
        vm.assume(caller != OWNER && caller != address(0) && caller != TRUSTED_FORWARDER);
        vm.prank(caller);
        vm.expectRevert("Ownable: caller is not the owner");
        coinvestedPosition.setCurrency(IERC20(address(eure)), 1);
    }

    function testSetCurrencyNonTrustedReverts() public {
        FakePaymentToken nonTrusted = new FakePaymentToken(0, 6);
        // not on allowList → 0 attributes, no TRUSTED_CURRENCY bit
        vm.prank(OWNER);
        vm.expectRevert("currency needs to be on the allowlist with TRUSTED_CURRENCY attribute");
        coinvestedPosition.setCurrency(IERC20(address(nonTrusted)), 1);
    }

    function testFuzz_SetCurrencyValidAccepted(uint8 decimals) public {
        FakePaymentToken newCurrency = new FakePaymentToken(0, decimals);

        // Not on allowList yet → revert
        vm.prank(OWNER);
        vm.expectRevert();
        coinvestedPosition.setCurrency(IERC20(address(newCurrency)), 1);

        // Add to allowList with TRUSTED_CURRENCY bit → accepted
        vm.prank(ADMIN);
        allowList.set(address(newCurrency), TRUSTED_CURRENCY);
        vm.prank(OWNER);
        coinvestedPosition.setCurrency(IERC20(address(newCurrency)), 1);
        assertEq(address(coinvestedPosition.currency()), address(newCurrency));
    }

    // ─────────────────────────────────────────────────────────────────────────
    // ── Section 4: setTokenPrice() / pause() / unpause() ─────────────────────
    // ─────────────────────────────────────────────────────────────────────────

    function testSetTokenPriceOnlyOwner() public {
        vm.prank(BUYER);
        vm.expectRevert("Ownable: caller is not the owner");
        coinvestedPosition.setTokenPrice(200e6);
    }

    function testPauseOnlyOwner() public {
        vm.prank(OWNER);
        coinvestedPosition.setTokenPrice(200e6);
        vm.prank(OWNER);
        coinvestedPosition.unpause();
        vm.prank(BUYER);
        vm.expectRevert("Ownable: caller is not the owner");
        coinvestedPosition.pause();
    }

    function testUnpauseOnlyOwner() public {
        vm.prank(OWNER);
        coinvestedPosition.setTokenPrice(200e6);
        vm.prank(BUYER);
        vm.expectRevert("Ownable: caller is not the owner");
        coinvestedPosition.unpause();
    }

    function testUnpauseRevertsWhenTokenPriceZero() public {
        // tokenPrice is 0 after init
        assertEq(coinvestedPosition.tokenPrice(), 0);
        vm.prank(OWNER);
        vm.expectRevert("tokenPrice must be set before unpausing");
        coinvestedPosition.unpause();
    }

    function testSetTokenPriceZeroReverts() public {
        vm.prank(OWNER);
        vm.expectRevert(ZeroPrice.selector);
        coinvestedPosition.setTokenPrice(0);
    }

    function testUnpauseSucceedsAfterSetTokenPrice() public {
        vm.prank(OWNER);
        coinvestedPosition.setTokenPrice(200e6);
        vm.prank(OWNER);
        coinvestedPosition.unpause();
        assertFalse(coinvestedPosition.paused());
    }

    function testPauseRePausesAndBuyReverts() public {
        _setupBuy(10e18, 200e6);
        vm.prank(OWNER);
        coinvestedPosition.pause();
        _fundBuyer(eurc, 2000e6);
        vm.prank(BUYER);
        vm.expectRevert("Pausable: paused");
        coinvestedPosition.buy(1e18, type(uint256).max, TOKEN_RECEIVER);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // ── Section 5: setReceiver() ──────────────────────────────────────────────
    // ─────────────────────────────────────────────────────────────────────────

    function testSetReceiverOnlyOwner() public {
        vm.prank(BUYER);
        vm.expectRevert("Ownable: caller is not the owner");
        coinvestedPosition.setReceiver(BUYER);
    }

    function testSetReceiverZeroAddressReverts() public {
        vm.prank(OWNER);
        vm.expectRevert(ZeroReceiverAddress.selector);
        coinvestedPosition.setReceiver(address(0));
    }

    function testSetReceiverStoresAndEmitsEvent() public {
        assertEq(coinvestedPosition.receiver(), RECEIVER);
        vm.prank(OWNER);
        vm.expectEmit(true, false, false, false);
        emit ReceiverChanged(LEAD_A);
        coinvestedPosition.setReceiver(LEAD_A);
        assertEq(coinvestedPosition.receiver(), LEAD_A);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // ── Section 6: buy() — Core Logic ────────────────────────────────────────
    // ─────────────────────────────────────────────────────────────────────────

    function testBuyWhenPausedReverts() public {
        // coinvestedPosition is paused after init
        eurc.mint(BUYER, 1000e6);
        vm.prank(BUYER);
        eurc.approve(address(coinvestedPosition), 1000e6);
        vm.prank(BUYER);
        vm.expectRevert("Pausable: paused");
        coinvestedPosition.buy(1e18, 1000e6, TOKEN_RECEIVER);
    }

    function testBuyMaxCurrencyAmountTooLowReverts() public {
        _setupBuy(10e18, 200e6);
        _fundBuyer(eurc, 200e6);
        vm.prank(BUYER);
        vm.expectRevert("Purchase more expensive than _maxCurrencyAmount");
        coinvestedPosition.buy(1e18, 100e6, TOKEN_RECEIVER); // needs 200e6 but max=100e6
    }

    function testBuyTokensGoToTokenReceiver() public {
        _setupBuy(10e18, 200e6);
        _fundBuyer(eurc, 400e6);
        address differentReceiver = address(0xBEEF);
        vm.prank(BUYER);
        coinvestedPosition.buy(1e18, 400e6, differentReceiver);
        assertEq(token.balanceOf(differentReceiver), 1e18, "tokens did not go to TOKEN_RECEIVER");
        assertEq(token.balanceOf(BUYER), 0, "BUYER received tokens");
    }

    function testBuyEmitsTokensBoughtEvent() public {
        _setupBuy(10e18, 200e6);
        _fundBuyer(eurc, 400e6);
        vm.prank(BUYER);
        vm.expectEmit(true, true, true, true);
        emit TokensBought(BUYER, 1e18, 200e6);
        coinvestedPosition.buy(1e18, 400e6, TOKEN_RECEIVER);
    }

    function testBuyZeroFeeCorrectCarrySplit() public {
        // 2 tokens at tokenPrice=200e6, basePrice=100e6
        // paid=400e6, fee=0, remaining=400e6, basePayout=200e6, carry=200e6
        // A (10%): floor(carry * CARRY_10PCT / uint64.max) = floor(200e6 * (uint64.max/10) / uint64.max) = 20e6
        // B (5%):  floor(carry * CARRY_5PCT / uint64.max)  = floor(200e6 * (uint64.max/20) / uint64.max) = 10e6
        // receiver: 400e6 - 20e6 - 10e6 = 370e6
        _setupBuy(10e18, 200e6);
        _fundBuyer(eurc, 400e6);

        uint256 carry = 200e6;
        uint256 expectedA = (uint256(CARRY_10PCT) * carry) / type(uint64).max;
        uint256 expectedB = (uint256(CARRY_5PCT) * carry) / type(uint64).max;
        uint256 expectedReceiver = 400e6 - expectedA - expectedB;

        // base price 100e6, sell 2 tokens for 200e6 each => 400e6 proceeds, of which 200e6 are carry
        assertEq(expectedA, 20e6 - 1, "LEAD_A expected wrong");
        assertEq(expectedB, 10e6 - 1, "LEAD_B expected wrong");
        assertEq(expectedReceiver, 400e6 - 30e6 + 2, "RECEIVER expected wrong");

        assertEq(eurc.balanceOf(LEAD_A), 0, "LEAD_A has currency");
        assertEq(eurc.balanceOf(LEAD_B), 0, "LEAD_B has currency");
        assertEq(eurc.balanceOf(RECEIVER), 0, "RECEIVER has currency");

        vm.prank(BUYER);
        coinvestedPosition.buy(2e18, 400e6, TOKEN_RECEIVER);

        assertEq(eurc.balanceOf(LEAD_A), expectedA, "LEAD_A carry");
        assertEq(eurc.balanceOf(LEAD_B), expectedB, "LEAD_B carry");
        assertEq(eurc.balanceOf(RECEIVER), expectedReceiver, "RECEIVER");
    }

    function testBuyNonZeroFeeDeductedBeforeCarry() public {
        // Deploy with non-zero fee
        IFeeSettingsV2 feeSettings100 = createFeeSettings(
            TRUSTED_FORWARDER,
            ADMIN,
            buildFeeTypes(0, 0, 100, FEE_COLLECTOR, FEE_COLLECTOR, FEE_COLLECTOR)
        );
        // Deploy new token with this fee settings
        Token tokenWithFee = Token(
            tokenFactory.createTokenProxy(0, TRUSTED_FORWARDER, feeSettings100, ADMIN, allowList, 0, "FeeToken", "FTK")
        );
        vm.startPrank(ADMIN);
        tokenWithFee.grantRole(tokenWithFee.MINTALLOWER_ROLE(), ADMIN);
        vm.stopPrank();

        LeadInvestor[] memory leadInvestors = _defaultLeadInvestors();
        CoinvestedPositionInitializerArguments memory args = CoinvestedPositionInitializerArguments({
            owner: OWNER,
            receiver: RECEIVER,
            leadInvestors: leadInvestors,
            basePrice: 100e6,
            baseCurrency: IERC20(address(eurc)),
            token: tokenWithFee,
            lockedUntil: 0,
            tokenExitRegistry: tokenExitRegistry
        });
        CoinvestedPosition coinvestedPositionWithFee = CoinvestedPosition(
            factory.createCoinvestedPositionClone(bytes32(0), TRUSTED_FORWARDER, args)
        );

        vm.prank(ADMIN);
        tokenWithFee.mint(address(coinvestedPositionWithFee), 10e18);
        vm.prank(OWNER);
        coinvestedPositionWithFee.setTokenPrice(200e6);
        vm.prank(OWNER);
        coinvestedPositionWithFee.unpause();

        uint256 currencyAmount = 400e6; // 2 tokens at 200e6
        eurc.mint(BUYER, currencyAmount);
        vm.prank(BUYER);
        eurc.approve(address(coinvestedPositionWithFee), currencyAmount);

        // fee = 1% of 400e6 = 4e6
        uint256 fee = 4e6;
        uint256 remaining = currencyAmount - fee;
        // scaledBasePrice = 100e6 (same dec), basePayout for 2 tokens = 200e6
        uint256 carry = remaining > 200e6 ? remaining - 200e6 : 0;
        uint256 expectedA = (uint256(CARRY_10PCT) * carry) / type(uint64).max;
        uint256 expectedB = (uint256(CARRY_5PCT) * carry) / type(uint64).max;
        uint256 expectedReceiver = remaining - expectedA - expectedB;

        vm.prank(BUYER);
        coinvestedPositionWithFee.buy(2e18, currencyAmount, TOKEN_RECEIVER);

        assertEq(eurc.balanceOf(FEE_COLLECTOR), fee, "fee collector");
        assertEq(eurc.balanceOf(LEAD_A), expectedA, "LEAD_A");
        assertEq(eurc.balanceOf(LEAD_B), expectedB, "LEAD_B");
        assertEq(eurc.balanceOf(RECEIVER), expectedReceiver, "RECEIVER");
    }

    function testBuyFeeEatsAllCarryLeadInvestorsGetNothing() public {
        // basePrice=100e6, tokenPrice=104e6, 1 token → paid=104e6
        // Without fee, carry would be 4e6.
        // With 5% fee (max allowed): fee=5.2e6, remaining=98.8e6 < basePayout=100e6 → carry=0
        IFeeSettingsV2 feeSettings10 = createFeeSettings(
            TRUSTED_FORWARDER,
            ADMIN,
            buildFeeTypes(0, 0, 500, FEE_COLLECTOR, FEE_COLLECTOR, FEE_COLLECTOR)
        );
        Token tokenHighFee = Token(
            tokenFactory.createTokenProxy(
                0,
                TRUSTED_FORWARDER,
                feeSettings10,
                ADMIN,
                allowList,
                0,
                "HighFeeToken",
                "HFT"
            )
        );
        vm.startPrank(ADMIN);
        tokenHighFee.grantRole(tokenHighFee.MINTALLOWER_ROLE(), ADMIN);
        vm.stopPrank();

        LeadInvestor[] memory leadInvestors = _defaultLeadInvestors();
        CoinvestedPositionInitializerArguments memory args = CoinvestedPositionInitializerArguments({
            owner: OWNER,
            receiver: RECEIVER,
            leadInvestors: leadInvestors,
            basePrice: 100e6,
            baseCurrency: IERC20(address(eurc)),
            token: tokenHighFee,
            lockedUntil: 0,
            tokenExitRegistry: tokenExitRegistry
        });
        CoinvestedPosition coinvestedPositionHighFee = CoinvestedPosition(
            factory.createCoinvestedPositionClone(bytes32(0), TRUSTED_FORWARDER, args)
        );

        vm.prank(ADMIN);
        tokenHighFee.mint(address(coinvestedPositionHighFee), 1e18);
        vm.prank(OWNER);
        coinvestedPositionHighFee.setTokenPrice(104e6);
        vm.prank(OWNER);
        coinvestedPositionHighFee.unpause();

        uint256 currencyAmount = 104e6; // 1 token at 104e6
        eurc.mint(BUYER, currencyAmount);
        vm.prank(BUYER);
        eurc.approve(address(coinvestedPositionHighFee), currencyAmount);

        // fee = 5% of 104e6 = 5.2e6; remaining = 98.8e6 < basePayout (100e6) → carry = 0
        uint256 expectedFee = (currencyAmount * 500) / 10000;
        uint256 remaining = currencyAmount - expectedFee;
        assertLt(remaining, 100e6, "precondition: remaining must be below basePayout");

        vm.prank(BUYER);
        coinvestedPositionHighFee.buy(1e18, currencyAmount, TOKEN_RECEIVER);

        assertEq(eurc.balanceOf(FEE_COLLECTOR), expectedFee, "fee collector");
        assertEq(eurc.balanceOf(LEAD_A), 0, "LEAD_A got carry despite fee");
        assertEq(eurc.balanceOf(LEAD_B), 0, "LEAD_B got carry despite fee");
        assertEq(eurc.balanceOf(RECEIVER), remaining, "RECEIVER did not get all remaining");
    }

    function testBuyAtExactlyBasePriceCarryIsZero() public {
        // tokenPrice == basePrice → carry = 0, RECEIVER gets everything
        _setupBuy(10e18, 100e6); // tokenPrice = basePrice = 100e6
        uint256 paid = 100e6; // 1 token
        _fundBuyer(eurc, paid);

        vm.prank(BUYER);
        coinvestedPosition.buy(1e18, paid, TOKEN_RECEIVER);

        assertEq(eurc.balanceOf(LEAD_A), 0, "LEAD_A got non-zero carry");
        assertEq(eurc.balanceOf(LEAD_B), 0, "LEAD_B got non-zero carry");
        assertEq(eurc.balanceOf(RECEIVER), paid, "RECEIVER did not get everything");
    }

    function testBuyBelowBasePriceCarryIsZero() public {
        // tokenPrice < basePrice → remaining < basePayout → carry = 0
        // Need to set tokenPrice below basePrice (which is 100e6)
        _setupBuy(10e18, 50e6); // tokenPrice = 50e6 < basePrice = 100e6
        uint256 paid = 50e6; // 1 token at 50e6
        _fundBuyer(eurc, paid);

        vm.prank(BUYER);
        coinvestedPosition.buy(1e18, paid, TOKEN_RECEIVER);

        assertEq(eurc.balanceOf(LEAD_A), 0, "LEAD_A got non-zero carry");
        assertEq(eurc.balanceOf(LEAD_B), 0, "LEAD_B got non-zero carry");
        assertEq(eurc.balanceOf(RECEIVER), paid, "RECEIVER did not get full remaining");
    }

    function testBuyConcreteExampleWithThreeLeadInvestors() public {
        // Setup: 0 fee, 2 Tokens (18 dec), basePrice = 300e6, tokenPrice = 400e6, currency 6 dec
        // Paid: 800e6. Fee: 0. Remaining: 800e6. BasePayout: 600e6. Carry: 200e6.
        // Lead investors: 5% + 2% + 10%
        LeadInvestor[] memory leadInvestors = new LeadInvestor[](3);
        leadInvestors[0] = LeadInvestor({account: LEAD_A, profitFraction: CARRY_5PCT}); // 5%
        leadInvestors[1] = LeadInvestor({account: LEAD_B, profitFraction: CARRY_2PCT}); // 2%
        leadInvestors[2] = LeadInvestor({account: TOKEN_RECEIVER, profitFraction: CARRY_10PCT}); // 10%
        CoinvestedPosition coinvestedPositionThreeLeads = _deployCoinvestedPosition(
            bytes32(0),
            300e6,
            eurc,
            leadInvestors
        );

        vm.prank(ADMIN);
        token.mint(address(coinvestedPositionThreeLeads), 2e18);
        vm.prank(OWNER);
        coinvestedPositionThreeLeads.setTokenPrice(400e6);
        vm.prank(OWNER);
        coinvestedPositionThreeLeads.unpause();

        uint256 paid = 800e6;
        eurc.mint(BUYER, paid);
        vm.prank(BUYER);
        eurc.approve(address(coinvestedPositionThreeLeads), paid);

        uint256 carry = 200e6;
        uint256 shareA = (uint256(CARRY_5PCT) * carry) / type(uint64).max;
        uint256 shareB = (uint256(CARRY_2PCT) * carry) / type(uint64).max;
        uint256 shareC = (uint256(CARRY_10PCT) * carry) / type(uint64).max;

        assertEq(token.balanceOf(address(coinvestedPositionThreeLeads)), 2e18, "wrong token amount");

        vm.prank(BUYER);
        coinvestedPositionThreeLeads.buy(2e18, paid, address(0xCAFE));

        assertEq(eurc.balanceOf(LEAD_A), shareA, "5% share"); // 10e6
        assertEq(eurc.balanceOf(LEAD_B), shareB, "2% share"); // 4e6
        assertEq(eurc.balanceOf(TOKEN_RECEIVER), shareC, "10% share"); // 20e6
        assertEq(eurc.balanceOf(RECEIVER), paid - shareA - shareB - shareC, "RECEIVER");
        assertEq(token.balanceOf(address(coinvestedPositionThreeLeads)), 0, "some tokens left");
    }

    function testBuyCurrencyAmountCeilingRounded() public {
        // 1 token at price 3 in a 0-decimal currency scenario:
        // currencyAmount = ceil(1 * 3 / 1) = 3 — trivial.
        // Instead test with indivisible: 1.5 token bits at price 1 = ceil(1.5) = 2 not 1.
        // tokenAmount = 1, tokenPrice = 3, token decimals = 18 → amount = ceil(1 * 3 / 1e18)
        // For a meaningful test: tokenAmount = 1e12 (sub-unit), tokenPrice = 1e6, ceil(1e12 * 1e6 / 1e18) = ceil(1) = 1
        // Test with non-divisible: tokenAmount = 1, tokenPrice = 1e6 → ceil(1 * 1e6 / 1e18) = 1
        // Better: tokenAmount = 1e12 + 1, tokenPrice = 1e6, need ceil((1e12+1)*1e6 / 1e18) = 2
        _setupBuy(10e18, 1e6); // tokenPrice = 1 eurc per token
        uint256 tokenAmt = 1e12 + 1; // slightly above 1 micro-token
        // exact = (1e12+1)*1e6 / 1e18 = 1.000001e6/1e6 → 1.000001... → ceiling = 2
        uint256 expectedCost = 2;
        eurc.mint(BUYER, 10e6);
        vm.prank(BUYER);
        eurc.approve(address(coinvestedPosition), 10e6);

        uint256 balBefore = eurc.balanceOf(BUYER);
        vm.prank(BUYER);
        coinvestedPosition.buy(tokenAmt, 10e6, TOKEN_RECEIVER);
        uint256 spent = balBefore - eurc.balanceOf(BUYER);
        assertEq(spent, expectedCost, "wrong ceiling rounding amount");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // ── Section 7: buy() — Cross-currency Decimal Scaling ────────────────────
    // ─────────────────────────────────────────────────────────────────────────

    function testScenarioA_Upscaling() public {
        // basePriceDecimals=6, setCurrency→EURe (18 dec), tokenPrice=200e18
        // scaledBasePrice = 100e6 scaled to 18 dec = 100e18
        // buy 2 tokens: paid=400e18, basePayout=200e18, carry=200e18

        vm.prank(OWNER);
        coinvestedPosition.setCurrency(IERC20(address(eure)), 100e18);

        vm.prank(ADMIN);
        token.mint(address(coinvestedPosition), 10e18);
        vm.prank(OWNER);
        coinvestedPosition.setTokenPrice(200e18);
        vm.prank(OWNER);
        coinvestedPosition.unpause();

        uint256 paid = 400e18;
        eure.mint(BUYER, paid);
        vm.prank(BUYER);
        eure.approve(address(coinvestedPosition), paid);

        // Base cost was 200e6 eurc, which equals 200€. Proceeds are 400e18 eure, which equals 400€. Carry is 200e18 eure = 200€.
        // All decimals must be handled correctly here.
        uint256 carry = 200e18;
        uint256 expectedA = (uint256(CARRY_10PCT) * carry) / type(uint64).max;
        uint256 expectedB = (uint256(CARRY_5PCT) * carry) / type(uint64).max;
        uint256 expectedReceiver = paid - expectedA - expectedB;

        vm.prank(BUYER);
        coinvestedPosition.buy(2e18, paid, TOKEN_RECEIVER);

        assertEq(eure.balanceOf(LEAD_A), expectedA, "LEAD_A (18dec)");
        assertEq(eure.balanceOf(LEAD_B), expectedB, "LEAD_B (18dec)");
        assertEq(eure.balanceOf(RECEIVER), expectedReceiver, "RECEIVER (18dec)");
    }

    function testScenarioB_Downscaling() public {
        // Deploy with EURe (18 dec) as baseCurrency → basePriceDecimals=18, basePrice=100e18
        // Then setCurrency→EURc (6 dec), tokenPrice=200e6
        // scaledBasePrice = 100e18 / 1e12 = 100e6
        CoinvestedPosition coinvestedPosition18 = _deployCoinvestedPosition(
            bytes32(0),
            100e18,
            eure,
            _defaultLeadInvestors()
        );
        vm.prank(OWNER);
        coinvestedPosition18.setCurrency(IERC20(address(eurc)), 100e6);

        vm.prank(ADMIN);
        token.mint(address(coinvestedPosition18), 10e18);
        vm.prank(OWNER);
        coinvestedPosition18.setTokenPrice(200e6);
        vm.prank(OWNER);
        coinvestedPosition18.unpause();

        // buy 2 tokens: paid=400e6, scaledBasePrice=100e6, basePayout=200e6, carry=200e6
        uint256 paid = 400e6;
        eurc.mint(BUYER, paid);
        vm.prank(BUYER);
        eurc.approve(address(coinvestedPosition18), paid);

        uint256 carry = 200e6;
        uint256 expectedA = (uint256(CARRY_10PCT) * carry) / type(uint64).max;
        uint256 expectedB = (uint256(CARRY_5PCT) * carry) / type(uint64).max;
        uint256 expectedReceiver = paid - expectedA - expectedB;

        vm.prank(BUYER);
        coinvestedPosition18.buy(2e18, paid, TOKEN_RECEIVER);

        assertEq(eurc.balanceOf(LEAD_A), expectedA, "LEAD_A (downscaled)");
        assertEq(eurc.balanceOf(LEAD_B), expectedB, "LEAD_B (downscaled)");
        assertEq(eurc.balanceOf(RECEIVER), expectedReceiver, "RECEIVER (downscaled)");
    }

    function testScenarioC_EqualDecimals_NoScaling() public {
        // basePriceDecimals=6, currency=EURc (6 dec) — same decimals, no scaling
        _setupBuy(10e18, 200e6);
        uint256 paid = 200e6; // 1 token
        _fundBuyer(eurc, paid);

        uint256 carry = 200e6 - 100e6; // 100e6
        uint256 expectedA = (uint256(CARRY_10PCT) * carry) / type(uint64).max;
        uint256 expectedB = (uint256(CARRY_5PCT) * carry) / type(uint64).max;
        uint256 expectedReceiver = paid - expectedA - expectedB;

        assertEq(token.balanceOf(address(coinvestedPosition)), 10e18, "wrong token amount before");
        assertEq(eurc.balanceOf(address(coinvestedPosition)), 0, "wrong currency amount before: coinvestedPosition");

        vm.prank(BUYER);
        coinvestedPosition.buy(1e18, paid, TOKEN_RECEIVER);

        assertEq(eurc.balanceOf(LEAD_A), expectedA);
        assertEq(eurc.balanceOf(LEAD_B), expectedB);
        assertEq(eurc.balanceOf(RECEIVER), expectedReceiver);
        assertEq(token.balanceOf(address(coinvestedPosition)), 9e18, "wrong token amount after: coinvestedPosition");
        assertEq(token.balanceOf(TOKEN_RECEIVER), 1e18, "wrong token amount after: TOKEN_RECEIVER");
        assertEq(eurc.balanceOf(address(coinvestedPosition)), 0, "wrong currency amount after: coinvestedPosition");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // ── Section 8: buy() — Sequential Partial Sells ───────────────────────────
    // ─────────────────────────────────────────────────────────────────────────

    function testSequentialPartialSells() public {
        // 100 tokens total; basePrice=100e6 EURc (6 dec); leads A=10%, B=5%
        vm.prank(ADMIN);
        token.mint(address(coinvestedPosition), 100e18);

        // ── Tranche 1: 5 tokens, EURc, tokenPrice=150e6 ──────────────────────
        vm.prank(OWNER);
        coinvestedPosition.setTokenPrice(150e6);
        vm.prank(OWNER);
        coinvestedPosition.unpause();

        uint256 t1paid = 750e6; // 5 tokens * 150e6
        eurc.mint(BUYER, t1paid);
        vm.prank(BUYER);
        eurc.approve(address(coinvestedPosition), t1paid);

        // basePayout = 5*100e6 = 500e6, carry = 250e6
        uint256 t1carry = 250e6;
        uint256 t1A = (uint256(CARRY_10PCT) * t1carry) / type(uint64).max;
        uint256 t1B = (uint256(CARRY_5PCT) * t1carry) / type(uint64).max;

        vm.prank(BUYER);
        coinvestedPosition.buy(5e18, t1paid, TOKEN_RECEIVER);

        assertEq(token.balanceOf(address(coinvestedPosition)), 95e18, "95 tokens after tranche 1");
        assertEq(eurc.balanceOf(LEAD_A), t1A, "LEAD_A after tranche 1");
        assertEq(eurc.balanceOf(LEAD_B), t1B, "LEAD_B after tranche 1");
        assertEq(eurc.balanceOf(RECEIVER), t1paid - t1A - t1B, "RECEIVER EURc after tranche 1");

        // ── Tranche 2: 40 tokens, EURe (18 dec), tokenPrice=200e18 ───────────
        vm.prank(OWNER);
        coinvestedPosition.pause();
        vm.prank(OWNER);
        coinvestedPosition.setCurrency(IERC20(address(eure)), 100e18);
        vm.prank(OWNER);
        coinvestedPosition.setTokenPrice(200e18);
        vm.prank(OWNER);
        coinvestedPosition.unpause();

        uint256 t2paid = 8000e18; // 40 tokens * 200e18
        eure.mint(BUYER, t2paid);
        vm.prank(BUYER);
        eure.approve(address(coinvestedPosition), t2paid);

        // scaledBasePrice: 100e6 scaled to 18 dec = 100e18
        // basePayout = 40 * 100e18 = 4000e18, carry = 4000e18
        uint256 t2carry = 4000e18;
        uint256 t2A = (uint256(CARRY_10PCT) * t2carry) / type(uint64).max;
        uint256 t2B = (uint256(CARRY_5PCT) * t2carry) / type(uint64).max;

        vm.prank(BUYER);
        coinvestedPosition.buy(40e18, t2paid, TOKEN_RECEIVER);

        assertEq(token.balanceOf(address(coinvestedPosition)), 55e18, "55 tokens after tranche 2");
        assertEq(eure.balanceOf(LEAD_A), t2A, "LEAD_A EURe after tranche 2");
        assertEq(eure.balanceOf(LEAD_B), t2B, "LEAD_B EURe after tranche 2");
        assertEq(eure.balanceOf(RECEIVER), t2paid - t2A - t2B, "RECEIVER EURe after tranche 2");
        // EURc balances from tranche 1 unchanged
        assertEq(eurc.balanceOf(LEAD_A), t1A, "LEAD_A EURc changed");
        assertEq(eurc.balanceOf(LEAD_B), t1B, "LEAD_B EURc changed");
        assertEq(eurc.balanceOf(RECEIVER), t1paid - t1A - t1B, "RECEIVER EURc changed");

        // ── Tranche 3: 55 tokens, tokenPrice=80e18 (below base after scaling) ─
        vm.prank(OWNER);
        coinvestedPosition.pause();
        vm.prank(OWNER);
        coinvestedPosition.setTokenPrice(80e18);
        vm.prank(OWNER);
        coinvestedPosition.unpause();

        uint256 t3paid = 55 * 80e18; // 4400e18
        eure.mint(BUYER, t3paid);
        vm.prank(BUYER);
        eure.approve(address(coinvestedPosition), t3paid);

        // scaledBasePrice = 100e18, basePayout = 55*100e18 = 5500e18 > 4400e18 → carry=0
        vm.prank(BUYER);
        coinvestedPosition.buy(55e18, t3paid, TOKEN_RECEIVER);

        assertEq(token.balanceOf(address(coinvestedPosition)), 0, "0 tokens after tranche 3");
        // carry=0 in tranche 3, so lead and RECEIVER EURe changes only for RECEIVER
        assertEq(eure.balanceOf(LEAD_A), t2A, "LEAD_A EURe changed after tranche 3");
        assertEq(eure.balanceOf(LEAD_B), t2B, "LEAD_B EURe changed after tranche 3");
        assertEq(eure.balanceOf(RECEIVER), t2paid - t2A - t2B + t3paid, "RECEIVER EURe after tranche 3");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // ── Section 9: _settle() Sweep Behavior ──────────────────────────────────
    // ─────────────────────────────────────────────────────────────────────────

    function testSettleSweepsExtraSameCurrencyToReceiver() public {
        // Extra 500e6 EURc sent before buy. Buy 10 tokens at 200e6, basePrice=100e6.
        // carry from BUYER = 1000e6; A gets 100e6; RECEIVER gets 1000e6 + 500e6 = ...
        // Actually: contract balance before sweep = 2000e6 (from BUYER) - 100e6 (A) + 500e6 (extra) = 2400e6
        // RECEIVER sweep = 2400e6

        // Use a fresh coinvestedPosition with single 10% lead investor to simplify
        LeadInvestor[] memory leadInvestors = new LeadInvestor[](1);
        leadInvestors[0] = LeadInvestor({account: LEAD_A, profitFraction: CARRY_10PCT});
        CoinvestedPosition coinvestedPositionSweep = _deployCoinvestedPosition(bytes32(0), 100e6, eurc, leadInvestors);

        vm.prank(ADMIN);
        token.mint(address(coinvestedPositionSweep), 10e18);
        vm.prank(OWNER);
        coinvestedPositionSweep.setTokenPrice(200e6);
        vm.prank(OWNER);
        coinvestedPositionSweep.unpause();

        // Send extra currency directly to contract
        eurc.mint(address(coinvestedPositionSweep), 500e6);

        // Buyer pays 2000e6 for 10 tokens
        uint256 paid = 2000e6;
        eurc.mint(BUYER, paid);
        vm.prank(BUYER);
        eurc.approve(address(coinvestedPositionSweep), paid);

        uint256 carry = 1000e6; // 2000e6 - 1000e6 basePayout
        uint256 expectedA = (uint256(CARRY_10PCT) * carry) / type(uint64).max;
        uint256 expectedReceiver = 2000e6 - expectedA + 500e6; // BUYER payment minus A's share, plus extra

        vm.prank(BUYER);
        coinvestedPositionSweep.buy(10e18, paid, TOKEN_RECEIVER);

        assertEq(eurc.balanceOf(LEAD_A), expectedA, "A's carry was inflated by extra balance");
        assertEq(eurc.balanceOf(RECEIVER), expectedReceiver, "RECEIVER did not get share + extra");
    }

    function testSettleSweepCarryZeroWithExtra() public {
        // tokenPrice == basePrice → carry=0; RECEIVER gets everything including extra
        LeadInvestor[] memory leadInvestors = new LeadInvestor[](1);
        leadInvestors[0] = LeadInvestor({account: LEAD_A, profitFraction: CARRY_10PCT});
        CoinvestedPosition coinvestedPositionZeroCarry = _deployCoinvestedPosition(
            bytes32(0),
            100e6,
            eurc,
            leadInvestors
        );

        vm.prank(ADMIN);
        token.mint(address(coinvestedPositionZeroCarry), 10e18);
        vm.prank(OWNER);
        coinvestedPositionZeroCarry.setTokenPrice(100e6);
        vm.prank(OWNER);
        coinvestedPositionZeroCarry.unpause();

        eurc.mint(address(coinvestedPositionZeroCarry), 300e6); // extra

        uint256 paid = 100e6; // 1 token at base price
        eurc.mint(BUYER, paid);
        vm.prank(BUYER);
        eurc.approve(address(coinvestedPositionZeroCarry), paid);

        vm.prank(BUYER);
        coinvestedPositionZeroCarry.buy(1e18, paid, TOKEN_RECEIVER);

        assertEq(eurc.balanceOf(LEAD_A), 0, "lead investor got non-zero carry when carry=0");
        assertEq(eurc.balanceOf(RECEIVER), paid + 300e6, "RECEIVER did not get all including extra");
    }

    function testSettleDifferentCurrencyNotSwept() public {
        // Active currency = EURe; a pre-existing EURc balance stays on the contract
        vm.prank(OWNER);
        coinvestedPosition.setCurrency(IERC20(address(eure)), 100e18);

        vm.prank(ADMIN);
        token.mint(address(coinvestedPosition), 10e18);
        vm.prank(OWNER);
        coinvestedPosition.setTokenPrice(200e18);
        vm.prank(OWNER);
        coinvestedPosition.unpause();

        // Put EURc on the contract
        eurc.mint(address(coinvestedPosition), 1000e6);

        uint256 paid = 200e18;
        eure.mint(BUYER, paid);
        vm.prank(BUYER);
        eure.approve(address(coinvestedPosition), paid);

        vm.prank(BUYER);
        coinvestedPosition.buy(1e18, paid, TOKEN_RECEIVER);

        // EURc should remain on contract (not swept)
        assertEq(eurc.balanceOf(address(coinvestedPosition)), 1000e6, "EURc was swept");
        // EURe swept to RECEIVER and leads
        assertEq(eure.balanceOf(address(coinvestedPosition)), 0, "EURe not fully distributed");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // ── Section 10: Fuzz ──────────────────────────────────────────────────────
    // ─────────────────────────────────────────────────────────────────────────

    /// @dev Verify lead-investor balances and the RECEIVER after a buy.
    ///      Extracted to avoid stack-too-deep in the fuzz entry point.
    function _assertCarrySplit(
        uint8 numLeads,
        uint64[] memory carries,
        address[] memory leadAddrs,
        uint256 spent,
        uint256 carry
    ) internal view {
        uint256 totalLeadShares;
        for (uint8 i = 0; i < numLeads; i++) {
            uint256 expectedShare = (uint256(carries[i]) * carry) / type(uint64).max;
            assertEq(eurc.balanceOf(leadAddrs[i]), expectedShare, "lead share mismatch");
            totalLeadShares += expectedShare;
        }
        assertEq(eurc.balanceOf(RECEIVER), spent - totalLeadShares, "RECEIVER mismatch");
        assertEq(eurc.balanceOf(RECEIVER) + totalLeadShares, spent, "payout sum invariant violated");
    }

    /// @dev Fuzz sell price, token amount, number of lead investors (1–10) and
    ///      their carry fractions.  Verifies:
    ///      1. Each lead investor receives exactly floor(carry × fraction / uint64.max).
    ///      2. The RECEIVER gets exactly (spent − Σ lead shares).
    ///      3. Σ all payouts == currency spent by the BUYER (conservation).
    function testFuzz_ComplexCarrySplitMultiLeadInvestors(
        uint8 numLeads,
        uint64[10] memory rawCarries,
        uint96 tokenAmt,
        uint64 priceAboveBase
    ) public {
        // ── Bound inputs ──────────────────────────────────────────────────────
        numLeads = uint8(bound(uint256(numLeads), 1, 10));
        tokenAmt = uint96(bound(uint256(tokenAmt), 1, 1e24));

        // Arrays hoisted so they survive the inner scope and reach the assertion
        address[] memory leadAddrs = new address[](numLeads);
        uint64[] memory carries = new uint64[](numLeads);
        uint256 spent;
        uint256 carry;

        // ── Scoped block: frees leadInvestors, fuzzPosition, etc. from stack ──
        // tokenPrice ≥ basePrice (100e6) so carry is always non-negative
        {
            uint256 tokenPrice = uint256(100e6) + uint256(priceAboveBase);

            // Cap each fraction so the sum can't overflow uint64:
            //   maxPerInvestor × numLeads ≤ uint64.max   ✓
            LeadInvestor[] memory leadInvestors = new LeadInvestor[](numLeads);
            for (uint8 i = 0; i < numLeads; i++) {
                carries[i] = uint64(bound(uint256(rawCarries[i]), 1, type(uint64).max / uint64(numLeads)));
                // Low addresses that don't collide with any named test constant
                leadAddrs[i] = address(uint160(0x2000 + i));
                leadInvestors[i] = LeadInvestor({account: leadAddrs[i], profitFraction: carries[i]});
            }

            CoinvestedPosition fuzzPosition = _deployCoinvestedPosition(
                keccak256(abi.encodePacked(numLeads, tokenAmt, priceAboveBase)),
                100e6,
                eurc,
                leadInvestors
            );
            vm.prank(ADMIN);
            token.mint(address(fuzzPosition), tokenAmt);
            vm.prank(OWNER);
            fuzzPosition.setTokenPrice(tokenPrice);
            vm.prank(OWNER);
            fuzzPosition.unpause();

            uint256 currencyAmount = (uint256(tokenAmt) * tokenPrice + 1e18 - 1) / 1e18;
            eurc.mint(BUYER, currencyAmount);
            vm.prank(BUYER);
            eurc.approve(address(fuzzPosition), currencyAmount);

            uint256 buyerBefore = eurc.balanceOf(BUYER);
            vm.prank(BUYER);
            fuzzPosition.buy(tokenAmt, currencyAmount, TOKEN_RECEIVER);
            spent = buyerBefore - eurc.balanceOf(BUYER);

            // basePayout = floor(tokenAmt × scaledBasePrice / 1e18)
            // scaledBasePrice = 100e6 (basePriceDecimals == currencyDecimals, no scaling)
            uint256 basePayout = (uint256(tokenAmt) * 100e6) / 1e18;
            carry = spent > basePayout ? spent - basePayout : 0;
        }

        // ── Verify distribution ───────────────────────────────────────────────
        _assertCarrySplit(numLeads, carries, leadAddrs, spent, carry);
    }

    function testFuzz_BuyPayoutsSum(uint96 tokenAmt, uint64 priceAboveBase) public {
        vm.assume(tokenAmt > 0 && tokenAmt <= 1e24); // reasonable range
        uint256 tokenPrice = uint256(100e6) + uint256(priceAboveBase); // at or above base

        vm.prank(ADMIN);
        token.mint(address(coinvestedPosition), tokenAmt);
        vm.prank(OWNER);
        coinvestedPosition.setTokenPrice(tokenPrice);
        vm.prank(OWNER);
        coinvestedPosition.unpause();

        uint256 currencyAmount = (uint256(tokenAmt) * tokenPrice + 1e18 - 1) / 1e18; // ceil
        eurc.mint(BUYER, currencyAmount);
        vm.prank(BUYER);
        eurc.approve(address(coinvestedPosition), currencyAmount);

        uint256 buyerBalBefore = eurc.balanceOf(BUYER);

        vm.prank(BUYER);
        coinvestedPosition.buy(tokenAmt, currencyAmount, TOKEN_RECEIVER);

        uint256 spent = buyerBalBefore - eurc.balanceOf(BUYER);
        uint256 totalOut = eurc.balanceOf(LEAD_A) + eurc.balanceOf(LEAD_B) + eurc.balanceOf(RECEIVER);

        assertEq(spent, totalOut, "invariant: sum of payouts != currency paid");
    }

    function testFuzz_ScaleToDecimals(uint8 baseDecimals, uint128 basePrice) public {
        baseDecimals = uint8(bound(uint256(baseDecimals), 0, 36));
        vm.assume(basePrice > 0);

        // Compute scaledBasePrice as the contract will when currency switches to eure (18 dec).
        // Mirrors CoinvestedPosition._scaleToDecimals(basePrice, 18).
        uint256 scaledBasePrice;
        if (baseDecimals <= 18) {
            scaledBasePrice = uint256(basePrice) * 10 ** (18 - baseDecimals);
        } else {
            scaledBasePrice = uint256(basePrice) / 10 ** (baseDecimals - 18);
            vm.assume(scaledBasePrice > 0); // discard inputs where downscaling floors to 0
        }

        // Create a fresh currency with fuzzed decimals and register it
        FakePaymentToken fuzzCurrency = new FakePaymentToken(0, baseDecimals);
        vm.prank(ADMIN);
        allowList.set(address(fuzzCurrency), TRUSTED_CURRENCY);

        // Deploy coinvestedPosition with the fuzz currency and price
        CoinvestedPosition fuzzPosition = _deployCoinvestedPosition(
            keccak256(abi.encodePacked(baseDecimals, basePrice)),
            uint256(basePrice),
            fuzzCurrency,
            _defaultLeadInvestors()
        );

        // Assert initial state is stored correctly
        assertEq(fuzzPosition.basePrice(), uint256(basePrice), "basePrice");

        // Switch currency to eure (18 dec) and set tokenPrice = 2× scaledBasePrice
        // so carry = scaledBasePrice (50% markup over base)
        uint256 tokenPrice = 2 * scaledBasePrice;
        vm.prank(OWNER);
        fuzzPosition.setCurrency(IERC20(address(eure)), scaledBasePrice);

        vm.prank(ADMIN);
        token.mint(address(fuzzPosition), 1e18);
        vm.prank(OWNER);
        fuzzPosition.setTokenPrice(tokenPrice);
        vm.prank(OWNER);
        fuzzPosition.unpause();

        // Fund BUYER: 1 token × tokenPrice / 1e18 = tokenPrice exactly (no rounding)
        eure.mint(BUYER, tokenPrice);
        vm.prank(BUYER);
        eure.approve(address(fuzzPosition), tokenPrice);

        vm.prank(BUYER);
        fuzzPosition.buy(1e18, tokenPrice, TOKEN_RECEIVER);

        // carry = tokenPrice - scaledBasePrice (for 1 token) = scaledBasePrice
        uint256 carry = scaledBasePrice;
        uint256 expectedA = (uint256(CARRY_10PCT) * carry) / type(uint64).max;
        uint256 expectedB = (uint256(CARRY_5PCT) * carry) / type(uint64).max;
        uint256 expectedReceiver = tokenPrice - expectedA - expectedB;

        assertEq(eure.balanceOf(LEAD_A), expectedA, "LEAD_A carry");
        assertEq(eure.balanceOf(LEAD_B), expectedB, "LEAD_B carry");
        assertEq(eure.balanceOf(RECEIVER), expectedReceiver, "RECEIVER");
        assertEq(token.balanceOf(TOKEN_RECEIVER), 1e18, "tokens received");
    }

    function testFuzz_ScaleToDecimals_BaseCurrencyEure(uint8 buyCurrencyDecimals, uint128 basePrice) public {
        buyCurrencyDecimals = uint8(bound(uint256(buyCurrencyDecimals), 0, 36));
        vm.assume(basePrice > 0);

        // Deploy with eure (18 dec) as base currency; basePriceDecimals = 18.
        // Compute scaledBasePrice as the contract will when buy currency has buyCurrencyDecimals.
        // Mirrors CoinvestedPosition._scaleToDecimals(basePrice, buyCurrencyDecimals).
        uint256 scaledBasePrice;
        if (buyCurrencyDecimals >= 18) {
            scaledBasePrice = uint256(basePrice) * 10 ** (buyCurrencyDecimals - 18);
        } else {
            scaledBasePrice = uint256(basePrice) / 10 ** (18 - buyCurrencyDecimals);
            vm.assume(scaledBasePrice > 0); // discard inputs where downscaling floors to 0
        }

        // Deploy coinvestedPosition with eure as base currency
        CoinvestedPosition fuzzPosition = _deployCoinvestedPosition(
            keccak256(abi.encodePacked(buyCurrencyDecimals, basePrice)),
            uint256(basePrice),
            eure,
            _defaultLeadInvestors()
        );

        // Assert initial state is stored correctly
        assertEq(fuzzPosition.basePrice(), uint256(basePrice), "basePrice");

        // Create a fresh buy currency with fuzzed decimals and register it
        FakePaymentToken buyCurrency = new FakePaymentToken(0, buyCurrencyDecimals);
        vm.prank(ADMIN);
        allowList.set(address(buyCurrency), TRUSTED_CURRENCY);

        // Switch to the fuzz buy currency and set tokenPrice = 2× scaledBasePrice
        // so carry = scaledBasePrice (50% markup over base)
        uint256 tokenPrice = 2 * scaledBasePrice;
        vm.prank(OWNER);
        fuzzPosition.setCurrency(IERC20(address(buyCurrency)), scaledBasePrice);

        vm.prank(ADMIN);
        token.mint(address(fuzzPosition), 1e18);
        vm.prank(OWNER);
        fuzzPosition.setTokenPrice(tokenPrice);
        vm.prank(OWNER);
        fuzzPosition.unpause();

        // Fund BUYER: 1 token × tokenPrice / 1e18 = tokenPrice exactly (no rounding)
        buyCurrency.mint(BUYER, tokenPrice);
        vm.prank(BUYER);
        buyCurrency.approve(address(fuzzPosition), tokenPrice);

        vm.prank(BUYER);
        fuzzPosition.buy(1e18, tokenPrice, TOKEN_RECEIVER);

        // carry = tokenPrice - scaledBasePrice (for 1 token) = scaledBasePrice
        uint256 carry = scaledBasePrice;
        uint256 expectedA = (uint256(CARRY_10PCT) * carry) / type(uint64).max;
        uint256 expectedB = (uint256(CARRY_5PCT) * carry) / type(uint64).max;
        uint256 expectedReceiver = tokenPrice - expectedA - expectedB;

        assertEq(buyCurrency.balanceOf(LEAD_A), expectedA, "LEAD_A carry");
        assertEq(buyCurrency.balanceOf(LEAD_B), expectedB, "LEAD_B carry");
        assertEq(buyCurrency.balanceOf(RECEIVER), expectedReceiver, "RECEIVER");
        assertEq(token.balanceOf(TOKEN_RECEIVER), 1e18, "tokens received");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // ── Section 11: Access Control (consolidated) ─────────────────────────────
    // ─────────────────────────────────────────────────────────────────────────

    function testFuzz_AccessControl_SetCurrency(address caller) public {
        vm.assume(caller != address(0) && caller != OWNER && caller != TRUSTED_FORWARDER);
        vm.prank(caller);
        vm.expectRevert("Ownable: caller is not the owner");
        coinvestedPosition.setCurrency(IERC20(address(eure)), 1);
    }

    function testFuzz_AccessControl_SetTokenPrice(address caller) public {
        vm.assume(caller != address(0) && caller != OWNER && caller != TRUSTED_FORWARDER);
        vm.prank(caller);
        vm.expectRevert("Ownable: caller is not the owner");
        coinvestedPosition.setTokenPrice(200e6);
    }

    function testFuzz_AccessControl_SetReceiver(address caller) public {
        vm.assume(caller != address(0) && caller != OWNER && caller != TRUSTED_FORWARDER);
        vm.prank(caller);
        vm.expectRevert("Ownable: caller is not the owner");
        coinvestedPosition.setReceiver(caller);
    }

    function testFuzz_AccessControl_Pause(address caller) public {
        vm.assume(caller != address(0) && caller != OWNER && caller != TRUSTED_FORWARDER);
        vm.prank(OWNER);
        coinvestedPosition.setTokenPrice(200e6);
        vm.prank(OWNER);
        coinvestedPosition.unpause();
        vm.prank(caller);
        vm.expectRevert("Ownable: caller is not the owner");
        coinvestedPosition.pause();
    }

    function testFuzz_AccessControl_Unpause(address caller) public {
        vm.assume(caller != address(0) && caller != OWNER && caller != TRUSTED_FORWARDER);
        vm.prank(OWNER);
        coinvestedPosition.setTokenPrice(200e6);
        vm.prank(caller);
        vm.expectRevert("Ownable: caller is not the owner");
        coinvestedPosition.unpause();
    }

    // ─────────────────────────────────────────────────────────────────────────
    // ── Section 12: Reentrancy ────────────────────────────────────────────────
    // ─────────────────────────────────────────────────────────────────────────

    // ─────────────────────────────────────────────────────────────────────────
    // ── Section 13: _settle rejects currency == held token ───────────────────
    // ─────────────────────────────────────────────────────────────────────────

    function testBuyRevertsWhenCurrencyIsHeldToken() public {
        // Give token TRUSTED_CURRENCY so the allowList check passes
        vm.prank(ADMIN);
        allowList.set(address(token), TRUSTED_CURRENCY);

        // setCurrency itself must reject the held token as currency
        vm.expectRevert("currency cannot be the held token");
        vm.prank(OWNER);
        coinvestedPosition.setCurrency(IERC20(address(token)), 1);
    }

    function testReentrancyBuyReverts() public {
        // Deploy malicious currency
        MaliciousCoinvestedToken malicious = new MaliciousCoinvestedToken();

        // Register on allowList
        vm.prank(ADMIN);
        allowList.set(address(malicious), TRUSTED_CURRENCY);

        // Deploy a coinvestedPosition using malicious currency
        LeadInvestor[] memory leadInvestors = _defaultLeadInvestors();
        CoinvestedPositionInitializerArguments memory args = CoinvestedPositionInitializerArguments({
            owner: OWNER,
            receiver: RECEIVER,
            leadInvestors: leadInvestors,
            basePrice: 100e6,
            baseCurrency: IERC20(address(malicious)),
            token: token,
            lockedUntil: 0,
            tokenExitRegistry: tokenExitRegistry
        });
        CoinvestedPosition coinvestedPositionMalicious = CoinvestedPosition(
            factory.createCoinvestedPositionClone(bytes32(0), TRUSTED_FORWARDER, args)
        );
        malicious.setTarget(address(coinvestedPositionMalicious));

        vm.prank(ADMIN);
        token.mint(address(coinvestedPositionMalicious), 100e18);
        vm.prank(OWNER);
        coinvestedPositionMalicious.setTokenPrice(200e6);
        vm.prank(OWNER);
        coinvestedPositionMalicious.unpause();

        malicious.mint(BUYER, 1000e6);
        vm.prank(BUYER);
        malicious.approve(address(coinvestedPositionMalicious), 1000e6);

        vm.prank(BUYER);
        vm.expectRevert("ReentrancyGuard: reentrant call");
        coinvestedPositionMalicious.buy(1e18, 1000e6, TOKEN_RECEIVER);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // ── Section: Additional revert coverage ───────────────────────────────────
    // ─────────────────────────────────────────────────────────────────────────

    function testInitZeroTokenExitRegistryReverts() public {
        CoinvestedPositionInitializerArguments memory args = CoinvestedPositionInitializerArguments({
            owner: OWNER,
            receiver: RECEIVER,
            leadInvestors: _defaultLeadInvestors(),
            basePrice: 100e6,
            baseCurrency: IERC20(address(eurc)),
            token: token,
            lockedUntil: 0,
            tokenExitRegistry: GlobalTokenExitRegistry(address(0))
        });
        vm.expectRevert("tokenExitRegistry can not be zero address");
        factory.createCoinvestedPositionClone(bytes32(0), TRUSTED_FORWARDER, args);
    }

    function testUnpauseRevertsIfTimelockNotExpired() public {
        uint64 futureUnlock = uint64(block.timestamp + 1000);
        CoinvestedPositionInitializerArguments memory args = CoinvestedPositionInitializerArguments({
            owner: OWNER,
            receiver: RECEIVER,
            leadInvestors: _defaultLeadInvestors(),
            basePrice: 100e6,
            baseCurrency: IERC20(address(eurc)),
            token: token,
            lockedUntil: futureUnlock,
            tokenExitRegistry: tokenExitRegistry
        });
        CoinvestedPosition locked = CoinvestedPosition(
            factory.createCoinvestedPositionClone(bytes32("1"), TRUSTED_FORWARDER, args)
        );

        vm.prank(OWNER);
        locked.setTokenPrice(200e6);

        vm.prank(OWNER);
        vm.expectRevert("timelock has not expired");
        locked.unpause();
    }

    function testSetCurrencyRevertsIfZeroAddress() public {
        vm.prank(OWNER);
        vm.expectRevert("zero address");
        coinvestedPosition.setCurrency(IERC20(address(0)), 1e6);
    }

    function testSetCurrencyRevertsIfBasePriceZero() public {
        vm.prank(OWNER);
        vm.expectRevert("altBasePrice must be > 0");
        coinvestedPosition.setCurrency(IERC20(address(eure)), 0);
    }

    function testClaimExitRevertsIfNoExitSet() public {
        vm.prank(ADMIN);
        token.mint(address(coinvestedPosition), 100e18);

        vm.prank(OWNER);
        vm.expectRevert("no exit set in tokenExitRegistry");
        coinvestedPosition.claimExit(0, 0);
    }
}
