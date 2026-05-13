// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import "./resources/CoinvestedPositionTestBase.sol";

/**
 * Integration test: multi-lead, multi-currency, multi-buy credit tracking.
 *
 * Scenario (all fees = 0):
 *   Phase 1 – currencyA, buy 2 tokens at 200e6
 *              assert credits, withdraw lead A, send extra balance, withdraw coinvestor
 *   Phase 2 – currencyA, buy 1 token at 150e6
 *              assert accumulated credits for leads B and C
 *   Phase 3 – switch to currencyB, buy 3 tokens at 300e18
 *              assert currencyB credits; currencyA credits unchanged
 *   Final   – withdraw all leads + coinvestor in both currencies; verify balances + conservation
 */
contract CoinvestedPositionCreditTrackingTest is CoinvestedPositionTestBase {
    address public constant BUYER = 0x1109709ecFA91a80626ff3989D68f67F5B1Dd121;
    address public constant LEAD_B = 0x3109709ECfA91A80626fF3989D68f67F5B1Dd123;
    address public constant LEAD_C = 0x4109709eCFa91A80626ff3989d68F67f5b1DD124;
    address public constant COINVESTOR_DEST = 0xD109709eCFA91a80626ff3989d68F67f5B1Dd12D;

    uint64 public constant CARRY_5PCT = type(uint64).max / 20;
    uint64 public constant CARRY_3PCT = uint64((uint256(type(uint64).max) * 3) / 100);

    uint256 public constant BASE_PRICE_A = 100e6;
    uint256 public constant EXTRA = 77e6; // accidentally-sent currencyA

    FakePaymentToken currencyA; // 6 decimals
    FakePaymentToken currencyB; // 18 decimals

    function setUp() public {
        allowList = createAllowList(TRUSTED_FORWARDER, ADMIN);
        feeSettings = createFeeSettings(TRUSTED_FORWARDER, ADMIN, buildFeeTypes(0, 0, 0, ADMIN, ADMIN, ADMIN));

        currencyA = new FakePaymentToken(0, 6);
        currencyB = new FakePaymentToken(0, 18);
        vm.startPrank(ADMIN);
        allowList.set(address(currencyA), TRUSTED_CURRENCY);
        allowList.set(address(currencyB), TRUSTED_CURRENCY);
        vm.stopPrank();

        address tokenLogic = address(new Token(TRUSTED_FORWARDER));
        tokenFactory = new TokenProxyFactory(tokenLogic);
        token = Token(
            tokenFactory.createTokenProxy(0, TRUSTED_FORWARDER, feeSettings, ADMIN, allowList, 0, "TestToken", "TTK")
        );
        vm.startPrank(ADMIN);
        token.grantRole(token.MINTALLOWER_ROLE(), ADMIN);
        vm.stopPrank();

        tokenExitRegistry = new GlobalTokenExitRegistry(TRUSTED_FORWARDER);

        CoinvestedPosition logic = new CoinvestedPosition(TRUSTED_FORWARDER);
        CoinvestedPositionCloneFactory cpFactory = new CoinvestedPositionCloneFactory(address(logic));

        LeadInvestor[] memory leads = new LeadInvestor[](3);
        leads[0] = LeadInvestor({account: LEAD_A, profitFraction: CARRY_10PCT}); // 10%
        leads[1] = LeadInvestor({account: LEAD_B, profitFraction: CARRY_5PCT}); //  5%
        leads[2] = LeadInvestor({account: LEAD_C, profitFraction: CARRY_3PCT}); //  3%

        coinvestedPosition = CoinvestedPosition(
            cpFactory.createCoinvestedPositionClone(
                bytes32(0),
                TRUSTED_FORWARDER,
                CoinvestedPositionInitializerArguments({
                    owner: OWNER,
                    leadInvestors: leads,
                    basePrice: BASE_PRICE_A,
                    baseCurrency: IERC20(address(currencyA)),
                    token: token,
                    lockedUntil: 1,
                    tokenExitRegistry: tokenExitRegistry
                })
            )
        );

        vm.prank(ADMIN);
        token.mint(address(coinvestedPosition), 10e18);
    }

    function _carry(uint64 fraction, uint256 profit) internal pure returns (uint256) {
        return (uint256(fraction) * profit) / type(uint64).max;
    }

    function _enableBuy(uint256 tokenPrice) internal {
        vm.prank(OWNER);
        coinvestedPosition.setTokenPrice(tokenPrice);
        vm.prank(OWNER);
        coinvestedPosition.unpause();
    }

    function _buy(IERC20 currency, uint256 tokenAmount) internal {
        uint256 cost = (tokenAmount * coinvestedPosition.tokenPrice() + 1e18 - 1) / 1e18;
        FakePaymentToken(address(currency)).mint(BUYER, cost);
        vm.prank(BUYER);
        currency.approve(address(coinvestedPosition), cost);
        vm.prank(BUYER);
        coinvestedPosition.buy(tokenAmount, type(uint256).max, TOKEN_RECEIVER);
    }

    function _assertTotalCreditMatchesSum(IERC20 currency) internal view {
        uint256 sum = coinvestedPosition.coinvestorCredit(currency);
        for (uint256 i = 0; i < coinvestedPosition.getLeadInvestorsCount(); i++) {
            sum += coinvestedPosition.leadInvestorCredit(i, currency);
        }
        assertEq(sum, coinvestedPosition.totalCredit(currency), "totalCredit != sum of credits");
        assertEq(
            FakePaymentToken(address(currency)).balanceOf(address(coinvestedPosition)),
            coinvestedPosition.totalCredit(currency),
            "balance != totalCredit"
        );
    }

    function testMultiLeadMultiCurrencyMultiBuy() public {
        // Carry totals accumulated across phases, referenced in the final assertions.
        uint256 totalCarryA_A; // lead A total currencyA
        uint256 totalCarryB_A; // lead B total currencyA
        uint256 totalCarryC_A; // lead C total currencyA
        uint256 totalCoinvestorA; // coinvestor total currencyA (credit + sweep)

        // ── Phase 1: buy 2 tokens at 200e6 currencyA ─────────────────────────
        {
            // Verify all credits start at zero before any operation.
            assertEq(coinvestedPosition.leadInvestorCredit(0, IERC20(address(currencyA))), 0, "p1: leadA not 0");
            assertEq(coinvestedPosition.leadInvestorCredit(1, IERC20(address(currencyA))), 0, "p1: leadB not 0");
            assertEq(coinvestedPosition.leadInvestorCredit(2, IERC20(address(currencyA))), 0, "p1: leadC not 0");
            assertEq(coinvestedPosition.coinvestorCredit(IERC20(address(currencyA))), 0, "p1: coinvestor not 0");
            assertEq(coinvestedPosition.totalCredit(IERC20(address(currencyA))), 0, "p1: total credit not 0");

            _enableBuy(200e6);
            _buy(IERC20(address(currencyA)), 2e18);

            uint256 profit = 200e6; // 400e6 paid - 200e6 base
            uint256 cA = _carry(CARRY_10PCT, profit);
            uint256 cB = _carry(CARRY_5PCT, profit);
            uint256 cC = _carry(CARRY_3PCT, profit);
            uint256 cInv = 400e6 - cA - cB - cC;

            assertEq(coinvestedPosition.leadInvestorCredit(0, IERC20(address(currencyA))), cA, "p1: leadA");
            assertEq(coinvestedPosition.leadInvestorCredit(1, IERC20(address(currencyA))), cB, "p1: leadB");
            assertEq(coinvestedPosition.leadInvestorCredit(2, IERC20(address(currencyA))), cC, "p1: leadC");
            assertEq(coinvestedPosition.coinvestorCredit(IERC20(address(currencyA))), cInv, "p1: coinvestor");
            _assertTotalCreditMatchesSum(IERC20(address(currencyA)));

            // Withdraw lead A — their credit zeroes
            vm.prank(LEAD_A);
            coinvestedPosition.withdrawAsLeadInvestor(0, IERC20(address(currencyA)));
            assertEq(currencyA.balanceOf(LEAD_A), cA, "p1: leadA withdraw");
            assertEq(coinvestedPosition.leadInvestorCredit(0, IERC20(address(currencyA))), 0, "p1: leadA credit zero");
            _assertTotalCreditMatchesSum(IERC20(address(currencyA)));

            // Send extra untracked currencyA to contract; coinvestor withdraw sweeps it
            currencyA.mint(address(coinvestedPosition), EXTRA);
            vm.prank(OWNER);
            coinvestedPosition.withdrawAsCoinvestor(IERC20(address(currencyA)), COINVESTOR_DEST);
            assertEq(currencyA.balanceOf(COINVESTOR_DEST), cInv + EXTRA, "p1: coinvestor withdraw+sweep");
            assertEq(coinvestedPosition.coinvestorCredit(IERC20(address(currencyA))), 0, "p1: coinvestor credit zero");
            _assertTotalCreditMatchesSum(IERC20(address(currencyA)));

            totalCarryA_A += cA;
            totalCarryB_A += cB;
            totalCarryC_A += cC;
            totalCoinvestorA += cInv + EXTRA;
        }

        // ── Phase 2: buy 1 token at 150e6 currencyA ──────────────────────────
        {
            vm.prank(OWNER);
            coinvestedPosition.pause();
            _enableBuy(150e6);
            _buy(IERC20(address(currencyA)), 1e18);

            uint256 profit = 50e6; // 150e6 paid - 100e6 base
            uint256 cA = _carry(CARRY_10PCT, profit);
            uint256 cB = _carry(CARRY_5PCT, profit);
            uint256 cC = _carry(CARRY_3PCT, profit);
            uint256 cInv = 150e6 - cA - cB - cC;

            // Lead A started from 0 after phase-1 withdrawal
            assertEq(coinvestedPosition.leadInvestorCredit(0, IERC20(address(currencyA))), cA, "p2: leadA");
            // Leads B and C accumulated from phase 1 (still pending)
            assertEq(
                coinvestedPosition.leadInvestorCredit(1, IERC20(address(currencyA))),
                totalCarryB_A + cB,
                "p2: leadB cumulative"
            );
            assertEq(
                coinvestedPosition.leadInvestorCredit(2, IERC20(address(currencyA))),
                totalCarryC_A + cC,
                "p2: leadC cumulative"
            );
            assertEq(coinvestedPosition.coinvestorCredit(IERC20(address(currencyA))), cInv, "p2: coinvestor");
            _assertTotalCreditMatchesSum(IERC20(address(currencyA)));

            totalCarryA_A += cA;
            totalCarryB_A += cB;
            totalCarryC_A += cC;
            totalCoinvestorA += cInv;
        }

        // ── Phase 3: switch to currencyB, buy 3 tokens at 300e18 ─────────────
        uint256 totalCarryA_B;
        uint256 totalCarryB_B;
        uint256 totalCarryC_B;
        uint256 totalCoinvestorB;
        {
            vm.prank(OWNER);
            coinvestedPosition.pause();
            vm.prank(OWNER);
            coinvestedPosition.setCurrency(IERC20(address(currencyB)), 100e18, 300e18); // basePrice = 100e18, tokenPrice = 300e18 in currencyB
            _enableBuy(300e18);
            _buy(IERC20(address(currencyB)), 3e18);

            uint256 profit = 600e18; // 900e18 paid - 300e18 base
            uint256 cA = _carry(CARRY_10PCT, profit);
            uint256 cB = _carry(CARRY_5PCT, profit);
            uint256 cC = _carry(CARRY_3PCT, profit);
            uint256 cInv = 900e18 - cA - cB - cC;

            assertEq(coinvestedPosition.leadInvestorCredit(0, IERC20(address(currencyB))), cA, "p3: leadA currencyB");
            assertEq(coinvestedPosition.leadInvestorCredit(1, IERC20(address(currencyB))), cB, "p3: leadB currencyB");
            assertEq(coinvestedPosition.leadInvestorCredit(2, IERC20(address(currencyB))), cC, "p3: leadC currencyB");
            assertEq(coinvestedPosition.coinvestorCredit(IERC20(address(currencyB))), cInv, "p3: coinvestor currencyB");
            _assertTotalCreditMatchesSum(IERC20(address(currencyB)));

            // currencyA credits are unaffected by the currencyB buy
            assertEq(
                coinvestedPosition.leadInvestorCredit(0, IERC20(address(currencyA))),
                totalCarryA_A - _carry(CARRY_10PCT, 200e6), // phase-2 only (phase-1 was withdrawn)
                "p3: leadA currencyA unchanged"
            );
            _assertTotalCreditMatchesSum(IERC20(address(currencyA)));

            totalCarryA_B = cA;
            totalCarryB_B = cB;
            totalCarryC_B = cC;
            totalCoinvestorB = cInv;
        }

        // ── Final: drain all, verify balances and conservation ────────────────
        {
            vm.prank(LEAD_A);
            coinvestedPosition.withdrawAsLeadInvestor(0, IERC20(address(currencyA)));
            vm.prank(LEAD_A);
            coinvestedPosition.withdrawAsLeadInvestor(0, IERC20(address(currencyB)));

            vm.prank(LEAD_B);
            coinvestedPosition.withdrawAsLeadInvestor(1, IERC20(address(currencyA)));
            vm.prank(LEAD_B);
            coinvestedPosition.withdrawAsLeadInvestor(1, IERC20(address(currencyB)));

            vm.prank(LEAD_C);
            coinvestedPosition.withdrawAsLeadInvestor(2, IERC20(address(currencyA)));
            vm.prank(LEAD_C);
            coinvestedPosition.withdrawAsLeadInvestor(2, IERC20(address(currencyB)));

            vm.prank(OWNER);
            coinvestedPosition.withdrawAsCoinvestor(IERC20(address(currencyA)), COINVESTOR_DEST);
            vm.prank(OWNER);
            coinvestedPosition.withdrawAsCoinvestor(IERC20(address(currencyB)), COINVESTOR_DEST);
        }

        // Lead A: already received carryA from phase 1, now gets phase 2 + phase 3
        assertEq(currencyA.balanceOf(LEAD_A), totalCarryA_A, "final: leadA currencyA");
        assertEq(currencyA.balanceOf(LEAD_B), totalCarryB_A, "final: leadB currencyA");
        assertEq(currencyA.balanceOf(LEAD_C), totalCarryC_A, "final: leadC currencyA");
        assertEq(currencyA.balanceOf(COINVESTOR_DEST), totalCoinvestorA, "final: coinvestor currencyA");

        assertEq(currencyB.balanceOf(LEAD_A), totalCarryA_B, "final: leadA currencyB");
        assertEq(currencyB.balanceOf(LEAD_B), totalCarryB_B, "final: leadB currencyB");
        assertEq(currencyB.balanceOf(LEAD_C), totalCarryC_B, "final: leadC currencyB");
        assertEq(currencyB.balanceOf(COINVESTOR_DEST), totalCoinvestorB, "final: coinvestor currencyB");

        assertEq(currencyA.balanceOf(address(coinvestedPosition)), 0, "coinvestedPosition holds residual currencyA");
        assertEq(currencyB.balanceOf(address(coinvestedPosition)), 0, "coinvestedPosition holds residual currencyB");

        // Conservation: all currencyA in (2 buys + extra) == all out
        uint256 outA = currencyA.balanceOf(LEAD_A) +
            currencyA.balanceOf(LEAD_B) +
            currencyA.balanceOf(LEAD_C) +
            currencyA.balanceOf(COINVESTOR_DEST);
        assertEq(outA, 400e6 + 150e6 + EXTRA, "currencyA conservation");

        // Conservation: all currencyB in == all out
        uint256 outB = currencyB.balanceOf(LEAD_A) +
            currencyB.balanceOf(LEAD_B) +
            currencyB.balanceOf(LEAD_C) +
            currencyB.balanceOf(COINVESTOR_DEST);
        assertEq(outB, 900e18, "currencyB conservation");
    }
}
