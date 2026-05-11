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

    /// 5% of uint64.max (floor)
    uint64 public constant CARRY_5PCT = type(uint64).max / 20;

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
        leads[0] = LeadInvestor({account: LEAD_A, profitFraction: CARRY_10PCT});
        leads[1] = LeadInvestor({account: LEAD_B, profitFraction: CARRY_5PCT});
        return leads;
    }

    function _deployWithBlacklistCurrency() internal returns (CoinvestedPosition) {
        CoinvestedPositionInitializerArguments memory args = CoinvestedPositionInitializerArguments({
            owner: OWNER,
            receiver: RECEIVER,
            leadInvestors: _defaultLeads(),
            basePrice: 100e6,
            baseCurrency: IERC20(address(blacklistCurrency)),
            token: token,
            lockedUntil: 0,
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
        // LEAD_A is blacklisted by the currency provider — buy() must still succeed.
        blacklistCurrency.setBlacklisted(LEAD_A, true);

        _setupAndBuy(2e18, 200e6, 400e6);

        // Credit accumulated, no transfer attempted yet → no DoS
        // 10% of 200e6 carry = 20e6 - 1 due to floor
        uint256 expectedA = (uint256(CARRY_10PCT) * 200e6) / type(uint64).max;
        assertEq(
            coinvestedPosition.leadInvestorCredit(0, IERC20(address(blacklistCurrency))),
            expectedA,
            "LEAD_A credit not accumulated"
        );

        // LEAD_B (not blacklisted) can withdraw; receiver can withdraw.
        vm.prank(LEAD_B);
        coinvestedPosition.withdrawAsLeadInvestor(1, IERC20(address(blacklistCurrency)));
        vm.prank(RECEIVER);
        coinvestedPosition.withdrawAsReceiver(IERC20(address(blacklistCurrency)));

        // LEAD_A's withdraw still reverts at the currency layer — but only LEAD_A is affected.
        vm.expectRevert("blacklisted recipient");
        vm.prank(LEAD_A);
        coinvestedPosition.withdrawAsLeadInvestor(0, IERC20(address(blacklistCurrency)));
    }

    function testBlacklistedReceiverDoesNotBlockBuy() public {
        // RECEIVER is blacklisted by the currency provider — buy() must still succeed.
        blacklistCurrency.setBlacklisted(RECEIVER, true);

        _setupAndBuy(2e18, 200e6, 400e6);

        // Lead investors can still withdraw their carry.
        vm.prank(LEAD_A);
        coinvestedPosition.withdrawAsLeadInvestor(0, IERC20(address(blacklistCurrency)));
        vm.prank(LEAD_B);
        coinvestedPosition.withdrawAsLeadInvestor(1, IERC20(address(blacklistCurrency)));

        // Receiver's withdraw reverts at the currency layer; receiver credit is preserved.
        assertGt(coinvestedPosition.receiverCredit(IERC20(address(blacklistCurrency))), 0, "receiver credit missing");
        vm.expectRevert("blacklisted recipient");
        vm.prank(RECEIVER);
        coinvestedPosition.withdrawAsReceiver(IERC20(address(blacklistCurrency)));
    }

    // ─────────────────────────────────────────────────────────────────────────
    // ── Self-rotation recovery ────────────────────────────────────────────────
    // ─────────────────────────────────────────────────────────────────────────

    function testSelfRotationRecoversBlacklistedLeadInvestor() public {
        blacklistCurrency.setBlacklisted(LEAD_A, true);
        _setupAndBuy(2e18, 200e6, 400e6);

        uint256 expectedA = (uint256(CARRY_10PCT) * 200e6) / type(uint64).max;

        // LEAD_A self-rotates to a non-blacklisted address. ERC20 blacklisting does not
        // prevent the address from signing transactions — only currency transfers.
        vm.prank(LEAD_A);
        coinvestedPosition.setLeadInvestorAccount(0, LEAD_RESCUE);

        // The pending credit follows the index, so LEAD_RESCUE can now withdraw it.
        vm.prank(LEAD_RESCUE);
        coinvestedPosition.withdrawAsLeadInvestor(0, IERC20(address(blacklistCurrency)));

        assertEq(blacklistCurrency.balanceOf(LEAD_RESCUE), expectedA, "rescue address didn't receive credit");
        assertEq(coinvestedPosition.leadInvestorCredit(0, IERC20(address(blacklistCurrency))), 0, "credit not zeroed");
        // Old account no longer controls the slot.
        vm.expectRevert(CoinvestedPosition.NotLeadInvestor.selector);
        vm.prank(LEAD_A);
        coinvestedPosition.withdrawAsLeadInvestor(0, IERC20(address(blacklistCurrency)));
    }

    // ─────────────────────────────────────────────────────────────────────────
    // ── Access control on rotation and withdrawals ────────────────────────────
    // ─────────────────────────────────────────────────────────────────────────

    function testSetLeadInvestorAccountOnlyByCurrentLead() public {
        // Owner cannot rotate (self-rotation only).
        vm.expectRevert(CoinvestedPosition.NotLeadInvestor.selector);
        vm.prank(OWNER);
        coinvestedPosition.setLeadInvestorAccount(0, LEAD_RESCUE);

        // A random caller cannot rotate.
        vm.expectRevert(CoinvestedPosition.NotLeadInvestor.selector);
        vm.prank(address(0xDEAD));
        coinvestedPosition.setLeadInvestorAccount(0, LEAD_RESCUE);

        // The current lead investor at the slot can.
        vm.prank(LEAD_A);
        coinvestedPosition.setLeadInvestorAccount(0, LEAD_RESCUE);
        (address acc, ) = coinvestedPosition.leadInvestors(0);
        assertEq(acc, LEAD_RESCUE, "rotation did not persist");
    }

    function testSetLeadInvestorAccountRejectsZeroAddress() public {
        vm.expectRevert(CoinvestedPosition.ZeroLeadInvestorAddress.selector);
        vm.prank(LEAD_A);
        coinvestedPosition.setLeadInvestorAccount(0, address(0));
    }

    function testSetLeadInvestorAccountRevertsOnIndexOutOfBounds() public {
        // Out-of-bounds index → Solidity 0.8+ array-access panic (0x32).
        vm.expectRevert();
        vm.prank(LEAD_A);
        coinvestedPosition.setLeadInvestorAccount(99, LEAD_RESCUE);
    }

    function testSetLeadInvestorAccountEmitsEvent() public {
        vm.expectEmit(true, true, true, true);
        emit CoinvestedPosition.LeadInvestorAccountChanged(0, LEAD_A, LEAD_RESCUE);
        vm.prank(LEAD_A);
        coinvestedPosition.setLeadInvestorAccount(0, LEAD_RESCUE);
    }

    function testWithdrawAsLeadInvestorRejectsNonLead() public {
        _setupAndBuy(2e18, 200e6, 400e6);
        vm.expectRevert(CoinvestedPosition.NotLeadInvestor.selector);
        vm.prank(address(0xBEEF));
        coinvestedPosition.withdrawAsLeadInvestor(0, IERC20(address(blacklistCurrency)));
    }

    function testWithdrawAsLeadInvestorRevertsOnZeroCredit() public {
        // No buy yet → zero credit
        vm.expectRevert(ZeroAmount.selector);
        vm.prank(LEAD_A);
        coinvestedPosition.withdrawAsLeadInvestor(0, IERC20(address(blacklistCurrency)));
    }

    function testWithdrawAsReceiverRejectsNonReceiver() public {
        _setupAndBuy(2e18, 200e6, 400e6);
        vm.expectRevert(CoinvestedPosition.NotReceiver.selector);
        vm.prank(address(0xBEEF));
        coinvestedPosition.withdrawAsReceiver(IERC20(address(blacklistCurrency)));
    }

    function testWithdrawAsReceiverRevertsOnZeroCredit() public {
        vm.expectRevert(ZeroAmount.selector);
        vm.prank(RECEIVER);
        coinvestedPosition.withdrawAsReceiver(IERC20(address(blacklistCurrency)));
    }

    // ─────────────────────────────────────────────────────────────────────────
    // ── sweepUntracked correctness ────────────────────────────────────────────
    // ─────────────────────────────────────────────────────────────────────────

    function testSweepUntrackedMovesOnlyUntrackedToReceiver() public {
        _setupAndBuy(2e18, 200e6, 400e6);

        // Credits exist; balance == totalCredit. sweepUntracked must revert with ZeroAmount.
        vm.expectRevert(ZeroAmount.selector);
        vm.prank(OWNER);
        coinvestedPosition.sweepUntracked(IERC20(address(blacklistCurrency)));

        uint256 leadACreditBefore = coinvestedPosition.leadInvestorCredit(0, IERC20(address(blacklistCurrency)));
        uint256 receiverCreditBefore = coinvestedPosition.receiverCredit(IERC20(address(blacklistCurrency)));

        // Mint extra (untracked) currency directly to the contract.
        uint256 extra = 123e6;
        blacklistCurrency.mint(address(coinvestedPosition), extra);

        vm.prank(OWNER);
        coinvestedPosition.sweepUntracked(IERC20(address(blacklistCurrency)));

        // Lead-investor credits are unchanged; receiver credit increased by exactly `extra`.
        assertEq(
            coinvestedPosition.leadInvestorCredit(0, IERC20(address(blacklistCurrency))),
            leadACreditBefore,
            "lead credit was disturbed"
        );
        assertEq(
            coinvestedPosition.receiverCredit(IERC20(address(blacklistCurrency))),
            receiverCreditBefore + extra,
            "receiver credit not increased by exactly extra"
        );
    }

    function testSweepUntrackedRejectsHeldToken() public {
        // Mark token as TRUSTED_CURRENCY just so we can attempt sweepUntracked on it
        vm.prank(ADMIN);
        allowList.set(address(token), TRUSTED_CURRENCY);

        vm.expectRevert(CurrencyEqualsToken.selector);
        vm.prank(OWNER);
        coinvestedPosition.sweepUntracked(IERC20(address(token)));
    }

    function testSweepUntrackedOnlyOwner() public {
        blacklistCurrency.mint(address(coinvestedPosition), 100e6);
        vm.expectRevert("Ownable: caller is not the owner");
        vm.prank(address(0xBEEF));
        coinvestedPosition.sweepUntracked(IERC20(address(blacklistCurrency)));
    }

    // ─────────────────────────────────────────────────────────────────────────
    // ── Receiver rotation ─────────────────────────────────────────────────────
    // ─────────────────────────────────────────────────────────────────────────

    function testReceiverRotationRedirectsPendingPot() public {
        _setupAndBuy(2e18, 200e6, 400e6);

        uint256 receiverCreditAmt = coinvestedPosition.receiverCredit(IERC20(address(blacklistCurrency)));
        assertGt(receiverCreditAmt, 0, "no receiver credit accumulated");

        // Owner rotates receiver before the old receiver withdraws.
        address NEW_RECEIVER = address(0xCAFEBABE);
        vm.prank(OWNER);
        coinvestedPosition.setReceiver(NEW_RECEIVER);

        // Old receiver no longer controls the pot.
        vm.expectRevert(CoinvestedPosition.NotReceiver.selector);
        vm.prank(RECEIVER);
        coinvestedPosition.withdrawAsReceiver(IERC20(address(blacklistCurrency)));

        // New receiver gets the entire pending pot.
        vm.prank(NEW_RECEIVER);
        coinvestedPosition.withdrawAsReceiver(IERC20(address(blacklistCurrency)));
        assertEq(blacklistCurrency.balanceOf(NEW_RECEIVER), receiverCreditAmt, "new receiver did not get pot");
        assertEq(blacklistCurrency.balanceOf(RECEIVER), 0, "old receiver received funds after rotation");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // ── Credit invariant fuzz ─────────────────────────────────────────────────
    // ─────────────────────────────────────────────────────────────────────────

    /// After any successful buy, the bookkeeping invariant holds:
    ///   receiverCredit + Σ leadInvestorCredit[i] == totalCredit
    /// And the contract holds at least totalCredit.
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
        uint256 leadCount = coinvestedPosition.getLeadInvestorsCount();
        for (uint256 i = 0; i < leadCount; i++) {
            sumLeads += coinvestedPosition.leadInvestorCredit(i, c);
        }
        uint256 receiverPot = coinvestedPosition.receiverCredit(c);
        uint256 total = coinvestedPosition.totalCredit(c);

        assertEq(sumLeads + receiverPot, total, "totalCredit != sum of credits");
        assertGe(blacklistCurrency.balanceOf(address(coinvestedPosition)), total, "contract balance < totalCredit");
    }
}
