// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.13;

import "../lib/forge-std/src/Test.sol";
import "../contracts/Token.sol";
import "../contracts/FeeSettings.sol";

contract FeeSettingsTest is Test {
    event SetFee(
        uint32 tokenFeeNumerator,
        uint32 tokenFeeDenominator,
        uint32 publicFundraisingFeeNumerator,
        uint32 publicFundraisingFeeDenominator,
        uint32 privateOfferFeeNumerator,
        uint32 privateOfferFeeDenominator
    );
    event FeeCollectorChanged(address indexed newFeeCollector);
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

    function testEnforceFeeRangeInConstructor(uint8 fee) public {
        vm.assume(!tokenOrPersonalInviteFeeInValidRange(fee));
        Fees memory _fees;

        console.log("Testing token fee");
        _fees = Fees(1, fee, 1, 30, 1, 100, 0);
        vm.expectRevert("Fee must be equal or less 5% (denominator must be >= 20)");
        new FeeSettings(_fees, admin);

        console.log("Testing PublicFundraising fee");
        _fees = Fees(1, 30, 1, fee, 1, 100, 0);
        if (fee < 10) {
            vm.expectRevert("ContinuousFundraising fee must be equal or less 10%");
            new FeeSettings(_fees, admin);
        } else {
            // this should not revert, as the fee is in valid range for continuous fundraising
            new FeeSettings(_fees, admin);
        }

        console.log("Testing PrivateOffer fee");
        _fees = Fees(1, 30, 1, 40, 1, fee, 0);
        vm.expectRevert("Fee must be equal or less 5% (denominator must be >= 20)");
        new FeeSettings(_fees, admin);
    }

    function testEnforceTokenFeeRangeInFeeChanger(uint8 fee) public {
        vm.assume(!tokenOrPrivateOfferFeeInValidRange(fee));
        Fees memory fees = Fees(1, 100, 1, 100, 1, 100, 0);
        FeeSettings _feeSettings = new FeeSettings(fees, admin, admin, admin);

        Fees memory feeChange = Fees(1, fee, 1, 100, 1, 100, uint64(block.timestamp + 7884001));
        vm.expectRevert("Fee must be equal or less 5%");
        _feeSettings.planFeeChange(feeChange);
    }

    function testEnforceContinuousFundraisingFeeRangeInFeeChanger(uint8 fee) public {
        vm.assume(fee < 10);
        Fees memory fees = Fees(1, 100, 1, 100, 1, 100, 0);
        FeeSettings _feeSettings = new FeeSettings(fees, admin, admin, admin);

        Fees memory feeChange = Fees(1, 100, 1, fee, 1, 100, uint64(block.timestamp + 7884001));
        vm.expectRevert("PublicFundraising fee must be equal or less 10%");
        _feeSettings.planFeeChange(feeChange);
    }

    function testEnforcePrivateOfferFeeRangeInFeeChanger(uint8 fee) public {
        vm.assume(!tokenOrPrivateOfferFeeInValidRange(fee));
        Fees memory fees = Fees(1, 100, 1, 100, 1, 100, 0);
        FeeSettings _feeSettings = new FeeSettings(fees, admin, admin, admin);

        Fees memory feeChange = Fees(1, 100, 1, 100, 1, fee, uint64(block.timestamp + 7884001));
        vm.expectRevert("Fee must be equal or less 5%");
        _feeSettings.planFeeChange(feeChange);
    }

    function testEnforceFeeChangeDelayOnIncrease(uint delay, uint32 startDenominator, uint32 newDenominator) public {
        vm.assume(delay <= 12 weeks);
        vm.assume(startDenominator >= 20 && newDenominator >= 20);
        vm.assume(newDenominator < startDenominator);
        Fees memory fees = Fees(1, startDenominator, 1, startDenominator, 1, startDenominator, 0);
        vm.prank(admin);
        FeeSettings _feeSettings = new FeeSettings(fees, admin);

        Fees memory feeChange = Fees(1, newDenominator, 0, 1, 0, 1, uint64(block.timestamp + delay));
        vm.prank(admin);
        vm.expectRevert("Fee change must be at least 12 weeks in the future");
        _feeSettings.planFeeChange(feeChange);

        feeChange = Fees(0, 1, 1, newDenominator, 0, 1, uint64(block.timestamp + delay));
        vm.prank(admin);
        vm.expectRevert("Fee change must be at least 12 weeks in the future");
        _feeSettings.planFeeChange(feeChange);

        feeChange = Fees(0, 1, 0, 1, 1, newDenominator, uint64(block.timestamp + delay));
        vm.prank(admin);
        vm.expectRevert("Fee change must be at least 12 weeks in the future");
        _feeSettings.planFeeChange(feeChange);
    }

    function testExecuteFeeChangeTooEarly(uint delayAnnounced, uint32 tokenFee, uint32 investmentFee) public {
        vm.assume(delayAnnounced > 12 weeks && delayAnnounced < 1000000000000);
        vm.assume(tokenOrPersonalInviteFeeInValidRange(tokenFee));
        vm.assume(tokenOrPersonalInviteFeeInValidRange(investmentFee));

        Fees memory fees = Fees(1, 50, 1, 50, 1, 50, 0);
        vm.prank(admin);
        FeeSettings _feeSettings = new FeeSettings(fees, admin);

        Fees memory feeChange = Fees(
            1,
            tokenFee,
            1,
            investmentFee,
            1,
            investmentFee,
            uint64(block.timestamp + delayAnnounced)
        );
        vm.prank(admin);
        _feeSettings.planFeeChange(feeChange);

        vm.prank(admin);
        vm.expectRevert("Fee change must be executed after the change time");
        vm.warp(uint64(block.timestamp + delayAnnounced) - 1);
        _feeSettings.executeFeeChange();
    }

    function testExecuteFeeChangeProperly(
        uint delayAnnounced,
        uint32 tokenFee,
        uint32 fundraisingFee,
        uint32 privateOfferFee
    ) public {
        vm.assume(delayAnnounced > 12 weeks && delayAnnounced < 100000000000);
        vm.assume(tokenOrPrivateOfferFeeInValidRange(tokenFee));
        vm.assume(tokenOrPrivateOfferFeeInValidRange(fundraisingFee));
        vm.assume(tokenOrPrivateOfferFeeInValidRange(privateOfferFee));
        Fees memory fees = Fees(1, 50, 1, 50, 1, 50, 0);
        vm.prank(admin);
        FeeSettings _feeSettings = new FeeSettings(fees, admin);

        Fees memory feeChange = Fees(
            1,
            tokenFee,
            1,
            fundraisingFee,
            1,
            privateOfferFee,
            uint64(block.timestamp + delayAnnounced)
        );
        vm.prank(admin);
        vm.expectEmit(true, true, true, true, address(_feeSettings));
        emit ChangeProposed(feeChange);
        _feeSettings.planFeeChange(feeChange);

        vm.prank(admin);
        vm.warp(uint64(block.timestamp + delayAnnounced) + 1);
        vm.expectEmit(true, true, true, true, address(_feeSettings));
        emit SetFee(1, tokenFee, 1, fundraisingFee, 1, privateOfferFee);
        _feeSettings.executeFeeChange();

        assertEq(_feeSettings.tokenFeeDenominator(), tokenFee);
        assertEq(_feeSettings.continuousFundraisingFeeDenominator(), fundraisingFee);
        //assertEq(_feeSettings.change, 0);
    }

    function testSetFeeTo0Immediately() public {
        Fees memory fees = Fees(1, 50, 1, 20, 1, 30, 0);
        vm.prank(admin);
        FeeSettings _feeSettings = new FeeSettings(fees, admin);

        Fees memory feeChange = Fees(0, 1, 0, 1, 0, 1, uint64(block.timestamp));

        assertEq(_feeSettings.tokenFeeNumerator(), 1);
        assertEq(_feeSettings.tokenFeeDenominator(), 50);
        assertEq(_feeSettings.publicFundraisingFeeNumerator(), 1);
        assertEq(_feeSettings.publicFundraisingFeeDenominator(), 20);
        assertEq(_feeSettings.privateOfferFeeNumerator(), 1);
        assertEq(_feeSettings.privateOfferFeeDenominator(), 30);

        vm.prank(admin);
        _feeSettings.planFeeChange(feeChange);

        vm.prank(admin);
        //vm.warp(uint64(block.timestamp + delayAnnounced) + 1);
        _feeSettings.executeFeeChange();

        assertEq(_feeSettings.tokenFeeNumerator(), 0);
        assertEq(_feeSettings.tokenFeeDenominator(), 1);
        assertEq(_feeSettings.publicFundraisingFeeNumerator(), 0);
        assertEq(_feeSettings.publicFundraisingFeeDenominator(), 1);
        assertEq(_feeSettings.privateOfferFeeNumerator(), 0);
        assertEq(_feeSettings.privateOfferFeeDenominator(), 1);

        //assertEq(_feeSettings.change, 0);
    }

    function testSetFeeToXFrom0Immediately() public {
        Fees memory fees = Fees(0, 1, 0, 1, 0, 1, 0);
        vm.prank(admin);
        FeeSettings _feeSettings = new FeeSettings(fees, admin);

        Fees memory feeChange = Fees(1, 20, 1, 30, 1, 50, 0);

        assertEq(_feeSettings.tokenFeeNumerator(), 0);
        assertEq(_feeSettings.tokenFeeDenominator(), 1);
        assertEq(_feeSettings.publicFundraisingFeeNumerator(), 0);
        assertEq(_feeSettings.publicFundraisingFeeDenominator(), 1);
        assertEq(_feeSettings.privateOfferFeeNumerator(), 0);
        assertEq(_feeSettings.privateOfferFeeDenominator(), 1);

        vm.prank(admin);
        vm.expectRevert("Fee change must be at least 12 weeks in the future");
        _feeSettings.planFeeChange(feeChange);
    }

    function testReduceFeeImmediately(uint32 tokenReductor, uint32 continuousReductor, uint32 personalReductor) public {
        vm.assume(tokenReductor >= 50);
        vm.assume(continuousReductor >= 20);
        vm.assume(personalReductor >= 30);
        Fees memory fees = Fees(1, 50, 1, 20, 1, 30, 0);
        vm.prank(admin);
        FeeSettings _feeSettings = new FeeSettings(fees, admin);

        Fees memory feeChange = Fees(1, tokenReductor, 1, continuousReductor, 1, personalReductor, 0);

        assertEq(_feeSettings.tokenFeeDenominator(), 50);
        assertEq(_feeSettings.continuousFundraisingFeeDenominator(), 20);
        assertEq(_feeSettings.personalInviteFeeDenominator(), 30);

        vm.prank(admin);
        _feeSettings.planFeeChange(feeChange);

        vm.prank(admin);
        //vm.warp(uint64(block.timestamp + delayAnnounced) + 1);
        _feeSettings.executeFeeChange();

        assertEq(_feeSettings.tokenFeeDenominator(), tokenReductor);
        assertEq(_feeSettings.continuousFundraisingFeeDenominator(), continuousReductor);
        assertEq(_feeSettings.personalInviteFeeDenominator(), personalReductor);

        //assertEq(_feeSettings.change, 0);
    }

    function testSetFeeInConstructor(uint8 tokenFee, uint8 investmentFee) public {
        vm.assume(tokenOrPersonalInviteFeeInValidRange(tokenFee));
        vm.assume(tokenOrPersonalInviteFeeInValidRange(investmentFee));
        FeeSettings _feeSettings;
        Fees memory fees = Fees(1, tokenFee, 1, investmentFee, 1, investmentFee, 0);
        _feeSettings = new FeeSettings(fees, admin, admin, admin);
        assertEq(_feeSettings.tokenFeeDenominator(), tokenFee, "Token fee mismatch");
        assertEq(_feeSettings.continuousFundraisingFeeDenominator(), investmentFee, "Investment fee mismatch");
    }

    function testFeeCollector0FailsInConstructor() public {
        vm.expectRevert("Fee collector cannot be 0x0");
        FeeSettings _feeSettings;
        Fees memory fees = Fees(1, 100, 1, 100, 1, 100, 0);
        _feeSettings = new FeeSettings(fees, address(0), address(0), address(0));
    }

    function testFeeCollector0FailsInSetter() public {
        FeeSettings _feeSettings;
        Fees memory fees = Fees(1, 100, 1, 100, 1, 100, 0);
        vm.prank(admin);
        _feeSettings = new FeeSettings(fees, admin);
        vm.expectRevert("Fee collector cannot be 0x0");
        vm.prank(admin);
        _feeSettings.setFeeCollector(address(0));
    }

    function testUpdateFeeCollector(address newCollector) public {
        vm.assume(newCollector != address(0));
        FeeSettings _feeSettings;
        Fees memory fees = Fees(1, 100, 1, 100, 1, 100, 0);
        vm.prank(admin);
        _feeSettings = new FeeSettings(fees, admin);
        vm.expectEmit(true, true, true, true, address(_feeSettings));
        emit FeeCollectorChanged(newCollector);
        vm.prank(admin);
        _feeSettings.setFeeCollector(newCollector);
        assertEq(_feeSettings.feeCollector(), newCollector); // IFeeSettingsV1
    }

    function tokenOrPersonalInviteFeeInValidRange(uint256 fee) internal pure returns (bool) {
        return fee >= 20;
    }

    function testCalculateProperFees(
        uint32 tokenFeeDenominator,
        uint32 publicFundraisingFeeDenominator,
        uint32 privateOfferFeeDenominator,
        uint256 amount
    ) public {
        vm.assume(tokenFeeDenominator >= 20 && tokenFeeDenominator < UINT256_MAX);
        vm.assume(continuousFundraisingFeeDenominator >= 20 && continuousFundraisingFeeDenominator < UINT256_MAX);
        vm.assume(personalInviteFeeDenominator >= 20 && personalInviteFeeDenominator < UINT256_MAX);

        Fees memory _fees = Fees(
            1,
            tokenFeeDenominator,
            1,
            publicFundraisingFeeDenominator,
            1,
            privateOfferFeeDenominator,
            0
        );
        FeeSettings _feeSettings = new FeeSettings(_fees, admin, admin, admin);

        assertEq(_feeSettings.tokenFee(amount), amount / tokenFeeDenominator, "Token fee mismatch");
        assertEq(
            _feeSettings.continuousFundraisingFee(amount),
            amount / continuousFundraisingFeeDenominator,
            "Investment fee mismatch"
        );
        assertEq(
            _feeSettings.personalInviteFee(amount),
            amount / personalInviteFeeDenominator,
            "Personal invite fee mismatch"
        );
    }

    function testCalculate0FeesForAnyAmount(
        uint32 tokenFeeDenominator,
        uint32 publicFundraisingFeeDenominator,
        uint32 privateOfferFeeDenominator,
        uint256 amount
    ) public {
        vm.assume(tokenFeeDenominator >= 20);
        vm.assume(publicFundraisingFeeDenominator >= 20);
        vm.assume(privateOfferFeeDenominator >= 20);
        vm.assume(amount < UINT256_MAX);

        // only token fee is 0

        Fees memory _fees = Fees(0, 1, 1, publicFundraisingFeeDenominator, 1, privateOfferFeeDenominator, 0);
        FeeSettings _feeSettings = new FeeSettings(_fees, admin, admin, admin);

        assertEq(_feeSettings.tokenFee(amount), 0, "Token fee mismatch");
        assertEq(
            _feeSettings.continuousFundraisingFee(amount),
            amount / continuousFundraisingFeeDenominator,
            "Investment fee mismatch"
        );
        assertEq(
            _feeSettings.personalInviteFee(amount),
            amount / personalInviteFeeDenominator,
            "Personal invite fee mismatch"
        );

        // only continuous fundraising fee is 0

        _fees = Fees(1, tokenFeeDenominator, 0, 1, 1, privateOfferFeeDenominator, 0);
        _feeSettings = new FeeSettings(_fees, admin, admin, admin);

        assertEq(_feeSettings.tokenFee(amount), amount / tokenFeeDenominator, "Token fee mismatch");
        assertEq(_feeSettings.continuousFundraisingFee(amount), 0, "Investment fee mismatch");
        assertEq(
            _feeSettings.personalInviteFee(amount),
            amount / personalInviteFeeDenominator,
            "Personal invite fee mismatch"
        );

        // only personal invite fee is 0

        _fees = Fees(1, tokenFeeDenominator, 1, publicFundraisingFeeDenominator, 0, 1, 0);
        _feeSettings = new FeeSettings(_fees, admin, admin, admin);

        assertEq(_feeSettings.tokenFee(amount), amount / tokenFeeDenominator, "Token fee mismatch");
        assertEq(
            _feeSettings.continuousFundraisingFee(amount),
            amount / continuousFundraisingFeeDenominator,
            "Investment fee mismatch"
        );
        assertEq(_feeSettings.personalInviteFee(amount), 0, "Personal invite fee mismatch");
    }

    function testERC165IsAvailable() public {
        FeeSettings _feeSettings;
        Fees memory fees = Fees(1, 100, 1, 100, 1, 100, 0);
        _feeSettings = new FeeSettings(fees, admin, admin, admin);
        assertEq(
            _feeSettings.supportsInterface(0x01ffc9a7), // type(IERC165).interfaceId
            true,
            "ERC165 not supported"
        );
    }

    function testIFeeSettingsV1IsAvailable() public {
        FeeSettings _feeSettings;
        Fees memory fees = Fees(1, 100, 1, 100, 1, 100, 0);
        _feeSettings = new FeeSettings(fees, admin, admin, admin);

        assertEq(
            _feeSettings.supportsInterface(type(IFeeSettingsV1).interfaceId),
            true,
            "IFeeSettingsV1 not supported"
        );
    }

    function testIFeeSettingsV2IsAvailable() public {
        FeeSettings _feeSettings;
        Fees memory fees = Fees(1, 100, 1, 100, 1, 100, 0);
        _feeSettings = new FeeSettings(fees, admin, admin, admin);

        assertEq(
            _feeSettings.supportsInterface(type(IFeeSettingsV2).interfaceId),
            true,
            "IFeeSettingsV1 not supported"
        );
    }

    function testNonsenseInterfacesAreNotAvailable(bytes4 _nonsenseInterface) public {
        vm.assume(_nonsenseInterface != type(IFeeSettingsV1).interfaceId);
        vm.assume(_nonsenseInterface != 0x01ffc9a7);
        FeeSettings _feeSettings;
        Fees memory fees = Fees(1, 100, 1, 100, 1, 100, 0);
        _feeSettings = new FeeSettings(fees, admin, admin, admin);

        assertEq(_feeSettings.supportsInterface(0x01ffc9b7), false, "This interface should not be supported");
    }

    /**
     * @dev the fee calculation WAS implemented to accept a wrong result in one case:
     *      if denominator is UINT256_MAX and amount is UINT256_MAX, the result will be 1 instead of 0
     *      This has now been fixed
     */
    function testCalculate0FeesForAmountUINT256_MAX(
        uint32 tokenFeeDenominator,
        uint32 publicFundraisingFeeDenominator,
        uint32 privateOfferFeeDenominator
    ) public {
        vm.assume(tokenFeeDenominator >= 20 && tokenFeeDenominator < UINT256_MAX);
        vm.assume(continuousFundraisingFeeDenominator >= 20 && continuousFundraisingFeeDenominator < UINT256_MAX);
        vm.assume(personalInviteFeeDenominator >= 20 && personalInviteFeeDenominator < UINT256_MAX);
        uint256 amount = UINT256_MAX;

        // only token fee is 0

        Fees memory _fees = Fees(0, 1, 1, publicFundraisingFeeDenominator, 1, privateOfferFeeDenominator, 0);
        FeeSettings _feeSettings = new FeeSettings(_fees, admin, admin, admin);

        assertEq(_feeSettings.tokenFee(amount), 0, "Token fee mismatch");
        assertEq(
            _feeSettings.continuousFundraisingFee(amount),
            amount / continuousFundraisingFeeDenominator,
            "Investment fee mismatch"
        );
        assertEq(
            _feeSettings.personalInviteFee(amount),
            amount / personalInviteFeeDenominator,
            "Personal invite fee mismatch"
        );

        // only continuous fundraising fee is 0

        _fees = Fees(1, tokenFeeDenominator, 0, 1, 1, privateOfferFeeDenominator, 0);
        _feeSettings = new FeeSettings(_fees, admin, admin, admin);

        assertEq(_feeSettings.tokenFee(amount), amount / tokenFeeDenominator, "Token fee mismatch");
        assertEq(_feeSettings.continuousFundraisingFee(amount), 1, "Investment fee mismatch");
        assertEq(
            _feeSettings.personalInviteFee(amount),
            amount / personalInviteFeeDenominator,
            "Personal invite fee mismatch"
        );

        // only personal invite fee is 0

        _fees = Fees(1, tokenFeeDenominator, 1, publicFundraisingFeeDenominator, 0, 1, 0);
        _feeSettings = new FeeSettings(_fees, admin, admin, admin);

        assertEq(_feeSettings.tokenFee(amount), amount / tokenFeeDenominator, "Token fee mismatch");
        assertEq(
            _feeSettings.continuousFundraisingFee(amount),
            amount / continuousFundraisingFeeDenominator,
            "Investment fee mismatch"
        );
        assertEq(_feeSettings.personalInviteFee(amount), 1, "Personal invite fee mismatch");
    }
}
