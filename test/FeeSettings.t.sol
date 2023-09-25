// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.13;

import "../lib/forge-std/src/Test.sol";
import "../contracts/Token.sol";
import "../contracts/FeeSettings.sol";

contract FeeSettingsTest is Test {
    event SetFeeDenominators(
        uint256 tokenFeeDenominator,
        uint256 continuousFundraisingFeeDenominator,
        uint256 personalInviteFeeDenominator
    );
    event FeeCollectorsChanged(
        address indexed newTokenFeeCollector,
        address indexed newContinuousFundraisingFeeCollector,
        address indexed newPersonalInviteFeeCollector
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

    function testEnforceFeeDenominatorRangeInConstructor(uint8 fee) public {
        vm.assume(!feeInValidRange(fee));
        Fees memory _fees;

        console.log("Testing token fee");
        _fees = Fees(fee, 30, 100, 0);
        vm.expectRevert("Fee must be equal or less 5% (denominator must be >= 20)");
        new FeeSettings(_fees, admin, admin, admin);

        console.log("Testing ContinuousFundraising fee");
        _fees = Fees(30, fee, 100, 0);
        vm.expectRevert("Fee must be equal or less 5% (denominator must be >= 20)");
        new FeeSettings(_fees, admin, admin, admin);

        console.log("Testing PersonalInvite fee");
        _fees = Fees(30, 40, fee, 0);
        vm.expectRevert("Fee must be equal or less 5% (denominator must be >= 20)");
        new FeeSettings(_fees, admin, admin, admin);
    }

    function testEnforceTokenFeeDenominatorRangeInFeeChanger(uint8 fee) public {
        vm.assume(!feeInValidRange(fee));
        Fees memory fees = Fees(100, 100, 100, 0);
        FeeSettings _feeSettings = new FeeSettings(fees, admin, admin, admin);

        Fees memory feeChange = Fees({
            tokenFeeDenominator: fee,
            continuousFundraisingFeeDenominator: 100,
            personalInviteFeeDenominator: 100,
            time: block.timestamp + 7884001
        });
        vm.expectRevert("Fee must be equal or less 5% (denominator must be >= 20)");
        _feeSettings.planFeeChange(feeChange);
    }

    function testEnforceContinuousFundraisingFeeDenominatorRangeInFeeChanger(uint8 fee) public {
        vm.assume(!feeInValidRange(fee));
        Fees memory fees = Fees(100, 100, 100, 0);
        FeeSettings _feeSettings = new FeeSettings(fees, admin, admin, admin);

        Fees memory feeChange = Fees({
            tokenFeeDenominator: 100,
            continuousFundraisingFeeDenominator: fee,
            personalInviteFeeDenominator: 100,
            time: block.timestamp + 7884001
        });
        vm.expectRevert("Fee must be equal or less 5% (denominator must be >= 20)");
        _feeSettings.planFeeChange(feeChange);
    }

    function testEnforcePersonalInviteFeeDenominatorRangeInFeeChanger(uint8 fee) public {
        vm.assume(!feeInValidRange(fee));
        Fees memory fees = Fees(100, 100, 100, 0);
        FeeSettings _feeSettings = new FeeSettings(fees, admin, admin, admin);

        Fees memory feeChange = Fees({
            tokenFeeDenominator: 100,
            continuousFundraisingFeeDenominator: 100,
            personalInviteFeeDenominator: fee,
            time: block.timestamp + 7884001
        });
        vm.expectRevert("Fee must be equal or less 5% (denominator must be >= 20)");
        _feeSettings.planFeeChange(feeChange);
    }

    function testEnforceFeeChangeDelayOnIncrease(uint delay, uint startDenominator, uint newDenominator) public {
        vm.assume(delay <= 12 weeks);
        vm.assume(startDenominator >= 20 && newDenominator >= 20);
        vm.assume(newDenominator < startDenominator);
        Fees memory fees = Fees(startDenominator, startDenominator, startDenominator, 0);
        vm.prank(admin);
        FeeSettings _feeSettings = new FeeSettings(fees, admin, admin, admin);

        Fees memory feeChange = Fees({
            tokenFeeDenominator: newDenominator,
            continuousFundraisingFeeDenominator: UINT256_MAX,
            personalInviteFeeDenominator: UINT256_MAX,
            time: block.timestamp + delay
        });
        vm.prank(admin);
        vm.expectRevert("Fee change must be at least 12 weeks in the future");
        _feeSettings.planFeeChange(feeChange);

        feeChange = Fees({
            tokenFeeDenominator: UINT256_MAX,
            continuousFundraisingFeeDenominator: newDenominator,
            personalInviteFeeDenominator: UINT256_MAX,
            time: block.timestamp + delay
        });
        vm.prank(admin);
        vm.expectRevert("Fee change must be at least 12 weeks in the future");
        _feeSettings.planFeeChange(feeChange);

        feeChange = Fees({
            tokenFeeDenominator: UINT256_MAX,
            continuousFundraisingFeeDenominator: UINT256_MAX,
            personalInviteFeeDenominator: newDenominator,
            time: block.timestamp + delay
        });
        vm.prank(admin);
        vm.expectRevert("Fee change must be at least 12 weeks in the future");
        _feeSettings.planFeeChange(feeChange);
    }

    function testExecuteFeeChangeTooEarly(uint delayAnnounced, uint256 tokenFee, uint256 investmentFee) public {
        vm.assume(delayAnnounced > 12 weeks && delayAnnounced < 1000000000000);
        vm.assume(feeInValidRange(tokenFee));
        vm.assume(feeInValidRange(investmentFee));

        Fees memory fees = Fees(50, 50, 50, 0);
        vm.prank(admin);
        FeeSettings _feeSettings = new FeeSettings(fees, admin, admin, admin);

        Fees memory feeChange = Fees({
            tokenFeeDenominator: tokenFee,
            continuousFundraisingFeeDenominator: investmentFee,
            personalInviteFeeDenominator: 100,
            time: block.timestamp + delayAnnounced
        });
        vm.prank(admin);
        _feeSettings.planFeeChange(feeChange);

        vm.prank(admin);
        vm.expectRevert("Fee change must be executed after the change time");
        vm.warp(block.timestamp + delayAnnounced - 1);
        _feeSettings.executeFeeChange();
    }

    function testExecuteFeeChangeProperly(
        uint delayAnnounced,
        uint256 tokenFee,
        uint256 fundraisingFee,
        uint256 personalInviteFee
    ) public {
        vm.assume(delayAnnounced > 12 weeks && delayAnnounced < 100000000000);
        vm.assume(feeInValidRange(tokenFee));
        vm.assume(feeInValidRange(fundraisingFee));
        vm.assume(feeInValidRange(personalInviteFee));
        Fees memory fees = Fees(50, 50, 50, 0);
        vm.prank(admin);
        FeeSettings _feeSettings = new FeeSettings(fees, admin, admin, admin);

        Fees memory feeChange = Fees({
            tokenFeeDenominator: tokenFee,
            continuousFundraisingFeeDenominator: fundraisingFee,
            personalInviteFeeDenominator: personalInviteFee,
            time: block.timestamp + delayAnnounced
        });
        vm.prank(admin);
        vm.expectEmit(true, true, true, true, address(_feeSettings));
        emit ChangeProposed(feeChange);
        _feeSettings.planFeeChange(feeChange);

        vm.prank(admin);
        vm.warp(block.timestamp + delayAnnounced + 1);
        vm.expectEmit(true, true, true, true, address(_feeSettings));
        emit SetFeeDenominators(tokenFee, fundraisingFee, personalInviteFee);
        _feeSettings.executeFeeChange();

        assertEq(_feeSettings.tokenFeeDenominator(), tokenFee);
        assertEq(_feeSettings.continuousFundraisingFeeDenominator(), fundraisingFee);
        //assertEq(_feeSettings.change, 0);
    }

    function testSetFeeTo0Immediately() public {
        Fees memory fees = Fees(50, 20, 30, 0);
        vm.prank(admin);
        FeeSettings _feeSettings = new FeeSettings(fees, admin, admin, admin);

        Fees memory feeChange = Fees({
            tokenFeeDenominator: UINT256_MAX,
            continuousFundraisingFeeDenominator: UINT256_MAX,
            personalInviteFeeDenominator: UINT256_MAX,
            time: 0
        });

        assertEq(_feeSettings.tokenFeeDenominator(), 50);
        assertEq(_feeSettings.continuousFundraisingFeeDenominator(), 20);
        assertEq(_feeSettings.personalInviteFeeDenominator(), 30);

        vm.prank(admin);
        _feeSettings.planFeeChange(feeChange);

        vm.prank(admin);
        //vm.warp(block.timestamp + delayAnnounced + 1);
        _feeSettings.executeFeeChange();

        assertEq(_feeSettings.tokenFeeDenominator(), UINT256_MAX);
        assertEq(_feeSettings.continuousFundraisingFeeDenominator(), UINT256_MAX);
        assertEq(_feeSettings.personalInviteFeeDenominator(), UINT256_MAX);

        //assertEq(_feeSettings.change, 0);
    }

    function testSetFeeToXFrom0Immediately() public {
        Fees memory fees = Fees(UINT256_MAX, UINT256_MAX, UINT256_MAX, 0);
        vm.prank(admin);
        FeeSettings _feeSettings = new FeeSettings(fees, admin, admin, admin);

        Fees memory feeChange = Fees({
            tokenFeeDenominator: 20,
            continuousFundraisingFeeDenominator: 30,
            personalInviteFeeDenominator: 50,
            time: 0
        });

        assertEq(_feeSettings.tokenFeeDenominator(), UINT256_MAX);
        assertEq(_feeSettings.continuousFundraisingFeeDenominator(), UINT256_MAX);
        assertEq(_feeSettings.personalInviteFeeDenominator(), UINT256_MAX);

        vm.prank(admin);
        vm.expectRevert("Fee change must be at least 12 weeks in the future");
        _feeSettings.planFeeChange(feeChange);
    }

    function testReduceFeeImmediately(
        uint256 tokenReductor,
        uint256 continuousReductor,
        uint256 personalReductor
    ) public {
        vm.assume(tokenReductor >= 50);
        vm.assume(continuousReductor >= 20);
        vm.assume(personalReductor >= 30);
        Fees memory fees = Fees(50, 20, 30, 0);
        vm.prank(admin);
        FeeSettings _feeSettings = new FeeSettings(fees, admin, admin, admin);

        Fees memory feeChange = Fees({
            tokenFeeDenominator: tokenReductor,
            continuousFundraisingFeeDenominator: continuousReductor,
            personalInviteFeeDenominator: personalReductor,
            time: 0
        });

        assertEq(_feeSettings.tokenFeeDenominator(), 50);
        assertEq(_feeSettings.continuousFundraisingFeeDenominator(), 20);
        assertEq(_feeSettings.personalInviteFeeDenominator(), 30);

        vm.prank(admin);
        _feeSettings.planFeeChange(feeChange);

        vm.prank(admin);
        //vm.warp(block.timestamp + delayAnnounced + 1);
        _feeSettings.executeFeeChange();

        assertEq(_feeSettings.tokenFeeDenominator(), tokenReductor);
        assertEq(_feeSettings.continuousFundraisingFeeDenominator(), continuousReductor);
        assertEq(_feeSettings.personalInviteFeeDenominator(), personalReductor);

        //assertEq(_feeSettings.change, 0);
    }

    function testSetFeeInConstructor(uint8 tokenFee, uint8 investmentFee) public {
        vm.assume(feeInValidRange(tokenFee));
        vm.assume(feeInValidRange(investmentFee));
        FeeSettings _feeSettings;
        Fees memory fees = Fees(tokenFee, investmentFee, investmentFee, 0);
        _feeSettings = new FeeSettings(fees, admin, admin, admin);
        assertEq(_feeSettings.tokenFeeDenominator(), tokenFee, "Token fee mismatch");
        assertEq(_feeSettings.continuousFundraisingFeeDenominator(), investmentFee, "Investment fee mismatch");
    }

    function testFeeCollector0FailsInConstructor() public {
        vm.expectRevert("Fee collector cannot be 0x0");
        FeeSettings _feeSettings;
        Fees memory fees = Fees(100, 100, 100, 0);
        _feeSettings = new FeeSettings(fees, address(0), address(0), address(0));
    }

    function testFeeCollector0FailsInSetter() public {
        FeeSettings _feeSettings;
        Fees memory fees = Fees(100, 100, 100, 0);
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
        address newContinuousFundraisingFeeCollector,
        address newPersonalInviteFeeCollector
    ) public {
        vm.assume(newTokenFeeCollector != address(0));
        vm.assume(newContinuousFundraisingFeeCollector != address(0));
        vm.assume(newPersonalInviteFeeCollector != address(0));
        FeeSettings _feeSettings;
        Fees memory fees = Fees(100, 100, 100, 0);
        vm.prank(admin);
        _feeSettings = new FeeSettings(fees, admin, admin, admin);
        vm.expectEmit(true, true, true, true, address(_feeSettings));
        emit FeeCollectorsChanged(
            newTokenFeeCollector,
            newContinuousFundraisingFeeCollector,
            newPersonalInviteFeeCollector
        );
        vm.prank(admin);
        _feeSettings.setFeeCollectors(
            newTokenFeeCollector,
            newContinuousFundraisingFeeCollector,
            newPersonalInviteFeeCollector
        );
        assertEq(_feeSettings.feeCollector(), newTokenFeeCollector); // IFeeSettingsV1
        assertEq(_feeSettings.tokenFeeCollector(), newTokenFeeCollector);
        assertEq(_feeSettings.continuousFundraisingFeeCollector(), newContinuousFundraisingFeeCollector);
        assertEq(_feeSettings.personalInviteFeeCollector(), newPersonalInviteFeeCollector);
    }

    function feeInValidRange(uint256 fee) internal pure returns (bool) {
        return fee >= 20;
    }

    function testCalculateProperFees(
        uint256 tokenFeeDenominator,
        uint256 continuousFundraisingFeeDenominator,
        uint256 personalInviteFeeDenominator,
        uint256 amount
    ) public {
        vm.assume(tokenFeeDenominator >= 20 && tokenFeeDenominator < UINT256_MAX);
        vm.assume(continuousFundraisingFeeDenominator >= 20 && continuousFundraisingFeeDenominator < UINT256_MAX);
        vm.assume(personalInviteFeeDenominator >= 20 && personalInviteFeeDenominator < UINT256_MAX);

        Fees memory _fees = Fees(
            tokenFeeDenominator,
            continuousFundraisingFeeDenominator,
            personalInviteFeeDenominator,
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

    function testCalculate0FeesForAmountLessThanUINT256_MAX(
        uint256 tokenFeeDenominator,
        uint256 continuousFundraisingFeeDenominator,
        uint256 personalInviteFeeDenominator,
        uint256 amount
    ) public {
        vm.assume(tokenFeeDenominator >= 20 && tokenFeeDenominator < UINT256_MAX);
        vm.assume(continuousFundraisingFeeDenominator >= 20 && continuousFundraisingFeeDenominator < UINT256_MAX);
        vm.assume(personalInviteFeeDenominator >= 20 && personalInviteFeeDenominator < UINT256_MAX);
        vm.assume(amount < UINT256_MAX);

        // only token fee is 0

        Fees memory _fees = Fees(UINT256_MAX, continuousFundraisingFeeDenominator, personalInviteFeeDenominator, 0);
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

        _fees = Fees(tokenFeeDenominator, UINT256_MAX, personalInviteFeeDenominator, 0);
        _feeSettings = new FeeSettings(_fees, admin, admin, admin);

        assertEq(_feeSettings.tokenFee(amount), amount / tokenFeeDenominator, "Token fee mismatch");
        assertEq(_feeSettings.continuousFundraisingFee(amount), 0, "Investment fee mismatch");
        assertEq(
            _feeSettings.personalInviteFee(amount),
            amount / personalInviteFeeDenominator,
            "Personal invite fee mismatch"
        );

        // only personal invite fee is 0

        _fees = Fees(tokenFeeDenominator, continuousFundraisingFeeDenominator, UINT256_MAX, 0);
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
        Fees memory fees = Fees(100, 100, 100, 0);
        _feeSettings = new FeeSettings(fees, admin, admin, admin);
        assertEq(
            _feeSettings.supportsInterface(0x01ffc9a7), // type(IERC165).interfaceId
            true,
            "ERC165 not supported"
        );
    }

    function testIFeeSettingsV1IsAvailable() public {
        FeeSettings _feeSettings;
        Fees memory fees = Fees(100, 100, 100, 0);
        _feeSettings = new FeeSettings(fees, admin, admin, admin);

        assertEq(
            _feeSettings.supportsInterface(type(IFeeSettingsV1).interfaceId),
            true,
            "IFeeSettingsV1 not supported"
        );
    }

    function testNonsenseInterfacesAreNotAvailable(bytes4 _nonsenseInterface) public {
        vm.assume(_nonsenseInterface != type(IFeeSettingsV1).interfaceId);
        vm.assume(_nonsenseInterface != 0x01ffc9a7);
        FeeSettings _feeSettings;
        Fees memory fees = Fees(100, 100, 100, 0);
        _feeSettings = new FeeSettings(fees, admin, admin, admin);

        assertEq(_feeSettings.supportsInterface(0x01ffc9b7), false, "This interface should not be supported");
    }

    /**
     * @dev the fee calculation is implemented to accept a wrong result in one case:
     *      if denominator is UINT256_MAX and amount is UINT256_MAX, the result will be 1 instead of 0
     */
    function testCalculate0FeesForAmountUINT256_MAX(
        uint256 tokenFeeDenominator,
        uint256 continuousFundraisingFeeDenominator,
        uint256 personalInviteFeeDenominator
    ) public {
        vm.assume(tokenFeeDenominator >= 20 && tokenFeeDenominator < UINT256_MAX);
        vm.assume(continuousFundraisingFeeDenominator >= 20 && continuousFundraisingFeeDenominator < UINT256_MAX);
        vm.assume(personalInviteFeeDenominator >= 20 && personalInviteFeeDenominator < UINT256_MAX);
        uint256 amount = UINT256_MAX;

        // only token fee is 0

        Fees memory _fees = Fees(UINT256_MAX, continuousFundraisingFeeDenominator, personalInviteFeeDenominator, 0);
        FeeSettings _feeSettings = new FeeSettings(_fees, admin, admin, admin);

        assertEq(_feeSettings.tokenFee(amount), 1, "Token fee mismatch");
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

        _fees = Fees(tokenFeeDenominator, UINT256_MAX, personalInviteFeeDenominator, 0);
        _feeSettings = new FeeSettings(_fees, admin, admin, admin);

        assertEq(_feeSettings.tokenFee(amount), amount / tokenFeeDenominator, "Token fee mismatch");
        assertEq(_feeSettings.continuousFundraisingFee(amount), 1, "Investment fee mismatch");
        assertEq(
            _feeSettings.personalInviteFee(amount),
            amount / personalInviteFeeDenominator,
            "Personal invite fee mismatch"
        );

        // only personal invite fee is 0

        _fees = Fees(tokenFeeDenominator, continuousFundraisingFeeDenominator, UINT256_MAX, 0);
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
