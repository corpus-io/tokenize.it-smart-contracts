// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.23;

import "../lib/forge-std/src/Test.sol";
import "../contracts/Token.sol";
import "../contracts/factories/FeeSettingsCloneFactory.sol";
import "../contracts/factories/CrowdinvestingCloneFactory.sol";
import "../contracts/factories/TokenProxyFactory.sol";
import "../contracts/factories/PrivateOfferFactory.sol";

contract FeeSettingsIntegrationTest is Test {
    FeeSettings feeSettings;
    Fees customFees;
    Token token;
    Token currency;

    uint256 MAX_INT = type(uint256).max;

    address public constant platformAdmin = 0x0109709eCFa91a80626FF3989D68f67f5b1dD120;
    address public constant investor = 0x1109709ecFA91a80626ff3989D68f67F5B1Dd121;
    address public constant companyAdmin = 0x2109709EcFa91a80626Ff3989d68F67F5B1Dd122;
    address public constant minter = 0x3109709ECfA91A80626fF3989D68f67F5B1Dd123;
    address public constant owner = 0x6109709EcFA91A80626FF3989d68f67F5b1dd126;
    address public constant receiver = 0x7109709eCfa91A80626Ff3989D68f67f5b1dD127;
    address public constant paymentTokenProvider = 0x8109709ecfa91a80626fF3989d68f67F5B1dD128;
    address public constant trustedForwarder = 0x9109709EcFA91A80626FF3989D68f67F5B1dD129;

    uint256 public constant price = 10000000;

    address public constant exampleTokenAddress = address(74);

    function setUp() public {
        FeeSettings feeSettingsLogic = new FeeSettings(trustedForwarder);
        FeeSettingsCloneFactory feeSettingsCloneFactory = new FeeSettingsCloneFactory(address(feeSettingsLogic));
        customFees = Fees(2, 1000, 3, 1000, 5, 1000, 101 * 365 days);
        Fees memory fees = Fees(1, 101, 2, 102, 3, 103, 0);
        vm.prank(platformAdmin);
        feeSettings = FeeSettings(
            feeSettingsCloneFactory.createFeeSettingsClone(
                "salt",
                trustedForwarder,
                platformAdmin,
                fees,
                platformAdmin,
                platformAdmin,
                platformAdmin
            )
        );

        AllowList allowList = new AllowList();

        Token tokenLogic = new Token(trustedForwarder);
        TokenProxyFactory tokenProxyFactory = new TokenProxyFactory(address(tokenLogic));
        token = Token(
            tokenProxyFactory.createTokenProxy(
                "salt",
                trustedForwarder,
                feeSettings,
                companyAdmin,
                allowList,
                0,
                "Test Token",
                "TST"
            )
        );

        Crowdinvesting crowdinvestingLogic = new Crowdinvesting(trustedForwarder);
        CrowdinvestingCloneFactory crowdinvestingCloneFactory = new CrowdinvestingCloneFactory(
            address(crowdinvestingLogic)
        );
    }

    function testMintUsesCustomFeeAndCollector(address customFeeCollector) public {
        vm.assume(customFeeCollector != address(0));
        vm.assume(customFeeCollector != platformAdmin);

        vm.warp(100 * 365 days);

        assertEq(token.balanceOf(investor), 0, "token.balanceOf(investor) != 0 before");
        assertEq(token.balanceOf(customFeeCollector), 0, "token.balanceOf(customFeeCollector) != 0 before");

        vm.startPrank(platformAdmin);
        feeSettings.setCustomFee(address(token), customFees);
        feeSettings.setCustomTokenFeeCollector(address(token), customFeeCollector);
        vm.stopPrank();
        uint256 amount = 1000e18;
        vm.prank(companyAdmin);
        token.mint(investor, amount);

        assertEq(token.balanceOf(investor), amount, "token.balanceOf(investor) != 100e18 after");
        assertEq(
            token.balanceOf(customFeeCollector),
            (amount * 2) / 1000,
            "token.balanceOf(customFeeCollector) != 3e18 after"
        );
    }
}
