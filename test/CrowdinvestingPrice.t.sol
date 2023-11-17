// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.23;

import "../lib/forge-std/src/Test.sol";
import "../contracts/factories/TokenProxyFactory.sol";
import "../contracts/FeeSettings.sol";
import "../contracts/factories/CrowdinvestingCloneFactory.sol";
import "./resources/FakePaymentToken.sol";
import "./resources/MaliciousPaymentToken.sol";

contract CrowdinvestingTest is Test {
    event CurrencyReceiverChanged(address indexed);
    event MinAmountPerBuyerChanged(uint256);
    event MaxAmountPerBuyerChanged(uint256);
    event TokenPriceAndCurrencyChanged(uint256, IERC20 indexed);
    event MaxAmountOfTokenToBeSoldChanged(uint256);
    event TokensBought(address indexed buyer, uint256 tokenAmount, uint256 currencyAmount);

    CrowdinvestingCloneFactory factory;
    Crowdinvesting raise;
    AllowList list;
    IFeeSettingsV2 feeSettings;

    address wrongFeeReceiver = address(5);

    TokenProxyFactory tokenCloneFactory;
    Token token;
    FakePaymentToken paymentToken;

    MaliciousPaymentToken maliciousPaymentToken;

    address public constant admin = 0x0109709eCFa91a80626FF3989D68f67f5b1dD120;
    address public constant buyer = 0x1109709ecFA91a80626ff3989D68f67F5B1Dd121;
    address public constant mintAllower = 0x2109709EcFa91a80626Ff3989d68F67F5B1Dd122;
    address public constant minter = 0x3109709ECfA91A80626fF3989D68f67F5B1Dd123;
    address public constant owner = 0x6109709EcFA91A80626FF3989d68f67F5b1dd126;
    address public constant receiver = 0x7109709eCfa91A80626Ff3989D68f67f5b1dD127;
    address public constant paymentTokenProvider = 0x8109709ecfa91a80626fF3989d68f67F5B1dD128;
    address public constant trustedForwarder = 0x9109709EcFA91A80626FF3989D68f67F5B1dD129;

    uint8 public constant paymentTokenDecimals = 6;
    uint256 public constant paymentTokenAmount = 1000 * 10 ** paymentTokenDecimals;

    uint256 public constant price = 7 * 10 ** paymentTokenDecimals; // 7 payment tokens per token

    uint256 public constant maxAmountOfTokenToBeSold = 20 * 10 ** 18; // 20 token
    uint256 public constant maxAmountPerBuyer = maxAmountOfTokenToBeSold / 2; // 10 token
    uint256 public constant minAmountPerBuyer = maxAmountOfTokenToBeSold / 200; // 0.1 token

    function setUp() public {
        list = new AllowList();
        Fees memory fees = Fees(1, 100, 1, 100, 1, 100, 100);
        feeSettings = new FeeSettings(fees, wrongFeeReceiver, admin, wrongFeeReceiver);

        // create token
        address tokenLogicContract = address(new Token(trustedForwarder));
        tokenCloneFactory = new TokenProxyFactory(tokenLogicContract);
        token = Token(
            tokenCloneFactory.createTokenProxy(0, trustedForwarder, feeSettings, admin, list, 0x0, "TESTTOKEN", "TEST")
        );

        // set up currency
        vm.prank(paymentTokenProvider);
        paymentToken = new FakePaymentToken(paymentTokenAmount, paymentTokenDecimals); // 1000 tokens with 6 decimals
        // transfer currency to buyer
        vm.prank(paymentTokenProvider);
        paymentToken.transfer(buyer, paymentTokenAmount);
        assertTrue(paymentToken.balanceOf(buyer) == paymentTokenAmount);

        vm.prank(owner);
        factory = new CrowdinvestingCloneFactory(address(new Crowdinvesting(trustedForwarder)));

        CrowdinvestingInitializerArguments memory arguments = CrowdinvestingInitializerArguments(
            owner,
            payable(receiver),
            minAmountPerBuyer,
            maxAmountPerBuyer,
            price,
            price,
            price,
            maxAmountOfTokenToBeSold,
            paymentToken,
            token,
            0,
            address(0)
        );

        raise = Crowdinvesting(factory.createCrowdinvestingClone(0, trustedForwarder, arguments));

        // allow raise contract to mint
        bytes32 roleMintAllower = token.MINTALLOWER_ROLE();

        vm.prank(admin);
        token.grantRole(roleMintAllower, mintAllower);
        vm.prank(mintAllower);
        token.increaseMintingAllowance(address(raise), maxAmountOfTokenToBeSold);

        // give raise contract allowance
        vm.prank(buyer);
        paymentToken.approve(address(raise), paymentTokenAmount);
    }
}
