// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.13;

import "../lib/forge-std/src/Test.sol";
import "../contracts/Token.sol";
import "../contracts/FeeSettings.sol";

contract FeeSettingsTest is Test {
    event SetFeeDenominators(
        uint256 tokenFeeDenominator,
        uint256 publicFundraisingFeeDenominator,
        uint256 privateOfferFeeDenominator
    );
    event FeeCollectorsChanged(
        address indexed newTokenFeeCollector,
        address indexed newPublicFundraisingFeeCollector,
        address indexed newPrivateOfferFeeCollector
    );
    event ChangeProposed(Fees proposal);

    FeeSettings feeSettings;
    Token token;
    Token currency;

    uint256 MAX_INT = type(uint256).max;

    address public constant admin = 0x0109709eCFa91a80626FF3989D68f67f5b1dD120;
    address public constant buyer = 0x1109709ecFA91a80626ff3989D68f67F5B1Dd121;
    address public constant mintAllower = 0x2109709EcFa91a80626Ff3989d68F67F5B1Dd122;
    address public constant minter = 0x3109709ECfA91A80626fF3989D68f67F5B1Dd123;
    address public constant owner = 0x6109709EcFA91A80626FF3989d68f67F5b1dd126;
    address public constant receiver = 0x7109709eCfa91A80626Ff3989D68f67f5b1dD127;
    address public constant paymentTokenProvider = 0x8109709ecfa91a80626fF3989d68f67F5B1dD128;
    address public constant trustedForwarder = 0x9109709EcFA91A80626FF3989D68f67F5B1dD129;

    uint256 public constant price = 10000000;

    FeeFactor feeOnePercent = FeeFactor(1, 100);

    function testEnforceFeeDenominatorRangeInConstructor(uint8 fee) public {
        vm.assume(!tokenOrPrivateOfferFeeInValidRange(1, fee));
        Fees memory _fees;

        FeeFactor memory feeThreePercent = FeeFactor(3, 100);
        FeeFactor memory feeVariable = FeeFactor(1, fee);

        console.log("Testing token fee");
        _fees = Fees(feeVariable, feeThreePercent, feeOnePercent, 0);
        vm.expectRevert("Fee must be equal or less 5% (denominator must be >= 20)");
        new FeeSettings(_fees, admin, admin, admin);

        console.log("Testing PublicFundraising fee");
        _fees = Fees(feeThreePercent, feeVariable, feeOnePercent, 0);
        if (fee < 10) {
            vm.expectRevert("PublicFundraising fee must be equal or less 10% (denominator must be >= 10)");
            new FeeSettings(_fees, admin, admin, admin);
        } else {
            // this should not revert, as the fee is in valid range for public fundraising
            new FeeSettings(_fees, admin, admin, admin);
        }

        console.log("Testing PrivateOffer fee");
        _fees = Fees(feeThreePercent, feeOnePercent, feeVariable, 0);
        vm.expectRevert("Fee must be equal or less 5% (denominator must be >= 20)");
        new FeeSettings(_fees, admin, admin, admin);
    }

    function testEnforceTokenFeeDenominatorRangeInFeeChanger(uint128 fee) public {
        vm.assume(!tokenOrPrivateOfferFeeInValidRange(1, fee));
        FeeFactor memory feeFactor = FeeFactor(1, 100);
        Fees memory fees = Fees(feeFactor, feeFactor, feeFactor, 0);
        FeeSettings _feeSettings = new FeeSettings(fees, admin, admin, admin);

        Fees memory feeChange = Fees(FeeFactor(1, fee), feeOnePercent, feeOnePercent, block.timestamp + 7884001);
        vm.expectRevert("Fee must be equal or less 5% (denominator must be >= 20)");
        _feeSettings.planFeeChange(feeChange);
    }

    function testEnforcePublicFundraisingFeeDenominatorRangeInFeeChanger(uint8 fee) public {
        vm.assume(fee < 10);
        FeeFactor memory feeFactor = FeeFactor(1, 100);
        Fees memory fees = Fees(feeFactor, feeFactor, feeFactor, 0);
        FeeSettings _feeSettings = new FeeSettings(fees, admin, admin, admin);

        Fees memory feeChange = Fees(feeOnePercent, FeeFactor(1, fee), feeOnePercent, block.timestamp + 7884001);

        vm.expectRevert("PublicFundraising fee must be equal or less 10% (denominator must be >= 10)");
        _feeSettings.planFeeChange(feeChange);
    }

    function testEnforcePrivateOfferFeeDenominatorRangeInFeeChanger(uint8 fee) public {
        vm.assume(!tokenOrPrivateOfferFeeInValidRange(1, fee));
        FeeFactor memory feeFactor = FeeFactor(1, 100);
        Fees memory fees = Fees(feeFactor, feeFactor, feeFactor, 0);
        FeeSettings _feeSettings = new FeeSettings(fees, admin, admin, admin);

        Fees memory feeChange = Fees(feeOnePercent, feeOnePercent, FeeFactor(1, fee), block.timestamp + 7884001);

        vm.expectRevert("Fee must be equal or less 5% (denominator must be >= 20)");
        _feeSettings.planFeeChange(feeChange);
    }

    function testEnforceFeeChangeDelayOnIncrease(uint delay, uint128 startDenominator, uint128 newDenominator) public {
        vm.assume(delay <= 12 weeks);
        vm.assume(startDenominator >= 20 && newDenominator >= 20);
        vm.assume(newDenominator < startDenominator);
        FeeFactor memory startFactor = FeeFactor(1, startDenominator);
        FeeFactor memory newFactor = FeeFactor(1, newDenominator);
        Fees memory fees = Fees(startFactor, startFactor, startFactor, 0);
        vm.prank(admin);
        FeeSettings _feeSettings = new FeeSettings(fees, admin, admin, admin);

        Fees memory feeChange = Fees(newFactor, startFactor, startFactor, block.timestamp + delay);
        vm.prank(admin);
        vm.expectRevert("Fee change must be at least 12 weeks in the future");
        _feeSettings.planFeeChange(feeChange);

        feeChange = Fees(startFactor, newFactor, startFactor, block.timestamp + delay);

        vm.prank(admin);
        vm.expectRevert("Fee change must be at least 12 weeks in the future");
        _feeSettings.planFeeChange(feeChange);

        feeChange = Fees(startFactor, startFactor, newFactor, block.timestamp + delay);
        vm.prank(admin);
        vm.expectRevert("Fee change must be at least 12 weeks in the future");
        _feeSettings.planFeeChange(feeChange);
    }

    function testExecuteFeeChangeTooEarly(uint delayAnnounced, uint128 tokenFee, uint128 investmentFee) public {
        vm.assume(delayAnnounced > 12 weeks && delayAnnounced < 1000000000000);
        vm.assume(tokenOrPrivateOfferFeeInValidRange(1, tokenFee));
        vm.assume(tokenOrPrivateOfferFeeInValidRange(1, investmentFee));

        FeeFactor memory feeFactor = FeeFactor(1, 50);
        Fees memory fees = Fees(feeFactor, feeFactor, feeFactor, 0);
        vm.prank(admin);
        FeeSettings _feeSettings = new FeeSettings(fees, admin, admin, admin);

        Fees memory feeChange = Fees(
            FeeFactor(1, tokenFee),
            FeeFactor(1, investmentFee),
            FeeFactor(1, 100),
            block.timestamp + delayAnnounced
        );
        vm.prank(admin);
        _feeSettings.planFeeChange(feeChange);

        vm.prank(admin);
        vm.expectRevert("Fee change must be executed after the change time");
        vm.warp(block.timestamp + delayAnnounced - 1);
        _feeSettings.executeFeeChange();
    }

    function testExecuteFeeChangeProperly(
        uint delayAnnounced,
        uint128 tokenFee,
        uint128 fundraisingFee,
        uint128 privateOfferFee
    ) public {
        vm.assume(delayAnnounced > 12 weeks && delayAnnounced < 100000000000);
        vm.assume(tokenOrPrivateOfferFeeInValidRange(1, tokenFee));
        vm.assume(tokenOrPrivateOfferFeeInValidRange(1, fundraisingFee));
        vm.assume(tokenOrPrivateOfferFeeInValidRange(1, privateOfferFee));
        FeeFactor memory feeFactor = FeeFactor(1, 50);
        Fees memory fees = Fees(feeFactor, feeFactor, feeFactor, 0);
        vm.prank(admin);
        FeeSettings _feeSettings = new FeeSettings(fees, admin, admin, admin);

        Fees memory feeChange = Fees(
            FeeFactor(1, tokenFee),
            FeeFactor(1, fundraisingFee),
            FeeFactor(1, privateOfferFee),
            block.timestamp + delayAnnounced
        );

        vm.prank(admin);
        vm.expectEmit(true, true, true, true, address(_feeSettings));
        emit ChangeProposed(feeChange);
        _feeSettings.planFeeChange(feeChange);

        vm.prank(admin);
        vm.warp(block.timestamp + delayAnnounced + 1);
        vm.expectEmit(true, true, true, true, address(_feeSettings));
        emit SetFeeDenominators(tokenFee, fundraisingFee, privateOfferFee);
        _feeSettings.executeFeeChange();

        (, uint128 currentTokenFeeDenominator) = _feeSettings.tokenFeeFactor();
        assertEq(currentTokenFeeDenominator, tokenFee);
        (, uint128 currentPublicFundraisingFeeDenominator) = _feeSettings.publicFundraisingFeeFactor();
        assertEq(currentPublicFundraisingFeeDenominator, fundraisingFee);
        (, uint128 currentPrivateOfferFeeDenominator) = _feeSettings.privateOfferFeeFactor();
        assertEq(currentPrivateOfferFeeDenominator, privateOfferFee);
    }

    function testSetFeeTo0Immediately() public {
        Fees memory fees = Fees(FeeFactor(1, 50), FeeFactor(1, 20), FeeFactor(1, 30), 0);
        vm.prank(admin);
        FeeSettings _feeSettings = new FeeSettings(fees, admin, admin, admin);

        Fees memory feeChange = Fees(FeeFactor(0, 1), FeeFactor(0, 1), FeeFactor(0, 1), 0);
        (uint128 numerator, uint128 denominator) = _feeSettings.tokenFeeFactor();
        assertEq(numerator, 1, "Token fee numerator mismatch");
        assertEq(denominator, 50, "Token fee denominator mismatch");
        (numerator, denominator) = _feeSettings.publicFundraisingFeeFactor();
        assertEq(numerator, 1, "Public fundraising fee numerator mismatch");
        assertEq(denominator, 20, "Public fundraising fee denominator mismatch");
        (numerator, denominator) = _feeSettings.privateOfferFeeFactor();
        assertEq(numerator, 1, "Private offer fee numerator mismatch");
        assertEq(denominator, 30, "Private offer fee denominator mismatch");

        vm.prank(admin);
        _feeSettings.planFeeChange(feeChange);

        vm.prank(admin);
        //vm.warp(block.timestamp + delayAnnounced + 1);
        _feeSettings.executeFeeChange();

        (numerator, denominator) = _feeSettings.tokenFeeFactor();
        assertEq(numerator, 0, "Token fee numerator mismatch");
        assertEq(denominator, 1, "Token fee denominator mismatch");
        (numerator, denominator) = _feeSettings.publicFundraisingFeeFactor();
        assertEq(numerator, 0, "Public fundraising fee numerator mismatch");
        assertEq(denominator, 1, "Public fundraising fee denominator mismatch");
        (numerator, denominator) = _feeSettings.privateOfferFeeFactor();
        assertEq(numerator, 0, "Private offer fee numerator mismatch");
        assertEq(denominator, 1, "Private offer fee denominator mismatch");
    }

    function testSetFeeToXFrom0Immediately() public {
        Fees memory fees = Fees(FeeFactor(0, 1), FeeFactor(0, 1), FeeFactor(0, 1), 0);

        vm.prank(admin);
        FeeSettings _feeSettings = new FeeSettings(fees, admin, admin, admin);

        Fees memory feeChange = Fees(FeeFactor(1, 50), FeeFactor(1, 20), FeeFactor(1, 30), 0);

        (uint128 numerator, uint128 denominator) = _feeSettings.tokenFeeFactor();
        assertEq(numerator, 0, "Token fee numerator mismatch");
        assertEq(denominator, 1, "Token fee denominator mismatch");
        (numerator, denominator) = _feeSettings.publicFundraisingFeeFactor();
        assertEq(numerator, 0, "Public fundraising fee numerator mismatch");
        assertEq(denominator, 1, "Public fundraising fee denominator mismatch");
        (numerator, denominator) = _feeSettings.privateOfferFeeFactor();
        assertEq(numerator, 0, "Private offer fee numerator mismatch");
        assertEq(denominator, 1, "Private offer fee denominator mismatch");

        vm.prank(admin);
        vm.expectRevert("Fee change must be at least 12 weeks in the future");
        _feeSettings.planFeeChange(feeChange);
    }

    function testReduceFeeImmediately(
        uint128 tokenReductor,
        uint128 continuousReductor,
        uint128 personalReductor
    ) public {
        vm.assume(tokenReductor >= 50);
        vm.assume(continuousReductor >= 20);
        vm.assume(personalReductor >= 30);
        Fees memory fees = Fees(FeeFactor(1, 50), FeeFactor(1, 20), FeeFactor(1, 30), 0);
        vm.prank(admin);
        FeeSettings _feeSettings = new FeeSettings(fees, admin, admin, admin);

        Fees memory feeChange = Fees(
            FeeFactor(1, tokenReductor),
            FeeFactor(1, continuousReductor),
            FeeFactor(1, personalReductor),
            0
        );

        (uint128 numerator, uint128 denominator) = _feeSettings.tokenFeeFactor();
        assertEq(numerator, 1, "Token fee numerator mismatch");
        assertEq(denominator, 50, "Token fee denominator mismatch");
        (numerator, denominator) = _feeSettings.publicFundraisingFeeFactor();
        assertEq(numerator, 1, "Public fundraising fee numerator mismatch");
        assertEq(denominator, 20, "Public fundraising fee denominator mismatch");
        (numerator, denominator) = _feeSettings.privateOfferFeeFactor();
        assertEq(numerator, 1, "Private offer fee numerator mismatch");
        assertEq(denominator, 30, "Private offer fee denominator mismatch");

        vm.prank(admin);
        _feeSettings.planFeeChange(feeChange);

        vm.prank(admin);
        //vm.warp(block.timestamp + delayAnnounced + 1);
        _feeSettings.executeFeeChange();

        (numerator, denominator) = _feeSettings.tokenFeeFactor();
        assertEq(numerator, 1, "Token fee numerator mismatch");
        assertEq(denominator, tokenReductor, "Token fee denominator mismatch");
        (numerator, denominator) = _feeSettings.publicFundraisingFeeFactor();
        assertEq(numerator, 1, "Public fundraising fee numerator mismatch");
        assertEq(denominator, continuousReductor, "Public fundraising fee denominator mismatch");
        (numerator, denominator) = _feeSettings.privateOfferFeeFactor();
        assertEq(numerator, 1, "Private offer fee numerator mismatch");
        assertEq(denominator, personalReductor, "Private offer fee denominator mismatch");
    }

    function testSetFeeInConstructor(
        uint128 tokenNumerator,
        uint128 tokenDenominator,
        uint128 publicNumerator,
        uint128 publicDenominator,
        uint128 privateNumerator,
        uint128 privateDenominator
    ) public {
        vm.assume(tokenOrPrivateOfferFeeInValidRange(tokenNumerator, tokenDenominator));
        vm.assume(tokenOrPrivateOfferFeeInValidRange(publicNumerator, publicDenominator));
        vm.assume(tokenOrPrivateOfferFeeInValidRange(privateNumerator, privateDenominator));

        FeeSettings _feeSettings;
        Fees memory fees = Fees(
            FeeFactor(tokenNumerator, tokenDenominator),
            FeeFactor(publicNumerator, publicDenominator),
            FeeFactor(privateNumerator, privateDenominator),
            0
        );
        _feeSettings = new FeeSettings(fees, admin, admin, admin);
        (uint128 numerator, uint128 denominator) = _feeSettings.tokenFeeFactor();
        assertEq(numerator, tokenNumerator, "Token fee numerator mismatch");
        assertEq(denominator, tokenDenominator, "Token fee denominator mismatch");
        (numerator, denominator) = _feeSettings.publicFundraisingFeeFactor();
        assertEq(numerator, publicNumerator, "Public fundraising fee numerator mismatch");
        assertEq(denominator, publicDenominator, "Public fundraising fee denominator mismatch");
        (numerator, denominator) = _feeSettings.privateOfferFeeFactor();
        assertEq(numerator, privateNumerator, "Private offer fee numerator mismatch");
        assertEq(denominator, privateDenominator, "Private offer fee denominator mismatch");
    }

    function testFeeCollector0FailsInConstructor() public {
        vm.expectRevert("Fee collector cannot be 0x0");
        FeeSettings _feeSettings;
        FeeFactor memory feeFactor = FeeFactor(1, 100);
        Fees memory fees = Fees(feeFactor, feeFactor, feeFactor, 0);
        _feeSettings = new FeeSettings(fees, address(0), address(0), address(0));
    }

    function testFeeCollector0FailsInSetter() public {
        FeeSettings _feeSettings;
        FeeFactor memory feeFactor = FeeFactor(1, 100);
        Fees memory fees = Fees(feeFactor, feeFactor, feeFactor, 0);
        vm.prank(admin);
        _feeSettings = new FeeSettings(fees, admin, admin, admin);
        vm.expectRevert("Fee collector cannot be 0x0");
        vm.prank(admin);
        _feeSettings.setFeeCollectors(address(0), address(1), address(2));
        vm.expectRevert("Fee collector cannot be 0x0");
        vm.prank(admin);
        _feeSettings.setFeeCollectors(address(2), address(0), address(1));
        vm.expectRevert("Fee collector cannot be 0x0");
        vm.prank(admin);
        _feeSettings.setFeeCollectors(address(1), address(2), address(0));
    }

    function testUpdateFeeCollectors(
        address newTokenFeeCollector,
        address newPublicFundraisingFeeCollector,
        address newPrivateOfferFeeCollector
    ) public {
        vm.assume(newTokenFeeCollector != address(0));
        vm.assume(newPublicFundraisingFeeCollector != address(0));
        vm.assume(newPrivateOfferFeeCollector != address(0));
        FeeSettings _feeSettings;
        FeeFactor memory feeFactor = FeeFactor(1, 100);
        Fees memory fees = Fees(feeFactor, feeFactor, feeFactor, 0);
        vm.prank(admin);
        _feeSettings = new FeeSettings(fees, admin, admin, admin);
        vm.expectEmit(true, true, true, true, address(_feeSettings));
        emit FeeCollectorsChanged(newTokenFeeCollector, newPublicFundraisingFeeCollector, newPrivateOfferFeeCollector);
        vm.prank(admin);
        _feeSettings.setFeeCollectors(
            newTokenFeeCollector,
            newPublicFundraisingFeeCollector,
            newPrivateOfferFeeCollector
        );
        assertEq(_feeSettings.feeCollector(), newTokenFeeCollector); // IFeeSettingsV1
        assertEq(_feeSettings.tokenFeeCollector(), newTokenFeeCollector);
        assertEq(_feeSettings.publicFundraisingFeeCollector(), newPublicFundraisingFeeCollector);
        assertEq(_feeSettings.privateOfferFeeCollector(), newPrivateOfferFeeCollector);
    }

    function tokenOrPrivateOfferFeeInValidRange(uint128 numerator, uint128 denominator) internal pure returns (bool) {
        return denominator / numerator >= 20;
    }

    function testCalculateProperFees(
        uint128 tokenFeeDenominator,
        uint128 publicFundraisingFeeDenominator,
        uint128 privateOfferFeeDenominator,
        uint256 amount
    ) public {
        vm.assume(tokenFeeDenominator >= 20 && tokenFeeDenominator < UINT256_MAX);
        vm.assume(publicFundraisingFeeDenominator >= 20 && publicFundraisingFeeDenominator < UINT256_MAX);
        vm.assume(privateOfferFeeDenominator >= 20 && privateOfferFeeDenominator < UINT256_MAX);

        Fees memory _fees = Fees(
            FeeFactor(1, tokenFeeDenominator),
            FeeFactor(1, publicFundraisingFeeDenominator),
            FeeFactor(1, privateOfferFeeDenominator),
            0
        );
        FeeSettings _feeSettings = new FeeSettings(_fees, admin, admin, admin);

        assertEq(_feeSettings.tokenFee(amount), amount / tokenFeeDenominator, "Token fee mismatch");
        assertEq(
            _feeSettings.publicFundraisingFee(amount),
            amount / publicFundraisingFeeDenominator,
            "Investment fee mismatch"
        );
        assertEq(
            _feeSettings.privateOfferFee(amount),
            amount / privateOfferFeeDenominator,
            "Private offer fee mismatch"
        );
    }

    function testCalculate0FeesForAmountLessThanUINT256_MAX(
        uint128 tokenFeeDenominator,
        uint128 publicFundraisingFeeDenominator,
        uint128 privateOfferFeeDenominator,
        uint256 amount
    ) public {
        vm.assume(tokenFeeDenominator >= 20 && tokenFeeDenominator < UINT256_MAX);
        vm.assume(publicFundraisingFeeDenominator >= 20 && publicFundraisingFeeDenominator < UINT256_MAX);
        vm.assume(privateOfferFeeDenominator >= 20 && privateOfferFeeDenominator < UINT256_MAX);
        vm.assume(amount < UINT256_MAX);

        // only token fee is 0

        Fees memory _fees = Fees(
            FeeFactor(0, 1),
            FeeFactor(1, publicFundraisingFeeDenominator),
            FeeFactor(1, privateOfferFeeDenominator),
            0
        );
        FeeSettings _feeSettings = new FeeSettings(_fees, admin, admin, admin);

        assertEq(_feeSettings.tokenFee(amount), 0, "Token fee mismatch");
        assertEq(
            _feeSettings.publicFundraisingFee(amount),
            amount / publicFundraisingFeeDenominator,
            "Investment fee mismatch"
        );
        assertEq(
            _feeSettings.privateOfferFee(amount),
            amount / privateOfferFeeDenominator,
            "Private offer fee mismatch"
        );

        // only public fundraising fee is 0

        _fees = Fees(FeeFactor(1, tokenFeeDenominator), FeeFactor(0, 1), FeeFactor(1, privateOfferFeeDenominator), 0);
        _feeSettings = new FeeSettings(_fees, admin, admin, admin);

        assertEq(_feeSettings.tokenFee(amount), amount / tokenFeeDenominator, "Token fee mismatch");
        assertEq(_feeSettings.publicFundraisingFee(amount), 0, "Investment fee mismatch");
        assertEq(
            _feeSettings.privateOfferFee(amount),
            amount / privateOfferFeeDenominator,
            "Private offer fee mismatch"
        );

        // only private offer fee is 0

        _fees = Fees(
            FeeFactor(1, tokenFeeDenominator),
            FeeFactor(1, publicFundraisingFeeDenominator),
            FeeFactor(0, 1),
            0
        );
        _feeSettings = new FeeSettings(_fees, admin, admin, admin);

        assertEq(_feeSettings.tokenFee(amount), amount / tokenFeeDenominator, "Token fee mismatch");
        assertEq(
            _feeSettings.publicFundraisingFee(amount),
            amount / publicFundraisingFeeDenominator,
            "Investment fee mismatch"
        );
        assertEq(_feeSettings.privateOfferFee(amount), 0, "Private offer fee mismatch");
    }

    function testERC165IsAvailable() public {
        FeeSettings _feeSettings;
        FeeFactor memory feeFactor = FeeFactor(1, 100);
        Fees memory fees = Fees(feeFactor, feeFactor, feeFactor, 0);
        _feeSettings = new FeeSettings(fees, admin, admin, admin);
        assertEq(
            _feeSettings.supportsInterface(0x01ffc9a7), // type(IERC165).interfaceId
            true,
            "ERC165 not supported"
        );
    }

    function testIFeeSettingsV1IsAvailable() public {
        FeeSettings _feeSettings;
        FeeFactor memory feeFactor = FeeFactor(1, 100);
        Fees memory fees = Fees(feeFactor, feeFactor, feeFactor, 0);
        _feeSettings = new FeeSettings(fees, admin, admin, admin);

        assertEq(
            _feeSettings.supportsInterface(type(IFeeSettingsV1).interfaceId),
            true,
            "IFeeSettingsV1 not supported"
        );
    }

    function testIFeeSettingsV2IsAvailable() public {
        FeeSettings _feeSettings;
        FeeFactor memory feeFactor = FeeFactor(1, 100);
        Fees memory fees = Fees(feeFactor, feeFactor, feeFactor, 0);
        _feeSettings = new FeeSettings(fees, admin, admin, admin);

        assertEq(
            _feeSettings.supportsInterface(type(IFeeSettingsV2).interfaceId),
            true,
            "IFeeSettingsV1 not supported"
        );
    }

    function testNonsenseInterfacesAreNotAvailable(bytes4 _nonsenseInterface) public {
        vm.assume(_nonsenseInterface != type(IFeeSettingsV1).interfaceId);
        vm.assume(_nonsenseInterface != type(IFeeSettingsV2).interfaceId);
        vm.assume(_nonsenseInterface != 0x01ffc9a7);
        FeeSettings _feeSettings;
        FeeFactor memory feeFactor = FeeFactor(1, 100);
        Fees memory fees = Fees(feeFactor, feeFactor, feeFactor, 0);
        _feeSettings = new FeeSettings(fees, admin, admin, admin);

        assertEq(_feeSettings.supportsInterface(0x01ffc9b7), false, "This interface should not be supported");
    }

    /**
     * @dev the fee calculation is implemented to accept a wrong result in one case:
     *      if denominator is UINT256_MAX and amount is UINT256_MAX, the result will be 1 instead of 0
     */
    function testCalculate0FeesForAmountUINT256_MAX(
        uint128 tokenFeeDenominator,
        uint128 publicFundraisingFeeDenominator,
        uint128 privateOfferFeeDenominator
    ) public {
        vm.assume(tokenFeeDenominator >= 20 && tokenFeeDenominator < UINT256_MAX);
        vm.assume(publicFundraisingFeeDenominator >= 20 && publicFundraisingFeeDenominator < UINT256_MAX);
        vm.assume(privateOfferFeeDenominator >= 20 && privateOfferFeeDenominator < UINT256_MAX);
        uint256 amount = UINT256_MAX;

        // only token fee is 0

        Fees memory _fees = Fees(
            FeeFactor(0, 1),
            FeeFactor(1, publicFundraisingFeeDenominator),
            FeeFactor(1, privateOfferFeeDenominator),
            0
        );
        FeeSettings _feeSettings = new FeeSettings(_fees, admin, admin, admin);

        assertEq(_feeSettings.tokenFee(amount), 1, "Token fee mismatch");
        assertEq(
            _feeSettings.publicFundraisingFee(amount),
            amount / publicFundraisingFeeDenominator,
            "Investment fee mismatch"
        );
        assertEq(
            _feeSettings.privateOfferFee(amount),
            amount / privateOfferFeeDenominator,
            "Private offer fee mismatch"
        );

        // only public fundraising fee is 0

        _fees = Fees(FeeFactor(1, tokenFeeDenominator), FeeFactor(0, 1), FeeFactor(1, privateOfferFeeDenominator), 0);
        _feeSettings = new FeeSettings(_fees, admin, admin, admin);

        assertEq(_feeSettings.tokenFee(amount), amount / tokenFeeDenominator, "Token fee mismatch");
        assertEq(_feeSettings.publicFundraisingFee(amount), 1, "Investment fee mismatch");
        assertEq(
            _feeSettings.privateOfferFee(amount),
            amount / privateOfferFeeDenominator,
            "Private offer fee mismatch"
        );

        // only private offer fee is 0

        _fees = Fees(
            FeeFactor(1, tokenFeeDenominator),
            FeeFactor(1, publicFundraisingFeeDenominator),
            FeeFactor(0, 1),
            0
        );
        _feeSettings = new FeeSettings(_fees, admin, admin, admin);

        assertEq(_feeSettings.tokenFee(amount), amount / tokenFeeDenominator, "Token fee mismatch");
        assertEq(
            _feeSettings.publicFundraisingFee(amount),
            amount / publicFundraisingFeeDenominator,
            "Investment fee mismatch"
        );
        assertEq(_feeSettings.privateOfferFee(amount), 1, "Private offer fee mismatch");
    }
}
