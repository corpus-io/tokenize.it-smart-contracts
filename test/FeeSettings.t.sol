// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "../lib/forge-std/src/Test.sol";
import "../contracts/Token.sol";
import "../contracts/FeeSettings.sol";

contract FeeSettingsTest is Test {
    FeeSettings feeSettings;
    Token token;
    Token currency; // todo: add different ERC20 token as currency!

    uint256 MAX_INT =
        115792089237316195423570985008687907853269984665640564039457584007913129639935;

    address public constant admin = 0x0109709eCFa91a80626FF3989D68f67f5b1dD120;
    address public constant buyer = 0x1109709ecFA91a80626ff3989D68f67F5B1Dd121;
    address public constant minterAdmin =
        0x2109709EcFa91a80626Ff3989d68F67F5B1Dd122;
    address public constant minter = 0x3109709ECfA91A80626fF3989D68f67F5B1Dd123;
    address public constant owner = 0x6109709EcFA91A80626FF3989d68f67F5b1dd126;
    address public constant receiver =
        0x7109709eCfa91A80626Ff3989D68f67f5b1dD127;
    address public constant paymentTokenProvider =
        0x8109709ecfa91a80626fF3989d68f67F5B1dD128;
    address public constant trustedForwarder =
        0x9109709EcFA91A80626FF3989D68f67F5B1dD129;

    uint256 public constant price = 10000000;

    // function setUp() public {
    //     feeSettings = new FeeSettings(100, 100, admin);
    // }

    function testEnforceTokenFeeDenominatorRangeinConstructor(
        uint8 fee
    ) public {
        vm.assume(!feeInValidRange(fee));
        FeeSettings _feeSettings;
        vm.expectRevert("Fee must be below 5% or 0");
        _feeSettings = new FeeSettings(fee, 100, admin);
    }

    function testEnforceInvestmentFeeDenominatorRangeinConstructor(
        uint8 fee
    ) public {
        vm.assume(!feeInValidRange(fee));
        FeeSettings _feeSettings;
        vm.expectRevert("Fee must be below 5% or 0");
        _feeSettings = new FeeSettings(100, fee, admin);
    }

    function testEnforceTokenFeeDenominatorRangeinFeeChanger(uint8 fee) public {
        vm.assume(!feeInValidRange(fee));
        FeeSettings _feeSettings = new FeeSettings(100, 100, admin);

        Change memory feeChange = Change({
            tokenFeeDenominator: fee,
            investmentFeeDenominator: 100,
            time: block.timestamp + 7884001
        });
        vm.expectRevert("Fee must be below 5% or 0");
        _feeSettings.planFeeChange(feeChange);
    }

    function testEnforceInvestmentFeeDenominatorRangeinFeeChanger(
        uint8 fee
    ) public {
        vm.assume(!feeInValidRange(fee));
        FeeSettings _feeSettings = new FeeSettings(100, 100, admin);

        Change memory feeChange = Change({
            tokenFeeDenominator: 100,
            investmentFeeDenominator: fee,
            time: block.timestamp + 7884001
        });
        vm.expectRevert("Fee must be below 5% or 0");
        _feeSettings.planFeeChange(feeChange);
    }

    function testEnforceFeeChangeDelay(uint delay) public {
        vm.assume(delay <= 12 weeks);
        vm.prank(admin);
        FeeSettings _feeSettings = new FeeSettings(50, 50, admin);

        Change memory feeChange = Change({
            tokenFeeDenominator: 100,
            investmentFeeDenominator: 100,
            time: block.timestamp + delay
        });
        vm.prank(admin);
        vm.expectRevert("Fee change must be at least 12 weeks in the future");
        _feeSettings.planFeeChange(feeChange);

        // vm.prank(admin);
        // _feeSettings.executeFeeChange();
    }

    function testExecuteFeeChangeTooEarly(
        uint delayAnnounced,
        uint8 tokenFee,
        uint8 investmentFee
    ) public {
        vm.assume(delayAnnounced > 12 weeks && delayAnnounced < 1000000000000);
        vm.assume(feeInValidRange(tokenFee));
        vm.assume(feeInValidRange(investmentFee));
        vm.prank(admin);
        FeeSettings _feeSettings = new FeeSettings(50, 50, admin);

        Change memory feeChange = Change({
            tokenFeeDenominator: tokenFee,
            investmentFeeDenominator: investmentFee,
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
        uint8 tokenFee,
        uint8 investmentFee
    ) public {
        vm.assume(delayAnnounced > 7884000 && delayAnnounced < 100000000000);
        vm.assume(feeInValidRange(tokenFee));
        vm.assume(feeInValidRange(investmentFee));
        vm.prank(admin);
        FeeSettings _feeSettings = new FeeSettings(50, 50, admin);

        Change memory feeChange = Change({
            tokenFeeDenominator: tokenFee,
            investmentFeeDenominator: investmentFee,
            time: block.timestamp + delayAnnounced
        });
        vm.prank(admin);
        _feeSettings.planFeeChange(feeChange);

        vm.prank(admin);
        vm.warp(block.timestamp + delayAnnounced + 1);
        _feeSettings.executeFeeChange();

        assertEq(_feeSettings.tokenFeeDenominator(), tokenFee);
        assertEq(_feeSettings.investmentFeeDenominator(), investmentFee);
        //assertEq(_feeSettings.change, 0);
    }

    function testSetFeeInConstructor(
        uint8 tokenFee,
        uint8 investmentFee
    ) public {
        vm.assume(feeInValidRange(tokenFee));
        vm.assume(feeInValidRange(investmentFee));
        FeeSettings _feeSettings;
        _feeSettings = new FeeSettings(tokenFee, investmentFee, admin);
        assertEq(
            _feeSettings.tokenFeeDenominator(),
            tokenFee,
            "Token fee mismatch"
        );
        assertEq(
            _feeSettings.investmentFeeDenominator(),
            investmentFee,
            "Investment fee mismatch"
        );
    }

    function testFeeCollector0FailsInConstructor() public {
        vm.expectRevert("Fee collector cannot be 0x0");
        FeeSettings _feeSettings;
        _feeSettings = new FeeSettings(100, 100, address(0));
    }

    function testFeeCollector0FailsInSetter() public {
        FeeSettings _feeSettings;
        vm.prank(admin);
        _feeSettings = new FeeSettings(100, 100, admin);
        vm.expectRevert("Fee collector cannot be 0x0");
        vm.prank(admin);
        _feeSettings.setFeeCollector(address(0));
    }

    function testUpdateFeeCollector(address newCollector) public {
        vm.assume(newCollector != address(0));
        FeeSettings _feeSettings;
        vm.prank(admin);
        _feeSettings = new FeeSettings(100, 100, admin);
        vm.prank(admin);
        _feeSettings.setFeeCollector(newCollector);
        assertEq(_feeSettings.feeCollector(), newCollector);
    }

    function feeInValidRange(uint8 fee) internal pure returns (bool) {
        return fee == 0 || fee >= 20;
    }
}
