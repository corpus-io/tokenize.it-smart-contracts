// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.23;

import "@openzeppelin/contracts/utils/math/Math.sol";
import "../lib/forge-std/src/Test.sol";
import "../contracts/factories/TokenProxyFactory.sol";
import "../contracts/factories/CoinvestedPositionCloneFactory.sol";
import "../contracts/factories/PrivateOfferFactory.sol";
import "../contracts/factories/TimeLockCloneFactory.sol";
import "../contracts/factories/FeeSplitterCloneFactory.sol";
import "../contracts/CoinvestedPosition.sol";
import "../contracts/FeeSplitter.sol";
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

    // ── Shared state ──────────────────────────────────────────────────────────
    CoinvestedPositionCloneFactory coinvestedPositionCloneFactory;
    FeeSplitterCloneFactory feeSplitterCloneFactory;
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
        CoinvestedPosition coinvestedPositionLogic = new CoinvestedPosition(trustedForwarder);
        coinvestedPositionCloneFactory = new CoinvestedPositionCloneFactory(address(coinvestedPositionLogic));

        feeSplitterCloneFactory = new FeeSplitterCloneFactory(address(new FeeSplitter()));

        TimeLock timeLockLogic = new TimeLock(trustedForwarder);
        TimeLockCloneFactory timeLockCloneFactory = new TimeLockCloneFactory(address(timeLockLogic));

        privateOfferFactory = new PrivateOfferFactory(timeLockCloneFactory, coinvestedPositionCloneFactory);
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    function _buildCoinvestedPositionArgs(
        LeadInvestor[] memory leadInvestors
    ) internal view returns (CoinvestedPositionInitializerArguments memory) {
        return
            CoinvestedPositionInitializerArguments({
                owner: owner,
                receiver: receiver,
                leadInvestors: leadInvestors,
                basePrice: 80e6,
                baseCurrency: IERC20(address(eurc)),
                token: token,
                lockedUntil: 0,
                tokenExitRegistry: tokenExitRegistry
            });
    }

    function _buildPrivateOfferArgs(
        uint256 tokenAmount,
        uint256 tokenPrice
    ) internal view returns (PrivateOfferArguments memory) {
        return
            PrivateOfferArguments({
                currencyPayer: receiver, // coinvestor pays PrivateOffer directly
                tokenReceiver: address(0), // overridden by factory to CoinvestedPosition address
                currencyReceiver: currencyReceiver,
                tokenAmount: tokenAmount,
                tokenPrice: tokenPrice,
                expiration: block.timestamp + 7 days,
                currency: IERC20(address(eurc)),
                token: token,
                tokenHolder: address(0)
            });
    }

    // ── Tests ─────────────────────────────────────────────────────────────────

    /**
     * @notice Demonstrates the PrivateOfferFactory flow for opening a coinvested position:
     *   1. Platform predicts both addresses
     *   2. Token issuer grants minting allowance to the predicted PrivateOffer address
     *   3. Coinvestor approves the predicted PrivateOffer address for the investment amount
     *   4. Anyone calls deployPrivateOfferWithCoinvestedPosition — atomically:
     *      - CoinvestedPosition clone is deployed and initialized
     *      - PrivateOffer is deployed: investment flows from coinvestor to token issuer,
     *        tokens land in CoinvestedPosition
     */
    function testDeployPrivateOfferWithCoinvestedPosition() public {
        uint256 tokenAmount = 1000e18;
        uint256 tokenPrice = 100e6; // 100 EURc per token (6 decimals)
        uint256 investmentAmount = Math.ceilDiv(tokenAmount * tokenPrice, 10 ** token.decimals());

        LeadInvestor[] memory leadInvestors = new LeadInvestor[](1);
        leadInvestors[0] = LeadInvestor({account: leadA, carryFraction: CARRY_10PCT});

        CoinvestedPositionInitializerArguments memory coinvestedPositionArgs = _buildCoinvestedPositionArgs(
            leadInvestors
        );
        PrivateOfferArguments memory privateOfferArgs = _buildPrivateOfferArgs(tokenAmount, tokenPrice);

        bytes32 rawSalt = bytes32(0);

        // ── Predict addresses ─────────────────────────────────────────────────

        (address expectedPrivateOffer, address expectedCoinvestedPosition) = privateOfferFactory
            .predictPrivateOfferAndCoinvestedPositionAddress(
                rawSalt,
                trustedForwarder,
                privateOfferArgs,
                coinvestedPositionArgs
            );

        // ── Set up approvals ──────────────────────────────────────────────────

        // Token issuer grants minting allowance to the predicted PrivateOffer address
        vm.prank(admin);
        token.increaseMintingAllowance(expectedPrivateOffer, tokenAmount);

        // Coinvestor approves the predicted PrivateOffer address for the investment amount
        eurc.mint(receiver, investmentAmount);
        vm.prank(receiver);
        eurc.approve(expectedPrivateOffer, investmentAmount);

        // ── Execute ───────────────────────────────────────────────────────────

        (address privateOfferAddress, address coinvestedPositionAddress) = privateOfferFactory
            .deployPrivateOfferWithCoinvestedPosition(
                rawSalt,
                trustedForwarder,
                privateOfferArgs,
                coinvestedPositionArgs
            );

        // ── Assert ────────────────────────────────────────────────────────────

        assertEq(privateOfferAddress, expectedPrivateOffer, "PrivateOffer address mismatch");
        assertEq(coinvestedPositionAddress, expectedCoinvestedPosition, "CoinvestedPosition address mismatch");
        assertEq(token.balanceOf(coinvestedPositionAddress), tokenAmount, "token balance wrong");
        assertEq(eurc.balanceOf(currencyReceiver), investmentAmount, "currencyReceiver balance wrong");
        assertEq(eurc.balanceOf(receiver), 0, "receiver should have spent all currency");
    }

    /**
     * @notice Demonstrates the FeeSplitter flow for paying a one-time syndicate fee:
     *   1. A CoinvestedPosition is deployed (provides the lead investor roster)
     *   2. Platform predicts the FeeSplitter address
     *   3. Fee payer approves the predicted FeeSplitter for the fee amount
     *   4. Anyone calls createFeeSplitterClone — immediately:
     *      - FeeSplitter pulls the fee from the payer
     *      - Fee is split proportionally among lead investors by carry fraction
     */
    function testFeeSplitter() public {
        uint256 tokenAmount = 1000e18;
        uint256 tokenPrice = 100e6;
        uint256 investmentAmount = Math.ceilDiv(tokenAmount * tokenPrice, 10 ** token.decimals());
        uint64 oneTimeFee2Pct = type(uint64).max / 50;
        uint256 feeAmount = (uint256(oneTimeFee2Pct) * investmentAmount) / type(uint64).max;

        // Build a CoinvestedPosition with 2 lead investors as the fee roster source
        LeadInvestor[] memory leadInvestors = new LeadInvestor[](2);
        leadInvestors[0] = LeadInvestor({account: leadA, carryFraction: CARRY_10PCT});
        leadInvestors[1] = LeadInvestor({account: leadB, carryFraction: CARRY_5PCT});

        CoinvestedPositionInitializerArguments memory coinvestedPositionArgs = _buildCoinvestedPositionArgs(
            leadInvestors
        );
        CoinvestedPosition coinvestedPositionInstance = CoinvestedPosition(
            coinvestedPositionCloneFactory.createCoinvestedPositionClone(
                bytes32(0),
                trustedForwarder,
                coinvestedPositionArgs
            )
        );

        // ── Predict FeeSplitter address ───────────────────────────────────────

        address expectedFeeSplitter = feeSplitterCloneFactory.predictCloneAddress(
            bytes32("1"),
            receiver,
            IERC20(address(eurc)),
            feeAmount,
            coinvestedPositionInstance
        );

        // ── Set up approval ───────────────────────────────────────────────────

        eurc.mint(receiver, feeAmount);
        vm.prank(receiver);
        eurc.approve(expectedFeeSplitter, feeAmount);

        // ── Execute: deploy FeeSplitter, which immediately distributes the fee ─

        address feeSplitterAddress = feeSplitterCloneFactory.createFeeSplitterClone(
            bytes32("1"),
            receiver,
            IERC20(address(eurc)),
            feeAmount,
            coinvestedPositionInstance
        );

        // ── Assert ────────────────────────────────────────────────────────────

        assertEq(feeSplitterAddress, expectedFeeSplitter, "FeeSplitter address mismatch");

        uint256 carryFractionsSum = uint256(CARRY_10PCT) + uint256(CARRY_5PCT);
        uint256 leadAShare = (uint256(CARRY_10PCT) * feeAmount) / carryFractionsSum;
        uint256 leadBShare = feeAmount - leadAShare; // last lead absorbs rounding dust

        assertEq(eurc.balanceOf(leadA), leadAShare, "leadA fee share wrong");
        assertEq(eurc.balanceOf(leadB), leadBShare, "leadB fee share wrong");
        assertEq(leadAShare + leadBShare, feeAmount, "fee shares do not sum to total fee");
        assertEq(eurc.balanceOf(receiver), 0, "feePayer should have spent all fee currency");
    }
}
