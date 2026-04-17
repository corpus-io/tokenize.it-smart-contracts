// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import "../lib/forge-std/src/Test.sol";
import "../contracts/factories/TokenProxyFactory.sol";
import "../contracts/factories/ExitCloneFactory.sol";
import "../contracts/Exit.sol";
import "./resources/FakePaymentToken.sol";
import "./resources/CloneCreators.sol";
import "./resources/MaliciousExitCurrency.sol";

contract ExitTest is Test {
    address public constant ADMIN = 0x0109709eCFa91a80626FF3989D68f67f5b1dD120;
    address public constant OWNER = 0x1109709ecFA91a80626ff3989D68f67F5B1Dd121;
    address public constant HOLDER = 0x2109709EcFa91a80626Ff3989d68F67F5B1Dd122;
    address public constant RECIPIENT = 0x3109709ECfA91A80626fF3989D68f67F5B1Dd123;
    address public constant CURRENCY_PROVIDER = 0x4109709eCFa91A80626ff3989d68F67f5b1DD124;
    address public constant FEE_COLLECTOR = 0x5109709EcFA91a80626ff3989d68f67F5B1dD125;
    address public constant TRUSTED_FORWARDER = 0x9109709EcFA91A80626FF3989D68f67F5B1dD129;

    uint8 public constant CURRENCY_DECIMALS = 6;
    // 2 currency units (6 dec) per token (18 dec)
    uint256 public constant PRICE_PER_TOKEN = 2e6;
    uint256 public constant TOKEN_SUPPLY = 100e18;
    uint256 public constant TOTAL_CURRENCY = 200e6; // 100 tokens × 2e6

    uint64 public lockedUntil;

    AllowList allowList;
    FakePaymentToken currency;
    Token token;
    Exit exitLogic;
    ExitCloneFactory factory;
    Exit exitContract;
    TokenProxyFactory tokenFactory;

    function setUp() public {
        lockedUntil = uint64(block.timestamp + 30 days);

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
            tokenFactory.createTokenProxy(0, TRUSTED_FORWARDER, feeSettings, ADMIN, allowList, 0, "ExitToken", "EXT")
        );

        vm.startPrank(ADMIN);
        token.grantRole(token.MINTALLOWER_ROLE(), ADMIN);
        token.mint(HOLDER, TOKEN_SUPPLY);
        vm.stopPrank();

        currency.mint(CURRENCY_PROVIDER, TOTAL_CURRENCY);
        exitLogic = new Exit(TRUSTED_FORWARDER);
        factory = new ExitCloneFactory(address(exitLogic));
        exitContract = _deployExit(bytes32(0), PRICE_PER_TOKEN, lockedUntil, TOTAL_CURRENCY);

        vm.prank(HOLDER);
        token.approve(address(exitContract), TOKEN_SUPPLY);
    }

    /// @dev Helper: predict address, approve, and deploy an Exit clone
    function _deployExit(bytes32 salt, uint256 price, uint64 end, uint256 totalCurrency) internal returns (Exit) {
        ExitInitializerArguments memory args = ExitInitializerArguments({
            owner: OWNER,
            token: token,
            currency: IERC20(address(currency)),
            pricePerToken: price,
            lockedUntil: end,
            referenceCurrencies: new IERC20[](0),
            referenceToExitRates: new uint256[](0)
        });
        address cloneAddr = factory.predictCloneAddress(salt, TRUSTED_FORWARDER, args);
        currency.mint(CURRENCY_PROVIDER, totalCurrency);
        vm.prank(CURRENCY_PROVIDER);
        currency.approve(cloneAddr, totalCurrency);
        return Exit(factory.createExitClone(salt, TRUSTED_FORWARDER, CURRENCY_PROVIDER, args, totalCurrency));
    }

    // ========== E1. Constructor / Logic Contract ==========

    function testLogicContractInitializeReverts() public {
        ExitInitializerArguments memory args = ExitInitializerArguments({
            owner: OWNER,
            token: token,
            currency: IERC20(address(currency)),
            pricePerToken: PRICE_PER_TOKEN,
            lockedUntil: lockedUntil,
            referenceCurrencies: new IERC20[](0),
            referenceToExitRates: new uint256[](0)
        });
        vm.expectRevert("Initializable: contract is already initialized");
        exitLogic.initialize(args, CURRENCY_PROVIDER, 0);
    }

    function testLogicContractStateIsZero() public view {
        assertEq(address(exitLogic.token()), address(0), "logic contract token should be zero");
        assertEq(address(exitLogic.currency()), address(0), "logic contract currency should be zero");
        assertEq(exitLogic.pricePerToken(), 0, "logic contract pricePerToken should be zero");
        assertEq(exitLogic.lockedUntil(), 0, "logic contract lockedUntil should be zero");
        assertEq(exitLogic.owner(), address(0), "logic contract OWNER should be zero");
    }

    function testLogicContractClaimReverts() public {
        // token is address(0) on uninitialized logic contract — balanceOf reverts (no code at address)
        vm.expectRevert();
        exitLogic.claim(RECIPIENT, 0);
    }

    function testLogicContractDrainReverts() public {
        // OWNER is address(0) on uninitialized logic contract → onlyOwner blocks everyone
        vm.warp(block.timestamp + 365 days);
        vm.expectRevert("Ownable: caller is not the owner");
        exitLogic.drain(RECIPIENT, currency);
    }

    function testSecondInitializeReverts() public {
        ExitInitializerArguments memory args = ExitInitializerArguments({
            owner: OWNER,
            token: token,
            currency: IERC20(address(currency)),
            pricePerToken: PRICE_PER_TOKEN,
            lockedUntil: lockedUntil,
            referenceCurrencies: new IERC20[](0),
            referenceToExitRates: new uint256[](0)
        });
        vm.expectRevert("Initializable: contract is already initialized");
        exitContract.initialize(args, CURRENCY_PROVIDER, 100);
    }

    // ========== E2. initialize() — Validation & State ==========

    function testInitializeZeroPriceReverts() public {
        ExitInitializerArguments memory args = ExitInitializerArguments({
            owner: OWNER,
            token: token,
            currency: IERC20(address(currency)),
            pricePerToken: 0,
            lockedUntil: lockedUntil,
            referenceCurrencies: new IERC20[](0),
            referenceToExitRates: new uint256[](0)
        });
        vm.expectRevert(ZeroPrice.selector);
        factory.createExitClone(bytes32(0), TRUSTED_FORWARDER, CURRENCY_PROVIDER, args, 0);
    }

    function testInitializePastLockedUntilReverts() public {
        ExitInitializerArguments memory args = ExitInitializerArguments({
            owner: OWNER,
            token: token,
            currency: IERC20(address(currency)),
            pricePerToken: PRICE_PER_TOKEN,
            lockedUntil: uint64(block.timestamp), // present moment is not in the future
            referenceCurrencies: new IERC20[](0),
            referenceToExitRates: new uint256[](0)
        });
        vm.expectRevert(LockedUntilNotInFuture.selector);
        factory.createExitClone("1", TRUSTED_FORWARDER, CURRENCY_PROVIDER, args, 0);
    }

    function testInitializeCurrencyEqualsTokenReverts() public {
        ExitInitializerArguments memory args = ExitInitializerArguments({
            owner: OWNER,
            token: token,
            currency: IERC20(address(token)),
            pricePerToken: PRICE_PER_TOKEN,
            lockedUntil: lockedUntil,
            referenceCurrencies: new IERC20[](0),
            referenceToExitRates: new uint256[](0)
        });
        vm.expectRevert(CurrencyEqualsToken.selector);
        factory.createExitClone(bytes32(0), TRUSTED_FORWARDER, CURRENCY_PROVIDER, args, 0);
    }

    function testInitializeNonTrustedCurrencyReverts() public {
        FakePaymentToken badCurrency = new FakePaymentToken(0, 6);
        // not set on allowList → 0 attributes
        ExitInitializerArguments memory args = ExitInitializerArguments({
            owner: OWNER,
            token: token,
            currency: IERC20(address(badCurrency)),
            pricePerToken: PRICE_PER_TOKEN,
            lockedUntil: lockedUntil,
            referenceCurrencies: new IERC20[](0),
            referenceToExitRates: new uint256[](0)
        });
        vm.expectRevert(UntrustedCurrency.selector);
        factory.createExitClone(bytes32(0), TRUSTED_FORWARDER, CURRENCY_PROVIDER, args, 0);
    }

    function testInitializeInsufficientAllowanceReverts() public {
        ExitInitializerArguments memory args = ExitInitializerArguments({
            owner: OWNER,
            token: token,
            currency: IERC20(address(currency)),
            pricePerToken: PRICE_PER_TOKEN,
            lockedUntil: lockedUntil,
            referenceCurrencies: new IERC20[](0),
            referenceToExitRates: new uint256[](0)
        });
        bytes32 salt = "3";
        address cloneAddr = factory.predictCloneAddress(salt, TRUSTED_FORWARDER, args);
        currency.mint(CURRENCY_PROVIDER, 1000e6);
        vm.prank(CURRENCY_PROVIDER);
        currency.approve(cloneAddr, 999e6); // one unit short
        vm.expectRevert("ERC20: insufficient allowance");
        factory.createExitClone(salt, TRUSTED_FORWARDER, CURRENCY_PROVIDER, args, 1000e6);
    }

    function testInitializeStateVariables() public view {
        assertEq(address(exitContract.token()), address(token), "token address mismatch");
        assertEq(address(exitContract.currency()), address(currency), "currency address mismatch");
        assertEq(exitContract.pricePerToken(), PRICE_PER_TOKEN, "pricePerToken mismatch");
        assertEq(exitContract.lockedUntil(), lockedUntil, "lockedUntil mismatch");
        assertEq(exitContract.owner(), OWNER, "OWNER mismatch");
        assertEq(currency.balanceOf(address(exitContract)), TOTAL_CURRENCY, "exitContract currency balance mismatch");
    }

    // ========== E3. claim(uint256, address) — Direct Claim ==========

    function testClaimAfterEndSucceeds() public {
        vm.warp(lockedUntil + 1);
        assertEq(currency.balanceOf(RECIPIENT), 0, "RECIPIENT currency balance should be zero before claim");
        vm.prank(HOLDER);
        exitContract.claim(RECIPIENT, 0);
        assertGt(currency.balanceOf(RECIPIENT), 0, "RECIPIENT should have received currency after claim");
    }

    function testClaimTransfersTokensToExitNotBurned() public {
        assertEq(token.balanceOf(address(exitContract)), 0, "exitContract token balance should be zero before claim");
        assertEq(token.balanceOf(HOLDER), TOKEN_SUPPLY, "HOLDER token balance should be full before claim");
        vm.prank(HOLDER);
        exitContract.claim(RECIPIENT, 0);
        // tokens go to Exit, not burned
        assertEq(token.balanceOf(address(exitContract)), TOKEN_SUPPLY, "exitContract should hold claimed tokens");
        assertEq(token.balanceOf(HOLDER), 0, "HOLDER token balance should be zero after full claim");
    }

    function testClaimSendsCurrencyToRecipient() public {
        assertEq(currency.balanceOf(RECIPIENT), 0, "RECIPIENT currency balance should be zero before claim");
        assertEq(currency.balanceOf(HOLDER), 0, "HOLDER currency balance should be zero before claim");
        vm.prank(HOLDER);
        exitContract.claim(RECIPIENT, 0);
        assertEq(currency.balanceOf(RECIPIENT), TOTAL_CURRENCY, "RECIPIENT should receive full currency amount");
        assertEq(currency.balanceOf(HOLDER), 0, "HOLDER should not receive any currency");
    }

    function testClaimRecipientDiffersFromSender() public {
        assertEq(currency.balanceOf(HOLDER), 0, "HOLDER currency balance should be zero before claim");
        assertEq(currency.balanceOf(RECIPIENT), 0, "RECIPIENT currency balance should be zero before claim");
        vm.prank(HOLDER);
        exitContract.claim(RECIPIENT, 0);
        assertEq(currency.balanceOf(HOLDER), 0, "HOLDER should not receive any currency");
        assertGt(currency.balanceOf(RECIPIENT), 0, "RECIPIENT should have received currency");
    }

    function testClaimNothingRevertsWhenNoTokens() public {
        address stranger = address(42);
        vm.expectRevert(NothingToClaim.selector);
        vm.prank(stranger);
        exitContract.claim(stranger, 0);
    }

    function testClaimWithoutTokenApprovalReverts() public {
        address stranger = address(42);
        vm.prank(ADMIN);
        token.mint(stranger, 10e18);
        // no approval → safeTransferFrom fails
        vm.expectRevert("ERC20: insufficient allowance");
        vm.prank(stranger);
        exitContract.claim(stranger, 0);
    }

    function testMultipleSequentialClaims() public {
        address holder1 = address(0xAA);
        address holder2 = address(0xBB);

        vm.startPrank(ADMIN);
        token.mint(holder1, 10e18);
        token.mint(holder2, 50e18);
        vm.stopPrank();

        uint256 totalNeeded = ((10e18 + 50e18) * PRICE_PER_TOKEN) / 1e18;
        Exit freshExit = _deployExit(keccak256("multi"), PRICE_PER_TOKEN, lockedUntil, totalNeeded);

        vm.prank(holder1);
        token.approve(address(freshExit), 10e18);
        vm.prank(holder2);
        token.approve(address(freshExit), 50e18);

        uint256 expected1 = (10e18 * PRICE_PER_TOKEN) / 1e18;
        uint256 expected2 = (50e18 * PRICE_PER_TOKEN) / 1e18;

        assertEq(currency.balanceOf(RECIPIENT), 0, "RECIPIENT currency balance should be zero before claims");
        assertEq(currency.balanceOf(address(44)), 0, "address(44) currency balance should be zero before claims");

        vm.prank(holder1);
        freshExit.claim(RECIPIENT, 0);
        vm.prank(holder2);
        freshExit.claim(address(44), 0);

        assertEq(currency.balanceOf(RECIPIENT), expected1, "RECIPIENT should receive correct currency amount");
        assertEq(currency.balanceOf(address(44)), expected2, "address(44) should receive correct currency amount");
        assertEq(
            currency.balanceOf(address(freshExit)),
            totalNeeded - expected1 - expected2,
            "freshExit currency balance should reflect both claims"
        );
    }

    function testClaimExceedingFundedAmountReverts() public {
        assertEq(
            currency.balanceOf(address(exitContract)),
            TOTAL_CURRENCY,
            "exitContract should hold full currency before drain claim"
        );
        // Drain exit fully first
        vm.prank(HOLDER);
        exitContract.claim(RECIPIENT, 0);
        assertEq(currency.balanceOf(address(exitContract)), 0, "exitContract should be empty after full claim");

        // One more token has nowhere to pull from
        address extra = address(45);
        vm.prank(ADMIN);
        token.mint(extra, 1e18);
        vm.prank(extra);
        token.approve(address(exitContract), 1e18);
        vm.expectRevert("ERC20: transfer amount exceeds balance");
        vm.prank(extra);
        exitContract.claim(extra, 0);
    }

    // ========== E6. drain() ==========

    function testDrainNonOwnerReverts() public {
        vm.warp(lockedUntil + 1);
        vm.expectRevert("Ownable: caller is not the owner");
        vm.prank(HOLDER);
        exitContract.drain(RECIPIENT, currency);
    }

    function testFuzzDrainNonOwnerReverts(address caller) public {
        vm.assume(caller != OWNER);
        vm.assume(caller != address(0));
        vm.assume(caller != TRUSTED_FORWARDER);
        vm.warp(lockedUntil + 1);
        vm.expectRevert("Ownable: caller is not the owner");
        vm.prank(caller);
        exitContract.drain(RECIPIENT, currency);
    }

    function testFuzzDrainTiming(uint64 timestamp) public {
        vm.assume(timestamp < type(uint64).max - 1);
        vm.warp(timestamp);
        if (timestamp < lockedUntil) {
            vm.expectRevert(DrainNotYetAvailable.selector);
            vm.prank(OWNER);
            exitContract.drain(RECIPIENT, currency);
        } else {
            uint256 contractBalance = currency.balanceOf(address(exitContract));
            uint256 balBefore = currency.balanceOf(RECIPIENT);
            vm.prank(OWNER);
            exitContract.drain(RECIPIENT, currency);
            assertEq(
                currency.balanceOf(RECIPIENT),
                balBefore + contractBalance,
                "RECIPIENT should receive full contract balance after drain"
            );
            assertEq(currency.balanceOf(address(exitContract)), 0, "exitContract should be empty after drain");
        }
    }

    function testDrainAtLockedUntilSucceeds() public {
        vm.warp(lockedUntil);
        uint256 contractBalance = currency.balanceOf(address(exitContract));
        vm.prank(OWNER);
        exitContract.drain(RECIPIENT, currency);
        assertEq(currency.balanceOf(RECIPIENT), contractBalance, "RECIPIENT should receive full balance");
        assertEq(currency.balanceOf(address(exitContract)), 0, "exitContract should be empty after drain");
    }

    function testDrainAfterDrainStartTransfersFullBalance() public {
        vm.warp(lockedUntil + 1);
        assertEq(currency.balanceOf(RECIPIENT), 0, "RECIPIENT currency balance should be zero before drain");
        assertEq(
            currency.balanceOf(address(exitContract)),
            TOTAL_CURRENCY,
            "exitContract should hold full currency before drain"
        );
        vm.prank(OWNER);
        exitContract.drain(RECIPIENT, currency);
        assertEq(
            currency.balanceOf(RECIPIENT),
            TOTAL_CURRENCY,
            "RECIPIENT should receive full currency balance after drain"
        );
        assertEq(currency.balanceOf(address(exitContract)), 0, "exitContract should be empty after drain");
    }

    // ========== E7. Math & Rounding ==========

    function testMathRoundsDown() public {
        // 1 token (1e18 wei) + 1 extra wei at PRICE_PER_TOKEN = 2e6:
        // (1e18 + 1) * 2e6 / 1e18 = 2e6, same as exactly 1 token — the extra wei is rounded away
        uint256 claimAmt = 1e18 + 1;
        vm.prank(ADMIN);
        token.mint(address(this), claimAmt);
        token.approve(address(exitContract), claimAmt);

        uint256 balBefore = currency.balanceOf(address(this));
        exitContract.claim(address(this), 0);
        assertEq(
            currency.balanceOf(address(this)) - balBefore,
            PRICE_PER_TOKEN, // exactly 1 token's worth; the +1 wei is rounded away
            "sub-wei token remainder should not increase currency payout"
        );
    }

    function testFuzzMathMultipleClaims(uint128 fuzzAmt) public {
        // price = 2e18 currency-wei per token (2 currency units if currency has 18 decimals)
        // fixed claim amounts: 1 token, 1.5 tokens, 3e6 token-wei (sub-unit, often rounds to 0)
        uint256 claim1 = 1e18;
        uint256 expected1 = 2e18; // 1e18  * 2e18 / 1e18
        uint256 claim2 = 15e17;
        uint256 expected2 = 3e18; // 15e17 * 2e18 / 1e18
        uint256 claim3 = 3e6;
        uint256 expected3 = 6e6; // 3e6   * 2e18 / 1e18
        vm.assume(uint256(fuzzAmt) <= 100e18 - claim1 - claim2 - claim3);

        // 100e18 tokens * 2e18 / 1e18 = 200e18 total currency
        Exit fuzzExit = _deployExit(keccak256(abi.encode("fuzzMath", fuzzAmt)), 2e18, lockedUntil, 200e18);

        address h1 = address(0x1001);
        address h2 = address(0x1002);
        address h3 = address(0x1003);
        address h4 = address(0x1004);

        vm.startPrank(ADMIN);
        token.mint(h1, claim1);
        token.mint(h2, claim2);
        token.mint(h3, claim3);
        if (fuzzAmt > 0) token.mint(h4, fuzzAmt);
        vm.stopPrank();

        vm.prank(h1);
        token.approve(address(fuzzExit), claim1);
        vm.prank(h2);
        token.approve(address(fuzzExit), claim2);
        vm.prank(h3);
        token.approve(address(fuzzExit), claim3);
        if (fuzzAmt > 0) {
            vm.prank(h4);
            token.approve(address(fuzzExit), fuzzAmt);
        }

        vm.prank(h1);
        fuzzExit.claim(h1, 0);
        vm.prank(h2);
        fuzzExit.claim(h2, 0);
        vm.prank(h3);
        fuzzExit.claim(h3, 0);
        if (fuzzAmt > 0) {
            vm.prank(h4);
            fuzzExit.claim(h4, 0);
        }

        assertEq(currency.balanceOf(h1), expected1, "claim1 payout wrong");
        assertEq(currency.balanceOf(h2), expected2, "claim2 payout wrong");
        assertEq(currency.balanceOf(h3), expected3, "claim3 payout wrong");
        if (fuzzAmt > 0) {
            assertEq(currency.balanceOf(h4), (uint256(fuzzAmt) * 2e18) / 1e18, "fuzz claim payout wrong");
        }

        uint256 expectedRemainder = 200e18 - expected1 - expected2 - expected3 - (uint256(fuzzAmt) * 2e18) / 1e18;
        assertEq(currency.balanceOf(address(fuzzExit)), expectedRemainder, "contract balance wrong after claims");
    }

    function testFuzzMathNeverOverpays(uint128 tokenAmt) public {
        vm.assume(tokenAmt > 0);

        uint256 expectedCurrency = (uint256(tokenAmt) * PRICE_PER_TOKEN) / 1e18;
        vm.assume(expectedCurrency <= TOTAL_CURRENCY);

        vm.prank(ADMIN);
        token.mint(address(this), tokenAmt);
        token.approve(address(exitContract), tokenAmt);

        uint256 balBefore = currency.balanceOf(address(this));
        exitContract.claim(address(this), 0);
        uint256 received = currency.balanceOf(address(this)) - balBefore;
        assertEq(received, expectedCurrency, "received currency should match floor division");
        // floor division: received ≤ what a full-precision calculation would give
        assertLe(
            received,
            (uint256(tokenAmt) * PRICE_PER_TOKEN) / 1e18 + 1,
            "received currency must not exceed full-precision result"
        );
    }

    // ========== E8. ERC2771 / Meta-transactions ==========

    function testERC2771IdentifiesHolderAsSender() public {
        assertEq(currency.balanceOf(RECIPIENT), 0, "RECIPIENT currency balance should be zero before meta-tx");
        assertEq(token.balanceOf(HOLDER), TOKEN_SUPPLY, "HOLDER token balance should be full before meta-tx");
        // Build meta-tx calldata: claim(RECIPIENT, minPayout) + appended HOLDER address
        bytes memory callData = abi.encodePacked(
            abi.encodeWithSelector(bytes4(keccak256("claim(address,uint256)")), RECIPIENT, uint256(0)),
            HOLDER
        );
        vm.prank(TRUSTED_FORWARDER);
        (bool success, ) = address(exitContract).call(callData);
        assertTrue(success, "meta-tx call should succeed");
        assertEq(currency.balanceOf(RECIPIENT), TOTAL_CURRENCY, "RECIPIENT should receive full currency via meta-tx");
        assertEq(token.balanceOf(HOLDER), 0, "HOLDER token balance should be zero after meta-tx");
    }

    // ========== E_Fee. Fee Collection per Claim ==========

    /// @dev Deploy an Exit backed by a token with 1% private offer fee.
    ///      Also approves the exit to spend HOLDER's tokens.
    function _deployExitWithNonZeroFee()
        internal
        returns (Exit feeExit, IFeeSettingsV2 feeSettingsWithFee, Token feeToken)
    {
        feeSettingsWithFee = createFeeSettings(
            TRUSTED_FORWARDER,
            ADMIN,
            buildFeeTypes(0, 0, 100, ADMIN, ADMIN, FEE_COLLECTOR)
        );
        feeToken = Token(
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
        feeToken.mint(HOLDER, TOKEN_SUPPLY);
        vm.stopPrank();

        ExitInitializerArguments memory args = ExitInitializerArguments({
            owner: OWNER,
            token: feeToken,
            currency: IERC20(address(currency)),
            pricePerToken: PRICE_PER_TOKEN,
            lockedUntil: lockedUntil,
            referenceCurrencies: new IERC20[](0),
            referenceToExitRates: new uint256[](0)
        });
        address cloneAddr = factory.predictCloneAddress(bytes32(0), TRUSTED_FORWARDER, args);
        currency.mint(CURRENCY_PROVIDER, TOTAL_CURRENCY);
        vm.prank(CURRENCY_PROVIDER);
        currency.approve(cloneAddr, TOTAL_CURRENCY);
        feeExit = Exit(factory.createExitClone(bytes32(0), TRUSTED_FORWARDER, CURRENCY_PROVIDER, args, TOTAL_CURRENCY));

        vm.prank(HOLDER);
        feeToken.approve(address(feeExit), TOKEN_SUPPLY);
    }

    function testClaimWithFeeDeductsFromRecipient() public {
        (Exit feeExit, IFeeSettingsV2 feeSettingsWithFee, Token feeToken) = _deployExitWithNonZeroFee();
        uint256 currencyAmount = (TOKEN_SUPPLY * PRICE_PER_TOKEN) / 10 ** feeToken.decimals();
        uint256 fee = feeSettingsWithFee.privateOfferFee(currencyAmount, address(feeToken));

        assertEq(currency.balanceOf(RECIPIENT), 0, "RECIPIENT currency balance should be zero before claim");
        vm.prank(HOLDER);
        feeExit.claim(RECIPIENT, 0);

        assertGt(fee, 0, "fee should be positive");
        assertEq(
            currency.balanceOf(RECIPIENT),
            currencyAmount - fee,
            "RECIPIENT should receive currency amount minus fee"
        );
    }

    function testClaimWithFeeSendsToFeeCollector() public {
        (Exit feeExit, IFeeSettingsV2 feeSettingsWithFee, Token feeToken) = _deployExitWithNonZeroFee();
        uint256 currencyAmount = (TOKEN_SUPPLY * PRICE_PER_TOKEN) / 10 ** feeToken.decimals();
        uint256 fee = feeSettingsWithFee.privateOfferFee(currencyAmount, address(feeToken));

        assertEq(currency.balanceOf(FEE_COLLECTOR), 0, "FEE_COLLECTOR currency balance should be zero before claim");
        vm.prank(HOLDER);
        feeExit.claim(RECIPIENT, 0);

        assertEq(currency.balanceOf(FEE_COLLECTOR), fee, "FEE_COLLECTOR should receive exact fee amount");
    }

    // ========== E_MinPayout. minPayout guard ==========

    /// minPayout == 0 always passes (no minimum)
    function testClaimMinPayoutZeroAlwaysPasses() public {
        vm.prank(HOLDER);
        exitContract.claim(RECIPIENT, 0);
        assertGt(currency.balanceOf(RECIPIENT), 0, "RECIPIENT should receive currency");
    }

    /// minPayout exactly equal to net payout succeeds
    function testClaimMinPayoutExactNetSucceeds() public {
        uint256 expectedNet = TOTAL_CURRENCY; // no fee, full balance = TOKEN_SUPPLY

        vm.prank(HOLDER);
        exitContract.claim(RECIPIENT, expectedNet);
        assertEq(currency.balanceOf(RECIPIENT), expectedNet, "RECIPIENT should receive exactly expectedNet");
    }

    /// minPayout one above net payout reverts
    function testClaimMinPayoutAboveNetReverts() public {
        uint256 expectedNet = TOTAL_CURRENCY;

        vm.prank(HOLDER);
        vm.expectRevert(PayoutBelowMinimum.selector);
        exitContract.claim(RECIPIENT, expectedNet + 1);
    }

    /// With a fee, minPayout exactly equal to net (gross - fee) succeeds
    function testClaimMinPayoutExactNetAfterFeeSucceeds() public {
        (Exit feeExit, IFeeSettingsV2 feeSettingsWithFee, Token feeToken) = _deployExitWithNonZeroFee();
        uint256 gross = (TOKEN_SUPPLY * PRICE_PER_TOKEN) / 10 ** feeToken.decimals();
        uint256 fee = feeSettingsWithFee.privateOfferFee(gross, address(feeToken));
        uint256 expectedNet = gross - fee;

        vm.prank(HOLDER);
        feeExit.claim(RECIPIENT, expectedNet);
        assertEq(currency.balanceOf(RECIPIENT), expectedNet, "RECIPIENT should receive net amount");
    }

    /// With a fee, minPayout equal to gross (above net) reverts
    function testClaimMinPayoutAboveNetAfterFeeReverts() public {
        (Exit feeExit, , Token feeToken) = _deployExitWithNonZeroFee();
        uint256 gross = (TOKEN_SUPPLY * PRICE_PER_TOKEN) / 10 ** feeToken.decimals();

        vm.prank(HOLDER);
        vm.expectRevert(PayoutBelowMinimum.selector);
        feeExit.claim(RECIPIENT, gross); // gross > net (gross - fee)
    }

    /// With a fee, using eligible() as minPayout succeeds
    function testClaimMinPayoutEligibleWithFeeSucceeds() public {
        (Exit feeExit, , Token feeToken) = _deployExitWithNonZeroFee();
        uint256 minPayout = feeExit.eligible(HOLDER); // eligible() returns net (gross - fee)

        vm.prank(HOLDER);
        feeExit.claim(RECIPIENT, minPayout);
        assertEq(currency.balanceOf(RECIPIENT), minPayout, "RECIPIENT should receive exactly eligible");
    }

    /// With a fee, minPayout one above eligible() reverts
    function testClaimMinPayoutAboveEligibleWithFeeReverts() public {
        (Exit feeExit, , Token feeToken) = _deployExitWithNonZeroFee();
        uint256 gross = (TOKEN_SUPPLY * PRICE_PER_TOKEN) / 10 ** feeToken.decimals();

        vm.prank(HOLDER);
        vm.expectRevert(PayoutBelowMinimum.selector);
        feeExit.claim(RECIPIENT, gross); // gross > eligible() (net)
    }

    /// Fuzz: claim always succeeds when minPayout <= net, reverts when minPayout > net
    function testFuzzClaimMinPayoutBoundary(uint256 minPayout) public {
        uint256 net = TOTAL_CURRENCY; // no fee, HOLDER has TOKEN_SUPPLY

        vm.prank(HOLDER);
        if (minPayout <= net) {
            exitContract.claim(RECIPIENT, minPayout);
            assertEq(currency.balanceOf(RECIPIENT), net, "RECIPIENT should receive net");
        } else {
            vm.expectRevert(PayoutBelowMinimum.selector);
            exitContract.claim(RECIPIENT, minPayout);
        }
    }

    // ========== E_Eligible. eligible() ==========

    function testEligibleReturnsCorrectAmountForHolder() public view {
        uint256 expectedCurrency = (TOKEN_SUPPLY * PRICE_PER_TOKEN) / 1e18;
        assertEq(
            exitContract.eligible(HOLDER),
            expectedCurrency,
            "eligible should return full currency for full token balance"
        );
    }

    function testEligibleZeroForAddressWithNoTokens() public view {
        assertEq(exitContract.eligible(address(0xdead)), 0, "eligible should be zero for address with no tokens");
    }

    function testEligibleDecreasesAfterClaim() public {
        uint256 eligibleBefore = exitContract.eligible(HOLDER);
        assertGt(eligibleBefore, 0, "eligible should be positive before claim");
        vm.prank(HOLDER);
        exitContract.claim(RECIPIENT, 0);
        assertEq(exitContract.eligible(HOLDER), 0, "eligible should be zero after full claim");
    }

    function testEligibleZeroAfterFullClaim() public {
        vm.prank(HOLDER);
        exitContract.claim(RECIPIENT, 0);
        assertEq(exitContract.eligible(HOLDER), 0, "eligible should be zero after full claim");
    }

    function testFuzzEligible(uint128 tokenBalance) public {
        vm.assume(tokenBalance > 0);
        address testHolder = address(0xABCD);
        vm.prank(ADMIN);
        token.mint(testHolder, tokenBalance);
        uint256 expectedCurrency = (uint256(tokenBalance) * PRICE_PER_TOKEN) / 1e18;
        assertEq(exitContract.eligible(testHolder), expectedCurrency, "eligible fuzz mismatch");
    }

    /// eligible() deducts the fee from the gross amount
    function testEligibleDeductsFee() public {
        (Exit feeExit, , Token feeToken) = _deployExitWithNonZeroFee();
        uint256 gross = (TOKEN_SUPPLY * PRICE_PER_TOKEN) / 10 ** feeToken.decimals();
        assertEq(feeExit.eligible(HOLDER), gross - gross / 100, "eligible should deduct fee");
    }

    function testDrainWithFeeReflectsCorrectRemainder() public {
        (Exit feeExit, IFeeSettingsV2 feeSettingsWithFee, Token feeToken) = _deployExitWithNonZeroFee();
        uint256 currencyAmount = (TOKEN_SUPPLY * PRICE_PER_TOKEN) / 10 ** feeToken.decimals();

        assertEq(
            currency.balanceOf(address(feeExit)),
            TOTAL_CURRENCY,
            "feeExit should hold full currency before claim"
        );
        assertEq(currency.balanceOf(FEE_COLLECTOR), 0, "FEE_COLLECTOR should start with zero balance");

        uint256 fee = feeSettingsWithFee.privateOfferFee(currencyAmount, address(feeToken));
        vm.prank(HOLDER);
        feeExit.claim(RECIPIENT, 0);

        assertEq(currency.balanceOf(FEE_COLLECTOR), fee, "FEE_COLLECTOR should receive fee on claim");

        // currencyAmount leaves the contract in total (split between fee and net to RECIPIENT)
        uint256 expected = TOTAL_CURRENCY - currencyAmount;
        assertEq(
            currency.balanceOf(address(feeExit)),
            expected,
            "feeExit currency balance should reflect full payout including fee"
        );

        vm.warp(lockedUntil + 1);
        vm.prank(OWNER);
        feeExit.drain(OWNER, currency);
        assertEq(currency.balanceOf(OWNER), expected, "OWNER should receive remaining currency after drain");
        assertEq(currency.balanceOf(address(feeExit)), 0, "feeExit should be empty after drain");
        assertEq(
            currency.balanceOf(FEE_COLLECTOR),
            fee,
            "FEE_COLLECTOR should not receive additional currency on drain"
        );
    }

    // ========== E_Reentrancy. Reentrancy protection ==========

    /// @dev Deploy an exit whose currency is a MaliciousExitCurrency.
    function _deployExitWithMaliciousCurrency(
        MaliciousExitCurrency maliciousCurrency,
        uint256 funding
    ) internal returns (Exit) {
        vm.prank(ADMIN);
        allowList.set(address(maliciousCurrency), TRUSTED_CURRENCY);

        ExitInitializerArguments memory args = ExitInitializerArguments({
            owner: OWNER,
            token: token,
            currency: IERC20(address(maliciousCurrency)),
            pricePerToken: PRICE_PER_TOKEN,
            lockedUntil: lockedUntil,
            referenceCurrencies: new IERC20[](0),
            referenceToExitRates: new uint256[](0)
        });
        address cloneAddr = factory.predictCloneAddress(bytes32(0), TRUSTED_FORWARDER, args);
        maliciousCurrency.mint(CURRENCY_PROVIDER, funding);
        vm.prank(CURRENCY_PROVIDER);
        maliciousCurrency.approve(cloneAddr, funding);
        return Exit(factory.createExitClone(bytes32(0), TRUSTED_FORWARDER, CURRENCY_PROVIDER, args, funding));
    }

    /// claim() reverts when the currency reenters claim() during the payout transfer
    function testReentrancyOnClaim() public {
        MaliciousExitCurrency maliciousCurrency = new MaliciousExitCurrency();
        Exit exitWithMaliciousCurrency = _deployExitWithMaliciousCurrency(maliciousCurrency, TOTAL_CURRENCY);
        maliciousCurrency.setExploitTarget(address(exitWithMaliciousCurrency), RECIPIENT);

        vm.prank(HOLDER);
        token.approve(address(exitWithMaliciousCurrency), TOKEN_SUPPLY);
        vm.prank(HOLDER);
        vm.expectRevert("ReentrancyGuard: reentrant call");
        exitWithMaliciousCurrency.claim(RECIPIENT, 0);
    }

    /// drain() reverts when the currency reenters claim() during the drain transfer
    function testReentrancyOnDrain() public {
        MaliciousExitCurrency maliciousCurrency = new MaliciousExitCurrency();
        Exit exitWithMaliciousCurrency = _deployExitWithMaliciousCurrency(maliciousCurrency, TOTAL_CURRENCY);
        maliciousCurrency.setExploitTarget(address(exitWithMaliciousCurrency), RECIPIENT);

        vm.warp(lockedUntil + 1);
        vm.prank(OWNER);
        vm.expectRevert("ReentrancyGuard: reentrant call");
        exitWithMaliciousCurrency.drain(OWNER, IERC20(address(maliciousCurrency)));
    }

    // ========== E9. referenceToExitRate initialization ==========

    /// Reverts when referenceCurrencies and referenceToExitRates arrays have different lengths.
    function testReferenceRateArrayLengthMismatchReverts() public {
        FakePaymentToken otherCurrency = new FakePaymentToken(0, 18);
        vm.prank(ADMIN);
        allowList.set(address(otherCurrency), TRUSTED_CURRENCY);

        IERC20[] memory referenceCurrencies = new IERC20[](1);
        referenceCurrencies[0] = IERC20(address(otherCurrency));
        uint256[] memory rates = new uint256[](0);

        ExitInitializerArguments memory args = ExitInitializerArguments({
            owner: OWNER,
            token: token,
            currency: IERC20(address(currency)),
            pricePerToken: PRICE_PER_TOKEN,
            lockedUntil: lockedUntil,
            referenceCurrencies: referenceCurrencies,
            referenceToExitRates: rates
        });
        vm.expectRevert(ArrayLengthMismatch.selector);
        factory.createExitClone(bytes32(0), TRUSTED_FORWARDER, CURRENCY_PROVIDER, args, 0);
    }

    /// Reverts when a referenceToExitRate entry is zero.
    function testReferenceRateZeroReverts() public {
        FakePaymentToken otherCurrency = new FakePaymentToken(0, 18);
        vm.prank(ADMIN);
        allowList.set(address(otherCurrency), TRUSTED_CURRENCY);

        IERC20[] memory referenceCurrencies = new IERC20[](1);
        referenceCurrencies[0] = IERC20(address(otherCurrency));
        uint256[] memory rates = new uint256[](1);
        rates[0] = 0;

        ExitInitializerArguments memory args = ExitInitializerArguments({
            owner: OWNER,
            token: token,
            currency: IERC20(address(currency)),
            pricePerToken: PRICE_PER_TOKEN,
            lockedUntil: lockedUntil,
            referenceCurrencies: referenceCurrencies,
            referenceToExitRates: rates
        });
        vm.expectRevert(ZeroPrice.selector);
        factory.createExitClone(bytes32(0), TRUSTED_FORWARDER, CURRENCY_PROVIDER, args, 0);
    }

    /// Reverts when a referenceCurrency equals the exit currency.
    function testReferenceCurrencyEqualToExitCurrencyReverts() public {
        IERC20[] memory referenceCurrencies = new IERC20[](1);
        referenceCurrencies[0] = IERC20(address(currency)); // same as exit currency
        uint256[] memory rates = new uint256[](1);
        rates[0] = 1e6;

        ExitInitializerArguments memory args = ExitInitializerArguments({
            owner: OWNER,
            token: token,
            currency: IERC20(address(currency)),
            pricePerToken: PRICE_PER_TOKEN,
            lockedUntil: lockedUntil,
            referenceCurrencies: referenceCurrencies,
            referenceToExitRates: rates
        });
        vm.expectRevert(Exit.ReferenceCurrencyEqualsExitCurrency.selector);
        factory.createExitClone(bytes32(0), TRUSTED_FORWARDER, CURRENCY_PROVIDER, args, 0);
    }

    /// referenceToExitRate values are stored correctly and retrievable.
    function testReferenceRatesStoredCorrectly() public {
        FakePaymentToken refCurrency = new FakePaymentToken(0, 18);
        vm.prank(ADMIN);
        allowList.set(address(refCurrency), TRUSTED_CURRENCY);

        IERC20[] memory referenceCurrencies = new IERC20[](1);
        referenceCurrencies[0] = IERC20(address(refCurrency));
        uint256[] memory rates = new uint256[](1);
        rates[0] = 1e6; // 10^18 refCurrency bits = 1e6 currency bits

        ExitInitializerArguments memory args = ExitInitializerArguments({
            owner: OWNER,
            token: token,
            currency: IERC20(address(currency)),
            pricePerToken: PRICE_PER_TOKEN,
            lockedUntil: lockedUntil,
            referenceCurrencies: referenceCurrencies,
            referenceToExitRates: rates
        });
        address cloneAddr = factory.predictCloneAddress(bytes32(0), TRUSTED_FORWARDER, args);
        currency.mint(CURRENCY_PROVIDER, TOTAL_CURRENCY);
        vm.prank(CURRENCY_PROVIDER);
        currency.approve(cloneAddr, TOTAL_CURRENCY);
        Exit exitWithRate = Exit(
            factory.createExitClone(bytes32(0), TRUSTED_FORWARDER, CURRENCY_PROVIDER, args, TOTAL_CURRENCY)
        );

        assertEq(exitWithRate.referenceToExitRate(IERC20(address(refCurrency))), 1e6, "rate not stored correctly");
        assertEq(exitWithRate.referenceToExitRate(IERC20(address(currency))), 0, "exit currency should have no rate");
    }

    /// referenceCurrency = address(0) must revert
    function testReferenceZeroAddressReverts() public {
        IERC20[] memory referenceCurrencies = new IERC20[](1);
        referenceCurrencies[0] = IERC20(address(0));
        uint256[] memory rates = new uint256[](1);
        rates[0] = 1e6;

        ExitInitializerArguments memory args = ExitInitializerArguments({
            owner: OWNER,
            token: token,
            currency: IERC20(address(currency)),
            pricePerToken: PRICE_PER_TOKEN,
            lockedUntil: lockedUntil,
            referenceCurrencies: referenceCurrencies,
            referenceToExitRates: rates
        });
        address cloneAddr = factory.predictCloneAddress(bytes32("1"), TRUSTED_FORWARDER, args);
        currency.mint(CURRENCY_PROVIDER, TOTAL_CURRENCY);
        vm.prank(CURRENCY_PROVIDER);
        currency.approve(cloneAddr, TOTAL_CURRENCY);

        vm.expectRevert(ZeroCurrencyAddress.selector);
        factory.createExitClone(bytes32("1"), TRUSTED_FORWARDER, CURRENCY_PROVIDER, args, TOTAL_CURRENCY);
    }
}
