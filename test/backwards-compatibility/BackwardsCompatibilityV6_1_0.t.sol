// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import "../../lib/forge-std/src/Test.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "../resources/FeeSettingsMissingV2.sol";
import "../../contracts/FeeSettings.sol";
import "../../contracts/factories/FeeSettingsCloneFactory.sol";

// Old contracts are deployed at runtime from npm artifact bytecode via deployCode —
// no source import, no legacy compilation, no OZ version conflict.
// npm package: @tokenize.it/contracts@6.1.0

// Minimal interfaces for v6.1.0 Token and AllowList (IFeeSettingsV2 era)
interface ITokenV6 {
    function feeSettings() external view returns (address);

    function increaseMintingAllowance(address minter, uint256 allowance) external;

    function mint(address to, uint256 amount) external;

    function balanceOf(address account) external view returns (uint256);
}

interface IAllowListV6 {
    function initialize(address owner) external;

    function set(address addr, uint256 attributes) external;
}

// PrivateOfferArguments struct matching v6.1.0 PrivateOffer constructor tuple.
// Adds tokenHolder compared to v5.0.1: when address(0), tokens are minted; otherwise transferred.
struct PrivateOfferArgumentsV610 {
    address currencyPayer;
    address tokenReceiver;
    address currencyReceiver;
    uint256 tokenAmount;
    uint256 tokenPrice;
    uint256 expiration;
    address currency; // IERC20 stored as address
    address token; // Token stored as address
    address tokenHolder; // address(0) → mint; non-zero → transferFrom
}

// Test-only ERC20 currency — compiled against current OZ, no legacy conflict.
contract TestCurrencyV6 is ERC20 {
    constructor(address recipient, uint256 amount) ERC20("TestCurrency", "TC") {
        _mint(recipient, amount);
    }
}

/**
 * @notice Verifies that Token and PrivateOffer from v6.1.0 still work with the current FeeSettings.
 * @dev Token (v6.1.0) uses IFeeSettingsV2: tokenFee(uint256,address) and tokenFeeCollector(address).
 *      PrivateOffer (v6.1.0) uses IFeeSettingsV2: privateOfferFee(uint256,address) and
 *      privateOfferFeeCollector(address), reading feeSettings from token.feeSettings().
 *      Both Token and AllowList are upgradeable (UUPS / ERC1167 clone).
 */
contract BackwardsCompatibilityV6_1_0 is Test {
    // Artifact path prefix for @tokenize.it/contracts@6.1.0
    string constant ARTIFACTS = "test/legacy/v6.1.0/node_modules/@tokenize.it/contracts/artifacts/contracts/";

    uint256 constant TRUSTED_CURRENCY = 2 ** 255;

    uint32 constant FEE_DENOMINATOR = 10_000;
    uint32 constant TOKEN_FEE_NUMERATOR = 100; // 1%
    uint32 constant PRIVATE_OFFER_FEE_NUMERATOR = 200; // 2%

    uint256 constant TOKEN_AMOUNT = 1_000e18;
    uint256 constant TOKEN_PRICE = 3e18; // 3 currency units per token (18 decimals)

    address constant platformAdmin = address(0x1001);
    address constant companyAdmin = address(0x1002);
    address constant investor = address(0x1003);
    address constant currencyReceiver = address(0x1004);
    address constant feeCollector = address(0x1005);
    address constant trustedForwarder = address(0x1006);

    address feeSettings;
    ITokenV6 token;
    IAllowListV6 allowList;
    TestCurrencyV6 currency;

    function setUp() public {
        FeeSettings feeSettingsLogic = new FeeSettings(trustedForwarder);
        FeeSettingsCloneFactory feeSettingsCloneFactory = new FeeSettingsCloneFactory(address(feeSettingsLogic));

        FeeSettings.FeeTypeInit[] memory feeTypes = new FeeSettings.FeeTypeInit[](2);
        feeTypes[0] = FeeSettings.FeeTypeInit(keccak256("TOKEN"), 500, TOKEN_FEE_NUMERATOR, feeCollector);
        feeTypes[1] = FeeSettings.FeeTypeInit(
            keccak256("PRIVATE_OFFER"),
            500,
            PRIVATE_OFFER_FEE_NUMERATOR,
            feeCollector
        );
        vm.prank(platformAdmin);
        feeSettings = feeSettingsCloneFactory.createFeeSettingsClone(
            "someSalt",
            trustedForwarder,
            platformAdmin,
            feeTypes
        );

        // Deploy v6.1.0 AllowList from npm artifact bytecode (upgradeable: impl + ERC1167 clone).
        // The test contract becomes the owner so it can register currencies without pranking.
        address allowListImpl = deployCode(
            string.concat(ARTIFACTS, "AllowList.sol/AllowList.json"),
            abi.encode(trustedForwarder)
        );
        allowList = IAllowListV6(Clones.clone(allowListImpl));
        allowList.initialize(address(this));

        // Deploy v6.1.0 Token from npm artifact bytecode (upgradeable: impl + ERC1967 proxy).
        address tokenImpl = deployCode(string.concat(ARTIFACTS, "Token.sol/Token.json"), abi.encode(trustedForwarder));
        bytes memory initData = abi.encodeWithSignature(
            "initialize(address,address,address,uint256,string,string)",
            feeSettings,
            companyAdmin,
            address(allowList),
            uint256(0),
            "TestToken",
            "TT"
        );
        token = ITokenV6(address(new ERC1967Proxy(tokenImpl, initData)));

        uint256 currencyAmount = (TOKEN_AMOUNT * TOKEN_PRICE) / 1e18;
        currency = new TestCurrencyV6(investor, currencyAmount);

        // PrivateOffer checks that the currency is registered as TRUSTED_CURRENCY in the token's allowList
        allowList.set(address(currency), TRUSTED_CURRENCY);
    }

    function testTokenPointsAtCurrentFeeSettings() public view {
        assertEq(token.feeSettings(), feeSettings);
    }

    function testMintWithFee() public {
        uint256 expectedFee = (TOKEN_AMOUNT * TOKEN_FEE_NUMERATOR) / FEE_DENOMINATOR;

        vm.prank(companyAdmin);
        token.increaseMintingAllowance(companyAdmin, TOKEN_AMOUNT);

        assertEq(token.balanceOf(investor), 0, "investor token balance not 0 before");
        assertEq(token.balanceOf(feeCollector), 0, "fee collector token balance not 0 before");

        vm.prank(companyAdmin);
        token.mint(investor, TOKEN_AMOUNT);

        assertEq(token.balanceOf(investor), TOKEN_AMOUNT, "investor token balance wrong after");
        assertEq(token.balanceOf(feeCollector), expectedFee, "fee collector token balance wrong after");
    }

    function testPrivateOfferWithFee() public {
        uint256 currencyAmount = (TOKEN_AMOUNT * TOKEN_PRICE) / 1e18;
        uint256 expectedCurrencyFee = (currencyAmount * PRIVATE_OFFER_FEE_NUMERATOR) / FEE_DENOMINATOR;

        // Predict the PrivateOffer address (deployCode uses CREATE, so address = f(deployer, nonce))
        address futurePrivateOffer = vm.computeCreateAddress(address(this), vm.getNonce(address(this)));

        // Grant minting allowance to the future PrivateOffer address
        vm.prank(companyAdmin);
        token.increaseMintingAllowance(futurePrivateOffer, TOKEN_AMOUNT);

        // Grant currency allowance from investor to the future PrivateOffer
        vm.prank(investor);
        currency.approve(futurePrivateOffer, currencyAmount);

        assertEq(token.balanceOf(investor), 0, "investor token balance not 0 before");
        assertEq(currency.balanceOf(investor), currencyAmount, "investor currency balance wrong before");
        assertEq(currency.balanceOf(feeCollector), 0, "fee collector currency balance not 0 before");
        assertEq(currency.balanceOf(currencyReceiver), 0, "currency receiver balance not 0 before");

        // Deploy PrivateOffer from npm artifact — its constructor executes the deal.
        // tokenHolder = address(0) → PrivateOffer mints tokens instead of transferring.
        deployCode(
            string.concat(ARTIFACTS, "PrivateOffer.sol/PrivateOffer.json"),
            abi.encode(
                PrivateOfferArgumentsV610({
                    currencyPayer: investor,
                    tokenReceiver: investor,
                    currencyReceiver: currencyReceiver,
                    tokenAmount: TOKEN_AMOUNT,
                    tokenPrice: TOKEN_PRICE,
                    expiration: block.timestamp + 1 days,
                    currency: address(currency),
                    token: address(token),
                    tokenHolder: address(0)
                })
            )
        );

        assertEq(token.balanceOf(investor), TOKEN_AMOUNT, "investor token balance");
        assertEq(currency.balanceOf(investor), 0, "investor currency balance");
        assertEq(currency.balanceOf(feeCollector), expectedCurrencyFee, "fee collector currency balance");
        assertEq(
            currency.balanceOf(currencyReceiver),
            currencyAmount - expectedCurrencyFee,
            "currency receiver balance"
        );
    }

    function testMintRevertsWithMissingV2FeeSettings() public {
        FeeSettingsMissingV2 brokenFeeSettings = new FeeSettingsMissingV2(feeCollector);
        address brokenTokenImpl = deployCode(
            string.concat(ARTIFACTS, "Token.sol/Token.json"),
            abi.encode(trustedForwarder)
        );
        bytes memory initData = abi.encodeWithSignature(
            "initialize(address,address,address,uint256,string,string)",
            address(brokenFeeSettings),
            companyAdmin,
            address(allowList),
            uint256(0),
            "BrokenToken",
            "BT"
        );
        // Initialization succeeds: supportsInterface lies and returns true for IFeeSettingsV2.
        ITokenV6 brokenToken = ITokenV6(address(new ERC1967Proxy(brokenTokenImpl, initData)));

        // Grant minting allowance so the revert comes from tokenFee(), not from missing allowance.
        vm.prank(companyAdmin);
        brokenToken.increaseMintingAllowance(companyAdmin, TOKEN_AMOUNT);

        // Minting reverts: tokenFee(uint256, address) is not implemented.
        vm.expectRevert();
        vm.prank(companyAdmin);
        brokenToken.mint(investor, TOKEN_AMOUNT);
    }
}
