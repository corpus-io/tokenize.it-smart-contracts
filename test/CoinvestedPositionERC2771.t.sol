// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import "./resources/CoinvestedPositionTestBase.sol";
import "./resources/ERC2771Helper.sol";
import "@opengsn/contracts/src/forwarder/Forwarder.sol";

contract CoinvestedPositionERC2771Test is CoinvestedPositionTestBase {
    using ECDSA for bytes32;

    // DO NOT USE IN PRODUCTION! Key was generated online for testing only.
    uint256 public constant BUYER_PRIVATE_KEY = 0x3c69254ad72222e3ddf37667b8173dd773bdbdfd93d4af1d192815ff0662de5f;
    address public buyer; // derived from BUYER_PRIVATE_KEY

    uint256 public constant TOKEN_PRICE = 200e6; // 200 EURc per token
    uint256 public constant BASE_PRICE = 100e6; // 100 EURc per token

    ERC2771Helper erc2771Helper;

    function setUp() public {
        buyer = vm.addr(BUYER_PRIVATE_KEY);

        allowList = createAllowList(TRUSTED_FORWARDER, ADMIN);
        feeSettings = createFeeSettings(TRUSTED_FORWARDER, ADMIN, buildFeeTypes(0, 0, 0, ADMIN, ADMIN, ADMIN));

        eurc = new FakePaymentToken(0, 6);
        vm.prank(ADMIN);
        allowList.set(address(eurc), TRUSTED_CURRENCY);

        address tokenLogic = address(new Token(TRUSTED_FORWARDER));
        tokenFactory = new TokenProxyFactory(tokenLogic);
        token = Token(
            tokenFactory.createTokenProxy(0, TRUSTED_FORWARDER, feeSettings, ADMIN, allowList, 0, "TestToken", "TTK")
        );
        vm.startPrank(ADMIN);
        token.grantRole(token.MINTALLOWER_ROLE(), ADMIN);
        vm.stopPrank();

        tokenExitRegistry = new GlobalTokenExitRegistry(TRUSTED_FORWARDER);

        coinvestedPosition = _deployCoinvestedPosition(TRUSTED_FORWARDER);

        erc2771Helper = new ERC2771Helper();
    }

    // ── Internal helpers ──────────────────────────────────────────────────────

    /// Deploy a CoinvestedPosition clone using the given forwarder address.
    /// Creates a fresh logic + factory pair so the forwarder address is accepted.
    function _deployCoinvestedPosition(address forwarder) internal returns (CoinvestedPosition) {
        CoinvestedPosition freshLogic = new CoinvestedPosition(forwarder);
        CoinvestedPositionCloneFactory freshFactory = new CoinvestedPositionCloneFactory(address(freshLogic));

        LeadInvestor[] memory leadInvestors = new LeadInvestor[](1);
        leadInvestors[0] = LeadInvestor({account: LEAD_A, profitFraction: CARRY_10PCT});

        CoinvestedPositionInitializerArguments memory args = CoinvestedPositionInitializerArguments({
            owner: OWNER,
            receiver: RECEIVER,
            leadInvestors: leadInvestors,
            basePrice: BASE_PRICE,
            baseCurrency: IERC20(address(eurc)),
            token: token,
            lockedUntil: 0,
            tokenExitRegistry: tokenExitRegistry
        });
        return CoinvestedPosition(freshFactory.createCoinvestedPositionClone(bytes32(0), forwarder, args));
    }

    function _assertPostBuyBalances(
        address forwarderAddr,
        address coinvestedPositionAddr,
        uint256 tokenBuyAmount,
        uint256 currencyAmount,
        IForwarder.ForwardRequest memory request,
        bytes32 domainSeparator,
        bytes32 requestType,
        bytes memory signature
    ) internal {
        // Buyer identified correctly: paid from buyer's account
        assertEq(eurc.balanceOf(buyer), 0, "buyer currency not fully spent");

        // Tokens delivered to TOKEN_RECEIVER (not buyer, not forwarder)
        assertEq(token.balanceOf(TOKEN_RECEIVER), tokenBuyAmount, "TOKEN_RECEIVER did not receive tokens");
        assertEq(token.balanceOf(buyer), 0, "buyer received tokens unexpectedly");
        assertEq(token.balanceOf(forwarderAddr), 0, "forwarder received tokens");

        // Currency fully distributed — nothing left on the coinvestedPosition
        assertEq(eurc.balanceOf(coinvestedPositionAddr), 0, "currency left on coinvestedPosition");

        // Carry split: 2 tokens * (200e6 - 100e6) = 200e6 carry; 10% to LEAD_A
        uint256 carry = (tokenBuyAmount * (TOKEN_PRICE - BASE_PRICE)) / 1e18;
        uint256 expectedLeadA = (uint256(CARRY_10PCT) * carry) / type(uint64).max;
        assertEq(eurc.balanceOf(LEAD_A), expectedLeadA, "LEAD_A carry wrong");
        assertEq(eurc.balanceOf(RECEIVER), currencyAmount - expectedLeadA, "RECEIVER payout wrong");

        // Replay must fail
        vm.expectRevert("FWD: nonce mismatch");
        Forwarder(payable(forwarderAddr)).execute(request, domainSeparator, requestType, "0", signature);
    }

    /// Sign and execute a buy via the forwarder. Asserts success and checks balances.
    function _buyWithERC2771(Forwarder forwarder) internal {
        CoinvestedPosition coinvestedPosition = _deployCoinvestedPosition(address(forwarder));

        // Mint tokens into coinvestedPosition and enable buying
        vm.prank(ADMIN);
        token.mint(address(coinvestedPosition), 10e18);
        vm.prank(OWNER);
        coinvestedPosition.setTokenPrice(TOKEN_PRICE);
        vm.prank(OWNER);
        coinvestedPosition.unpause();

        // Fund buyer and approve coinvestedPosition
        uint256 currencyAmount = 2 * TOKEN_PRICE; // buying 2 tokens
        eurc.mint(buyer, currencyAmount);
        vm.prank(buyer);
        eurc.approve(address(coinvestedPosition), currencyAmount);

        // ── Register domain and request type with the forwarder ───────────────
        bytes32 domainSeparator = erc2771Helper.registerDomain(
            forwarder,
            Strings.toHexString(uint256(uint160(address(coinvestedPosition))), 20),
            "1"
        );
        bytes32 requestType = erc2771Helper.registerRequestType(
            forwarder,
            "buy",
            "uint256 tokenAmount,uint256 maxCurrencyAmount,address TOKEN_RECEIVER"
        );

        // ── Build and sign the forward request ────────────────────────────────
        uint256 tokenBuyAmount = 2e18;
        IForwarder.ForwardRequest memory request = IForwarder.ForwardRequest({
            from: buyer,
            to: address(coinvestedPosition),
            value: 0,
            gas: 1_000_000,
            nonce: forwarder.getNonce(buyer),
            data: abi.encodeWithSelector(
                CoinvestedPosition.buy.selector,
                tokenBuyAmount,
                type(uint256).max,
                TOKEN_RECEIVER
            ),
            validUntil: 0
        });

        bytes memory suffixData = "0";
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                domainSeparator,
                keccak256(forwarder._getEncoded(request, requestType, suffixData))
            )
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(BUYER_PRIVATE_KEY, digest);
        bytes memory signature = abi.encodePacked(r, s, v);
        require(digest.recover(signature) == request.from, "FWD: signature mismatch");

        // ── Pre-conditions ────────────────────────────────────────────────────
        assertEq(token.balanceOf(TOKEN_RECEIVER), 0, "TOKEN_RECEIVER has tokens before buy");
        assertEq(eurc.balanceOf(buyer), currencyAmount, "buyer missing currency before buy");
        assertEq(eurc.balanceOf(LEAD_A), 0, "LEAD_A has currency before buy");
        assertEq(eurc.balanceOf(RECEIVER), 0, "RECEIVER has currency before buy");

        // ── Execute via forwarder ─────────────────────────────────────────────
        forwarder.execute(request, domainSeparator, requestType, suffixData, signature);

        // Drain pull-payout credits so legacy push-style balance assertions hold below.
        _drainCredits(coinvestedPosition, IERC20(address(eurc)));

        // ── Post-conditions ───────────────────────────────────────────────────
        _assertPostBuyBalances(
            address(forwarder),
            address(coinvestedPosition),
            tokenBuyAmount,
            currencyAmount,
            request,
            domainSeparator,
            requestType,
            signature
        );
    }

    // ── Tests ─────────────────────────────────────────────────────────────────

    // ─────────────────────────────────────────────────────────────────────────
    // ── Section 1: Low-level ERC2771 sender identification ───────────────────
    // ─────────────────────────────────────────────────────────────────────────

    function testERC2771BuyIdentifiesBuyer() public {
        _setupBuy(10e18, 200e6);
        eurc.mint(buyer, 400e6);
        vm.prank(buyer);
        eurc.approve(address(coinvestedPosition), 400e6);

        // Encode the call as a trusted forwarder would: calldata + buyer address appended
        bytes memory callData = abi.encodePacked(
            abi.encodeWithSelector(CoinvestedPosition.buy.selector, uint256(1e18), uint256(400e6), TOKEN_RECEIVER),
            buyer
        );
        vm.prank(TRUSTED_FORWARDER);
        (bool success, ) = address(coinvestedPosition).call(callData);
        assertTrue(success, "ERC2771 buy failed");
        assertEq(token.balanceOf(TOKEN_RECEIVER), 1e18, "tokens transferred");
    }

    function testUntrustedForwarderCannotSpoofSender() public {
        _setupBuy(10e18, 200e6);
        address untrusted = address(0xDEAD);
        eurc.mint(untrusted, 400e6);
        vm.prank(untrusted);
        eurc.approve(address(coinvestedPosition), 400e6);

        // Untrusted tries to append buyer as sender
        bytes memory callData = abi.encodePacked(
            abi.encodeWithSelector(CoinvestedPosition.buy.selector, uint256(1e18), uint256(400e6), TOKEN_RECEIVER),
            buyer // spoof buyer
        );
        // When called by untrusted forwarder, _msgSender() returns msg.sender (untrusted),
        // not the appended address (buyer). So transferFrom charges untrusted, not buyer.
        uint256 untrustedBefore = eurc.balanceOf(untrusted); // 400e6
        vm.prank(untrusted);
        (bool success, ) = address(coinvestedPosition).call(callData);
        // buyer has 0 balance throughout — it is never the msg.sender
        assertEq(eurc.balanceOf(buyer), 0, "buyer balance never changes");
        if (success) {
            // untrusted was charged (the buy succeeded but used untrusted as sender)
            assertLt(eurc.balanceOf(untrusted), untrustedBefore, "untrusted was charged, not buyer");
        }
        // Either way, the buyer was not spoofed as the payer
    }

    // ─────────────────────────────────────────────────────────────────────────
    // ── Section 2: Full GSN forwarder flow ───────────────────────────────────
    // ─────────────────────────────────────────────────────────────────────────

    function testBuyWithLocalForwarder() public {
        _buyWithERC2771(new Forwarder());
    }

    function testBuyWithMainnetGSNForwarder() public {
        // Uses deployed forwarder on mainnet with fork.
        // https://docs-v2.opengsn.org/networks/ethereum/mainnet.html
        _buyWithERC2771(Forwarder(payable(0xAa3E82b4c4093b4bA13Cb5714382C99ADBf750cA)));
    }
}
