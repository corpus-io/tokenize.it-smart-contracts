// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.13;

import "../lib/forge-std/src/Test.sol";
import "../contracts/ContinuousFundraisingCloneFactory.sol";
import "../contracts/TokenCloneFactory.sol";
import "../contracts/FeeSettings.sol";
import "./resources/ERC2771Helper.sol";

contract tokenTest is Test {
    using ECDSA for bytes32;

    AllowList allowList;
    FeeSettings feeSettings;
    TokenCloneFactory tokenFactory;
    ContinuousFundraising fundraisingImplementation;
    ContinuousFundraisingCloneFactory fundraisingFactory;
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
        feeSettings = new FeeSettings(
            fees,
            feeSettingsAndAllowListOwner,
            feeSettingsAndAllowListOwner,
            feeSettingsAndAllowListOwner
        );
        vm.stopPrank();

        Token tokenImplementation = new Token(trustedForwarder);
        tokenFactory = new TokenCloneFactory(address(tokenImplementation));

        fundraisingImplementation = new ContinuousFundraising(trustedForwarder);
        fundraisingFactory = new ContinuousFundraisingCloneFactory(address(fundraisingImplementation));
    }

    function testAddressPrediction(
        bytes32 _rawSalt,
        address _trustedForwarder,
        address _owner,
        address _currencyReceiver,
        uint256 _minAmountPerBuyer,
        uint256 _maxAmountPerBuyer,
        uint256 _tokenPrice,
        uint256 _maxAmountOfTokenToBeSold,
        IERC20 _currency,
        Token _token
    ) public {
        vm.assume(_trustedForwarder != address(0));
        vm.assume(_owner != address(0));
        vm.assume(address(_currency) != address(0));
        vm.assume(address(_token) != address(0));
        vm.assume(_currencyReceiver != address(0));
        vm.assume(_minAmountPerBuyer > 0);
        vm.assume(_maxAmountPerBuyer >= _minAmountPerBuyer);
        vm.assume(_tokenPrice > 0);
        vm.assume(_maxAmountOfTokenToBeSold > _maxAmountPerBuyer);

        // create new clone factory so we can use the local forwarder
        fundraisingImplementation = new ContinuousFundraising(_trustedForwarder);
        fundraisingFactory = new ContinuousFundraisingCloneFactory(address(fundraisingImplementation));

        bytes32 salt = keccak256(
            abi.encodePacked(
                _rawSalt,
                _trustedForwarder,
                _owner,
                _currencyReceiver,
                _minAmountPerBuyer,
                _maxAmountPerBuyer,
                _tokenPrice,
                _maxAmountOfTokenToBeSold,
                _currency,
                _token
            )
        );

        address expected1 = fundraisingFactory.predictCloneAddress(salt);
        address expected2 = fundraisingFactory.predictCloneAddress(
            _rawSalt,
            _trustedForwarder,
            _owner,
            _currencyReceiver,
            _minAmountPerBuyer,
            _maxAmountPerBuyer,
            _tokenPrice,
            _maxAmountOfTokenToBeSold,
            _currency,
            _token
        );
        assertEq(expected1, expected2, "address prediction with salt and params not equal");

        address actual = fundraisingFactory.createContinuousFundraisingClone(
            _rawSalt,
            _trustedForwarder,
            _owner,
            _currencyReceiver,
            _minAmountPerBuyer,
            _maxAmountPerBuyer,
            _tokenPrice,
            _maxAmountOfTokenToBeSold,
            _currency,
            _token
        );
        assertEq(expected1, actual, "address prediction failed");
    }

    function testSecondDeploymentFails(
        bytes32 _rawSalt,
        address _owner,
        address _currencyReceiver,
        uint256 _minAmountPerBuyer,
        uint256 _maxAmountPerBuyer,
        uint256 _tokenPrice,
        uint256 _maxAmountOfTokenToBeSold,
        IERC20 _currency,
        Token _token
    ) public {
        vm.assume(_owner != address(0));
        vm.assume(address(_currency) != address(0));
        vm.assume(address(_token) != address(0));
        vm.assume(_currencyReceiver != address(0));
        vm.assume(_minAmountPerBuyer > 0);
        vm.assume(_maxAmountPerBuyer >= _minAmountPerBuyer);
        vm.assume(_tokenPrice > 0);
        vm.assume(_maxAmountOfTokenToBeSold > _maxAmountPerBuyer);

        // deploy once
        fundraisingFactory.createContinuousFundraisingClone(
            _rawSalt,
            trustedForwarder,
            _owner,
            _currencyReceiver,
            _minAmountPerBuyer,
            _maxAmountPerBuyer,
            _tokenPrice,
            _maxAmountOfTokenToBeSold,
            _currency,
            _token
        );

        // deploy again
        vm.expectRevert("ERC1167: create2 failed");
        fundraisingFactory.createContinuousFundraisingClone(
            _rawSalt,
            trustedForwarder,
            _owner,
            _currencyReceiver,
            _minAmountPerBuyer,
            _maxAmountPerBuyer,
            _tokenPrice,
            _maxAmountOfTokenToBeSold,
            _currency,
            _token
        );
    }

    function testInitialization(
        bytes32 _rawSalt,
        address _trustedForwarder,
        address _owner,
        address _currencyReceiver,
        uint256 _minAmountPerBuyer,
        uint256 _maxAmountPerBuyer,
        uint256 _tokenPrice,
        uint256 _maxAmountOfTokenToBeSold,
        IERC20 _currency,
        Token _token
    ) public {
        vm.assume(_trustedForwarder != address(0));
        vm.assume(_owner != address(0));
        vm.assume(address(_currency) != address(0));
        vm.assume(address(_token) != address(0));
        vm.assume(_currencyReceiver != address(0));
        vm.assume(_minAmountPerBuyer > 0);
        vm.assume(_maxAmountPerBuyer >= _minAmountPerBuyer);
        vm.assume(_tokenPrice > 0);
        vm.assume(_maxAmountOfTokenToBeSold > _maxAmountPerBuyer);

        // create new clone factory so we can use the local forwarder
        fundraisingImplementation = new ContinuousFundraising(_trustedForwarder);
        fundraisingFactory = new ContinuousFundraisingCloneFactory(address(fundraisingImplementation));

        ContinuousFundraising raise = ContinuousFundraising(
            fundraisingFactory.createContinuousFundraisingClone(
                _rawSalt,
                _trustedForwarder,
                _owner,
                _currencyReceiver,
                _minAmountPerBuyer,
                _maxAmountPerBuyer,
                _tokenPrice,
                _maxAmountOfTokenToBeSold,
                _currency,
                _token
            )
        );

        assertTrue(raise.isTrustedForwarder(_trustedForwarder), "trustedForwarder not set");
        assertEq(raise.owner(), _owner, "owner not set");
        assertEq(raise.currencyReceiver(), _currencyReceiver, "currencyReceiver not set");
        assertEq(raise.minAmountPerBuyer(), _minAmountPerBuyer, "minAmountPerBuyer not set");
        assertEq(raise.maxAmountPerBuyer(), _maxAmountPerBuyer, "maxAmountPerBuyer not set");
        assertEq(raise.tokenPrice(), _tokenPrice, "tokenPrice not set");
        assertEq(raise.maxAmountOfTokenToBeSold(), _maxAmountOfTokenToBeSold, "maxAmountOfTokenToBeSold not set");
        assertEq(address(raise.currency()), address(_currency), "currency not set");
        assertEq(address(raise.token()), address(_token), "token not set");
    }

    /*
        pausing and unpausing
    */
    function testPausing(address _admin, address rando) public {
        vm.assume(_admin != address(0));
        vm.assume(rando != address(0));
        vm.assume(rando != _admin);

        ContinuousFundraising raise = ContinuousFundraising(
            fundraisingFactory.createContinuousFundraisingClone(
                0,
                trustedForwarder,
                _admin,
                _admin,
                1,
                2,
                3,
                4,
                IERC20(address(1)),
                Token(address(2))
            )
        );

        vm.prank(rando);
        vm.expectRevert("Ownable: caller is not the owner");
        raise.pause();

        assertFalse(raise.paused());
        vm.prank(_admin);
        raise.pause();
        assertTrue(raise.paused());

        vm.prank(rando);
        vm.expectRevert("Ownable: caller is not the owner");
        raise.unpause();

        // can't buy when paused
        vm.prank(rando);
        vm.expectRevert("Pausable: paused");
        raise.buy(1, address(this));

        vm.warp(block.timestamp + 1 days + 1);
        vm.prank(_admin);
        raise.unpause();
    }
}
