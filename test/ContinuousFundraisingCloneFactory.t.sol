// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.13;

import "../lib/forge-std/src/Test.sol";
import "../contracts/ContinuousFundraisingCloneFactory.sol";
import "../contracts/FeeSettings.sol";
import "./resources/FakePaymentToken.sol";

contract ContinuousFundraisingCloneFactoryTest is Test {
    ContinuousFundraising continuousFundraisingImplementation;
    Token tokenImplementation;
    AllowList allowList;
    FeeSettings feeSettings;
    FakePaymentToken fakePaymentToken;
    ContinuousFundraisingCloneFactory cloneFactory;
    address public constant trustedForwarder = 0x9109709EcFA91A80626FF3989D68f67F5B1dD129;
    address public constant admin = 0x0109709eCFa91a80626FF3989D68f67f5b1dD120;
    address public constant requirer = 0x1109709ecFA91a80626ff3989D68f67F5B1Dd121;
    address public constant mintAllower = 0x2109709EcFa91a80626Ff3989d68F67F5B1Dd122;
    address public constant minter = 0x3109709ECfA91A80626fF3989D68f67F5B1Dd123;
    address public constant burner = 0x4109709eCFa91A80626ff3989d68F67f5b1DD124;
    address public constant transfererAdmin = 0x5109709EcFA91a80626ff3989d68f67F5B1dD125;
    address public constant transferer = 0x6109709EcFA91A80626FF3989d68f67F5b1dd126;
    address public constant pauser = 0x7109709eCfa91A80626Ff3989D68f67f5b1dD127;
    address public constant feeSettingsAndAllowListOwner = 0x8109709ecfa91a80626fF3989d68f67F5B1dD128;

    uint256 requirements = 0;

    event RequirementsChanged(uint256 newRequirements);

    function setUp() public {
        vm.startPrank(feeSettingsAndAllowListOwner);
        allowList = new AllowList();
        Fees memory fees = Fees(100, 100, 100, 0);
        feeSettings = new FeeSettings(fees, feeSettingsAndAllowListOwner);
        fakePaymentToken = new FakePaymentToken(100000, 18);
        vm.stopPrank();

        tokenImplementation = new Token(
            trustedForwarder,
            feeSettings,
            admin,
            allowList,
            requirements,
            "testToken",
            "TEST"
        );

        continuousFundraisingImplementation = new ContinuousFundraising(
            address(trustedForwarder),
            admin,
            100,
            100,
            100,
            100,
            IERC20(fakePaymentToken),
            tokenImplementation
        );

        cloneFactory = new ContinuousFundraisingCloneFactory(address(continuousFundraisingImplementation));
    }

    function testAddressPrediction(bytes32 salt) public {
        address expected = cloneFactory.predictCloneAddress(salt);
        address actual = cloneFactory.createContinuousFundraisingClone(
            salt,
            admin,
            222,
            333,
            444,
            555,
            fakePaymentToken,
            tokenImplementation
        );
        assertEq(expected, actual, "address prediction failed");
    }

    function testInitialization(
        bytes32 salt,
        address _currencyReceiver,
        uint256 _minAmountPerBuyer,
        uint256 _maxAmountPerBuyer,
        uint256 _tokenPrice,
        uint256 _maxAmountOfTokenToBeSold,
        address _currency,
        address _token
    ) public {
        vm.assume(_currencyReceiver != address(0));
        vm.assume(_minAmountPerBuyer < _maxAmountPerBuyer);
        vm.assume(_tokenPrice > 0);
        vm.assume(_maxAmountOfTokenToBeSold > _minAmountPerBuyer);
        vm.assume(_maxAmountOfTokenToBeSold > 0);
        vm.assume(_currency != address(0));
        vm.assume(_token != address(0));

        ContinuousFundraising clone = ContinuousFundraising(
            cloneFactory.createContinuousFundraisingClone(
                salt,
                _currencyReceiver,
                _minAmountPerBuyer,
                _maxAmountPerBuyer,
                _tokenPrice,
                _maxAmountOfTokenToBeSold,
                IERC20(_currency),
                Token(_token)
            )
        );

        // ensure that the clone is initialized correctly
        assertEq(clone.currencyReceiver(), _currencyReceiver, "currencyReceiver not set");
        assertEq(clone.minAmountPerBuyer(), _minAmountPerBuyer, "minAmountPerBuyer not set");
        assertEq(clone.maxAmountPerBuyer(), _maxAmountPerBuyer, "maxAmountPerBuyer not set");
        assertEq(clone.tokenPrice(), _tokenPrice, "tokenPrice not set");
        assertEq(clone.maxAmountOfTokenToBeSold(), _maxAmountOfTokenToBeSold, "maxAmountOfTokenToBeSold not set");
        assertEq(address(clone.currency()), _currency, "currency not set");
        assertEq(address(clone.token()), _token, "token not set");

        // check that the clone uses the same trustedForwarder as the implementation
        assertTrue(clone.isTrustedForwarder(trustedForwarder), "trustedForwarder is wrong");

        console.log("owner: %s", clone.owner());

        assertTrue(false);
    }

    // function testEmptyStringReverts(
    //     bytes32 salt,
    //     string memory someString,
    //     address _admin,
    //     address _allowList,
    //     uint256 _requirements
    // ) public {
    //     vm.assume(_admin != address(0));
    //     vm.assume(_allowList != address(0));
    //     vm.assume(bytes(someString).length > 0);

    //     FeeSettings _feeSettings = new FeeSettings(Fees(100, 100, 100, 0), feeSettingsAndAllowListOwner);

    //     vm.expectRevert("String must not be empty");
    //     cloneFactory.createTokenClone(salt, _feeSettings, _admin, AllowList(_allowList), _requirements, "", someString);

    //     vm.expectRevert("String must not be empty");
    //     cloneFactory.createTokenClone(salt, _feeSettings, _admin, AllowList(_allowList), _requirements, someString, "");
    // }
}
