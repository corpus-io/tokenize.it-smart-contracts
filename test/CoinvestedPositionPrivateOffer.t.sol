// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.23;

import "@openzeppelin/contracts/utils/math/Math.sol";
import "../lib/forge-std/src/Test.sol";
import "../contracts/factories/TokenProxyFactory.sol";
import "../contracts/factories/CoinvestedPositionCloneFactory.sol";
import "../contracts/factories/PrivateOfferFactory.sol";
import "../contracts/factories/TimeLockCloneFactory.sol";
import "../contracts/CoinvestedPosition.sol";
import "../contracts/TimeLock.sol";
import "../contracts/GlobalTokenExitRegistry.sol";
import "./resources/CoinvestedPositionTestBase.sol";
import "./resources/CloneCreators.sol";

contract CoinvestedPositionPrivateOfferTest is CoinvestedPositionTestBase {
    // ── Well-known addresses ──────────────────────────────────────────────────
    address public constant leadB = 0x3109709ECfA91A80626fF3989D68f67F5B1Dd123;
    address public constant currencyReceiver = 0x4109709eCFa91A80626ff3989d68F67f5b1DD124;

    // ── Test constants ────────────────────────────────────────────────────────
    uint64 public constant CARRY_5PCT = type(uint64).max / 20;
    uint64 public constant ONE_TIME_FEE_2PCT = type(uint64).max / 50;

    // ── Shared state ──────────────────────────────────────────────────────────
    CoinvestedPositionCloneFactory coinvestedPositionFactory;
    PrivateOfferFactory privateOfferFactory;

    function setUp() public {
        // Infrastructure
        allowList = createAllowList(trustedForwarder, admin);
        feeSettings = createFeeSettings(trustedForwarder, admin, buildFeeTypes(0, 0, 0, admin, admin, admin));

        eurc = new FakePaymentToken(0, 6);
        vm.prank(admin);
        allowList.set(address(eurc), TRUSTED_CURRENCY);

        // Token (18 decimals)
        address tokenLogic = address(new Token(trustedForwarder));
        tokenFactory = new TokenProxyFactory(tokenLogic);
        token = Token(
            tokenFactory.createTokenProxy(0, trustedForwarder, feeSettings, admin, allowList, 0, "TestToken", "TTK")
        );
        vm.startPrank(admin);
        token.grantRole(token.MINTALLOWER_ROLE(), admin);
        vm.stopPrank();

        tokenExitRegistry = new GlobalTokenExitRegistry(trustedForwarder);

        // Factories
        CoinvestedPosition logic = new CoinvestedPosition(trustedForwarder);
        coinvestedPositionFactory = new CoinvestedPositionCloneFactory(address(logic));

        TimeLock timeLockLogic = new TimeLock(trustedForwarder);
        TimeLockCloneFactory timeLockCloneFactory = new TimeLockCloneFactory(address(timeLockLogic));
        privateOfferFactory = new PrivateOfferFactory(timeLockCloneFactory);
    }

    /**
     * @notice Demonstrates the full one-transaction coinvested position opening flow:
     *   1. Platform predicts both addresses
     *   2. Token issuer grants minting allowance to predicted PrivateOffer address
     *   3. Coinvestor approves predicted CoinvestedPosition address for investment + one-time fee
     *   4. Anyone executes createCoinvestedPositionWithPrivateOffer — atomically:
     *      - CoinvestedPosition is initialized
     *      - One-time syndicate fee is pulled from coinvestor and split among lead investors
     *      - PrivateOffer is deployed: investment flows to token issuer, tokens land in CoinvestedPosition
     */
    function testCreateCoinvestedPositionWithPrivateOffer() public {
        uint256 tokenAmount = 1000e18;
        uint256 tokenPrice = 100e6; // 100 EURc per token (6 decimals)

        // investmentAmount: what coinvestor pays for the tokens (excluding one-time fee)
        uint256 investmentAmount = Math.ceilDiv(tokenAmount * tokenPrice, 10 ** token.decimals());

        // one-time fee: 2% of investmentAmount, computed with same formula as the contract
        uint256 oneTimeFeeAmount = (uint256(ONE_TIME_FEE_2PCT) * investmentAmount) / type(uint64).max;

        // ── Build arguments ───────────────────────────────────────────────────

        LeadInvestor[] memory leadInvestors = new LeadInvestor[](2);
        leadInvestors[0] = LeadInvestor({ account: leadA, carryFraction: CARRY_10PCT });
        leadInvestors[1] = LeadInvestor({ account: leadB, carryFraction: CARRY_5PCT });

        CoinvestedPositionInitializerArguments memory coinvestedPositionArgs = CoinvestedPositionInitializerArguments({
            owner: owner,
            receiver: receiver,
            leadInvestors: leadInvestors,
            basePrice: 80e6, // base price at which coinvestor breaks even
            baseCurrency: IERC20(address(eurc)),
            token: token,
            lockedUntil: 0,
            tokenExitRegistry: tokenExitRegistry
        });

        // currencyPayer and tokenReceiver are placeholders; they are overridden to the
        // CoinvestedPosition address by both predict and create functions.
        PrivateOfferArguments memory privateOfferArgs = PrivateOfferArguments({
            currencyPayer: address(0),
            tokenReceiver: address(0),
            currencyReceiver: currencyReceiver,
            tokenAmount: tokenAmount,
            tokenPrice: tokenPrice,
            expiration: block.timestamp + 7 days,
            currency: IERC20(address(eurc)),
            token: token,
            tokenHolder: address(0)
        });

        bytes32 rawSalt = bytes32("coinvested-demo");

        // ── Predict addresses ─────────────────────────────────────────────────

        (address expectedCoinvestedPosition, address expectedPrivateOffer) = coinvestedPositionFactory
            .predictCoinvestedPositionAndPrivateOfferAddress(
                rawSalt,
                trustedForwarder,
                coinvestedPositionArgs,
                privateOfferFactory,
                privateOfferArgs,
                ONE_TIME_FEE_2PCT
            );

        // ── Set up approvals ──────────────────────────────────────────────────

        // Token issuer grants minting allowance to the predicted PrivateOffer address
        vm.prank(admin);
        token.increaseMintingAllowance(expectedPrivateOffer, tokenAmount);

        // Coinvestor approves the predicted CoinvestedPosition for investment + one-time fee (single approval)
        eurc.mint(receiver, investmentAmount + oneTimeFeeAmount);
        vm.prank(receiver);
        eurc.approve(expectedCoinvestedPosition, investmentAmount + oneTimeFeeAmount);

        // ── Execute: anyone can trigger (here: the platform) ─────────────────

        (address coinvestedPositionAddress, address privateOfferAddress) = coinvestedPositionFactory
            .createCoinvestedPositionWithPrivateOffer(
                rawSalt,
                trustedForwarder,
                coinvestedPositionArgs,
                privateOfferFactory,
                privateOfferArgs,
                ONE_TIME_FEE_2PCT
            );

        // ── Assert: addresses match predictions ───────────────────────────────

        assertEq(coinvestedPositionAddress, expectedCoinvestedPosition, "CoinvestedPosition address mismatch");
        assertEq(privateOfferAddress, expectedPrivateOffer, "PrivateOffer address mismatch");

        // ── Assert: tokens landed in CoinvestedPosition ───────────────────────

        assertEq(token.balanceOf(coinvestedPositionAddress), tokenAmount, "token balance wrong");

        // ── Assert: investment reached the token issuer ───────────────────────

        assertEq(eurc.balanceOf(currencyReceiver), investmentAmount, "currencyReceiver balance wrong");

        // ── Assert: one-time fee split proportionally among lead investors ─────

        uint256 carryFractionsSum = uint256(CARRY_10PCT) + uint256(CARRY_5PCT);
        uint256 leadAShare = (uint256(CARRY_10PCT) * oneTimeFeeAmount) / carryFractionsSum;
        uint256 leadBShare = oneTimeFeeAmount - leadAShare; // last lead absorbs rounding dust

        assertEq(eurc.balanceOf(leadA), leadAShare, "leadA fee share wrong");
        assertEq(eurc.balanceOf(leadB), leadBShare, "leadB fee share wrong");
        assertEq(leadAShare + leadBShare, oneTimeFeeAmount, "fee shares do not sum to total fee");

        // ── Assert: coinvestor paid exactly investment + fee, nothing left ─────

        assertEq(eurc.balanceOf(receiver), 0, "receiver should have spent all approved currency");
    }
}
