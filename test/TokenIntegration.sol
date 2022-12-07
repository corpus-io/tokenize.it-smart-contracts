// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "../lib/forge-std/src/Test.sol";
import "../contracts/Token.sol";

contract tokenTest is Test {
    Token token;
    AllowList allowList;
    FeeSettings feeSettings;
    address public constant trustedForwarder =
        0x9109709EcFA91A80626FF3989D68f67F5B1dD129;
    address public constant admin = 0x0109709eCFa91a80626FF3989D68f67f5b1dD120;
    address public constant requirer =
        0x1109709ecFA91a80626ff3989D68f67F5B1Dd121;
    address public constant mintAllower =
        0x2109709EcFa91a80626Ff3989d68F67F5B1Dd122;
    address public constant minter = 0x3109709ECfA91A80626fF3989D68f67F5B1Dd123;
    address public constant burner = 0x4109709eCFa91A80626ff3989d68F67f5b1DD124;
    address public constant transfererAdmin =
        0x5109709EcFA91a80626ff3989d68f67F5B1dD125;
    address public constant transferer =
        0x6109709EcFA91A80626FF3989d68f67F5b1dd126;
    address public constant pauser = 0x7109709eCfa91A80626Ff3989D68f67f5b1dD127;
    address public constant feeSettingsOwner =
        0x8109709ecfa91a80626fF3989d68f67F5B1dD128;

    event RequirementsChanged(uint256 newRequirements);

    function setUp() public {
        vm.prank(admin);
        allowList = new AllowList();
        vm.prank(feeSettingsOwner);
        Fees memory fees = Fees(100, 100, 100, 0);
        feeSettings = new FeeSettings(fees, admin);
        token = new Token(
            trustedForwarder,
            feeSettings,
            admin,
            allowList,
            0x0,
            "testToken",
            "TEST"
        );
        console.log(msg.sender);

        // set up roles
        vm.startPrank(admin);
        token.grantRole(token.BURNER_ROLE(), burner);
        token.grantRole(token.TRANSFERER_ROLE(), transferer);
        token.grantRole(token.PAUSER_ROLE(), pauser);
        token.grantRole(token.REQUIREMENT_ROLE(), requirer);
        token.grantRole(token.MINTALLOWER_ROLE(), mintAllower);
        token.grantRole(token.TRANSFERERADMIN_ROLE(), transfererAdmin);

        // revoke roles from admin
        token.revokeRole(token.BURNER_ROLE(), admin);
        token.revokeRole(token.TRANSFERER_ROLE(), admin);
        token.revokeRole(token.PAUSER_ROLE(), admin);
        token.revokeRole(token.REQUIREMENT_ROLE(), admin);
        token.revokeRole(token.MINTALLOWER_ROLE(), admin);
        token.revokeRole(token.TRANSFERERADMIN_ROLE(), admin);

        vm.stopPrank();
    }

    function testSuggestNewFeeSettingsWrongCaller(address wrongUpdater) public {
        vm.assume(wrongUpdater != feeSettings.owner());
        Fees memory fees = Fees(0, 0, 0, 0);
        FeeSettings newFeeSettings = new FeeSettings(fees, pauser);
        vm.prank(wrongUpdater);
        vm.expectRevert(
            "Only fee settings owner can suggest fee settings update"
        );
        token.suggestNewFeeSettings(newFeeSettings);
    }

    function testSuggestNewFeeSettingsFeeCollector() public {
        Fees memory fees = Fees(0, 0, 0, 0);
        FeeSettings newFeeSettings = new FeeSettings(fees, pauser);
        vm.prank(feeSettings.feeCollector());
        vm.expectRevert(
            "Only fee settings owner can suggest fee settings update"
        );
        token.suggestNewFeeSettings(newFeeSettings);
    }

    function testSuggestNewFeeSettings0() public {
        vm.prank(feeSettings.owner());
        vm.expectRevert("Fee settings cannot be zero address");
        token.suggestNewFeeSettings(FeeSettings(address(0)));
    }

    function testSuggestNewFeeSettings(address newCollector) public {
        vm.assume(newCollector != address(0));
        Fees memory fees = Fees(0, 0, 0, 0);
        FeeSettings newFeeSettings = new FeeSettings(fees, newCollector);
        FeeSettings oldFeeSettings = token.feeSettings();
        uint oldInvestmentFeeDenominator = oldFeeSettings
            .continuousFundraisingFeeDenominator();
        uint oldTokenFeeDenominator = oldFeeSettings.tokenFeeDenominator();
        vm.prank(feeSettings.owner());
        token.suggestNewFeeSettings(newFeeSettings);

        // make sure old fees are still in effect
        assertTrue(
            address(token.feeSettings()) == address(oldFeeSettings),
            "fee settings have changed!"
        );
        assertTrue(
            token.suggestedFeeSettings() == newFeeSettings,
            "suggested fee settings not set!"
        );
        assertTrue(
            token.feeSettings().continuousFundraisingFeeDenominator() ==
                oldInvestmentFeeDenominator,
            "investment fee denominator changed!"
        );
        assertTrue(
            token.feeSettings().tokenFeeDenominator() == oldTokenFeeDenominator,
            "token fee denominator changed!"
        );
    }

    function testAcceptNewFeeSettings(address newCollector) public {
        vm.assume(newCollector != address(0));
        Fees memory fees = Fees(0, 0, 0, 0);
        FeeSettings newFeeSettings = new FeeSettings(fees, newCollector);
        FeeSettings oldFeeSettings = token.feeSettings();
        uint oldInvestmentFeeDenominator = oldFeeSettings
            .continuousFundraisingFeeDenominator();
        uint oldTokenFeeDenominator = oldFeeSettings.tokenFeeDenominator();
        vm.prank(feeSettings.owner());
        token.suggestNewFeeSettings(newFeeSettings);

        // accept
        vm.prank(admin);
        token.acceptNewFeeSettings(newFeeSettings);
        assertTrue(
            token.feeSettings() == newFeeSettings,
            "fee settings not changed!"
        );
        assertEq(
            token.feeSettings().feeCollector(),
            newCollector,
            "Wrong feeCollector"
        );
        assertTrue(
            address(token.suggestedFeeSettings()) == address(0),
            "suggested fee settings not reset!"
        );
        assertTrue(
            token.feeSettings().continuousFundraisingFeeDenominator() !=
                oldInvestmentFeeDenominator,
            "investment fee denominator changed!"
        );
        assertTrue(
            token.feeSettings().tokenFeeDenominator() != oldTokenFeeDenominator,
            "token fee denominator changed!"
        );
    }

    function testFrontrunFeeSettingsAcceptance(
        address newFeeSettingsPretendAddress
    ) public {
        vm.assume(newFeeSettingsPretendAddress != address(0));
        Fees memory fees = Fees(0, 0, 0, 0);
        FeeSettings newFeeSettings = new FeeSettings(
            fees,
            newFeeSettingsPretendAddress
        );
        vm.assume(newFeeSettingsPretendAddress != address(newFeeSettings));

        vm.prank(feeSettings.owner());
        token.suggestNewFeeSettings(newFeeSettings);
        console.log("Suggested fee settings: ", address(newFeeSettings));

        // admin thinks he is accepting a, but suggestion is b
        vm.expectRevert("Only suggested fee settings can be accepted");
        vm.prank(admin);
        token.acceptNewFeeSettings(FeeSettings(newFeeSettingsPretendAddress));
    }

    function testFeeCollectorCanAlwaysTransact() public {
        address tokenHolder = vm.addr(1);
        address localMinter = vm.addr(2);
        address feeCollector = feeSettings.feeCollector();

        console.log("Token holder: ", tokenHolder);
        console.log("Local minter: ", localMinter);
        console.log("Fee collector: ", feeSettings.feeCollector());
        console.log("transfererAdmin: ", transfererAdmin);
        console.log("mintAllower: ", mintAllower);
        console.log("this: ", address(this));

        // set requirements
        vm.prank(requirer);
        token.setRequirements(812349);

        uint256 _amount = 2 * 10 ** 18;

        // allow minter to mint
        vm.prank(mintAllower);
        token.increaseMintingAllowance(localMinter, _amount);

        // allow token holder to transfer
        console.log("before");
        vm.startPrank(transfererAdmin);
        token.grantRole(token.TRANSFERER_ROLE(), tokenHolder);
        vm.stopPrank();

        console.log("after: ", tokenHolder);

        // mint tokens for token holder. Currently, this also mints tokens to the fee collector, already proving they can receive tokens.
        // But if the test fee is ever set to 0, the tests above might fail if the fee collector can't send or receive tokens for some reason.
        vm.startPrank(localMinter);
        token.mint(tokenHolder, _amount);
        vm.stopPrank();

        uint feeCollectorBalanceBeforeTransfer = token.balanceOf(feeCollector);

        assertTrue(
            token.balanceOf(feeCollector) == feeCollectorBalanceBeforeTransfer,
            "fee collector has too many tokens"
        );

        // test if fee collector can receive
        vm.prank(tokenHolder);
        token.transfer(feeCollector, _amount);

        assertTrue(
            token.balanceOf(feeCollector) ==
                feeCollectorBalanceBeforeTransfer + _amount,
            "fee collector has no tokens"
        );
        console.log(
            "fee collector balance is: ",
            token.balanceOf(feeCollector)
        );
        console.log("_amount is: ", _amount);

        // test if fee collector can send
        vm.prank(feeCollector);
        token.transfer(tokenHolder, 500);

        console.log(
            "fee collector balance is: ",
            token.balanceOf(feeCollector)
        );
        console.log("fee collector balance should be: ", _amount - 500);

        assertTrue(
            token.balanceOf(feeCollector) ==
                feeCollectorBalanceBeforeTransfer + _amount - 500,
            "fee collector has wrong balance"
        );
    }
}
