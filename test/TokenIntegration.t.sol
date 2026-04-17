// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import "../lib/forge-std/src/Test.sol";
import "../lib/forge-std/src/console.sol";
import "../contracts/factories/TokenProxyFactory.sol";
import "../contracts/FeeSettings.sol";
import "../contracts/common/IFeeSettings.sol";
import "./resources/WrongFeeSettings.sol";
import "./resources/CloneCreators.sol";

contract tokenTest is Test {
    event AllowListChanged(AllowList indexed newAllowList);
    event NewFeeSettingsSuggested(IFeeSettingsV1 indexed _feeSettings);
    event FeeSettingsChanged(IFeeSettingsV1 indexed newFeeSettings);

    Token token;
    AllowList allowList;
    FeeSettings feeSettings;
    address public constant TRUSTED_FORWARDER = 0x9109709EcFA91A80626FF3989D68f67F5B1dD129;
    address public constant ADMIN = 0x0109709eCFa91a80626FF3989D68f67f5b1dD120;
    address public constant REQUIRER = 0x1109709ecFA91a80626ff3989D68f67F5B1Dd121;
    address public constant MINT_ALLOWER = 0x2109709EcFa91a80626Ff3989d68F67F5B1Dd122;
    address public constant MINTER = 0x3109709ECfA91A80626fF3989D68f67F5B1Dd123;
    address public constant BURNER = 0x4109709eCFa91A80626ff3989d68F67f5b1DD124;
    address public constant TRANSFERER_ADMIN = 0x5109709EcFA91a80626ff3989d68f67F5B1dD125;
    address public constant TRANSFERER = 0x6109709EcFA91A80626FF3989d68f67F5b1dd126;
    address public constant PAUSER = 0x7109709eCfa91A80626Ff3989D68f67f5b1dD127;
    address public constant FEE_SETTINGS_OWNER = 0x8109709ecfa91a80626fF3989d68f67F5B1dD128;

    event RequirementsChanged(uint256 newRequirements);

    function setUp() public {
        allowList = createAllowList(TRUSTED_FORWARDER, ADMIN);
        feeSettings = createFeeSettings(
            TRUSTED_FORWARDER,
            FEE_SETTINGS_OWNER,
            buildFeeTypes(100, 100, 100, ADMIN, ADMIN, ADMIN)
        );
        Token implementation = new Token(TRUSTED_FORWARDER);
        TokenProxyFactory tokenCloneFactory = new TokenProxyFactory(address(implementation));
        token = Token(
            tokenCloneFactory.createTokenProxy(
                0,
                TRUSTED_FORWARDER,
                feeSettings,
                ADMIN,
                allowList,
                0x0,
                "testToken",
                "TEST"
            )
        );
        console.log(msg.sender);

        // set up roles
        vm.startPrank(ADMIN);
        token.grantRole(token.BURNER_ROLE(), BURNER);
        token.grantRole(token.TRANSFERER_ROLE(), TRANSFERER);
        token.grantRole(token.PAUSER_ROLE(), PAUSER);
        token.grantRole(token.REQUIREMENT_ROLE(), REQUIRER);
        token.grantRole(token.MINTALLOWER_ROLE(), MINT_ALLOWER);
        token.grantRole(token.TRANSFERERADMIN_ROLE(), TRANSFERER_ADMIN);

        // revoke roles from ADMIN
        token.revokeRole(token.BURNER_ROLE(), ADMIN);
        token.revokeRole(token.TRANSFERER_ROLE(), ADMIN);
        token.revokeRole(token.PAUSER_ROLE(), ADMIN);
        token.revokeRole(token.REQUIREMENT_ROLE(), ADMIN);
        token.revokeRole(token.MINTALLOWER_ROLE(), ADMIN);
        token.revokeRole(token.TRANSFERERADMIN_ROLE(), ADMIN);

        vm.stopPrank();
    }

    function testUpdateAllowList() public {
        AllowList newAllowList = createAllowList(TRUSTED_FORWARDER, ADMIN); // deploy new AllowList
        assertTrue(token.allowList() != newAllowList);
        vm.prank(ADMIN);
        vm.expectEmit(true, true, true, true, address(token));
        emit AllowListChanged(newAllowList);
        token.setAllowList(newAllowList);
        assertTrue(token.allowList() == newAllowList);
    }

    function testUpdateAllowList0() public {
        vm.expectRevert(Token.ZeroAllowListAddress.selector);
        vm.prank(ADMIN);
        token.setAllowList(AllowList(address(0)));
    }

    function testSuggestNewFeeSettingsWrongCaller(address wrongUpdater) public {
        vm.assume(wrongUpdater != feeSettings.owner());
        FeeSettings newFeeSettings = createFeeSettings(
            TRUSTED_FORWARDER,
            address(this),
            buildFeeTypes(0, 0, 0, PAUSER, PAUSER, PAUSER)
        );
        vm.prank(wrongUpdater);
        vm.expectRevert(Token.OnlyFeeSettingsOwner.selector);
        token.suggestNewFeeSettings(newFeeSettings);
    }

    function testSuggestNewFeeSettingsFeeCollector() public {
        FeeSettings newFeeSettings = createFeeSettings(
            TRUSTED_FORWARDER,
            address(this),
            buildFeeTypes(0, 0, 0, PAUSER, PAUSER, PAUSER)
        );
        vm.prank(feeSettings.feeCollector());
        vm.expectRevert(Token.OnlyFeeSettingsOwner.selector);
        token.suggestNewFeeSettings(newFeeSettings);
    }

    function testSuggestNewFeeSettings0() public {
        vm.prank(feeSettings.owner());
        vm.expectRevert();
        token.suggestNewFeeSettings(FeeSettings(address(0)));
    }

    function testSuggestNewFeeSettings(address newCollector) public {
        vm.assume(newCollector != address(0));
        FeeSettings newFeeSettings = createFeeSettings(
            TRUSTED_FORWARDER,
            address(this),
            buildFeeTypes(0, 0, 0, newCollector, newCollector, newCollector)
        );

        (, uint32 _oldTokenFeeNumerator) = FeeSettings(address(token.feeSettings())).feeTypeConfigs(FeeTypes.TOKEN);
        (, uint32 _oldCrowdinvestingFeeNumerator) = FeeSettings(address(token.feeSettings())).feeTypeConfigs(
            FeeTypes.CROWDINVESTING
        );
        (, uint32 _oldPrivateOfferFeeNumerator) = FeeSettings(address(token.feeSettings())).feeTypeConfigs(
            FeeTypes.PRIVATE_OFFER
        );

        vm.expectEmit(true, true, true, true, address(token));
        emit NewFeeSettingsSuggested(newFeeSettings);
        vm.prank(feeSettings.owner());
        token.suggestNewFeeSettings(newFeeSettings);

        // make sure old fees are still in effect
        (, uint32 _newTokenFeeNumerator) = FeeSettings(address(token.feeSettings())).feeTypeConfigs(FeeTypes.TOKEN);
        (, uint32 _newCrowdinvestingFeeNumerator) = FeeSettings(address(token.feeSettings())).feeTypeConfigs(
            FeeTypes.CROWDINVESTING
        );
        (, uint32 _newPrivateOfferFeeNumerator) = FeeSettings(address(token.feeSettings())).feeTypeConfigs(
            FeeTypes.PRIVATE_OFFER
        );

        assertTrue(_oldTokenFeeNumerator == _newTokenFeeNumerator, "token fee numerator changed!");
        assertTrue(
            _oldCrowdinvestingFeeNumerator == _newCrowdinvestingFeeNumerator,
            "crowdinvesting fee numerator changed!"
        );
        assertTrue(
            _oldPrivateOfferFeeNumerator == _newPrivateOfferFeeNumerator,
            "private offer fee numerator changed!"
        );
    }

    function testAcceptNewFeeSettings(address newCollector) public {
        vm.assume(newCollector != address(0));
        FeeSettings newFeeSettings = createFeeSettings(
            TRUSTED_FORWARDER,
            address(this),
            buildFeeTypes(0, 0, 0, newCollector, newCollector, newCollector)
        );
        (, uint32 _oldTokenFeeNumerator) = FeeSettings(address(token.feeSettings())).feeTypeConfigs(FeeTypes.TOKEN);
        (, uint32 _oldCrowdinvestingFeeNumerator) = FeeSettings(address(token.feeSettings())).feeTypeConfigs(
            FeeTypes.CROWDINVESTING
        );

        vm.prank(feeSettings.owner());
        token.suggestNewFeeSettings(newFeeSettings);

        // accept
        vm.expectEmit(true, true, true, true, address(token));
        emit FeeSettingsChanged(newFeeSettings);
        vm.prank(ADMIN);
        token.acceptNewFeeSettings(newFeeSettings);

        (, uint32 _newTokenFeeNumerator) = FeeSettings(address(token.feeSettings())).feeTypeConfigs(FeeTypes.TOKEN);
        (, uint32 _newCrowdinvestingFeeNumerator) = FeeSettings(address(token.feeSettings())).feeTypeConfigs(
            FeeTypes.CROWDINVESTING
        );
        assertTrue(FeeSettings(address(token.feeSettings())) == newFeeSettings, "fee settings not changed!");
        assertEq(FeeSettings(address(token.feeSettings())).feeCollector(), newCollector, "Wrong feeCollector");
        assertTrue(
            _newCrowdinvestingFeeNumerator != _oldCrowdinvestingFeeNumerator,
            "investment fee denominator changed!"
        );
        assertTrue(_newTokenFeeNumerator != _oldTokenFeeNumerator, "token fee denominator changed!");
    }

    function testAcceptFeeCollectorInsteadOfFeeSettings(address newFeeSettingsPretendAddress) public {
        vm.assume(newFeeSettingsPretendAddress != address(0));
        FeeSettings newFeeSettings = createFeeSettings(
            TRUSTED_FORWARDER,
            address(this),
            buildFeeTypes(
                0,
                0,
                0,
                newFeeSettingsPretendAddress,
                newFeeSettingsPretendAddress,
                newFeeSettingsPretendAddress
            )
        );
        vm.assume(newFeeSettingsPretendAddress != address(newFeeSettings));

        vm.prank(feeSettings.owner());
        token.suggestNewFeeSettings(newFeeSettings);
        console.log("Suggested fee settings: ", address(newFeeSettings));

        // ADMIN thinks he is accepting a, but suggestion is b
        vm.expectRevert();
        vm.prank(ADMIN);
        token.acceptNewFeeSettings(FeeSettings(newFeeSettingsPretendAddress));
    }

    function testAcceptWrongFeeSettings() public {
        {
            FeeSettings realNewFeeSettings = createFeeSettings(
                TRUSTED_FORWARDER,
                feeSettings.owner(),
                buildFeeTypes(
                    0,
                    0,
                    0,
                    feeSettings.feeCollector(),
                    feeSettings.feeCollector(),
                    feeSettings.feeCollector()
                )
            );
            FeeSettings fakeNewFeeSettings = createFeeSettings(
                TRUSTED_FORWARDER,
                address(this),
                buildFeeTypes(
                    0,
                    0,
                    0,
                    feeSettings.feeCollector(),
                    feeSettings.feeCollector(),
                    feeSettings.feeCollector()
                )
            );

            assertTrue(
                address(fakeNewFeeSettings) != address(realNewFeeSettings),
                "fakeNewFeeSettings == realNewFeeSettings, that should never happen"
            );

            vm.prank(feeSettings.owner());
            token.suggestNewFeeSettings(realNewFeeSettings);
            console.log("Suggested fee settings: ", address(realNewFeeSettings));

            // ADMIN thinks he is accepting a, but suggestion is b
            vm.expectRevert(Token.OnlySuggestedFeeSettings.selector);
            vm.prank(ADMIN);
            token.acceptNewFeeSettings(fakeNewFeeSettings);
        }
    }

    function testFeeCollectorCanAlwaysReceiveFee() public {
        address tokenHolder = vm.addr(1);
        address localMinter = vm.addr(2);
        address feeCollector = feeSettings.feeCollector();

        console.log("Token holder: ", tokenHolder);
        console.log("Local MINTER: ", localMinter);
        console.log("Fee collector: ", feeSettings.feeCollector());
        console.log("TRANSFERER_ADMIN: ", TRANSFERER_ADMIN);
        console.log("MINT_ALLOWER: ", MINT_ALLOWER);
        console.log("this: ", address(this));

        // set requirements
        vm.prank(REQUIRER);
        token.setRequirements(812349);

        uint256 _amount = 2 * 10 ** 18;

        // allow MINTER to mint
        vm.prank(MINT_ALLOWER);
        token.increaseMintingAllowance(localMinter, _amount);

        // allow token holder to transfer
        console.log("before");
        vm.startPrank(TRANSFERER_ADMIN);
        token.grantRole(token.TRANSFERER_ROLE(), tokenHolder);
        vm.stopPrank();

        console.log("after: ", tokenHolder);

        // ensure fee collector does not meet requirements
        assertTrue(token.requirements() > 0, "fee collector might meet requirements");
        assertTrue(token.allowList().map(feeCollector) == 0, "fee collector might meet requirements");
        // ensure fee collector is not a TRANSFERER
        assertEq(token.hasRole(token.TRANSFERER_ROLE(), feeCollector), false, "fee collector is a TRANSFERER");

        uint feeCollectorBalanceBeforeMint = token.balanceOf(feeCollector);
        // mint tokens for token holder. Currently, this also mints tokens to the fee collector, already proving they can receive tokens.
        // But if the test fee is ever set to 0, the tests above might fail if the fee collector can't send or receive tokens for some reason.
        vm.startPrank(localMinter);
        token.mint(tokenHolder, _amount);
        vm.stopPrank();

        uint feeCollectorBalanceAfterMint = token.balanceOf(feeCollector);

        assertTrue(
            feeCollectorBalanceBeforeMint <= feeCollectorBalanceAfterMint,
            "fee collector has not received tokens"
        );
        assertEq(
            feeCollectorBalanceAfterMint - feeCollectorBalanceBeforeMint,
            token.feeSettings().tokenFee(_amount, address(token)),
            "fee collector has received wrong token amount"
        );
    }

    function testFeeCollectorCanNotAlwaysBuy() public {
        address localMinter = vm.addr(2);
        address feeCollector = feeSettings.feeCollector();

        console.log("Local MINTER: ", localMinter);
        console.log("Fee collector: ", feeSettings.feeCollector());
        console.log("TRANSFERER_ADMIN: ", TRANSFERER_ADMIN);
        console.log("MINT_ALLOWER: ", MINT_ALLOWER);
        console.log("this: ", address(this));

        // set requirements
        vm.prank(REQUIRER);
        token.setRequirements(812349);

        uint256 _amount = 2 * 10 ** 18;

        // allow MINTER to mint
        vm.prank(MINT_ALLOWER);
        token.increaseMintingAllowance(localMinter, _amount);

        // ensure fee collector does not meet requirements
        assertTrue(token.requirements() > 0, "fee collector might meet requirements");
        assertTrue(token.allowList().map(feeCollector) == 0, "fee collector might meet requirements");
        // ensure fee collector is not a TRANSFERER
        assertEq(token.hasRole(token.TRANSFERER_ROLE(), feeCollector), false, "fee collector is a TRANSFERER");

        // mint tokens for feeCollector
        vm.startPrank(localMinter);
        vm.expectRevert(Token.NotAllowedToTransact.selector);
        token.mint(feeCollector, _amount);
        vm.stopPrank();
    }

    function testFeeSettingsUpdateRevertsWhenContractFailsERC165Check() public {
        FeeSettings[] memory feeSettingsArray = new FeeSettings[](3);
        feeSettingsArray[0] = new FeeSettingsFailERC165Check0();
        feeSettingsArray[1] = new FeeSettingsFailERC165Check1();
        feeSettingsArray[2] = new FeeSettingsFailIFeeSettingsV2Check();

        vm.startPrank(feeSettings.owner());
        // cycle through the fake contracts and make sure each one triggers a revert
        for (uint i = 0; i < feeSettingsArray.length; i++) {
            vm.expectRevert(Token.FeeSettingsInterfaceNotSupported.selector);
            token.suggestNewFeeSettings(feeSettingsArray[i]);
        }
        vm.stopPrank();
    }
}
