// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import "./resources/CoinvestedPositionTestBase.sol";

/// ERC20 stand-in that reverts on `transfer` to a configured "blacklisted" address.
/// Mirrors how USDC/USDT enforce blacklists at the currency-contract level.
contract BlacklistingPaymentToken is FakePaymentToken {
    mapping(address => bool) public blacklisted;

    constructor(uint8 _decimals) FakePaymentToken(0, _decimals) {}

    function setBlacklisted(address account, bool value) external {
        blacklisted[account] = value;
    }

    function transfer(address to, uint256 amount) public override returns (bool) {
        require(!blacklisted[to], "blacklisted recipient");
        return super.transfer(to, amount);
    }

    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        require(!blacklisted[from] && !blacklisted[to], "blacklisted");
        return super.transferFrom(from, to, amount);
    }
}

contract CoinvestedPositionPullPayoutsTest is CoinvestedPositionTestBase {
    address public constant BUYER = 0x1109709ecFA91a80626ff3989D68f67F5B1Dd121;
    address public constant LEAD_B = 0x3109709ECfA91A80626fF3989D68f67F5B1Dd123;
    address public constant LEAD_RESCUE = 0xc109709eCFa91a80626FF3989D68f67F5B1Dd12C;

    /// 5% of uint32.max (floor)
    uint32 public constant CARRY_5PCT = type(uint32).max / 20;

    BlacklistingPaymentToken blacklistCurrency;
    CoinvestedPosition logic;
    CoinvestedPositionCloneFactory factory;

    function setUp() public {
        allowList = createAllowList(TRUSTED_FORWARDER, ADMIN);
        feeSettings = createFeeSettings(TRUSTED_FORWARDER, ADMIN, buildFeeTypes(0, 0, 0, ADMIN, ADMIN, ADMIN));

        blacklistCurrency = new BlacklistingPaymentToken(6);
        eurc = new FakePaymentToken(0, 6);

        vm.startPrank(ADMIN);
        allowList.set(address(blacklistCurrency), TRUSTED_CURRENCY);
        allowList.set(address(eurc), TRUSTED_CURRENCY);
        vm.stopPrank();

        address tokenLogic = address(new Token(TRUSTED_FORWARDER));
        tokenFactory = new TokenProxyFactory(tokenLogic);
        token = Token(
            tokenFactory.createTokenProxy(0, TRUSTED_FORWARDER, feeSettings, ADMIN, allowList, 0, "TestToken", "TTK")
        );

        vm.startPrank(ADMIN);
        token.grantRole(token.MINTALLOWER_ROLE(), ADMIN);
        vm.stopPrank();

        logic = new CoinvestedPosition(TRUSTED_FORWARDER);
        factory = new CoinvestedPositionCloneFactory(address(logic));

        tokenExitRegistry = new GlobalTokenExitRegistry(TRUSTED_FORWARDER);

        coinvestedPosition = _deployWithBlacklistCurrency();
    }

    function _defaultLeads() internal pure returns (LeadInvestor[] memory) {
        LeadInvestor[] memory leads = new LeadInvestor[](2);
        leads[0] = LeadInvestor({account: LEAD_A, profitFraction: CARRY_10PCT, recoveryArmedAt: 0});
        leads[1] = LeadInvestor({account: LEAD_B, profitFraction: CARRY_5PCT, recoveryArmedAt: 0});
        return leads;
    }

    function _deployWithBlacklistCurrency() internal returns (CoinvestedPosition) {
        CoinvestedPositionInitializerArguments memory args = CoinvestedPositionInitializerArguments({
            owner: OWNER,
            leadInvestors: _defaultLeads(),
            basePrice: 100e6,
            baseCurrency: IERC20(address(blacklistCurrency)),
            token: token,
            lockedUntil: 1,
            tokenExitRegistry: tokenExitRegistry
        });
        return CoinvestedPosition(factory.createCoinvestedPositionClone(bytes32(0), TRUSTED_FORWARDER, args));
    }

    function _setupAndBuy(uint256 tokenAmount, uint256 tokenPrice, uint256 paid) internal {
        vm.prank(ADMIN);
        token.mint(address(coinvestedPosition), tokenAmount);
        vm.prank(OWNER);
        coinvestedPosition.setTokenPrice(tokenPrice);
        vm.prank(OWNER);
        coinvestedPosition.unpause();

        blacklistCurrency.mint(BUYER, paid);
        vm.prank(BUYER);
        blacklistCurrency.approve(address(coinvestedPosition), paid);
        vm.prank(BUYER);
        coinvestedPosition.buy(tokenAmount, paid, TOKEN_RECEIVER);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // ── Blacklist DoS regression ──────────────────────────────────────────────
    // ─────────────────────────────────────────────────────────────────────────

    function testBlacklistedLeadInvestorDoesNotBlockBuy() public {
        blacklistCurrency.setBlacklisted(LEAD_A, true);

        _setupAndBuy(2e18, 200e6, 400e6);

        // Credit accumulated, no transfer attempted during buy — no DoS.
        uint256 expectedA = (uint256(CARRY_10PCT) * 200e6) / type(uint32).max;
        assertEq(
            coinvestedPosition.leadInvestorCredit(0, IERC20(address(blacklistCurrency))),
            expectedA,
            "LEAD_A credit not accumulated"
        );

        // LEAD_B (not blacklisted) can withdraw; coinvestor can withdraw to any address.
        vm.prank(LEAD_B);
        coinvestedPosition.withdrawAsLeadInvestor(1, IERC20(address(blacklistCurrency)), LEAD_B);
        vm.prank(OWNER);
        coinvestedPosition.withdrawAsCoinvestor(IERC20(address(blacklistCurrency)), RECEIVER);

        // LEAD_A pulling to themselves reverts at currency layer — but only LEAD_A is affected.
        vm.expectRevert("blacklisted recipient");
        vm.prank(LEAD_A);
        coinvestedPosition.withdrawAsLeadInvestor(0, IERC20(address(blacklistCurrency)), LEAD_A);
    }

    function testBlacklistedCoinvestorDestinationDoesNotBlockLeadInvestors() public {
        _setupAndBuy(2e18, 200e6, 400e6);

        // RECEIVER is blacklisted — but the coinvestor (owner) can route to any destination.
        blacklistCurrency.setBlacklisted(RECEIVER, true);

        // Lead investors are unaffected.
        vm.prank(LEAD_A);
        coinvestedPosition.withdrawAsLeadInvestor(0, IERC20(address(blacklistCurrency)), LEAD_A);
        vm.prank(LEAD_B);
        coinvestedPosition.withdrawAsLeadInvestor(1, IERC20(address(blacklistCurrency)), LEAD_B);

        // Owner routes coinvestor share to an unblacklisted address.
        address altDest = address(0xABCD);
        vm.prank(OWNER);
        coinvestedPosition.withdrawAsCoinvestor(IERC20(address(blacklistCurrency)), altDest);
        assertGt(blacklistCurrency.balanceOf(altDest), 0, "alt destination received nothing");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // ── Self-rotation recovery ────────────────────────────────────────────────
    // ─────────────────────────────────────────────────────────────────────────

    function testSelfRotationRecoversBlacklistedLeadInvestor() public {
        blacklistCurrency.setBlacklisted(LEAD_A, true);
        _setupAndBuy(2e18, 200e6, 400e6);

        uint256 expectedA = (uint256(CARRY_10PCT) * 200e6) / type(uint32).max;

        // ERC20 blacklisting only blocks currency transfers — LEAD_A can still sign transactions.
        vm.prank(LEAD_A);
        coinvestedPosition.rotateLeadInvestorAccount(0, LEAD_RESCUE);

        // Credit follows the index: LEAD_RESCUE can now withdraw it.
        vm.prank(LEAD_RESCUE);
        coinvestedPosition.withdrawAsLeadInvestor(0, IERC20(address(blacklistCurrency)), LEAD_RESCUE);

        assertEq(blacklistCurrency.balanceOf(LEAD_RESCUE), expectedA, "rescue address didn't receive credit");
        assertEq(coinvestedPosition.leadInvestorCredit(0, IERC20(address(blacklistCurrency))), 0, "credit not zeroed");
        vm.expectRevert(CoinvestedPosition.NotLeadInvestor.selector);
        vm.prank(LEAD_A);
        coinvestedPosition.withdrawAsLeadInvestor(0, IERC20(address(blacklistCurrency)), LEAD_A);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // ── Access control on rotation and withdrawals ────────────────────────────
    // ─────────────────────────────────────────────────────────────────────────

    function testRotateLeadInvestorAccountOnlyByCurrentLead() public {
        vm.expectRevert(CoinvestedPosition.NotLeadInvestor.selector);
        vm.prank(OWNER);
        coinvestedPosition.rotateLeadInvestorAccount(0, LEAD_RESCUE);

        vm.expectRevert(CoinvestedPosition.NotLeadInvestor.selector);
        vm.prank(address(0xDEAD));
        coinvestedPosition.rotateLeadInvestorAccount(0, LEAD_RESCUE);

        vm.prank(LEAD_A);
        coinvestedPosition.rotateLeadInvestorAccount(0, LEAD_RESCUE);
        (address acc, , ) = coinvestedPosition.leadInvestors(0);
        assertEq(acc, LEAD_RESCUE, "rotation did not persist");
    }

    function testRotateLeadInvestorAccountRejectsZeroAddress() public {
        vm.expectRevert(CoinvestedPosition.ZeroLeadInvestorAddress.selector);
        vm.prank(LEAD_A);
        coinvestedPosition.rotateLeadInvestorAccount(0, address(0));
    }

    function testRotateLeadInvestorAccountRevertsOnIndexOutOfBounds() public {
        vm.expectRevert();
        vm.prank(LEAD_A);
        coinvestedPosition.rotateLeadInvestorAccount(99, LEAD_RESCUE);
    }

    function testRotateLeadInvestorAccountEmitsEvent() public {
        vm.expectEmit(true, true, true, true);
        emit CoinvestedPosition.LeadInvestorAccountRotated(0, LEAD_A, LEAD_RESCUE);
        vm.prank(LEAD_A);
        coinvestedPosition.rotateLeadInvestorAccount(0, LEAD_RESCUE);
    }

    function testWithdrawAsLeadInvestorRejectsNonLead() public {
        _setupAndBuy(2e18, 200e6, 400e6);
        vm.expectRevert(CoinvestedPosition.NotLeadInvestor.selector);
        vm.prank(address(0xBEEF));
        coinvestedPosition.withdrawAsLeadInvestor(0, IERC20(address(blacklistCurrency)), address(0xBEEF));
    }

    function testWithdrawAsLeadInvestorRevertsOnZeroCredit() public {
        vm.expectRevert(ZeroAmount.selector);
        vm.prank(LEAD_A);
        coinvestedPosition.withdrawAsLeadInvestor(0, IERC20(address(blacklistCurrency)), LEAD_A);
    }

    function testWithdrawAsLeadInvestorRejectsZeroDestination() public {
        _setupAndBuy(2e18, 200e6, 400e6);
        vm.expectRevert(ZeroReceiverAddress.selector);
        vm.prank(LEAD_A);
        coinvestedPosition.withdrawAsLeadInvestor(0, IERC20(address(blacklistCurrency)), address(0));
    }

    function testWithdrawAsLeadInvestorRoutesAroundBlacklistedRegisteredAddress() public {
        // LEAD_A's registered address is blacklisted; they can still pull to a fresh address
        // without permanently rotating the slot.
        blacklistCurrency.setBlacklisted(LEAD_A, true);
        _setupAndBuy(2e18, 200e6, 400e6);

        uint256 expectedA = (uint256(CARRY_10PCT) * 200e6) / type(uint32).max;
        address altDest = address(0xBADCAFE);

        vm.prank(LEAD_A);
        coinvestedPosition.withdrawAsLeadInvestor(0, IERC20(address(blacklistCurrency)), altDest);

        assertEq(blacklistCurrency.balanceOf(altDest), expectedA, "altDest did not receive credit");
        assertEq(blacklistCurrency.balanceOf(LEAD_A), 0, "blacklisted address received funds");
        assertEq(coinvestedPosition.leadInvestorCredit(0, IERC20(address(blacklistCurrency))), 0, "credit not zeroed");

        // Slot still points at LEAD_A — no permanent rotation was required.
        (address acc, , ) = coinvestedPosition.leadInvestors(0);
        assertEq(acc, LEAD_A, "slot was unexpectedly rotated");
    }

    function testWithdrawAsCoinvestorOnlyOwner() public {
        _setupAndBuy(2e18, 200e6, 400e6);
        vm.expectRevert("Ownable: caller is not the owner");
        vm.prank(address(0xBEEF));
        coinvestedPosition.withdrawAsCoinvestor(IERC20(address(blacklistCurrency)), RECEIVER);
    }

    function testWithdrawAsCoinvestorRevertsOnZeroAmount() public {
        // No credit and no untracked balance → ZeroAmount.
        vm.expectRevert(ZeroAmount.selector);
        vm.prank(OWNER);
        coinvestedPosition.withdrawAsCoinvestor(IERC20(address(blacklistCurrency)), RECEIVER);
    }

    function testWithdrawAsCoinvestorRejectsZeroDestination() public {
        _setupAndBuy(2e18, 200e6, 400e6);
        vm.expectRevert(ZeroReceiverAddress.selector);
        vm.prank(OWNER);
        coinvestedPosition.withdrawAsCoinvestor(IERC20(address(blacklistCurrency)), address(0));
    }

    function testWithdrawAsCoinvestorCanRouteToAnyDestination() public {
        _setupAndBuy(2e18, 200e6, 400e6);

        uint256 coinvestorOwed = coinvestedPosition.coinvestorCredit(IERC20(address(blacklistCurrency)));
        assertGt(coinvestorOwed, 0, "no coinvestor credit");

        address dest = address(0xCAFE);
        vm.prank(OWNER);
        coinvestedPosition.withdrawAsCoinvestor(IERC20(address(blacklistCurrency)), dest);
        assertEq(blacklistCurrency.balanceOf(dest), coinvestorOwed, "wrong amount at destination");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // ── Auto-sweep of untracked balance via withdrawAsCoinvestor ─────────────
    // ─────────────────────────────────────────────────────────────────────────

    function testWithdrawAsCoinvestorSweepsUntrackedBalance() public {
        _setupAndBuy(2e18, 200e6, 400e6);

        uint256 coinvestorOwed = coinvestedPosition.coinvestorCredit(IERC20(address(blacklistCurrency)));
        uint256 leadACreditBefore = coinvestedPosition.leadInvestorCredit(0, IERC20(address(blacklistCurrency)));

        // Mint extra (untracked) currency directly to the contract.
        uint256 extra = 123e6;
        blacklistCurrency.mint(address(coinvestedPosition), extra);

        vm.prank(OWNER);
        coinvestedPosition.withdrawAsCoinvestor(IERC20(address(blacklistCurrency)), RECEIVER);

        // Lead credit is unchanged; coinvestor received their credit + extra.
        assertEq(
            coinvestedPosition.leadInvestorCredit(0, IERC20(address(blacklistCurrency))),
            leadACreditBefore,
            "lead credit was disturbed"
        );
        assertEq(blacklistCurrency.balanceOf(RECEIVER), coinvestorOwed + extra, "sweep not included in withdrawal");
    }

    function testWithdrawAsCoinvestorSweepsWithNoCreditToo() public {
        // No prior buy — coinvestorCredit == 0. But extra currency was sent to the contract.
        uint256 extra = 100e6;
        blacklistCurrency.mint(address(coinvestedPosition), extra);

        vm.prank(OWNER);
        coinvestedPosition.withdrawAsCoinvestor(IERC20(address(blacklistCurrency)), RECEIVER);
        assertEq(blacklistCurrency.balanceOf(RECEIVER), extra, "untracked not swept");
    }

    function testWithdrawAsCoinvestorEmitsSeparateWithdrawnAndSweptEvents() public {
        _setupAndBuy(2e18, 200e6, 400e6);
        uint256 owed = coinvestedPosition.coinvestorCredit(IERC20(address(blacklistCurrency)));
        uint256 extra = 55e6;
        blacklistCurrency.mint(address(coinvestedPosition), extra);

        vm.expectEmit(true, true, false, true);
        emit CoinvestedPosition.CoinvestorWithdrawn(IERC20(address(blacklistCurrency)), RECEIVER, owed);
        vm.expectEmit(true, true, false, true);
        emit CoinvestedPosition.CoinvestorSwept(IERC20(address(blacklistCurrency)), RECEIVER, extra);
        vm.prank(OWNER);
        coinvestedPosition.withdrawAsCoinvestor(IERC20(address(blacklistCurrency)), RECEIVER);
    }

    function testWithdrawAsCoinvestorRejectsHeldToken() public {
        vm.prank(ADMIN);
        allowList.set(address(token), TRUSTED_CURRENCY);
        vm.expectRevert(CurrencyEqualsToken.selector);
        vm.prank(OWNER);
        coinvestedPosition.withdrawAsCoinvestor(IERC20(address(token)), RECEIVER);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // ── Credit invariant fuzz ─────────────────────────────────────────────────
    // ─────────────────────────────────────────────────────────────────────────

    function testFuzz_CreditInvariantAfterBuy(uint96 tokenAmt, uint64 priceAboveBase) public {
        vm.assume(tokenAmt > 0 && tokenAmt <= 1e24);
        uint256 tokenPrice = 100e6 + uint256(priceAboveBase);

        vm.prank(ADMIN);
        token.mint(address(coinvestedPosition), tokenAmt);
        vm.prank(OWNER);
        coinvestedPosition.setTokenPrice(tokenPrice);
        vm.prank(OWNER);
        coinvestedPosition.unpause();

        uint256 currencyAmount = (uint256(tokenAmt) * tokenPrice + 1e18 - 1) / 1e18;
        blacklistCurrency.mint(BUYER, currencyAmount);
        vm.prank(BUYER);
        blacklistCurrency.approve(address(coinvestedPosition), currencyAmount);
        vm.prank(BUYER);
        coinvestedPosition.buy(tokenAmt, currencyAmount, TOKEN_RECEIVER);

        IERC20 c = IERC20(address(blacklistCurrency));
        uint256 sumLeads;
        for (uint256 i = 0; i < coinvestedPosition.getLeadInvestorsCount(); i++) {
            sumLeads += coinvestedPosition.leadInvestorCredit(i, c);
        }
        uint256 coinvestorPot = coinvestedPosition.coinvestorCredit(c);
        uint256 total = coinvestedPosition.totalCredit(c);

        assertEq(sumLeads + coinvestorPot, total, "totalCredit != sum of credits");
        assertEq(blacklistCurrency.balanceOf(address(coinvestedPosition)), total, "balance != totalCredit");
    }
}
