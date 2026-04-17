// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import "../../lib/forge-std/src/Test.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "../../contracts/FeeSettings.sol";
import "../../contracts/factories/FeeSettingsCloneFactory.sol";

// Old contracts are deployed at runtime from npm artifact bytecode via deployCode —
// no source import, no legacy compilation, no OZ version conflict.
// npm package: @tokenize.it/contracts@4.2.0-beta.0

// Minimal interfaces for v4.2.0-beta.0 Token and AllowList (IFeeSettingsV1 era)
interface ITokenV4 {
    function feeSettings() external view returns (address);

    function increaseMintingAllowance(address minter, uint256 allowance) external;

    function mint(address to, uint256 amount) external;

    function balanceOf(address account) external view returns (uint256);
}

// Test-only ERC20 currency — compiled against current OZ, no legacy conflict.
contract TestCurrencyV4 is ERC20 {
    constructor(address recipient, uint256 amount) ERC20("TestCurrency", "TC") {
        _mint(recipient, amount);
    }
}

/**
 * @notice Verifies that Token and PersonalInvite from v4.2.0-beta.0 still work with the current FeeSettings.
 * @dev Token (v4) uses IFeeSettingsV1: tokenFee(uint256) and feeCollector().
 *      PersonalInvite (v4) uses IFeeSettingsV1: personalInviteFee(uint256) and feeCollector().
 *      Both contracts are plain (non-upgradeable): Token takes all params in its constructor,
 *      AllowList has no explicit constructor (owner = deployer).
 */
contract BackwardsCompatibilityV4_2_0_beta_0 is Test {
    // Artifact path prefix for @tokenize.it/contracts@4.2.0-beta.0
    string constant ARTIFACTS = "test/legacy/v4.2.0-beta.0/node_modules/@tokenize.it/contracts/artifacts/contracts/";

    uint32 constant FEE_DENOMINATOR = 10_000;
    uint32 constant TOKEN_FEE_NUMERATOR = 100; // 1%
    uint32 constant PERSONAL_INVITE_FEE_NUMERATOR = 200; // 2%

    uint256 constant TOKEN_AMOUNT = 1_000e18;
    uint256 constant TOKEN_PRICE = 3e18; // 3 currency units per token (18 decimals)

    address constant platformAdmin = address(0x1001);
    address constant companyAdmin = address(0x1002);
    address constant investor = address(0x1003);
    address constant currencyReceiver = address(0x1004);
    address constant feeCollector = address(0x1005);
    address constant trustedForwarder = address(0x1006);

    address feeSettings;
    ITokenV4 token;
    TestCurrencyV4 currency;

    function setUp() public {
        FeeSettings feeSettingsLogic = new FeeSettings(trustedForwarder);
        FeeSettingsCloneFactory feeSettingsCloneFactory = new FeeSettingsCloneFactory(address(feeSettingsLogic));

        FeeSettings.FeeTypeInit[] memory feeTypes = new FeeSettings.FeeTypeInit[](2);
        feeTypes[0] = FeeSettings.FeeTypeInit(keccak256("TOKEN"), 500, TOKEN_FEE_NUMERATOR, feeCollector);
        // personalInviteFee(uint256) in the current FeeSettings routes through FeeTypes.PRIVATE_OFFER
        feeTypes[1] = FeeSettings.FeeTypeInit(
            keccak256("PRIVATE_OFFER"),
            500,
            PERSONAL_INVITE_FEE_NUMERATOR,
            feeCollector
        );
        vm.prank(platformAdmin);
        feeSettings = feeSettingsCloneFactory.createFeeSettingsClone(
            "someSalt",
            trustedForwarder,
            platformAdmin,
            feeTypes
        );

        // Deploy v4.2.0-beta.0 AllowList from npm artifact bytecode.
        // No constructor args; the test contract (address(this)) becomes the owner.
        // With requirements = 0, no allowList entries are needed during minting.
        address allowList = deployCode(string.concat(ARTIFACTS, "AllowList.sol/AllowList.json"));

        // Deploy v4.2.0-beta.0 Token from npm artifact bytecode (non-upgradeable, plain constructor).
        token = ITokenV4(
            deployCode(
                string.concat(ARTIFACTS, "Token.sol/Token.json"),
                abi.encode(trustedForwarder, feeSettings, companyAdmin, allowList, uint256(0), "TestToken", "TT")
            )
        );

        uint256 currencyAmount = (TOKEN_AMOUNT * TOKEN_PRICE) / 1e18;
        currency = new TestCurrencyV4(investor, currencyAmount);
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

    function testPersonalInviteWithFee() public {
        uint256 currencyAmount = (TOKEN_AMOUNT * TOKEN_PRICE) / 1e18;
        uint256 expectedCurrencyFee = (currencyAmount * PERSONAL_INVITE_FEE_NUMERATOR) / FEE_DENOMINATOR;

        // Predict the PersonalInvite address (deployCode uses CREATE, so address = f(deployer, nonce))
        address futurePersonalInvite = vm.computeCreateAddress(address(this), vm.getNonce(address(this)));

        // Grant minting allowance to the future PersonalInvite address
        vm.prank(companyAdmin);
        token.increaseMintingAllowance(futurePersonalInvite, TOKEN_AMOUNT);

        // Grant currency allowance from investor to the future PersonalInvite
        vm.prank(investor);
        currency.approve(futurePersonalInvite, currencyAmount);

        assertEq(token.balanceOf(investor), 0, "investor token balance not 0 before");
        assertEq(currency.balanceOf(investor), currencyAmount, "investor currency balance wrong before");
        assertEq(currency.balanceOf(feeCollector), 0, "fee collector currency balance not 0 before");
        assertEq(currency.balanceOf(currencyReceiver), 0, "currency receiver balance not 0 before");

        // Deploy PersonalInvite from npm artifact — its constructor executes the deal
        deployCode(
            string.concat(ARTIFACTS, "PersonalInvite.sol/PersonalInvite.json"),
            abi.encode(
                investor,
                investor,
                currencyReceiver,
                TOKEN_AMOUNT,
                TOKEN_PRICE,
                block.timestamp + 1 days,
                address(currency),
                address(token)
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
}
