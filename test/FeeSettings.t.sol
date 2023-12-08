// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.23;

import "../lib/forge-std/src/Test.sol";
import "../contracts/Token.sol";
import "../contracts/factories/FeeSettingsCloneFactory.sol";

contract FeeSettingsTest is Test {
    uint32 constant MAX_TOKEN_FEE = 500;
    uint32 constant MAX_CROWDINVESTING_FEE = 1000;
    uint32 constant MAX_PRIVATE_OFFER_FEE = 500;

    event SetFee(uint32 tokenFeeNumerator, uint32 crowdinvestingFeeNumerator, uint32 privateOfferFeeNumerator);
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

    address public constant exampleTokenAddress = address(74);

    function setUp() public {
        FeeSettings logic = new FeeSettings(trustedForwarder);
        feeSettingsCloneFactory = new FeeSettingsCloneFactory(address(logic));

        fees = Fees(1, 2, 3, 0);
        vm.prank(admin);
        feeSettings = FeeSettings(
            feeSettingsCloneFactory.createFeeSettingsClone("salt", trustedForwarder, admin, fees, admin, admin, admin)
        );
    }

    function testLogicContractCannotBeInitialized() public {
        FeeSettings logic = new FeeSettings(trustedForwarder);
        vm.expectRevert("Initializable: contract is already initialized");
        logic.initialize(admin, fees, admin, admin, admin);

        assertEq(logic.owner(), address(0), "Owner should be 0");
    }

    function testEnforceFeeRangeInInitializer(uint32 numerator, uint32 denominator) public {
        vm.assume(denominator > 0);
        vm.assume(!tokenOrPrivateOfferFeeInValidRange(numerator));
        Fees memory _fees;

        console.log("Testing token fee");
        _fees = Fees(numerator, 1, 1, 0);
        vm.expectRevert("Token fee must be equal or less 5%");
        feeSettingsCloneFactory.createFeeSettingsClone("salt", trustedForwarder, admin, _fees, admin, admin, admin);

        console.log("Testing Crowdinvesting fee");
        _fees = Fees(1, numerator, 1, 0);
        if (!crowdinvestingFeeInValidRange(numerator)) {
            vm.expectRevert("Crowdinvesting fee must be equal or less 10%");
            feeSettingsCloneFactory.createFeeSettingsClone("salt", trustedForwarder, admin, _fees, admin, admin, admin);
        } else {
            // this should not revert, as the fee is in valid range for crowdinvesting
            feeSettingsCloneFactory.createFeeSettingsClone("salt", trustedForwarder, admin, _fees, admin, admin, admin);
        }

        console.log("Testing PrivateOffer fee");
        _fees = Fees(1, 1, numerator, 0);
        vm.expectRevert("PrivateOffer fee must be equal or less 5%");
        feeSettingsCloneFactory.createFeeSettingsClone("salt", trustedForwarder, admin, _fees, admin, admin, admin);
    }

    function testEnforceTokenFeeRangeInFeeChanger(uint32 numerator, uint32 denominator) public {
        vm.assume(denominator > 0);
        vm.assume(!tokenOrPrivateOfferFeeInValidRange(numerator));

        Fees memory feeChange = Fees(numerator, 1, 1, uint64(block.timestamp + 7884001));
        vm.expectRevert("Token fee must be equal or less 5%");
        vm.prank(admin);
        feeSettings.planFeeChange(feeChange);
    }

    function testEnforceCrowdinvestingFeeRangeInFeeChanger(uint32 numerator, uint32 denominator) public {
        vm.assume(denominator > 0);
        vm.assume(!crowdinvestingFeeInValidRange(numerator));

        Fees memory feeChange = Fees(1, numerator, 1, uint64(block.timestamp + 7884001));
        vm.expectRevert("Crowdinvesting fee must be equal or less 10%");
        vm.prank(admin);
        feeSettings.planFeeChange(feeChange);
    }

    function testEnforcePrivateOfferFeeRangeInFeeChanger(uint32 numerator, uint32 denominator) public {
        vm.assume(denominator > 0);
        vm.assume(!tokenOrPrivateOfferFeeInValidRange(numerator));

        Fees memory feeChange = Fees(1, 1, numerator, uint64(block.timestamp + 7884001));
        vm.expectRevert("PrivateOffer fee must be equal or less 5%");
        vm.prank(admin);
        feeSettings.planFeeChange(feeChange);
    }

    function testEnforceFeeChangeDelayOnIncrease(uint delay, uint32 startNumerator, uint32 newNumerator) public {
        vm.assume(delay <= 12 weeks);
        vm.assume(newNumerator <= MAX_PRIVATE_OFFER_FEE);
        vm.assume(newNumerator > startNumerator);
        Fees memory _fees = Fees(startNumerator, startNumerator, startNumerator, 0);
        FeeSettings _feeSettings = FeeSettings(
            feeSettingsCloneFactory.createFeeSettingsClone("salt", trustedForwarder, admin, _fees, admin, admin, admin)
        );

        Fees memory feeChange = Fees(newNumerator, 0, 0, uint64(block.timestamp + delay));
        vm.prank(admin);
        vm.expectRevert("Fee change must be at least 12 weeks in the future");
        _feeSettings.planFeeChange(feeChange);

        feeChange = Fees(0, newNumerator, 0, uint64(block.timestamp + delay));
        vm.prank(admin);
        vm.expectRevert("Fee change must be at least 12 weeks in the future");
        _feeSettings.planFeeChange(feeChange);

        feeChange = Fees(0, 0, newNumerator, uint64(block.timestamp + delay));
        vm.prank(admin);
        vm.expectRevert("Fee change must be at least 12 weeks in the future");
        _feeSettings.planFeeChange(feeChange);
    }

    function testExecuteFeeChangeTooEarly(
        uint delayAnnounced,
        uint32 tokenFeeNumerator,
        uint32 investmentFeeNumerator
    ) public {
        vm.assume(delayAnnounced > 12 weeks && delayAnnounced < 1000000000000);
        vm.assume(tokenOrPrivateOfferFeeInValidRange(tokenFeeNumerator));
        vm.assume(tokenOrPrivateOfferFeeInValidRange(investmentFeeNumerator));

        Fees memory feeChange = Fees(
            tokenFeeNumerator,
            investmentFeeNumerator,
            investmentFeeNumerator,
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
        uint32 tokenFeeNumerator,
        uint32 crowdinvestingFeeNumerator,
        uint32 privateOfferFeeNumerator
    ) public {
        vm.assume(delayAnnounced > 12 weeks && delayAnnounced < 100000000000);
        tokenFeeNumerator = tokenFeeNumerator % MAX_TOKEN_FEE;
        crowdinvestingFeeNumerator = crowdinvestingFeeNumerator % MAX_CROWDINVESTING_FEE;
        privateOfferFeeNumerator = privateOfferFeeNumerator % MAX_PRIVATE_OFFER_FEE;
        vm.assume(tokenFeeNumerator <= MAX_TOKEN_FEE);
        vm.assume(crowdinvestingFeeNumerator <= MAX_CROWDINVESTING_FEE);
        vm.assume(privateOfferFeeNumerator <= MAX_PRIVATE_OFFER_FEE);

        Fees memory feeChange = Fees(
            tokenFeeNumerator,
            crowdinvestingFeeNumerator,
            privateOfferFeeNumerator,
            uint64(block.timestamp + delayAnnounced)
        );
        vm.prank(admin);
        vm.expectEmit(true, true, true, true, address(feeSettings));
        emit ChangeProposed(feeChange);
        feeSettings.planFeeChange(feeChange);

        vm.prank(admin);
        vm.warp(uint64(block.timestamp + delayAnnounced) + 1);
        vm.expectEmit(true, true, true, true, address(feeSettings));
        emit SetFee(tokenFeeNumerator, crowdinvestingFeeNumerator, privateOfferFeeNumerator);
        feeSettings.executeFeeChange();

        (
            uint32 _tokenFeeNumerator,
            uint32 _crowdinvestingFeeNumerator,
            uint32 _privateOfferFeeNumerator,

        ) = feeSettings.fees(address(0));

        assertEq(_tokenFeeNumerator, tokenFeeNumerator);
        assertEq(_crowdinvestingFeeNumerator, crowdinvestingFeeNumerator);
        assertEq(_privateOfferFeeNumerator, privateOfferFeeNumerator);
    }

    function testSetFeeTo0Immediately() public {
        Fees memory feeChange = Fees(0, 0, 0, uint64(block.timestamp));

        (
            uint32 _tokenFeeNumerator,
            uint32 _crowdinvestingFeeNumerator,
            uint32 _privateOfferFeeNumerator,

        ) = feeSettings.fees(address(0));

        assertEq(_tokenFeeNumerator, 1);
        assertEq(_crowdinvestingFeeNumerator, 2);
        assertEq(_privateOfferFeeNumerator, 3);

        vm.prank(admin);
        feeSettings.planFeeChange(feeChange);

        vm.prank(admin);
        //vm.warp(uint64(block.timestamp + delayAnnounced) + 1);
        feeSettings.executeFeeChange();

        (_tokenFeeNumerator, _crowdinvestingFeeNumerator, _privateOfferFeeNumerator, ) = feeSettings.fees(address(0));

        assertEq(_tokenFeeNumerator, 0);
        assertEq(_crowdinvestingFeeNumerator, 0);
        assertEq(_privateOfferFeeNumerator, 0);

        (uint32 tokenFeeNumerator, , , uint64 time) = feeSettings.proposedDefaultFees();

        assertEq(tokenFeeNumerator, 0, "Token fee denominator mismatch");
        assertEq(time, 0, "Time mismatch");
    }

    function testSetFeeToXFrom0Immediately() public {
        Fees memory _fees = Fees(0, 0, 0, 0);
        vm.prank(admin);
        FeeSettings _feeSettings = FeeSettings(
            feeSettingsCloneFactory.createFeeSettingsClone("salt", trustedForwarder, admin, _fees, admin, admin, admin)
        );

        Fees memory feeChange = Fees(1, 1, 1, 0);

        (
            uint32 _tokenFeeNumerator,
            uint32 _crowdinvestingFeeNumerator,
            uint32 _privateOfferFeeNumerator,

        ) = _feeSettings.fees(address(0));

        assertEq(_tokenFeeNumerator, 0, "Token fee numerator mismatch");
        assertEq(_crowdinvestingFeeNumerator, 0, "Crowdinvesting fee numerator mismatch");
        assertEq(_privateOfferFeeNumerator, 0, "PrivateOffer fee numerator mismatch");

        vm.prank(admin);
        vm.expectRevert("Fee change must be at least 12 weeks in the future");
        _feeSettings.planFeeChange(feeChange);
    }

    function testReduceFeeImmediately(uint32 tokenFee, uint32 crowdinvestingFee, uint32 privateOfferFee) public {
        vm.assume(tokenFee <= MAX_TOKEN_FEE);
        vm.assume(crowdinvestingFee <= MAX_CROWDINVESTING_FEE);
        vm.assume(privateOfferFee <= MAX_PRIVATE_OFFER_FEE);

        // create new fee settings with max fee
        Fees memory maxFee = Fees(MAX_TOKEN_FEE, MAX_CROWDINVESTING_FEE, MAX_PRIVATE_OFFER_FEE, 0);
        feeSettings = FeeSettings(
            feeSettingsCloneFactory.createFeeSettingsClone("salt", trustedForwarder, admin, maxFee, admin, admin, admin)
        );

        (
            uint32 _tokenFeeNumerator,
            uint32 _crowdinvestingFeeNumerator,
            uint32 _privateOfferFeeNumerator,

        ) = feeSettings.fees(address(0));

        assertEq(_tokenFeeNumerator, MAX_TOKEN_FEE);
        assertEq(_crowdinvestingFeeNumerator, MAX_CROWDINVESTING_FEE);
        assertEq(_privateOfferFeeNumerator, MAX_PRIVATE_OFFER_FEE);

        // change fee to something lower
        Fees memory feeChange = Fees(tokenFee, crowdinvestingFee, privateOfferFee, 0);
        vm.prank(admin);
        feeSettings.planFeeChange(feeChange);

        vm.prank(admin);
        feeSettings.executeFeeChange();

        (_tokenFeeNumerator, _crowdinvestingFeeNumerator, _privateOfferFeeNumerator, ) = feeSettings.fees(address(0));

        assertEq(_tokenFeeNumerator, tokenFee);
        assertEq(_crowdinvestingFeeNumerator, crowdinvestingFee);
        assertEq(_privateOfferFeeNumerator, privateOfferFee);
    }

    function testSetFeeInInitializer(
        uint32 tokenFeeNumerator,
        uint32 crowdinvestingFeeNumerator,
        uint32 privateOfferFeeNumerator
    ) public {
        vm.assume(
            tokenFeeNumerator <= MAX_TOKEN_FEE &&
                crowdinvestingFeeNumerator <= MAX_CROWDINVESTING_FEE &&
                privateOfferFeeNumerator <= MAX_PRIVATE_OFFER_FEE
        );
        FeeSettings _feeSettings;
        Fees memory _fees = Fees(tokenFeeNumerator, crowdinvestingFeeNumerator, privateOfferFeeNumerator, 0);
        _feeSettings = FeeSettings(
            feeSettingsCloneFactory.createFeeSettingsClone("salt2", trustedForwarder, admin, _fees, admin, admin, admin)
        );

        (
            uint32 _tokenFeeNumerator,
            uint32 _crowdinvestingFeeNumerator,
            uint32 _privateOfferFeeNumerator,

        ) = _feeSettings.fees(address(0));

        assertEq(_tokenFeeNumerator, tokenFeeNumerator, "Token fee numerator mismatch");
        assertEq(_crowdinvestingFeeNumerator, crowdinvestingFeeNumerator, "Crowdinvesting fee numerator mismatch");
        assertEq(_privateOfferFeeNumerator, privateOfferFeeNumerator, "PrivateOffer fee numerator mismatch");
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
        assertEq(feeSettings.tokenFeeCollector(address(4)), newTokenFeeCollector);
        assertEq(feeSettings.crowdinvestingFeeCollector(address(4)), newCrowdinvestingFeeCollector);
        assertEq(feeSettings.privateOfferFeeCollector(address(4)), newPrivateOfferFeeCollector);
    }

    function tokenOrPrivateOfferFeeInValidRange(uint32 numerator) internal pure returns (bool) {
        return numerator <= 500;
    }

    function crowdinvestingFeeInValidRange(uint32 numerator) internal pure returns (bool) {
        return numerator <= 1000;
    }

    function testCalculateProperFees(
        uint32 tokenFeeNumerator,
        uint32 crowdinvestingFeeNumerator,
        uint32 privateOfferFeeNumerator,
        uint256 amount
    ) public {
        vm.assume(tokenFeeNumerator <= MAX_TOKEN_FEE);
        vm.assume(crowdinvestingFeeNumerator <= MAX_CROWDINVESTING_FEE);
        vm.assume(privateOfferFeeNumerator <= MAX_PRIVATE_OFFER_FEE);
        vm.assume(amount < UINT256_MAX / MAX_CROWDINVESTING_FEE);

        Fees memory _fees = Fees(tokenFeeNumerator, crowdinvestingFeeNumerator, privateOfferFeeNumerator, 0);
        FeeSettings _feeSettings = FeeSettings(
            feeSettingsCloneFactory.createFeeSettingsClone("salt5", trustedForwarder, admin, _fees, admin, admin, admin)
        );

        assertEq(
            _feeSettings.tokenFee(amount, address(0)),
            (amount * tokenFeeNumerator) / _feeSettings.FEE_DENOMINATOR(),
            "Token fee mismatch"
        );
        assertEq(
            _feeSettings.crowdinvestingFee(amount, address(0)),
            (amount * crowdinvestingFeeNumerator) / _feeSettings.FEE_DENOMINATOR(),
            "Investment fee mismatch"
        );
        assertEq(
            _feeSettings.privateOfferFee(amount, address(0)),
            (amount * privateOfferFeeNumerator) / _feeSettings.FEE_DENOMINATOR(),
            "Private offer fee mismatch"
        );
    }

    function testCalculate0FeesForAnyAmount(
        uint32 tokenFeeNumerator,
        uint32 crowdinvestingFeeNumerator,
        uint32 privateOfferFeeNumerator,
        uint256 amount
    ) public {
        vm.assume(tokenFeeNumerator <= MAX_TOKEN_FEE);
        vm.assume(crowdinvestingFeeNumerator <= MAX_CROWDINVESTING_FEE);
        vm.assume(privateOfferFeeNumerator <= MAX_PRIVATE_OFFER_FEE);
        vm.assume(amount < UINT256_MAX / MAX_CROWDINVESTING_FEE);

        // only token fee is 0

        Fees memory _fees = Fees(0, crowdinvestingFeeNumerator, privateOfferFeeNumerator, 0);
        FeeSettings _feeSettings = FeeSettings(
            feeSettingsCloneFactory.createFeeSettingsClone("salt4", trustedForwarder, admin, _fees, admin, admin, admin)
        );

        assertEq(_feeSettings.tokenFee(amount, address(0)), 0, "Token fee mismatch");
        assertEq(
            _feeSettings.crowdinvestingFee(amount, address(0)),
            (amount * crowdinvestingFeeNumerator) / _feeSettings.FEE_DENOMINATOR(),
            "Investment fee mismatch"
        );
        assertEq(
            _feeSettings.privateOfferFee(amount, address(0)),
            (amount * privateOfferFeeNumerator) / _feeSettings.FEE_DENOMINATOR(),
            "Private offer fee mismatch"
        );

        // only crowdinvesting fee is 0

        _fees = Fees(tokenFeeNumerator, 0, privateOfferFeeNumerator, 0);
        _feeSettings = FeeSettings(
            feeSettingsCloneFactory.createFeeSettingsClone("salt3", trustedForwarder, admin, _fees, admin, admin, admin)
        );
        assertEq(
            _feeSettings.tokenFee(amount, address(0)),
            (amount * tokenFeeNumerator) / _feeSettings.FEE_DENOMINATOR(),
            "Token fee mismatch"
        );
        assertEq(_feeSettings.crowdinvestingFee(amount, address(0)), 0, "Investment fee mismatch");
        assertEq(
            _feeSettings.privateOfferFee(amount, address(0)),
            (amount * privateOfferFeeNumerator) / _feeSettings.FEE_DENOMINATOR(),
            "Private offer fee mismatch"
        );

        // only private offer fee is 0

        _fees = Fees(tokenFeeNumerator, crowdinvestingFeeNumerator, 0, 0);
        _feeSettings = FeeSettings(
            feeSettingsCloneFactory.createFeeSettingsClone("salt2", trustedForwarder, admin, _fees, admin, admin, admin)
        );
        assertEq(
            _feeSettings.tokenFee(amount, address(0)),
            (amount * tokenFeeNumerator) / _feeSettings.FEE_DENOMINATOR(),
            "Token fee mismatch"
        );
        assertEq(
            _feeSettings.crowdinvestingFee(amount, address(0)),
            (amount * crowdinvestingFeeNumerator) / _feeSettings.FEE_DENOMINATOR(),
            "Investment fee mismatch"
        );
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

        assertEq(
            feeSettings.continuousFundraisingFee(_amount),
            feeSettings.crowdinvestingFee(_amount, address(0)),
            "Crowdinvesting Fee mismatch"
        );

        assertEq(
            feeSettings.privateOfferFee(_amount, address(0)),
            feeSettings.personalInviteFee(_amount),
            "Private offer fee mismatch"
        );
        assertEq(feeSettings.feeCollector(), feeSettings.tokenFeeCollector(address(0)), "Fee collector mismatch");
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

    function testAddingCustomFees(address _someTokenAddress) public {
        vm.assume(_someTokenAddress != address(0));

        Fees memory _fees = Fees(11, 22, 55, 0);
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
            uint32 crowdinvestingFeeNumerator,
            uint32 privateOfferFeeNumerator,
            uint64 endTime
        ) = _feeSettings.fees(_someTokenAddress);
        assertEq(tokenFeeNumerator, 0, "Token fee numerator should be 0");
        assertEq(crowdinvestingFeeNumerator, 0, "Crowdinvesting fee numerator should be 0");
        assertEq(privateOfferFeeNumerator, 0, "Private offer fee numerator should be 0");
        assertEq(endTime, 0, "End time should be 0");

        // check the token fee, private offer fee and crowdinvesting fee are as expected
        assertEq(_feeSettings.tokenFee(10000, _someTokenAddress), 11, "Token fee should be 11");
        assertEq(_feeSettings.crowdinvestingFee(10000, _someTokenAddress), 22, "Crowdinvesting fee should be 22");
        assertEq(_feeSettings.privateOfferFee(10000, _someTokenAddress), 55, "Private offer fee should be 55");

        // add custom fee entry for this token address
        uint256 realEndTime = block.timestamp + 100;
        _fees = Fees(3, 4, 2, uint64(realEndTime));
        _feeSettings.setCustomFee(_someTokenAddress, _fees);

        // check the token fee, private offer fee and crowdinvesting fee change as expected
        assertEq(_feeSettings.tokenFee(10000, _someTokenAddress), 3, "Token fee should be 3 now");
        assertEq(_feeSettings.crowdinvestingFee(10000, _someTokenAddress), 4, "Crowdinvesting fee should be 4 now");
        assertEq(_feeSettings.privateOfferFee(10000, _someTokenAddress), 2, "Private offer fee should be 2 now");

        // check the custom fee entry is as expected
        (tokenFeeNumerator, crowdinvestingFeeNumerator, privateOfferFeeNumerator, endTime) = _feeSettings.fees(
            _someTokenAddress
        );
        assertEq(tokenFeeNumerator, 3, "Token fee numerator should be 3");
        assertEq(crowdinvestingFeeNumerator, 4, "Crowdinvesting fee numerator should be 4");
        assertEq(privateOfferFeeNumerator, 2, "Private offer fee numerator should be 2");
        assertEq(endTime, realEndTime, "End time should match");

        // check that the custom fee is not applied after the end time
        vm.warp(realEndTime + 1);
        assertEq(_feeSettings.tokenFee(10000, _someTokenAddress), 11, "Token fee should be 11 again");
        assertEq(_feeSettings.crowdinvestingFee(10000, _someTokenAddress), 22, "Crowdinvesting fee should be 22 again");
        assertEq(_feeSettings.privateOfferFee(10000, _someTokenAddress), 55, "Private offer fee should be 55 again");
    }

    function testOnlyManagerCanAddCustomFees(address _rando) public {
        address someTokenAddress = address(74);
        vm.assume(_rando != address(0));
        vm.assume(_rando != admin);

        Fees memory _fees = Fees(1, 1, 1, 0);

        vm.expectRevert("Only managers can call this function");
        vm.prank(_rando);
        feeSettings.setCustomFee(someTokenAddress, _fees);
    }

    function testCustomFeesAreNotAppliedToOtherTokens(address _someTokenAddress, address _otherTokenAddress) public {
        vm.assume(_someTokenAddress != address(0));
        vm.assume(_otherTokenAddress != address(0));
        vm.assume(_someTokenAddress != _otherTokenAddress);

        Fees memory _fees = Fees(10, 20, 50, 0);
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
        _fees = Fees(3, 4, 2, uint64(block.timestamp + 100));
        _feeSettings.setCustomFee(_someTokenAddress, _fees);

        // check the token fee, private offer fee and crowdinvesting fee are as expected
        assertEq(_feeSettings.tokenFee(10000, _otherTokenAddress), 10, "Token fee should be 10");
        assertEq(_feeSettings.crowdinvestingFee(10000, _otherTokenAddress), 20, "Crowdinvesting fee should be 20");
        assertEq(_feeSettings.privateOfferFee(10000, _otherTokenAddress), 50, "Private offer fee should be 50");
    }

    function testCustomFeesDoNotIncreaseFee() public {
        address someTokenAddress = address(74);
        Fees memory _fees = Fees(0, 0, 0, 0);
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
        _fees = Fees(1, 1, 1, uint64(block.timestamp + 100));
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
        Fees memory _fees = Fees(10, 20, 50, 0);
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
        _fees = Fees(3, 4, 2, uint64(block.timestamp + 100));
        _feeSettings.setCustomFee(someTokenAddress, _fees);

        // check the token fee, private offer fee and crowdinvesting fee are as expected
        assertEq(_feeSettings.tokenFee(10000, someTokenAddress), 3, "Token fee should be 3");
        assertEq(_feeSettings.crowdinvestingFee(10000, someTokenAddress), 4, "Crowdinvesting fee should be 4");
        assertEq(_feeSettings.privateOfferFee(10000, someTokenAddress), 2, "Private offer fee should be 2");

        // remove custom fee entry for this token address
        _feeSettings.removeCustomFee(someTokenAddress);

        // check the token fee, private offer fee and crowdinvesting fee are as expected
        assertEq(_feeSettings.tokenFee(10000, someTokenAddress), 10, "Token fee should be 10");
        assertEq(_feeSettings.crowdinvestingFee(10000, someTokenAddress), 20, "Crowdinvesting fee should be 20");
        assertEq(_feeSettings.privateOfferFee(10000, someTokenAddress), 50, "Private offer fee should be 50");
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
        vm.assume(_manager != trustedForwarder);
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
        vm.assume(_manager != trustedForwarder);
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

    function testAddingCustomTokenFeeCollector(address _feeCollector) public {
        vm.assume(_feeCollector != address(0));
        vm.assume(_feeCollector != admin);

        assertEq(
            feeSettings.customTokenFeeCollector(exampleTokenAddress),
            address(0),
            "Should not be custom fee collector yet"
        );

        assertEq(
            feeSettings.tokenFeeCollector(exampleTokenAddress),
            feeSettings.feeCollector(),
            "Fee collector mismatch between V1 and V2"
        );
        assertEq(feeSettings.tokenFeeCollector(exampleTokenAddress), admin, "Fee collector not admin address");

        vm.prank(admin);
        feeSettings.setCustomTokenFeeCollector(exampleTokenAddress, _feeCollector);

        assertEq(feeSettings.customTokenFeeCollector(exampleTokenAddress), _feeCollector, "Custom fee collector wrong");
        assertEq(
            feeSettings.tokenFeeCollector(exampleTokenAddress),
            _feeCollector,
            "Fee collector wrong with custom fee collector"
        );
        assertEq(admin, feeSettings.feeCollector(), "V1 fee collector should still be default value");
    }

    function testRemovingCustomTokenFeeCollector(address _feeCollector) public {
        vm.assume(_feeCollector != address(0));
        vm.assume(_feeCollector != admin);

        vm.prank(admin);
        feeSettings.setCustomTokenFeeCollector(exampleTokenAddress, _feeCollector);

        assertEq(
            feeSettings.tokenFeeCollector(exampleTokenAddress),
            _feeCollector,
            "Fee collector wrong with custom fee collector"
        );

        vm.prank(admin);
        feeSettings.removeCustomTokenFeeCollector(exampleTokenAddress);

        assertEq(
            feeSettings.customTokenFeeCollector(exampleTokenAddress),
            address(0),
            "Should not be custom fee collector yet"
        );

        assertEq(
            feeSettings.tokenFeeCollector(exampleTokenAddress),
            feeSettings.feeCollector(),
            "Fee collector mismatch between V1 and V2"
        );
        assertEq(feeSettings.tokenFeeCollector(exampleTokenAddress), admin, "Fee collector not admin address");
    }

    function testAddingCustomCrowdinvestingFeeCollector(address _feeCollector) public {
        vm.assume(_feeCollector != address(0));
        vm.assume(_feeCollector != admin);

        assertEq(
            feeSettings.customCrowdinvestingFeeCollector(exampleTokenAddress),
            address(0),
            "Should not be custom fee collector yet"
        );

        assertEq(feeSettings.crowdinvestingFeeCollector(exampleTokenAddress), admin, "Fee collector not admin address");

        vm.prank(admin);
        feeSettings.setCustomCrowdinvestingFeeCollector(exampleTokenAddress, _feeCollector);

        assertEq(
            feeSettings.customCrowdinvestingFeeCollector(exampleTokenAddress),
            _feeCollector,
            "Custom fee collector wrong"
        );
        assertEq(
            feeSettings.crowdinvestingFeeCollector(exampleTokenAddress),
            _feeCollector,
            "Fee collector wrong with custom fee collector"
        );
    }

    function testRemovingCustomCrowdinvestingFeeCollector(address _feeCollector) public {
        vm.assume(_feeCollector != address(0));
        vm.assume(_feeCollector != admin);

        vm.prank(admin);
        feeSettings.setCustomCrowdinvestingFeeCollector(exampleTokenAddress, _feeCollector);

        assertEq(
            feeSettings.crowdinvestingFeeCollector(exampleTokenAddress),
            _feeCollector,
            "Fee collector wrong with custom fee collector"
        );

        vm.prank(admin);
        feeSettings.removeCustomCrowdinvestingFeeCollector(exampleTokenAddress);

        assertEq(
            feeSettings.customCrowdinvestingFeeCollector(exampleTokenAddress),
            address(0),
            "Should not be custom fee collector yet"
        );

        assertEq(feeSettings.crowdinvestingFeeCollector(exampleTokenAddress), admin, "Fee collector not admin address");
    }

    function testAddingCustomPrivateOfferFeeCollector(address _feeCollector) public {
        vm.assume(_feeCollector != address(0));
        vm.assume(_feeCollector != admin);

        assertEq(
            feeSettings.customPrivateOfferFeeCollector(exampleTokenAddress),
            address(0),
            "Should not be custom fee collector yet"
        );

        assertEq(feeSettings.privateOfferFeeCollector(exampleTokenAddress), admin, "Fee collector not admin address");

        vm.prank(admin);
        feeSettings.setCustomPrivateOfferFeeCollector(exampleTokenAddress, _feeCollector);

        assertEq(
            feeSettings.customPrivateOfferFeeCollector(exampleTokenAddress),
            _feeCollector,
            "Custom fee collector wrong"
        );
        assertEq(
            feeSettings.privateOfferFeeCollector(exampleTokenAddress),
            _feeCollector,
            "Fee collector wrong with custom fee collector"
        );
    }

    function testRemovingCustomPrivateOfferFeeCollector(address _feeCollector) public {
        vm.assume(_feeCollector != address(0));
        vm.assume(_feeCollector != admin);

        vm.prank(admin);
        feeSettings.setCustomPrivateOfferFeeCollector(exampleTokenAddress, _feeCollector);

        assertEq(
            feeSettings.privateOfferFeeCollector(exampleTokenAddress),
            _feeCollector,
            "Fee collector wrong with custom fee collector"
        );

        vm.prank(admin);
        feeSettings.removeCustomPrivateOfferFeeCollector(exampleTokenAddress);

        assertEq(
            feeSettings.customPrivateOfferFeeCollector(exampleTokenAddress),
            address(0),
            "Should not be custom fee collector yet"
        );

        assertEq(feeSettings.privateOfferFeeCollector(exampleTokenAddress), admin, "Fee collector not admin address");
    }

    function testManagerCanSetAndRemoveCustomFeeCollector(address _manager, address _customFeeCollector) public {
        vm.assume(_manager != address(0));
        vm.assume(_manager != trustedForwarder);
        vm.assume(_manager != admin);
        vm.assume(_customFeeCollector != address(0));
        vm.assume(_customFeeCollector != admin);

        vm.prank(admin);
        feeSettings.addManager(_manager);

        assertEq(
            feeSettings.customTokenFeeCollector(exampleTokenAddress),
            address(0),
            "Should not be custom fee collector yet"
        );
        assertEq(
            feeSettings.customCrowdinvestingFeeCollector(exampleTokenAddress),
            address(0),
            "Should not be custom fee collector yet"
        );
        assertEq(
            feeSettings.customPrivateOfferFeeCollector(exampleTokenAddress),
            address(0),
            "Should not be custom fee collector yet"
        );

        vm.startPrank(_manager);
        feeSettings.setCustomTokenFeeCollector(exampleTokenAddress, _customFeeCollector);
        feeSettings.setCustomCrowdinvestingFeeCollector(exampleTokenAddress, _customFeeCollector);
        feeSettings.setCustomPrivateOfferFeeCollector(exampleTokenAddress, _customFeeCollector);
        vm.stopPrank();

        assertEq(
            feeSettings.customTokenFeeCollector(exampleTokenAddress),
            _customFeeCollector,
            "Custom fee collector wrong"
        );
        assertEq(
            feeSettings.customCrowdinvestingFeeCollector(exampleTokenAddress),
            _customFeeCollector,
            "Custom fee collector wrong"
        );
        assertEq(
            feeSettings.customPrivateOfferFeeCollector(exampleTokenAddress),
            _customFeeCollector,
            "Custom fee collector wrong"
        );

        vm.startPrank(_manager);
        feeSettings.removeCustomTokenFeeCollector(exampleTokenAddress);
        feeSettings.removeCustomCrowdinvestingFeeCollector(exampleTokenAddress);
        feeSettings.removeCustomPrivateOfferFeeCollector(exampleTokenAddress);
        vm.stopPrank();

        assertEq(
            feeSettings.customTokenFeeCollector(exampleTokenAddress),
            address(0),
            "Should not be custom fee collector yet"
        );
        assertEq(
            feeSettings.customCrowdinvestingFeeCollector(exampleTokenAddress),
            address(0),
            "Should not be custom fee collector yet"
        );
        assertEq(
            feeSettings.customPrivateOfferFeeCollector(exampleTokenAddress),
            address(0),
            "Should not be custom fee collector yet"
        );
    }

    function testRandoCanNotSetOrRemoveCustomFeeCollectors(address _rando, address _customFeeCollector) public {
        vm.assume(_rando != address(0));
        vm.assume(_rando != admin);
        vm.assume(_customFeeCollector != address(0));
        vm.assume(_customFeeCollector != admin);

        vm.expectRevert("Only managers can call this function");
        vm.prank(_rando);
        feeSettings.setCustomTokenFeeCollector(exampleTokenAddress, _customFeeCollector);

        vm.expectRevert("Only managers can call this function");
        vm.prank(_rando);
        feeSettings.setCustomCrowdinvestingFeeCollector(exampleTokenAddress, _customFeeCollector);

        vm.expectRevert("Only managers can call this function");
        vm.prank(_rando);
        feeSettings.setCustomPrivateOfferFeeCollector(exampleTokenAddress, _customFeeCollector);

        vm.expectRevert("Only managers can call this function");
        vm.prank(_rando);
        feeSettings.removeCustomTokenFeeCollector(exampleTokenAddress);

        vm.expectRevert("Only managers can call this function");
        vm.prank(_rando);
        feeSettings.removeCustomCrowdinvestingFeeCollector(exampleTokenAddress);

        vm.expectRevert("Only managers can call this function");
        vm.prank(_rando);
        feeSettings.removeCustomPrivateOfferFeeCollector(exampleTokenAddress);
    }

    function testSettingCustomFeeCollectorFor0AddressReverts() public {
        vm.expectRevert("Fee collector cannot be 0x0");
        vm.prank(admin);
        feeSettings.setCustomTokenFeeCollector(exampleTokenAddress, address(0));

        vm.expectRevert("Fee collector cannot be 0x0");
        vm.prank(admin);
        feeSettings.setCustomCrowdinvestingFeeCollector(exampleTokenAddress, address(0));

        vm.expectRevert("Fee collector cannot be 0x0");
        vm.prank(admin);
        feeSettings.setCustomPrivateOfferFeeCollector(exampleTokenAddress, address(0));
    }

    function testSettingCustomFeesFor0AddressReverts() public {
        vm.expectRevert("Token cannot be 0x0");
        vm.prank(admin);
        feeSettings.setCustomFee(address(0), Fees(1, 1, 1, 0));
    }

    function testCustomFeeCollectorsOnlyApplyToSpecifiedAddress(address specifiedAddress, address someAddress) public {
        vm.assume(specifiedAddress != address(0));
        vm.assume(specifiedAddress != someAddress);

        address customFeeCollector = address(75);
        assertTrue(customFeeCollector != admin);

        vm.startPrank(admin);

        // check token fee collector
        feeSettings.setCustomTokenFeeCollector(specifiedAddress, customFeeCollector);
        assertEq(
            feeSettings.tokenFeeCollector(specifiedAddress),
            customFeeCollector,
            "Token fee collector wrong for specifiedAddress"
        );
        assertEq(
            feeSettings.crowdinvestingFeeCollector(specifiedAddress),
            admin,
            "Crowdinvesting fee collector wrong for specifiedAddress"
        );
        assertEq(
            feeSettings.privateOfferFeeCollector(specifiedAddress),
            admin,
            "Token fee collector wrong for specifiedAddress"
        );

        assertEq(feeSettings.tokenFeeCollector(someAddress), admin, "Token fee collector wrong");
        assertEq(feeSettings.crowdinvestingFeeCollector(someAddress), admin, "Crowdinvesting fee collector wrong");
        assertEq(feeSettings.privateOfferFeeCollector(someAddress), admin, "Private offer fee collector wrong");

        feeSettings.removeCustomTokenFeeCollector(specifiedAddress);

        // test crowdinvesting fee collector
        feeSettings.setCustomCrowdinvestingFeeCollector(specifiedAddress, customFeeCollector);
        assertEq(
            feeSettings.tokenFeeCollector(specifiedAddress),
            admin,
            "Token fee collector wrong for specifiedAddress"
        );
        assertEq(
            feeSettings.crowdinvestingFeeCollector(specifiedAddress),
            customFeeCollector,
            "Crowdinvesting fee collector wrong for specifiedAddress"
        );
        assertEq(
            feeSettings.privateOfferFeeCollector(specifiedAddress),
            admin,
            "Token fee collector wrong for specifiedAddress"
        );

        assertEq(feeSettings.tokenFeeCollector(someAddress), admin, "Token fee collector wrong");
        assertEq(feeSettings.crowdinvestingFeeCollector(someAddress), admin, "Crowdinvesting fee collector wrong");
        assertEq(feeSettings.privateOfferFeeCollector(someAddress), admin, "Private offer fee collector wrong");

        feeSettings.removeCustomCrowdinvestingFeeCollector(specifiedAddress);

        // test private offer fee collector
        feeSettings.setCustomPrivateOfferFeeCollector(specifiedAddress, customFeeCollector);
        assertEq(
            feeSettings.tokenFeeCollector(specifiedAddress),
            admin,
            "Token fee collector wrong for specifiedAddress"
        );
        assertEq(
            feeSettings.crowdinvestingFeeCollector(specifiedAddress),
            admin,
            "Crowdinvesting fee collector wrong for specifiedAddress"
        );
        assertEq(
            feeSettings.privateOfferFeeCollector(specifiedAddress),
            customFeeCollector,
            "Token fee collector wrong for specifiedAddress"
        );

        assertEq(feeSettings.tokenFeeCollector(someAddress), admin, "Token fee collector wrong");
        assertEq(feeSettings.crowdinvestingFeeCollector(someAddress), admin, "Crowdinvesting fee collector wrong");
        assertEq(feeSettings.privateOfferFeeCollector(someAddress), admin, "Private offer fee collector wrong");
    }

    function testRemovingCustomFeeFor0AddressReverts() public {
        vm.expectRevert("Token cannot be 0x0");
        vm.prank(admin);
        feeSettings.removeCustomFee(address(0));
    }

    function testRemovingCustomFeeCollectorsFor0AddressReverts() public {
        vm.expectRevert("Token cannot be 0x0");
        vm.prank(admin);
        feeSettings.removeCustomTokenFeeCollector(address(0));

        vm.expectRevert("Token cannot be 0x0");
        vm.prank(admin);
        feeSettings.removeCustomCrowdinvestingFeeCollector(address(0));

        vm.expectRevert("Token cannot be 0x0");
        vm.prank(admin);
        feeSettings.removeCustomPrivateOfferFeeCollector(address(0));
    }
}
