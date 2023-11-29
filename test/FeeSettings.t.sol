// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.23;

import "../lib/forge-std/src/Test.sol";
import "../contracts/Token.sol";
import "../contracts/factories/FeeSettingsCloneFactory.sol";
import "./resources/FakeCrowdinvestingAndToken.sol";

contract FeeSettingsTest is Test {
    event SetFee(
        uint32 tokenFeeNumerator,
        uint32 tokenFeeDenominator,
        uint32 crowdinvestingFeeNumerator,
        uint32 crowdinvestingFeeDenominator,
        uint32 privateOfferFeeNumerator,
        uint32 privateOfferFeeDenominator
    );
    event FeeCollectorsChanged(
        address indexed newTokenFeeCollector,
        address indexed newCrowdinvestingFeeCollector,
        address indexed newPrivateOfferFeeCollector
    );
    event ChangeProposed(Fees proposal);

    FeeSettings feeSettings;
    FeeSettingsCloneFactory feeSettingsCloneFactory;
    Fees fees;
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

    function setUp() public {
        FeeSettings logic = new FeeSettings(trustedForwarder);
        feeSettingsCloneFactory = new FeeSettingsCloneFactory(address(logic));

        fees = Fees(1, 101, 2, 102, 3, 103, 0);
        vm.prank(admin);
        feeSettings = FeeSettings(
            feeSettingsCloneFactory.createFeeSettingsClone("salt", trustedForwarder, admin, fees, admin, admin, admin)
        );
    }

    function testEnforceFeeRangeInInitializer(uint32 numerator, uint32 denominator) public {
        vm.assume(denominator > 0);
        vm.assume(!tokenOrPrivateOfferFeeInValidRange(numerator, denominator));
        Fees memory _fees;

        console.log("Testing token fee");
        _fees = Fees(numerator, denominator, 1, 30, 1, 100, 0);
        vm.expectRevert("Token fee must be equal or less 5%");
        feeSettingsCloneFactory.createFeeSettingsClone("salt", trustedForwarder, admin, _fees, admin, admin, admin);

        console.log("Testing Crowdinvesting fee");
        _fees = Fees(1, 30, numerator, denominator, 1, 100, 0);
        if (!crowdinvestingFeeInValidRange(numerator, denominator)) {
            vm.expectRevert("Crowdinvesting fee must be equal or less 10%");
            feeSettingsCloneFactory.createFeeSettingsClone("salt", trustedForwarder, admin, _fees, admin, admin, admin);
        } else {
            // this should not revert, as the fee is in valid range for crowdinvesting
            feeSettingsCloneFactory.createFeeSettingsClone("salt", trustedForwarder, admin, _fees, admin, admin, admin);
        }

        console.log("Testing PrivateOffer fee");
        _fees = Fees(1, 30, 1, 40, numerator, denominator, 0);
        vm.expectRevert("PrivateOffer fee must be equal or less 5%");
        feeSettingsCloneFactory.createFeeSettingsClone("salt", trustedForwarder, admin, _fees, admin, admin, admin);
    }

    function testEnforceTokenFeeRangeInFeeChanger(uint32 numerator, uint32 denominator) public {
        vm.assume(denominator > 0);
        vm.assume(!tokenOrPrivateOfferFeeInValidRange(numerator, denominator));

        Fees memory feeChange = Fees(numerator, denominator, 1, 100, 1, 100, uint64(block.timestamp + 7884001));
        vm.expectRevert("Token fee must be equal or less 5%");
        vm.prank(admin);
        feeSettings.planFeeChange(feeChange);
    }

    function testEnforceCrowdinvestingFeeRangeInFeeChanger(uint32 numerator, uint32 denominator) public {
        vm.assume(denominator > 0);
        vm.assume(!crowdinvestingFeeInValidRange(numerator, denominator));

        Fees memory feeChange = Fees(1, 100, numerator, denominator, 1, 100, uint64(block.timestamp + 7884001));
        vm.expectRevert("Crowdinvesting fee must be equal or less 10%");
        vm.prank(admin);
        feeSettings.planFeeChange(feeChange);
    }

    function testEnforcePrivateOfferFeeRangeInFeeChanger(uint32 numerator, uint32 denominator) public {
        vm.assume(denominator > 0);
        vm.assume(!tokenOrPrivateOfferFeeInValidRange(numerator, denominator));

        Fees memory feeChange = Fees(1, 100, 1, 100, numerator, denominator, uint64(block.timestamp + 7884001));
        vm.expectRevert("PrivateOffer fee must be equal or less 5%");
        vm.prank(admin);
        feeSettings.planFeeChange(feeChange);
    }

    function testEnforceFeeChangeDelayOnIncrease(uint delay, uint32 startDenominator, uint32 newDenominator) public {
        vm.assume(delay <= 12 weeks);
        vm.assume(startDenominator >= 20 && newDenominator >= 20);
        vm.assume(newDenominator < startDenominator);
        Fees memory _fees = Fees(1, startDenominator, 1, startDenominator, 1, startDenominator, 0);
        FeeSettings _feeSettings = FeeSettings(
            feeSettingsCloneFactory.createFeeSettingsClone("salt", trustedForwarder, admin, _fees, admin, admin, admin)
        );

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
        vm.assume(tokenOrPrivateOfferFeeInValidRange(1, tokenFee));
        vm.assume(tokenOrPrivateOfferFeeInValidRange(1, investmentFee));

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
        feeSettings.planFeeChange(feeChange);

        vm.prank(admin);
        vm.expectRevert("Fee change must be executed after the change time");
        vm.warp(uint64(block.timestamp + delayAnnounced) - 1);
        feeSettings.executeFeeChange();
    }

    function testExecuteFeeChangeProperly(
        uint delayAnnounced,
        uint32 tokenFeeDenominator,
        uint32 crowdinvestingFeeDenominator,
        uint32 privateOfferFeeDenominator
    ) public {
        uint32 tokenFeeNumerator = 2;
        uint32 crowdinvestingFeeNumerator = 3;
        uint32 privateOfferFeeNumerator = 4;
        vm.assume(delayAnnounced > 12 weeks && delayAnnounced < 100000000000);
        vm.assume(tokenOrPrivateOfferFeeInValidRange(tokenFeeNumerator, tokenFeeDenominator));
        vm.assume(crowdinvestingFeeInValidRange(crowdinvestingFeeNumerator, crowdinvestingFeeDenominator));
        vm.assume(tokenOrPrivateOfferFeeInValidRange(privateOfferFeeNumerator, privateOfferFeeDenominator));

        Fees memory feeChange = Fees(
            tokenFeeNumerator,
            tokenFeeDenominator,
            crowdinvestingFeeNumerator,
            crowdinvestingFeeDenominator,
            privateOfferFeeNumerator,
            privateOfferFeeDenominator,
            uint64(block.timestamp + delayAnnounced)
        );
        vm.prank(admin);
        vm.expectEmit(true, true, true, true, address(feeSettings));
        emit ChangeProposed(feeChange);
        feeSettings.planFeeChange(feeChange);

        vm.prank(admin);
        vm.warp(uint64(block.timestamp + delayAnnounced) + 1);
        vm.expectEmit(true, true, true, true, address(feeSettings));
        emit SetFee(
            tokenFeeNumerator,
            tokenFeeDenominator,
            crowdinvestingFeeNumerator,
            crowdinvestingFeeDenominator,
            privateOfferFeeNumerator,
            privateOfferFeeDenominator
        );
        feeSettings.executeFeeChange();

        assertEq(feeSettings.tokenFeeNumerator(), tokenFeeNumerator);
        assertEq(feeSettings.tokenFeeDenominator(), tokenFeeDenominator);
        assertEq(feeSettings.crowdinvestingFeeNumerator(), crowdinvestingFeeNumerator);
        assertEq(feeSettings.crowdinvestingFeeDenominator(), crowdinvestingFeeDenominator);
        assertEq(feeSettings.privateOfferFeeNumerator(), privateOfferFeeNumerator);
        assertEq(feeSettings.privateOfferFeeDenominator(), privateOfferFeeDenominator);
    }

    function testSetFeeTo0Immediately() public {
        Fees memory feeChange = Fees(0, 1, 0, 1, 0, 1, uint64(block.timestamp));

        assertEq(feeSettings.tokenFeeNumerator(), 1);
        assertEq(feeSettings.tokenFeeDenominator(), 101);
        assertEq(feeSettings.crowdinvestingFeeNumerator(), 2);
        assertEq(feeSettings.crowdinvestingFeeDenominator(), 102);
        assertEq(feeSettings.privateOfferFeeNumerator(), 3);
        assertEq(feeSettings.privateOfferFeeDenominator(), 103);

        vm.prank(admin);
        feeSettings.planFeeChange(feeChange);

        vm.prank(admin);
        //vm.warp(uint64(block.timestamp + delayAnnounced) + 1);
        feeSettings.executeFeeChange();

        assertEq(feeSettings.tokenFeeNumerator(), 0);
        assertEq(feeSettings.tokenFeeDenominator(), 1);
        assertEq(feeSettings.crowdinvestingFeeNumerator(), 0);
        assertEq(feeSettings.crowdinvestingFeeDenominator(), 1);
        assertEq(feeSettings.privateOfferFeeNumerator(), 0);
        assertEq(feeSettings.privateOfferFeeDenominator(), 1);

        (, uint32 tokenFeeDenominator, , , , , uint64 time) = feeSettings.proposedFees();

        assertEq(tokenFeeDenominator, 0, "Token fee denominator mismatch");
        assertEq(time, 0, "Time mismatch");
    }

    function testSetFeeToXFrom0Immediately() public {
        Fees memory _fees = Fees(0, 1, 0, 1, 0, 1, 0);
        vm.prank(admin);
        FeeSettings _feeSettings = FeeSettings(
            feeSettingsCloneFactory.createFeeSettingsClone("salt", trustedForwarder, admin, _fees, admin, admin, admin)
        );

        Fees memory feeChange = Fees(1, 20, 1, 30, 1, 50, 0);

        assertEq(_feeSettings.tokenFeeNumerator(), 0);
        assertEq(_feeSettings.tokenFeeDenominator(), 1);
        assertEq(_feeSettings.crowdinvestingFeeNumerator(), 0);
        assertEq(_feeSettings.crowdinvestingFeeDenominator(), 1);
        assertEq(_feeSettings.privateOfferFeeNumerator(), 0);
        assertEq(_feeSettings.privateOfferFeeDenominator(), 1);

        vm.prank(admin);
        vm.expectRevert("Fee change must be at least 12 weeks in the future");
        _feeSettings.planFeeChange(feeChange);
    }

    function testReduceFeeImmediately(uint32 tokenReductor, uint32 continuousReductor, uint32 personalReductor) public {
        vm.assume(tokenReductor >= 101);
        vm.assume(continuousReductor >= 102);
        vm.assume(personalReductor >= 103);

        Fees memory feeChange = Fees(1, tokenReductor, 2, continuousReductor, 3, personalReductor, 0);

        assertEq(feeSettings.tokenFeeDenominator(), 101, "Token fee denominator mismatch");
        assertEq(feeSettings.crowdinvestingFeeDenominator(), 102, "Crowdinvesting fee denominator mismatch");
        assertEq(feeSettings.privateOfferFeeDenominator(), 103, "Private offer fee denominator mismatch");

        vm.prank(admin);
        feeSettings.planFeeChange(feeChange);

        vm.prank(admin);
        //vm.warp(uint64(block.timestamp + delayAnnounced) + 1);
        feeSettings.executeFeeChange();

        assertEq(feeSettings.tokenFeeDenominator(), tokenReductor);
        assertEq(feeSettings.crowdinvestingFeeDenominator(), continuousReductor);
        assertEq(feeSettings.privateOfferFeeDenominator(), personalReductor);

        //assertEq(_feeSettings.change, 0);
    }

    function testSetFeeInInitializer(
        uint32 tokenFeeNumerator,
        uint32 tokenFeeDenominator,
        uint32 crowdinvestingFeeNumerator,
        uint32 crowdinvestingFeeDenominator,
        uint32 privateOfferFeeNumerator,
        uint32 privateOfferFeeDenominator
    ) public {
        vm.assume(tokenFeeDenominator > 0 && crowdinvestingFeeDenominator > 0 && privateOfferFeeDenominator > 0);
        vm.assume(tokenOrPrivateOfferFeeInValidRange(tokenFeeNumerator, tokenFeeDenominator));
        vm.assume(tokenOrPrivateOfferFeeInValidRange(privateOfferFeeNumerator, privateOfferFeeDenominator));
        vm.assume(crowdinvestingFeeInValidRange(crowdinvestingFeeNumerator, crowdinvestingFeeDenominator));
        FeeSettings _feeSettings;
        Fees memory _fees = Fees(
            tokenFeeNumerator,
            tokenFeeDenominator,
            crowdinvestingFeeNumerator,
            crowdinvestingFeeDenominator,
            privateOfferFeeNumerator,
            privateOfferFeeDenominator,
            0
        );
        _feeSettings = FeeSettings(
            feeSettingsCloneFactory.createFeeSettingsClone("salt", trustedForwarder, admin, _fees, admin, admin, admin)
        );
        assertEq(_feeSettings.tokenFeeNumerator(), tokenFeeNumerator, "Token fee numerator mismatch");
        assertEq(_feeSettings.tokenFeeDenominator(), tokenFeeDenominator, "Token fee denominator mismatch");
        assertEq(
            _feeSettings.crowdinvestingFeeNumerator(),
            crowdinvestingFeeNumerator,
            "Crowdinvesting fee numerator mismatch"
        );
        assertEq(
            _feeSettings.crowdinvestingFeeDenominator(),
            crowdinvestingFeeDenominator,
            "Crowdinvesting fee denominator mismatch"
        );
        assertEq(
            _feeSettings.privateOfferFeeNumerator(),
            privateOfferFeeNumerator,
            "PrivateOffer fee numerator mismatch"
        );
        assertEq(
            _feeSettings.privateOfferFeeDenominator(),
            privateOfferFeeDenominator,
            "PrivateOffer fee denominator mismatch"
        );
    }

    function testFeeCollector0FailsInInitializer() public {
        FeeSettings _feeSettings;

        vm.expectRevert("Fee collector cannot be 0x0");
        _feeSettings = FeeSettings(
            feeSettingsCloneFactory.createFeeSettingsClone(
                "salt",
                trustedForwarder,
                admin,
                fees,
                address(0),
                admin,
                admin
            )
        );

        vm.expectRevert("Fee collector cannot be 0x0");
        _feeSettings = FeeSettings(
            feeSettingsCloneFactory.createFeeSettingsClone(
                "salt",
                trustedForwarder,
                admin,
                fees,
                admin,
                address(0),
                admin
            )
        );

        vm.expectRevert("Fee collector cannot be 0x0");
        _feeSettings = FeeSettings(
            feeSettingsCloneFactory.createFeeSettingsClone(
                "salt",
                trustedForwarder,
                admin,
                fees,
                admin,
                admin,
                address(0)
            )
        );
    }

    function testOwner0FailsInInitializer() public {
        vm.expectRevert("owner can not be zero address");
        feeSettingsCloneFactory.createFeeSettingsClone("salt", trustedForwarder, address(0), fees, admin, admin, admin);
    }

    function testFeeCollector0FailsInSetter() public {
        vm.expectRevert("Fee collector cannot be 0x0");
        vm.prank(admin);
        feeSettings.setFeeCollectors(address(0), address(1), address(2));
        vm.expectRevert("Fee collector cannot be 0x0");
        vm.prank(admin);
        feeSettings.setFeeCollectors(address(2), address(0), address(1));
        vm.expectRevert("Fee collector cannot be 0x0");
        vm.prank(admin);
        feeSettings.setFeeCollectors(address(1), address(2), address(0));
    }

    function testUpdateFeeCollectors(
        address newTokenFeeCollector,
        address newCrowdinvestingFeeCollector,
        address newPrivateOfferFeeCollector
    ) public {
        vm.assume(newTokenFeeCollector != address(0));
        vm.assume(newCrowdinvestingFeeCollector != address(0));
        vm.assume(newPrivateOfferFeeCollector != address(0));

        vm.expectEmit(true, true, true, true, address(feeSettings));
        emit FeeCollectorsChanged(newTokenFeeCollector, newCrowdinvestingFeeCollector, newPrivateOfferFeeCollector);
        vm.prank(admin);
        feeSettings.setFeeCollectors(newTokenFeeCollector, newCrowdinvestingFeeCollector, newPrivateOfferFeeCollector);
        assertEq(feeSettings.feeCollector(), newTokenFeeCollector); // IFeeSettingsV1
        assertEq(feeSettings.tokenFeeCollector(), newTokenFeeCollector);
        assertEq(feeSettings.crowdinvestingFeeCollector(), newCrowdinvestingFeeCollector);
        assertEq(feeSettings.privateOfferFeeCollector(), newPrivateOfferFeeCollector);
    }

    function tokenOrPrivateOfferFeeInValidRange(uint32 numerator, uint32 denominator) internal pure returns (bool) {
        return uint256(numerator) * 20 <= denominator;
    }

    function crowdinvestingFeeInValidRange(uint32 numerator, uint32 denominator) internal pure returns (bool) {
        return uint256(numerator) * 10 <= denominator;
    }

    function testCalculateProperFees(
        uint32 tokenFeeDenominator,
        uint32 crowdinvestingFeeDenominator,
        uint32 privateOfferFeeDenominator,
        uint256 amount
    ) public {
        vm.assume(tokenFeeDenominator >= 20 && tokenFeeDenominator < UINT256_MAX);
        vm.assume(crowdinvestingFeeDenominator >= 20 && crowdinvestingFeeDenominator < UINT256_MAX);
        vm.assume(privateOfferFeeDenominator >= 20 && privateOfferFeeDenominator < UINT256_MAX);

        Fees memory _fees = Fees(
            1,
            tokenFeeDenominator,
            1,
            crowdinvestingFeeDenominator,
            1,
            privateOfferFeeDenominator,
            0
        );
        FeeSettings _feeSettings = FeeSettings(
            feeSettingsCloneFactory.createFeeSettingsClone("salt", trustedForwarder, admin, _fees, admin, admin, admin)
        );

        FakeToken _fakeToken = new FakeToken(address(_feeSettings));
        FakeCrowdinvesting _fakeCrowdinvesting = new FakeCrowdinvesting(address(_fakeToken));

        assertEq(_fakeToken.fee(amount), amount / tokenFeeDenominator, "Token fee mismatch");
        assertEq(_fakeCrowdinvesting.fee(amount), amount / crowdinvestingFeeDenominator, "Investment fee mismatch");
        assertEq(
            _feeSettings.privateOfferFee(amount, address(0)),
            amount / privateOfferFeeDenominator,
            "Private offer fee mismatch"
        );
    }

    function testCalculate0FeesForAnyAmount(
        uint32 tokenFeeDenominator,
        uint32 crowdinvestingFeeDenominator,
        uint32 privateOfferFeeDenominator,
        uint256 amount
    ) public {
        vm.assume(tokenFeeDenominator >= 20);
        vm.assume(crowdinvestingFeeDenominator >= 20);
        vm.assume(privateOfferFeeDenominator >= 20);
        vm.assume(amount < UINT256_MAX);

        // only token fee is 0

        Fees memory _fees = Fees(0, 1, 1, crowdinvestingFeeDenominator, 1, privateOfferFeeDenominator, 0);
        FeeSettings _feeSettings = FeeSettings(
            feeSettingsCloneFactory.createFeeSettingsClone("salt", trustedForwarder, admin, _fees, admin, admin, admin)
        );

        FakeToken _fakeToken = new FakeToken(address(_feeSettings));
        FakeCrowdinvesting _fakeCrowdinvesting = new FakeCrowdinvesting(address(_fakeToken));

        assertEq(_fakeToken.fee(amount), 0, "Token fee mismatch");
        assertEq(_fakeCrowdinvesting.fee(amount), amount / crowdinvestingFeeDenominator, "Investment fee mismatch");
        assertEq(
            _feeSettings.privateOfferFee(amount, address(0)),
            amount / privateOfferFeeDenominator,
            "Private offer fee mismatch"
        );

        // only crowdinvesting fee is 0

        _fees = Fees(1, tokenFeeDenominator, 0, 1, 1, privateOfferFeeDenominator, 0);
        _feeSettings = FeeSettings(
            feeSettingsCloneFactory.createFeeSettingsClone("salt", trustedForwarder, admin, _fees, admin, admin, admin)
        );
        _fakeToken = new FakeToken(address(_feeSettings));
        _fakeCrowdinvesting = new FakeCrowdinvesting(address(_fakeToken));

        assertEq(_fakeToken.fee(amount), amount / tokenFeeDenominator, "Token fee mismatch");
        assertEq(_fakeCrowdinvesting.fee(amount), 0, "Investment fee mismatch");
        assertEq(
            _feeSettings.privateOfferFee(amount, address(0)),
            amount / privateOfferFeeDenominator,
            "Private offer fee mismatch"
        );

        // only private offer fee is 0

        _fees = Fees(1, tokenFeeDenominator, 1, crowdinvestingFeeDenominator, 0, 1, 0);
        _feeSettings = FeeSettings(
            feeSettingsCloneFactory.createFeeSettingsClone("salt", trustedForwarder, admin, _fees, admin, admin, admin)
        );
        _fakeToken = new FakeToken(address(_feeSettings));
        _fakeCrowdinvesting = new FakeCrowdinvesting(address(_fakeToken));

        assertEq(_fakeToken.fee(amount), amount / tokenFeeDenominator, "Token fee mismatch");
        assertEq(_fakeCrowdinvesting.fee(amount), amount / crowdinvestingFeeDenominator, "Investment fee mismatch");
        assertEq(_feeSettings.privateOfferFee(amount, address(0)), 0, "Private offer fee mismatch");
    }

    function testERC165IsAvailable() public {
        assertEq(
            feeSettings.supportsInterface(0x01ffc9a7), // type(IERC165).interfaceId
            true,
            "ERC165 not supported"
        );
    }

    function testIFeeSettingsV1IsAvailable(uint256 _amount) public {
        vm.assume(_amount < UINT256_MAX / 3);
        assertEq(feeSettings.supportsInterface(type(IFeeSettingsV1).interfaceId), true, "IFeeSettingsV1 not supported");

        // these functions must be present, so the call can not revert

        // set up fake crowdinvesting for this to work
        FakeToken _fakeToken = new FakeToken(address(feeSettings));
        FakeCrowdinvesting _fakeCrowdinvesting = new FakeCrowdinvesting(address(_fakeToken));

        assertEq(_fakeCrowdinvesting.fee(_amount), _fakeCrowdinvesting.feeV1(_amount), "Crowdinvesting Fee mismatch");

        assertEq(
            feeSettings.privateOfferFee(_amount, address(0)),
            feeSettings.personalInviteFee(_amount),
            "Private offer fee mismatch"
        );
        assertEq(feeSettings.feeCollector(), feeSettings.tokenFeeCollector(), "Fee collector mismatch");
    }

    function testIFeeSettingsV2IsAvailable() public {
        assertEq(feeSettings.supportsInterface(type(IFeeSettingsV2).interfaceId), true, "IFeeSettingsV2 not supported");
    }

    function testNonsenseInterfacesAreNotAvailable(bytes4 _nonsenseInterface) public {
        vm.assume(_nonsenseInterface != type(IFeeSettingsV1).interfaceId);
        vm.assume(_nonsenseInterface != type(IFeeSettingsV2).interfaceId);
        vm.assume(_nonsenseInterface != 0x01ffc9a7);

        assertEq(feeSettings.supportsInterface(0x01ffc9b7), false, "This interface should not be supported");
    }

    /**
     * @dev the fee calculation WAS implemented to accept a wrong result in one case:
     *      if denominator is UINT256_MAX and amount is UINT256_MAX, the result will be 1 instead of 0
     *      This has now been fixed
     */
    function testCalculate0FeesForAmountUINT256_MAX(
        uint32 tokenFeeDenominator,
        uint32 crowdinvestingFeeDenominator,
        uint32 privateOfferFeeDenominator
    ) public {
        vm.assume(tokenFeeDenominator >= 20 && tokenFeeDenominator < UINT256_MAX);
        vm.assume(crowdinvestingFeeDenominator >= 20 && crowdinvestingFeeDenominator < UINT256_MAX);
        vm.assume(privateOfferFeeDenominator >= 20 && privateOfferFeeDenominator < UINT256_MAX);
        uint256 amount = UINT256_MAX;

        // only token fee is 0

        Fees memory _fees = Fees(0, 1, 1, crowdinvestingFeeDenominator, 1, privateOfferFeeDenominator, 0);
        FeeSettings _feeSettings = FeeSettings(
            feeSettingsCloneFactory.createFeeSettingsClone("salt", trustedForwarder, admin, _fees, admin, admin, admin)
        );

        FakeToken _fakeToken = new FakeToken(address(_feeSettings));
        FakeCrowdinvesting _fakeCrowdinvesting = new FakeCrowdinvesting(address(_fakeToken));

        assertEq(_fakeToken.fee(amount), 0, "Token fee mismatch");
        assertEq(_fakeCrowdinvesting.fee(amount), amount / crowdinvestingFeeDenominator, "Investment fee mismatch");
        assertEq(
            _feeSettings.privateOfferFee(amount, address(0)),
            amount / privateOfferFeeDenominator,
            "Private offer fee mismatch"
        );

        // only crowdinvesting fee is 0

        _fees = Fees(1, tokenFeeDenominator, 0, 1, 1, privateOfferFeeDenominator, 0);
        _feeSettings = FeeSettings(
            feeSettingsCloneFactory.createFeeSettingsClone("salt", trustedForwarder, admin, _fees, admin, admin, admin)
        );
        _fakeToken = new FakeToken(address(_feeSettings));
        _fakeCrowdinvesting = new FakeCrowdinvesting(address(_fakeToken));

        assertEq(_feeSettings.tokenFee(amount), amount / tokenFeeDenominator, "Token fee mismatch");
        assertEq(_fakeCrowdinvesting.fee(amount), 0, "Investment fee mismatch");
        assertEq(
            _feeSettings.privateOfferFee(amount, address(0)),
            amount / privateOfferFeeDenominator,
            "Private offer fee mismatch"
        );

        // only private offer fee is 0

        _fees = Fees(1, tokenFeeDenominator, 1, crowdinvestingFeeDenominator, 0, 1, 0);
        _feeSettings = FeeSettings(
            feeSettingsCloneFactory.createFeeSettingsClone("salt", trustedForwarder, admin, _fees, admin, admin, admin)
        );
        _fakeToken = new FakeToken(address(_feeSettings));
        _fakeCrowdinvesting = new FakeCrowdinvesting(address(_fakeToken));

        assertEq(_feeSettings.tokenFee(amount), amount / tokenFeeDenominator, "Token fee mismatch");
        assertEq(_fakeCrowdinvesting.fee(amount), amount / crowdinvestingFeeDenominator, "Investment fee mismatch");
        assertEq(_feeSettings.privateOfferFee(amount, address(0)), 0, "Private offer fee mismatch");
    }

    function test0DenominatorIsNotPossible() public {
        Fees memory _fees = Fees(1, 0, 1, 0, 1, 0, 0);
        vm.expectRevert("Denominator cannot be 0");
        feeSettingsCloneFactory.createFeeSettingsClone("salt", trustedForwarder, admin, _fees, admin, admin, admin);

        // set 0 fee first, then update to 0 denominator
        _fees = Fees(0, 1, 0, 1, 0, 1, 0);
        FeeSettings _feeSettings = FeeSettings(
            feeSettingsCloneFactory.createFeeSettingsClone("salt", trustedForwarder, admin, _fees, admin, admin, admin)
        );
        _fees = Fees(0, 0, 0, 1, 0, 1, 0);
        vm.expectRevert("Denominator cannot be 0");
        vm.prank(admin);
        _feeSettings.planFeeChange(_fees);

        _fees = Fees(0, 1, 0, 0, 0, 1, 0);
        vm.expectRevert("Denominator cannot be 0");
        vm.prank(admin);
        _feeSettings.planFeeChange(_fees);

        _fees = Fees(0, 1, 0, 1, 0, 0, 0);
        vm.expectRevert("Denominator cannot be 0");
        vm.prank(admin);
        _feeSettings.planFeeChange(_fees);
    }

    function testAddingCustomFees(address _someTokenAddress) public {
        vm.assume(_someTokenAddress != address(0));

        Fees memory _fees = Fees(1, 100, 1, 50, 1, 20, 0);
        // deploying from here makes address(this) the admin
        FeeSettings _feeSettings = FeeSettings(
            feeSettingsCloneFactory.createFeeSettingsClone(
                "salt",
                trustedForwarder,
                address(this),
                _fees,
                address(this),
                address(this),
                address(this)
            )
        );
        // check there is no entry for this token address
        (
            uint32 tokenFeeNumerator,
            uint32 tokenFeeDenominator,
            uint32 crowdinvestingFeeNumerator,
            uint32 crowdinvestingFeeDenominator,
            uint32 privateOfferFeeNumerator,
            uint32 privateOfferFeeDenominator,
            uint64 endTime
        ) = _feeSettings.customFees(_someTokenAddress);
        assertEq(tokenFeeNumerator, 0, "Token fee numerator should be 0");
        assertEq(tokenFeeDenominator, 0, "Token fee denominator should be 0");
        assertEq(crowdinvestingFeeNumerator, 0, "Crowdinvesting fee numerator should be 0");
        assertEq(crowdinvestingFeeDenominator, 0, "Crowdinvesting fee denominator should be 0");
        assertEq(privateOfferFeeNumerator, 0, "Private offer fee numerator should be 0");
        assertEq(privateOfferFeeDenominator, 0, "Private offer fee denominator should be 0");
        assertEq(endTime, 0, "End time should be 0");

        // check the token fee, private offer fee and crowdinvesting fee are as expected
        assertEq(_feeSettings.tokenFee(1000, _someTokenAddress), 10, "Token fee should be 10");
        assertEq(_feeSettings.crowdinvestingFee(1000, _someTokenAddress), 20, "Crowdinvesting fee should be 20");
        assertEq(_feeSettings.privateOfferFee(1000, _someTokenAddress), 50, "Private offer fee should be 50");

        // add custom fee entry for this token address
        uint256 realEndTime = block.timestamp + 100;
        _fees = Fees(3, 1000, 4, 1000, 2, 1000, uint64(realEndTime));
        _feeSettings.setCustomFee(_someTokenAddress, _fees);

        // check the token fee, private offer fee and crowdinvesting fee change as expected
        assertEq(_feeSettings.tokenFee(1000, _someTokenAddress), 3, "Token fee should be 3");
        assertEq(_feeSettings.crowdinvestingFee(1000, _someTokenAddress), 4, "Crowdinvesting fee should be 4");
        assertEq(_feeSettings.privateOfferFee(1000, _someTokenAddress), 2, "Private offer fee should be 2");

        // check the custom fee entry is as expected
        (
            tokenFeeNumerator,
            tokenFeeDenominator,
            crowdinvestingFeeNumerator,
            crowdinvestingFeeDenominator,
            privateOfferFeeNumerator,
            privateOfferFeeDenominator,
            endTime
        ) = _feeSettings.customFees(_someTokenAddress);
        assertEq(tokenFeeNumerator, 3, "Token fee numerator should be 3");
        assertEq(tokenFeeDenominator, 1000, "Token fee denominator should be 1000");
        assertEq(crowdinvestingFeeNumerator, 4, "Crowdinvesting fee numerator should be 4");
        assertEq(crowdinvestingFeeDenominator, 1000, "Crowdinvesting fee denominator should be 1000");
        assertEq(privateOfferFeeNumerator, 2, "Private offer fee numerator should be 2");
        assertEq(privateOfferFeeDenominator, 1000, "Private offer fee denominator should be 1000");
        assertEq(endTime, realEndTime, "End time should match");

        // check that the custom fee is not applied after the end time
        vm.warp(realEndTime + 1);
        assertEq(_feeSettings.tokenFee(1000, _someTokenAddress), 10, "Token fee should be 10 again");
        assertEq(_feeSettings.crowdinvestingFee(1000, _someTokenAddress), 20, "Crowdinvesting fee should be 20 again");
        assertEq(_feeSettings.privateOfferFee(1000, _someTokenAddress), 50, "Private offer fee should be 50 again");
    }

    function testOnlyManagerCanAddCustomFees(address _rando) public {
        address someTokenAddress = address(74);
        vm.assume(_rando != address(0));
        vm.assume(_rando != admin);

        Fees memory _fees = Fees(1, 100, 1, 50, 1, 20, 0);

        vm.expectRevert("Only managers can call this function");
        vm.prank(_rando);
        feeSettings.setCustomFee(someTokenAddress, _fees);
    }

    function testCustomFeesAreNotAppliedToOtherTokens(address _someTokenAddress, address _otherTokenAddress) public {
        vm.assume(_someTokenAddress != address(0));
        vm.assume(_otherTokenAddress != address(0));
        vm.assume(_someTokenAddress != _otherTokenAddress);

        Fees memory _fees = Fees(1, 100, 1, 50, 1, 20, 0);
        FeeSettings _feeSettings = FeeSettings(
            feeSettingsCloneFactory.createFeeSettingsClone(
                "salt",
                trustedForwarder,
                address(this),
                _fees,
                admin,
                admin,
                admin
            )
        );
        // add custom fee entry for this token address
        _fees = Fees(3, 1000, 4, 1000, 2, 1000, uint64(block.timestamp + 100));
        _feeSettings.setCustomFee(_someTokenAddress, _fees);

        // check the token fee, private offer fee and crowdinvesting fee are as expected
        assertEq(_feeSettings.tokenFee(1000, _otherTokenAddress), 10, "Token fee should be 10");
        assertEq(_feeSettings.crowdinvestingFee(1000, _otherTokenAddress), 20, "Crowdinvesting fee should be 20");
        assertEq(_feeSettings.privateOfferFee(1000, _otherTokenAddress), 50, "Private offer fee should be 50");
    }

    function testCustomFeesDoNotIncreaseFee() public {
        address someTokenAddress = address(74);
        Fees memory _fees = Fees(0, 1, 0, 1, 0, 1, 0);
        FeeSettings _feeSettings = FeeSettings(
            feeSettingsCloneFactory.createFeeSettingsClone(
                "salt",
                trustedForwarder,
                address(this),
                _fees,
                admin,
                admin,
                admin
            )
        );

        // check the token fee, private offer fee and crowdinvesting fee are as expected
        assertEq(_feeSettings.tokenFee(type(uint256).max, someTokenAddress), 0, "Token fee should be 0");
        assertEq(
            _feeSettings.crowdinvestingFee(type(uint256).max, someTokenAddress),
            0,
            "Crowdinvesting fee should be 0"
        );
        assertEq(_feeSettings.privateOfferFee(type(uint256).max, someTokenAddress), 0, "Private offer fee should be 0");

        // add custom fee entry for this token address
        _fees = Fees(1, 20, 1, 10, 1, 20, uint64(block.timestamp + 100));
        _feeSettings.setCustomFee(someTokenAddress, _fees);

        // check the token fee, private offer fee and crowdinvesting fee are as expected
        assertEq(_feeSettings.tokenFee(type(uint256).max, someTokenAddress), 0, "Token fee should still be 0");
        assertEq(
            _feeSettings.crowdinvestingFee(type(uint256).max, someTokenAddress),
            0,
            "Crowdinvesting fee should still be 0"
        );
        assertEq(
            _feeSettings.privateOfferFee(type(uint256).max, someTokenAddress),
            0,
            "Private offer fee should still be 0"
        );
    }

    function testRemovingCustomFee() public {
        address someTokenAddress = address(74);
        Fees memory _fees = Fees(1, 100, 1, 50, 1, 20, 0);
        FeeSettings _feeSettings = FeeSettings(
            feeSettingsCloneFactory.createFeeSettingsClone(
                "salt",
                trustedForwarder,
                address(this),
                _fees,
                admin,
                admin,
                admin
            )
        );
        // add custom fee entry for this token address
        _fees = Fees(3, 1000, 4, 1000, 2, 1000, uint64(block.timestamp + 100));
        _feeSettings.setCustomFee(someTokenAddress, _fees);

        // check the token fee, private offer fee and crowdinvesting fee are as expected
        assertEq(_feeSettings.tokenFee(1000, someTokenAddress), 3, "Token fee should be 3");
        assertEq(_feeSettings.crowdinvestingFee(1000, someTokenAddress), 4, "Crowdinvesting fee should be 4");
        assertEq(_feeSettings.privateOfferFee(1000, someTokenAddress), 2, "Private offer fee should be 2");

        // remove custom fee entry for this token address
        _feeSettings.removeCustomFee(someTokenAddress);

        // check the token fee, private offer fee and crowdinvesting fee are as expected
        assertEq(_feeSettings.tokenFee(1000, someTokenAddress), 10, "Token fee should be 10");
        assertEq(_feeSettings.crowdinvestingFee(1000, someTokenAddress), 20, "Crowdinvesting fee should be 20");
        assertEq(_feeSettings.privateOfferFee(1000, someTokenAddress), 50, "Private offer fee should be 50");
    }

    function testOnlyManagerCanRemoveCustomFees(address _rando) public {
        address someTokenAddress = address(74);
        vm.assume(feeSettings.managers(_rando) == false);
        vm.expectRevert("Only managers can call this function");
        vm.prank(_rando);
        feeSettings.removeCustomFee(someTokenAddress);
    }

    function testOwnerCanAddManager(address _manager) public {
        vm.assume(_manager != address(0));
        vm.assume(_manager != admin);

        assertEq(feeSettings.managers(_manager), false, "Should not be manager yet");

        vm.prank(admin);
        feeSettings.addManager(_manager);

        assertEq(feeSettings.managers(_manager), true, "Manager should be added");
    }

    function testRandoCanNotAddManager(address _rando) public {
        vm.assume(_rando != address(0));
        vm.assume(_rando != admin);

        vm.expectRevert("Ownable: caller is not the owner");
        vm.prank(_rando);
        feeSettings.addManager(_rando);
    }

    function testOwnerCanRemoveManager(address _manager) public {
        vm.assume(_manager != address(0));
        vm.assume(_manager != admin);

        vm.prank(admin);
        feeSettings.addManager(_manager);

        assertEq(feeSettings.managers(_manager), true, "Should be manager");

        vm.prank(admin);
        feeSettings.removeManager(_manager);

        assertEq(feeSettings.managers(_manager), false, "Manager should be removed");
    }

    function testRandoCanNotRemoveManager(address _rando) public {
        vm.assume(_rando != address(0));
        vm.assume(_rando != admin);

        vm.expectRevert("Ownable: caller is not the owner");
        vm.prank(_rando);
        feeSettings.removeManager(_rando);
    }

    function testFeeCalculationFunctionsAreEqual() public {
        Fees memory _fees = Fees(1, 100, 1, 50, 1, 20, 0);
        FeeSettings _feeSettings = FeeSettings(
            feeSettingsCloneFactory.createFeeSettingsClone(
                "salt",
                trustedForwarder,
                address(this),
                _fees,
                admin,
                admin,
                admin
            )
        );

        FakeToken fakeToken = new FakeToken(address(_feeSettings));
        FakeCrowdinvesting fakeCrowdinvesting = new FakeCrowdinvesting(address(fakeToken));

        uint256 amount = 1000e20;
        assertEq(_feeSettings.tokenFee(amount, address(fakeToken)), fakeToken.fee(amount), "Token fee mismatch");
        assertEq(
            _feeSettings.crowdinvestingFee(amount, address(fakeToken)),
            fakeCrowdinvesting.fee(amount),
            "Crowdinvesting fee mismatch"
        );
        assertEq(_feeSettings.privateOfferFee(amount, address(fakeToken)), amount / 20, "Private offer fee mismatch");
    }
}
