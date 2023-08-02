// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.13;

import "../lib/forge-std/src/Test.sol";
import "../contracts/ContinuousFundraisingCloneFactory.sol";
import "../contracts/FeeSettings.sol";
import "./resources/FakePaymentToken.sol";
import "./resources/MaliciousPaymentToken.sol";

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
    address public constant feeSettingsAndAllowListadmin = 0x8109709ecfa91a80626fF3989d68f67F5B1dD128;

    uint256 requirements = 0;

    event RequirementsChanged(uint256 newRequirements);

    function setUp() public {
        vm.startPrank(feeSettingsAndAllowListadmin);
        allowList = new AllowList();
        Fees memory fees = Fees(100, 100, 100, 0);
        feeSettings = new FeeSettings(fees, feeSettingsAndAllowListadmin);
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
        bytes32 _salt,
        address _admin,
        address _currencyReceiver,
        uint256 _minAmountPerBuyer,
        uint256 _maxAmountPerBuyer,
        uint256 _tokenPrice,
        uint256 _maxAmountOfTokenToBeSold,
        address _currency,
        address _token
    ) public {
        vm.assume(_admin != address(0));
        vm.assume(_currencyReceiver != address(0));
        vm.assume(_minAmountPerBuyer < _maxAmountPerBuyer);
        vm.assume(_tokenPrice > 0);
        vm.assume(_maxAmountOfTokenToBeSold > _minAmountPerBuyer);
        vm.assume(_maxAmountOfTokenToBeSold > 0);
        vm.assume(_currency != address(0));
        vm.assume(_token != address(0));

        ContinuousFundraising clone = ContinuousFundraising(
            cloneFactory.createContinuousFundraisingClone(
                _salt,
                _admin,
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
        assertEq(clone.owner(), _admin, "admin not set");
        assertEq(clone.currencyReceiver(), _currencyReceiver, "currencyReceiver not set");
        assertEq(clone.minAmountPerBuyer(), _minAmountPerBuyer, "minAmountPerBuyer not set");
        assertEq(clone.maxAmountPerBuyer(), _maxAmountPerBuyer, "maxAmountPerBuyer not set");
        assertEq(clone.tokenPrice(), _tokenPrice, "tokenPrice not set");
        assertEq(clone.maxAmountOfTokenToBeSold(), _maxAmountOfTokenToBeSold, "maxAmountOfTokenToBeSold not set");
        assertEq(address(clone.currency()), _currency, "currency not set");
        assertEq(address(clone.token()), _token, "token not set");

        // check that the clone uses the same trustedForwarder as the implementation
        assertTrue(clone.isTrustedForwarder(trustedForwarder), "trustedForwarder is wrong");
    }

    function testAddress0Revert(
        bytes32 _salt,
        address _admin,
        address _currencyReceiver,
        uint256 _minAmountPerBuyer,
        uint256 _maxAmountPerBuyer,
        uint256 _tokenPrice,
        uint256 _maxAmountOfTokenToBeSold,
        address _currency,
        address _token
    ) public {
        vm.assume(_admin != address(0));
        vm.assume(_currencyReceiver != address(0));
        vm.assume(_minAmountPerBuyer < _maxAmountPerBuyer);
        vm.assume(_tokenPrice > 0);
        vm.assume(_maxAmountOfTokenToBeSold > _minAmountPerBuyer);
        vm.assume(_maxAmountOfTokenToBeSold > 0);
        vm.assume(_currency != address(0));
        vm.assume(_token != address(0));

        vm.expectRevert("admin can not be zero address");
        cloneFactory.createContinuousFundraisingClone(
            _salt,
            address(0),
            _currencyReceiver,
            _minAmountPerBuyer,
            _maxAmountPerBuyer,
            _tokenPrice,
            _maxAmountOfTokenToBeSold,
            IERC20(_currency),
            Token(_token)
        );

        vm.expectRevert("currencyReceiver can not be zero address");
        cloneFactory.createContinuousFundraisingClone(
            _salt,
            _admin,
            address(0),
            _minAmountPerBuyer,
            _maxAmountPerBuyer,
            _tokenPrice,
            _maxAmountOfTokenToBeSold,
            IERC20(_currency),
            Token(_token)
        );

        vm.expectRevert("currency can not be zero address");
        cloneFactory.createContinuousFundraisingClone(
            _salt,
            _admin,
            _currencyReceiver,
            _minAmountPerBuyer,
            _maxAmountPerBuyer,
            _tokenPrice,
            _maxAmountOfTokenToBeSold,
            IERC20(address(0)),
            Token(_token)
        );

        vm.expectRevert("token can not be zero address");
        cloneFactory.createContinuousFundraisingClone(
            _salt,
            _admin,
            _currencyReceiver,
            _minAmountPerBuyer,
            _maxAmountPerBuyer,
            _tokenPrice,
            _maxAmountOfTokenToBeSold,
            IERC20(_currency),
            Token(address(0))
        );
    }

    function testWrongNumbersRevert(
        bytes32 _salt,
        address _admin,
        address _currencyReceiver,
        uint256 _minAmountPerBuyer,
        uint256 _maxAmountPerBuyer,
        uint256 _tokenPrice,
        uint256 _maxAmountOfTokenToBeSold,
        address _currency,
        address _token
    ) public {
        vm.assume(_admin != address(0));
        vm.assume(_currencyReceiver != address(0));
        vm.assume(_minAmountPerBuyer < _maxAmountPerBuyer);
        vm.assume(_tokenPrice > 0);
        vm.assume(_maxAmountOfTokenToBeSold > _minAmountPerBuyer);
        vm.assume(_maxAmountOfTokenToBeSold > 0);
        vm.assume(_currency != address(0));
        vm.assume(_token != address(0));

        vm.expectRevert("_minAmountPerBuyer needs to be smaller or equal to _maxAmountPerBuyer");
        cloneFactory.createContinuousFundraisingClone(
            _salt,
            _admin,
            _currencyReceiver,
            _minAmountPerBuyer + 1,
            _minAmountPerBuyer,
            _tokenPrice,
            _maxAmountOfTokenToBeSold,
            IERC20(_currency),
            Token(_token)
        );

        vm.expectRevert("_tokenPrice needs to be a non-zero amount");
        cloneFactory.createContinuousFundraisingClone(
            _salt,
            _admin,
            _currencyReceiver,
            _minAmountPerBuyer,
            _maxAmountPerBuyer,
            0,
            _maxAmountOfTokenToBeSold,
            IERC20(_currency),
            Token(_token)
        );

        vm.expectRevert("_maxAmountOfTokenToBeSold needs to be larger than zero");
        cloneFactory.createContinuousFundraisingClone(
            _salt,
            _admin,
            _currencyReceiver,
            _minAmountPerBuyer,
            _maxAmountPerBuyer,
            _tokenPrice,
            0,
            IERC20(_currency),
            Token(_token)
        );
    }

    /*
    set up with MaliciousPaymentToken which tries to reenter the buy function
    */
    function testCloneIsProtectedFromReentrancy() public {
        MaliciousPaymentToken _paymentToken;
        uint8 _paymentTokenDecimals = 18;
        address buyer = pauser;

        /*
        _paymentToken: 1 FPT = 10**_paymentTokenDecimals FPTbits (bit = smallest subunit of token)
        Token: 1 CT = 10**18 CTbits
        price definition: 30FPT buy 1CT, but must be expressed in FPTbits/CT
        price = 30 * 10**_paymentTokenDecimals
        */

        uint256 _price = 7 * 10 ** _paymentTokenDecimals;
        uint256 _maxMintAmount = 1000 * 10 ** 18; // 2**256 - 1; // need maximum possible value because we are using a fake token with variable decimals
        uint256 _paymentTokenAmount = 100000 * 10 ** _paymentTokenDecimals;

        AllowList list = new AllowList();
        Token _token = new Token(trustedForwarder, feeSettings, admin, list, 0x0, "TESTTOKEN", "TEST");

        _paymentToken = new MaliciousPaymentToken(_paymentTokenAmount);

        vm.prank(admin);
        ContinuousFundraising _raise = ContinuousFundraising(
            cloneFactory.createContinuousFundraisingClone(
                0,
                admin,
                admin,
                1,
                _maxMintAmount / 100,
                _price,
                _maxMintAmount,
                _paymentToken,
                _token
            )
        );

        // allow invite contract to mint
        bytes32 roleMintAllower = _token.MINTALLOWER_ROLE();

        vm.prank(admin);
        _token.grantRole(roleMintAllower, mintAllower);
        vm.startPrank(mintAllower);
        _token.increaseMintingAllowance(address(_raise), _maxMintAmount - _token.mintingAllowance(address(_raise)));
        vm.stopPrank();

        // mint _paymentToken for buyer

        _paymentToken.transfer(buyer, _paymentTokenAmount);
        assertTrue(_paymentToken.balanceOf(buyer) == _paymentTokenAmount);

        // set exploitTarget
        _paymentToken.setExploitTarget(address(_raise), 3, _maxMintAmount / 200000);

        // give invite contract allowance
        vm.prank(buyer);
        _paymentToken.approve(address(_raise), _paymentTokenAmount);

        // store some state
        //uint buyerPaymentBalanceBefore = _paymentToken.balanceOf(buyer);

        // run actual test
        assertTrue(_paymentToken.balanceOf(buyer) == _paymentTokenAmount);
        uint256 buyAmount = _maxMintAmount / 100000;
        vm.prank(buyer);
        vm.expectRevert("ReentrancyGuard: reentrant call");
        _raise.buy(buyAmount, buyer);
    }

    /*
        pausing and unpausing
    */
    function testPausing(address rando) public {
        vm.assume(rando != address(0));
        vm.assume(rando != admin);
        ContinuousFundraising _raise = ContinuousFundraising(
            cloneFactory.createContinuousFundraisingClone(
                0,
                admin,
                admin,
                1,
                1000,
                100,
                1000,
                IERC20(address(5)),
                Token(address(7))
            )
        );

        vm.prank(rando);
        vm.expectRevert("Ownable: caller is not the owner");
        _raise.pause();

        vm.prank(rando);
        vm.expectRevert("Ownable: caller is not the owner");
        _raise.unpause();

        assertFalse(_raise.paused());
        vm.prank(admin);
        _raise.pause();
        assertTrue(_raise.paused());

        vm.expectRevert("There needs to be at minimum one day to change parameters");
        vm.prank(admin);
        _raise.unpause();

        vm.warp(block.timestamp + 1 days + 1);
        vm.prank(admin);
        _raise.unpause();
        assertFalse(_raise.paused());
    }
}
