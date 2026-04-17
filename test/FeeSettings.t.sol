// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.23;

import "../lib/forge-std/src/Test.sol";
import "../lib/forge-std/src/console.sol";
import "../contracts/Token.sol";
import "../contracts/factories/FeeSettingsCloneFactory.sol";
import "../contracts/common/IFeeSettings.sol";
import "./resources/CloneCreators.sol";

contract FeeSettingsTest is Test {
    uint32 constant MAX_TOKEN = 500;
    uint32 constant MAX_CROWDINVESTING = 1000;
    uint32 constant MAX_PRIVATE_OFFER = 500;

    event SetFee(uint32 tokenFeeNumerator, uint32 crowdinvestingFeeNumerator, uint32 privateOfferFeeNumerator);
    event FeeCollectorsChanged(
        address indexed newTokenFeeCollector,
        address indexed newCrowdinvestingFeeCollector,
        address indexed newPrivateOfferFeeCollector
    );
    event ManagerAdded(address indexed manager);
    event ManagerRemoved(address indexed manager);

    FeeSettings feeSettings;
    FeeSettingsCloneFactory feeSettingsCloneFactory;
    Token token;
    Token currency;

    uint256 MAX_INT = type(uint256).max;

    address public constant ADMIN = 0x0109709eCFa91a80626FF3989D68f67f5b1dD120;
    address public constant BUYER = 0x1109709ecFA91a80626ff3989D68f67F5B1Dd121;
    address public constant MINT_ALLOWER = 0x2109709EcFa91a80626Ff3989d68F67F5B1Dd122;
    address public constant MINTER = 0x3109709ECfA91A80626fF3989D68f67F5B1Dd123;
    address public constant OWNER = 0x6109709EcFA91A80626FF3989d68f67F5b1dd126;
    address public constant RECEIVER = 0x7109709eCfa91A80626Ff3989D68f67f5b1dD127;
    address public constant PAYMENT_TOKEN_PROVIDER = 0x8109709ecfa91a80626fF3989d68f67F5B1dD128;
    address public constant TRUSTED_FORWARDER = 0x9109709EcFA91A80626FF3989D68f67F5B1dD129;

    uint256 public constant PRICE = 10000000;

    address public constant EXAMPLE_TOKEN_ADDRESS = address(74);

    function _buildFeeTypes(address collector) internal pure returns (FeeSettings.FeeTypeInit[] memory) {
        FeeSettings.FeeTypeInit[] memory feeTypes = new FeeSettings.FeeTypeInit[](6);
        feeTypes[0] = FeeSettings.FeeTypeInit(FeeTypes.TOKEN, 500, 1, collector);
        feeTypes[1] = FeeSettings.FeeTypeInit(FeeTypes.CROWDINVESTING, 1000, 2, collector);
        feeTypes[2] = FeeSettings.FeeTypeInit(FeeTypes.PRIVATE_OFFER, 500, 3, collector);
        feeTypes[3] = FeeSettings.FeeTypeInit(FeeTypes.SECONDARY_MARKET, 500, 0, collector);
        feeTypes[4] = FeeSettings.FeeTypeInit(FeeTypes.DISTRIBUTION, 500, 0, collector);
        feeTypes[5] = FeeSettings.FeeTypeInit(FeeTypes.EXIT, 500, 0, collector);
        return feeTypes;
    }

    function setUp() public {
        FeeSettings logic = new FeeSettings(TRUSTED_FORWARDER);
        feeSettingsCloneFactory = new FeeSettingsCloneFactory(address(logic));

        vm.prank(ADMIN);
        feeSettings = FeeSettings(
            feeSettingsCloneFactory.createFeeSettingsClone("salt", TRUSTED_FORWARDER, ADMIN, _buildFeeTypes(ADMIN))
        );
    }

    function testLogicContractCannotBeInitialized() public {
        FeeSettings logic = new FeeSettings(TRUSTED_FORWARDER);
        vm.expectRevert("Initializable: contract is already initialized");
        logic.initialize(ADMIN, _buildFeeTypes(ADMIN));

        assertEq(logic.owner(), address(0), "Owner should be 0");
    }

    function testEnforceFeeRangeInInitializer(uint32 numerator, uint32 denominator) public {
        vm.assume(denominator > 0);
        vm.assume(!tokenOrPrivateOfferFeeInValidRange(numerator));

        console.log("Testing token fee");
        {
            FeeSettings.FeeTypeInit[] memory feeType = new FeeSettings.FeeTypeInit[](1);
            feeType[0] = FeeSettings.FeeTypeInit(FeeTypes.TOKEN, 500, numerator, ADMIN);
            vm.expectRevert("default exceeds max");
            feeSettingsCloneFactory.createFeeSettingsClone("salt", TRUSTED_FORWARDER, ADMIN, feeType);
        }

        console.log("Testing Crowdinvesting fee");
        {
            FeeSettings.FeeTypeInit[] memory feeType = new FeeSettings.FeeTypeInit[](1);
            feeType[0] = FeeSettings.FeeTypeInit(FeeTypes.CROWDINVESTING, 1000, numerator, ADMIN);
            if (!crowdinvestingFeeInValidRange(numerator)) {
                vm.expectRevert("default exceeds max");
                feeSettingsCloneFactory.createFeeSettingsClone("salt", TRUSTED_FORWARDER, ADMIN, feeType);
            } else {
                // this should not revert, as the fee is in valid range for crowdinvesting
                feeSettingsCloneFactory.createFeeSettingsClone("salt", TRUSTED_FORWARDER, ADMIN, feeType);
            }
        }

        console.log("Testing PrivateOffer fee");
        {
            FeeSettings.FeeTypeInit[] memory feeType = new FeeSettings.FeeTypeInit[](1);
            feeType[0] = FeeSettings.FeeTypeInit(FeeTypes.PRIVATE_OFFER, 500, numerator, ADMIN);
            vm.expectRevert("default exceeds max");
            feeSettingsCloneFactory.createFeeSettingsClone("salt", TRUSTED_FORWARDER, ADMIN, feeType);
        }
    }

    function testEnforceTokenFeeRangeInFeeChanger(uint32 numerator, uint32 denominator) public {
        vm.assume(denominator > 0);
        vm.assume(!tokenOrPrivateOfferFeeInValidRange(numerator));

        vm.expectRevert("exceeds max numerator");
        vm.prank(ADMIN);
        feeSettings.planFeeChange(FeeTypes.TOKEN, numerator, uint64(block.timestamp + 7884001));
    }

    function testEnforceCrowdinvestingFeeRangeInFeeChanger(uint32 numerator, uint32 denominator) public {
        vm.assume(denominator > 0);
        vm.assume(!crowdinvestingFeeInValidRange(numerator));

        vm.expectRevert("exceeds max numerator");
        vm.prank(ADMIN);
        feeSettings.planFeeChange(FeeTypes.CROWDINVESTING, numerator, uint64(block.timestamp + 7884001));
    }

    function testEnforcePrivateOfferFeeRangeInFeeChanger(uint32 numerator, uint32 denominator) public {
        vm.assume(denominator > 0);
        vm.assume(!tokenOrPrivateOfferFeeInValidRange(numerator));

        vm.expectRevert("exceeds max numerator");
        vm.prank(ADMIN);
        feeSettings.planFeeChange(FeeTypes.PRIVATE_OFFER, numerator, uint64(block.timestamp + 7884001));
    }

    function testEnforceFeeChangeDelayOnIncrease(uint delay, uint32 startNumerator, uint32 newNumerator) public {
        vm.assume(delay <= 12 weeks);
        vm.assume(newNumerator <= MAX_PRIVATE_OFFER);
        vm.assume(newNumerator > startNumerator);
        FeeSettings _feeSettings = FeeSettings(
            feeSettingsCloneFactory.createFeeSettingsClone(
                "salt",
                TRUSTED_FORWARDER,
                ADMIN,
                buildFeeTypes(startNumerator, startNumerator, startNumerator, ADMIN, ADMIN, ADMIN)
            )
        );

        vm.prank(ADMIN);
        vm.expectRevert("fee increase needs 12 week delay");
        _feeSettings.planFeeChange(FeeTypes.TOKEN, newNumerator, uint64(block.timestamp + delay));

        vm.prank(ADMIN);
        vm.expectRevert("fee increase needs 12 week delay");
        _feeSettings.planFeeChange(FeeTypes.CROWDINVESTING, newNumerator, uint64(block.timestamp + delay));

        vm.prank(ADMIN);
        vm.expectRevert("fee increase needs 12 week delay");
        _feeSettings.planFeeChange(FeeTypes.PRIVATE_OFFER, newNumerator, uint64(block.timestamp + delay));
    }

    function testExecuteFeeChangeTooEarly(
        uint delayAnnounced,
        uint32 tokenFeeNumerator,
        uint32 investmentFeeNumerator
    ) public {
        vm.assume(delayAnnounced > 12 weeks && delayAnnounced < 1000000000000);
        vm.assume(tokenOrPrivateOfferFeeInValidRange(tokenFeeNumerator));
        vm.assume(tokenOrPrivateOfferFeeInValidRange(investmentFeeNumerator));

        uint64 activationDate = uint64(block.timestamp + delayAnnounced);
        vm.prank(ADMIN);
        feeSettings.planFeeChange(FeeTypes.TOKEN, tokenFeeNumerator, activationDate);
        vm.prank(ADMIN);
        feeSettings.planFeeChange(FeeTypes.CROWDINVESTING, investmentFeeNumerator, activationDate);
        vm.prank(ADMIN);
        feeSettings.planFeeChange(FeeTypes.PRIVATE_OFFER, investmentFeeNumerator, activationDate);

        vm.prank(ADMIN);
        vm.expectRevert("activation date not reached");
        vm.warp(activationDate - 1);
        feeSettings.executeFeeChange(FeeTypes.TOKEN);
    }

    function testExecuteFeeChangeProperly(
        uint delayAnnounced,
        uint32 tokenFeeNumerator,
        uint32 crowdinvestingFeeNumerator,
        uint32 privateOfferFeeNumerator
    ) public {
        vm.assume(delayAnnounced > 12 weeks && delayAnnounced < 100000000000);
        tokenFeeNumerator = tokenFeeNumerator % MAX_TOKEN;
        crowdinvestingFeeNumerator = crowdinvestingFeeNumerator % MAX_CROWDINVESTING;
        privateOfferFeeNumerator = privateOfferFeeNumerator % MAX_PRIVATE_OFFER;
        vm.assume(tokenFeeNumerator <= MAX_TOKEN);
        vm.assume(crowdinvestingFeeNumerator <= MAX_CROWDINVESTING);
        vm.assume(privateOfferFeeNumerator <= MAX_PRIVATE_OFFER);

        uint64 activationDate = uint64(block.timestamp + delayAnnounced);
        vm.prank(ADMIN);
        feeSettings.planFeeChange(FeeTypes.TOKEN, tokenFeeNumerator, activationDate);
        vm.prank(ADMIN);
        feeSettings.planFeeChange(FeeTypes.CROWDINVESTING, crowdinvestingFeeNumerator, activationDate);
        vm.prank(ADMIN);
        feeSettings.planFeeChange(FeeTypes.PRIVATE_OFFER, privateOfferFeeNumerator, activationDate);

        vm.prank(ADMIN);
        vm.warp(activationDate + 1);
        feeSettings.executeFeeChange(FeeTypes.TOKEN);
        vm.prank(ADMIN);
        feeSettings.executeFeeChange(FeeTypes.CROWDINVESTING);
        vm.prank(ADMIN);
        feeSettings.executeFeeChange(FeeTypes.PRIVATE_OFFER);

        (, uint32 _tokenFeeNumerator) = feeSettings.feeTypeConfigs(FeeTypes.TOKEN);
        (, uint32 _crowdinvestingFeeNumerator) = feeSettings.feeTypeConfigs(FeeTypes.CROWDINVESTING);
        (, uint32 _privateOfferFeeNumerator) = feeSettings.feeTypeConfigs(FeeTypes.PRIVATE_OFFER);

        assertEq(_tokenFeeNumerator, tokenFeeNumerator);
        assertEq(_crowdinvestingFeeNumerator, crowdinvestingFeeNumerator);
        assertEq(_privateOfferFeeNumerator, privateOfferFeeNumerator);
    }

    function testSetFeeTo0Immediately() public {
        uint64 activationDate = uint64(block.timestamp);

        (, uint32 _tokenFeeNumerator) = feeSettings.feeTypeConfigs(FeeTypes.TOKEN);
        (, uint32 _crowdinvestingFeeNumerator) = feeSettings.feeTypeConfigs(FeeTypes.CROWDINVESTING);
        (, uint32 _privateOfferFeeNumerator) = feeSettings.feeTypeConfigs(FeeTypes.PRIVATE_OFFER);

        assertEq(_tokenFeeNumerator, 1);
        assertEq(_crowdinvestingFeeNumerator, 2);
        assertEq(_privateOfferFeeNumerator, 3);

        vm.prank(ADMIN);
        feeSettings.planFeeChange(FeeTypes.TOKEN, 0, activationDate);
        vm.prank(ADMIN);
        feeSettings.planFeeChange(FeeTypes.CROWDINVESTING, 0, activationDate);
        vm.prank(ADMIN);
        feeSettings.planFeeChange(FeeTypes.PRIVATE_OFFER, 0, activationDate);

        vm.prank(ADMIN);
        feeSettings.executeFeeChange(FeeTypes.TOKEN);
        vm.prank(ADMIN);
        feeSettings.executeFeeChange(FeeTypes.CROWDINVESTING);
        vm.prank(ADMIN);
        feeSettings.executeFeeChange(FeeTypes.PRIVATE_OFFER);

        (, _tokenFeeNumerator) = feeSettings.feeTypeConfigs(FeeTypes.TOKEN);
        (, _crowdinvestingFeeNumerator) = feeSettings.feeTypeConfigs(FeeTypes.CROWDINVESTING);
        (, _privateOfferFeeNumerator) = feeSettings.feeTypeConfigs(FeeTypes.PRIVATE_OFFER);

        assertEq(_tokenFeeNumerator, 0);
        assertEq(_crowdinvestingFeeNumerator, 0);
        assertEq(_privateOfferFeeNumerator, 0);

        (uint32 proposedNumerator, uint64 proposedActivationDate) = feeSettings.proposedFeeChanges(FeeTypes.TOKEN);

        assertEq(proposedNumerator, 0, "Token fee denominator mismatch");
        assertEq(proposedActivationDate, 0, "Time mismatch");
    }

    function testSetFeeToXFrom0Immediately() public {
        vm.prank(ADMIN);
        FeeSettings _feeSettings = FeeSettings(
            feeSettingsCloneFactory.createFeeSettingsClone(
                "salt",
                TRUSTED_FORWARDER,
                ADMIN,
                buildFeeTypes(0, 0, 0, ADMIN, ADMIN, ADMIN)
            )
        );

        (, uint32 _tokenFeeNumerator) = _feeSettings.feeTypeConfigs(FeeTypes.TOKEN);
        (, uint32 _crowdinvestingFeeNumerator) = _feeSettings.feeTypeConfigs(FeeTypes.CROWDINVESTING);
        (, uint32 _privateOfferFeeNumerator) = _feeSettings.feeTypeConfigs(FeeTypes.PRIVATE_OFFER);

        assertEq(_tokenFeeNumerator, 0, "Token fee numerator mismatch");
        assertEq(_crowdinvestingFeeNumerator, 0, "Crowdinvesting fee numerator mismatch");
        assertEq(_privateOfferFeeNumerator, 0, "PrivateOffer fee numerator mismatch");

        vm.prank(ADMIN);
        vm.expectRevert("fee increase needs 12 week delay");
        _feeSettings.planFeeChange(FeeTypes.TOKEN, 1, 0);
    }

    function testReduceFeeImmediately(uint32 tokenFee, uint32 crowdinvestingFee, uint32 privateOfferFee) public {
        vm.assume(tokenFee <= MAX_TOKEN);
        vm.assume(crowdinvestingFee <= MAX_CROWDINVESTING);
        vm.assume(privateOfferFee <= MAX_PRIVATE_OFFER);

        // create new fee settings with max fee
        feeSettings = FeeSettings(
            feeSettingsCloneFactory.createFeeSettingsClone(
                "salt",
                TRUSTED_FORWARDER,
                ADMIN,
                buildFeeTypes(MAX_TOKEN, MAX_CROWDINVESTING, MAX_PRIVATE_OFFER, ADMIN, ADMIN, ADMIN)
            )
        );

        (, uint32 _tokenFeeNumerator) = feeSettings.feeTypeConfigs(FeeTypes.TOKEN);
        (, uint32 _crowdinvestingFeeNumerator) = feeSettings.feeTypeConfigs(FeeTypes.CROWDINVESTING);
        (, uint32 _privateOfferFeeNumerator) = feeSettings.feeTypeConfigs(FeeTypes.PRIVATE_OFFER);

        assertEq(_tokenFeeNumerator, MAX_TOKEN);
        assertEq(_crowdinvestingFeeNumerator, MAX_CROWDINVESTING);
        assertEq(_privateOfferFeeNumerator, MAX_PRIVATE_OFFER);

        // change fee to something lower (immediate since it's a decrease)
        vm.prank(ADMIN);
        feeSettings.planFeeChange(FeeTypes.TOKEN, tokenFee, 0);
        vm.prank(ADMIN);
        feeSettings.planFeeChange(FeeTypes.CROWDINVESTING, crowdinvestingFee, 0);
        vm.prank(ADMIN);
        feeSettings.planFeeChange(FeeTypes.PRIVATE_OFFER, privateOfferFee, 0);

        vm.prank(ADMIN);
        feeSettings.executeFeeChange(FeeTypes.TOKEN);
        vm.prank(ADMIN);
        feeSettings.executeFeeChange(FeeTypes.CROWDINVESTING);
        vm.prank(ADMIN);
        feeSettings.executeFeeChange(FeeTypes.PRIVATE_OFFER);

        (, _tokenFeeNumerator) = feeSettings.feeTypeConfigs(FeeTypes.TOKEN);
        (, _crowdinvestingFeeNumerator) = feeSettings.feeTypeConfigs(FeeTypes.CROWDINVESTING);
        (, _privateOfferFeeNumerator) = feeSettings.feeTypeConfigs(FeeTypes.PRIVATE_OFFER);

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
            tokenFeeNumerator <= MAX_TOKEN &&
                crowdinvestingFeeNumerator <= MAX_CROWDINVESTING &&
                privateOfferFeeNumerator <= MAX_PRIVATE_OFFER
        );
        FeeSettings _feeSettings = FeeSettings(
            feeSettingsCloneFactory.createFeeSettingsClone(
                "salt2",
                TRUSTED_FORWARDER,
                ADMIN,
                buildFeeTypes(
                    tokenFeeNumerator,
                    crowdinvestingFeeNumerator,
                    privateOfferFeeNumerator,
                    ADMIN,
                    ADMIN,
                    ADMIN
                )
            )
        );

        (, uint32 _tokenFeeNumerator) = _feeSettings.feeTypeConfigs(FeeTypes.TOKEN);
        (, uint32 _crowdinvestingFeeNumerator) = _feeSettings.feeTypeConfigs(FeeTypes.CROWDINVESTING);
        (, uint32 _privateOfferFeeNumerator) = _feeSettings.feeTypeConfigs(FeeTypes.PRIVATE_OFFER);

        assertEq(_tokenFeeNumerator, tokenFeeNumerator, "Token fee numerator mismatch");
        assertEq(_crowdinvestingFeeNumerator, crowdinvestingFeeNumerator, "Crowdinvesting fee numerator mismatch");
        assertEq(_privateOfferFeeNumerator, privateOfferFeeNumerator, "PrivateOffer fee numerator mismatch");
    }

    function testFeeCollector0FailsInInitializer() public {
        FeeSettings _feeSettings;

        {
            FeeSettings.FeeTypeInit[] memory feeType = new FeeSettings.FeeTypeInit[](1);
            feeType[0] = FeeSettings.FeeTypeInit(FeeTypes.TOKEN, 500, 1, address(0));
            vm.expectRevert("Fee collector cannot be 0x0");
            _feeSettings = FeeSettings(
                feeSettingsCloneFactory.createFeeSettingsClone("salt", TRUSTED_FORWARDER, ADMIN, feeType)
            );
        }

        {
            FeeSettings.FeeTypeInit[] memory feeType = new FeeSettings.FeeTypeInit[](1);
            feeType[0] = FeeSettings.FeeTypeInit(FeeTypes.CROWDINVESTING, 1000, 2, address(0));
            vm.expectRevert("Fee collector cannot be 0x0");
            _feeSettings = FeeSettings(
                feeSettingsCloneFactory.createFeeSettingsClone("salt", TRUSTED_FORWARDER, ADMIN, feeType)
            );
        }

        {
            FeeSettings.FeeTypeInit[] memory feeType = new FeeSettings.FeeTypeInit[](1);
            feeType[0] = FeeSettings.FeeTypeInit(FeeTypes.PRIVATE_OFFER, 500, 3, address(0));
            vm.expectRevert("Fee collector cannot be 0x0");
            _feeSettings = FeeSettings(
                feeSettingsCloneFactory.createFeeSettingsClone("salt", TRUSTED_FORWARDER, ADMIN, feeType)
            );
        }
    }

    function testOwner0FailsInInitializer() public {
        vm.expectRevert("owner can not be zero address");
        feeSettingsCloneFactory.createFeeSettingsClone("salt", TRUSTED_FORWARDER, address(0), _buildFeeTypes(ADMIN));
    }

    function testFeeCollector0FailsInSetter() public {
        vm.expectRevert("collector cannot be 0x0");
        vm.prank(ADMIN);
        feeSettings.setDefaultFeeCollector(FeeTypes.TOKEN, address(0));
        vm.expectRevert("collector cannot be 0x0");
        vm.prank(ADMIN);
        feeSettings.setDefaultFeeCollector(FeeTypes.CROWDINVESTING, address(0));
        vm.expectRevert("collector cannot be 0x0");
        vm.prank(ADMIN);
        feeSettings.setDefaultFeeCollector(FeeTypes.PRIVATE_OFFER, address(0));
    }

    function testUpdateFeeCollectors(
        address newTokenFeeCollector,
        address newCrowdinvestingFeeCollector,
        address newPrivateOfferFeeCollector
    ) public {
        vm.assume(newTokenFeeCollector != address(0));
        vm.assume(newCrowdinvestingFeeCollector != address(0));
        vm.assume(newPrivateOfferFeeCollector != address(0));

        vm.startPrank(ADMIN);
        feeSettings.setDefaultFeeCollector(FeeTypes.TOKEN, newTokenFeeCollector);
        feeSettings.setDefaultFeeCollector(FeeTypes.CROWDINVESTING, newCrowdinvestingFeeCollector);
        feeSettings.setDefaultFeeCollector(FeeTypes.PRIVATE_OFFER, newPrivateOfferFeeCollector);
        vm.stopPrank();
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
        vm.assume(tokenFeeNumerator <= MAX_TOKEN);
        vm.assume(crowdinvestingFeeNumerator <= MAX_CROWDINVESTING);
        vm.assume(privateOfferFeeNumerator <= MAX_PRIVATE_OFFER);
        vm.assume(amount < UINT256_MAX / MAX_CROWDINVESTING);

        FeeSettings _feeSettings = FeeSettings(
            feeSettingsCloneFactory.createFeeSettingsClone(
                "salt5",
                TRUSTED_FORWARDER,
                ADMIN,
                buildFeeTypes(
                    tokenFeeNumerator,
                    crowdinvestingFeeNumerator,
                    privateOfferFeeNumerator,
                    ADMIN,
                    ADMIN,
                    ADMIN
                )
            )
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
        vm.assume(tokenFeeNumerator <= MAX_TOKEN);
        vm.assume(crowdinvestingFeeNumerator <= MAX_CROWDINVESTING);
        vm.assume(privateOfferFeeNumerator <= MAX_PRIVATE_OFFER);
        vm.assume(amount < UINT256_MAX / MAX_CROWDINVESTING);

        // only token fee is 0

        {
            FeeSettings _feeSettings = FeeSettings(
                feeSettingsCloneFactory.createFeeSettingsClone(
                    "salt4",
                    TRUSTED_FORWARDER,
                    ADMIN,
                    buildFeeTypes(0, crowdinvestingFeeNumerator, privateOfferFeeNumerator, ADMIN, ADMIN, ADMIN)
                )
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
        }

        // only crowdinvesting fee is 0

        {
            FeeSettings _feeSettings = FeeSettings(
                feeSettingsCloneFactory.createFeeSettingsClone(
                    "salt3",
                    TRUSTED_FORWARDER,
                    ADMIN,
                    buildFeeTypes(tokenFeeNumerator, 0, privateOfferFeeNumerator, ADMIN, ADMIN, ADMIN)
                )
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
        }

        // only private offer fee is 0

        {
            FeeSettings _feeSettings = FeeSettings(
                feeSettingsCloneFactory.createFeeSettingsClone(
                    "salt2",
                    TRUSTED_FORWARDER,
                    ADMIN,
                    buildFeeTypes(tokenFeeNumerator, crowdinvestingFeeNumerator, 0, ADMIN, ADMIN, ADMIN)
                )
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
    }

    function testERC165IsAvailable() public view {
        assertEq(
            feeSettings.supportsInterface(0x01ffc9a7), // type(IERC165).interfaceId
            true,
            "ERC165 not supported"
        );
    }

    function testIFeeSettingsV1IsAvailable(uint256 _amount) public view {
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

    function testIFeeSettingsV2IsAvailable() public view {
        assertEq(feeSettings.supportsInterface(type(IFeeSettingsV2).interfaceId), true, "IFeeSettingsV2 not supported");
    }

    function testNonsenseInterfacesAreNotAvailable(bytes4 _nonsenseInterface) public view {
        vm.assume(_nonsenseInterface != type(IFeeSettingsV1).interfaceId);
        vm.assume(_nonsenseInterface != type(IFeeSettingsV2).interfaceId);
        vm.assume(_nonsenseInterface != 0x01ffc9a7);

        assertEq(feeSettings.supportsInterface(0x01ffc9b7), false, "This interface should not be supported");
    }

    function testAddingCustomFees(address _someTokenAddress) public {
        vm.assume(_someTokenAddress != address(0));

        // deploying from here makes address(this) the ADMIN
        FeeSettings _feeSettings = FeeSettings(
            feeSettingsCloneFactory.createFeeSettingsClone(
                "salt",
                TRUSTED_FORWARDER,
                address(this),
                buildFeeTypes(11, 22, 55, address(this), address(this), address(this))
            )
        );
        // check there is no entry for this token address
        {
            (uint32 tokenNum, uint64 tokenValidity) = _feeSettings.customFees(FeeTypes.TOKEN, _someTokenAddress);
            (uint32 ciNum, uint64 ciValidity) = _feeSettings.customFees(FeeTypes.CROWDINVESTING, _someTokenAddress);
            (uint32 poNum, uint64 poValidity) = _feeSettings.customFees(FeeTypes.PRIVATE_OFFER, _someTokenAddress);
            assertEq(tokenNum, 0, "Token fee numerator should be 0");
            assertEq(ciNum, 0, "Crowdinvesting fee numerator should be 0");
            assertEq(poNum, 0, "Private offer fee numerator should be 0");
            assertEq(tokenValidity, 0, "End time should be 0");
            assertEq(ciValidity, 0, "End time should be 0");
            assertEq(poValidity, 0, "End time should be 0");
        }

        // check the token fee, private offer fee and crowdinvesting fee are as expected
        assertEq(_feeSettings.tokenFee(10000, _someTokenAddress), 11, "Token fee should be 11");
        assertEq(_feeSettings.crowdinvestingFee(10000, _someTokenAddress), 22, "Crowdinvesting fee should be 22");
        assertEq(_feeSettings.privateOfferFee(10000, _someTokenAddress), 55, "Private offer fee should be 55");

        // add custom fee entry for this token address
        uint256 realEndTime = block.timestamp + 100;
        _feeSettings.setCustomFee(FeeTypes.TOKEN, _someTokenAddress, 3, uint64(realEndTime));
        _feeSettings.setCustomFee(FeeTypes.CROWDINVESTING, _someTokenAddress, 4, uint64(realEndTime));
        _feeSettings.setCustomFee(FeeTypes.PRIVATE_OFFER, _someTokenAddress, 2, uint64(realEndTime));

        // check the token fee, private offer fee and crowdinvesting fee change as expected
        assertEq(_feeSettings.tokenFee(10000, _someTokenAddress), 3, "Token fee should be 3 now");
        assertEq(_feeSettings.crowdinvestingFee(10000, _someTokenAddress), 4, "Crowdinvesting fee should be 4 now");
        assertEq(_feeSettings.privateOfferFee(10000, _someTokenAddress), 2, "Private offer fee should be 2 now");

        // check the custom fee entry is as expected
        {
            (uint32 tokenNum, uint64 tokenValidity) = _feeSettings.customFees(FeeTypes.TOKEN, _someTokenAddress);
            (uint32 ciNum, ) = _feeSettings.customFees(FeeTypes.CROWDINVESTING, _someTokenAddress);
            (uint32 poNum, ) = _feeSettings.customFees(FeeTypes.PRIVATE_OFFER, _someTokenAddress);
            assertEq(tokenNum, 3, "Token fee numerator should be 3");
            assertEq(ciNum, 4, "Crowdinvesting fee numerator should be 4");
            assertEq(poNum, 2, "Private offer fee numerator should be 2");
            assertEq(tokenValidity, realEndTime, "End time should match");
        }

        // check that the custom fee is not applied after the end time
        vm.warp(realEndTime + 1);
        assertEq(_feeSettings.tokenFee(10000, _someTokenAddress), 11, "Token fee should be 11 again");
        assertEq(_feeSettings.crowdinvestingFee(10000, _someTokenAddress), 22, "Crowdinvesting fee should be 22 again");
        assertEq(_feeSettings.privateOfferFee(10000, _someTokenAddress), 55, "Private offer fee should be 55 again");
    }

    function testOnlyManagerCanAddCustomFees(address _rando) public {
        address someTokenAddress = address(74);
        vm.assume(_rando != address(0));
        vm.assume(_rando != ADMIN);
        vm.assume(_rando != TRUSTED_FORWARDER);

        vm.expectRevert("Only managers can call this function");
        vm.prank(_rando);
        feeSettings.setCustomFee(FeeTypes.TOKEN, someTokenAddress, 1, uint64(block.timestamp + 100));
    }

    function testCustomFeesAreNotAppliedToOtherTokens(address _someTokenAddress, address _otherTokenAddress) public {
        vm.assume(_someTokenAddress != address(0));
        vm.assume(_otherTokenAddress != address(0));
        vm.assume(_someTokenAddress != _otherTokenAddress);

        FeeSettings _feeSettings = FeeSettings(
            feeSettingsCloneFactory.createFeeSettingsClone(
                "salt",
                TRUSTED_FORWARDER,
                address(this),
                buildFeeTypes(10, 20, 50, ADMIN, ADMIN, ADMIN)
            )
        );
        // add custom fee entry for this token address
        uint64 customFeeValidity = uint64(block.timestamp + 100);
        _feeSettings.setCustomFee(FeeTypes.TOKEN, _someTokenAddress, 3, customFeeValidity);
        _feeSettings.setCustomFee(FeeTypes.CROWDINVESTING, _someTokenAddress, 4, customFeeValidity);
        _feeSettings.setCustomFee(FeeTypes.PRIVATE_OFFER, _someTokenAddress, 2, customFeeValidity);

        // check the token fee, private offer fee and crowdinvesting fee are as expected
        assertEq(_feeSettings.tokenFee(10000, _otherTokenAddress), 10, "Token fee should be 10");
        assertEq(_feeSettings.crowdinvestingFee(10000, _otherTokenAddress), 20, "Crowdinvesting fee should be 20");
        assertEq(_feeSettings.privateOfferFee(10000, _otherTokenAddress), 50, "Private offer fee should be 50");
    }

    function testCustomFeesDoNotIncreaseFee() public {
        address someTokenAddress = address(74);
        FeeSettings _feeSettings = FeeSettings(
            feeSettingsCloneFactory.createFeeSettingsClone(
                "salt",
                TRUSTED_FORWARDER,
                address(this),
                buildFeeTypes(0, 0, 0, ADMIN, ADMIN, ADMIN)
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
        uint64 customValidity = uint64(block.timestamp + 100);
        _feeSettings.setCustomFee(FeeTypes.TOKEN, someTokenAddress, 1, customValidity);
        _feeSettings.setCustomFee(FeeTypes.CROWDINVESTING, someTokenAddress, 1, customValidity);
        _feeSettings.setCustomFee(FeeTypes.PRIVATE_OFFER, someTokenAddress, 1, customValidity);

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
        FeeSettings _feeSettings = FeeSettings(
            feeSettingsCloneFactory.createFeeSettingsClone(
                "salt",
                TRUSTED_FORWARDER,
                address(this),
                buildFeeTypes(10, 20, 50, ADMIN, ADMIN, ADMIN)
            )
        );
        // add custom fee entry for this token address
        uint64 customFeeValidity = uint64(block.timestamp + 100);
        _feeSettings.setCustomFee(FeeTypes.TOKEN, someTokenAddress, 3, customFeeValidity);
        _feeSettings.setCustomFee(FeeTypes.CROWDINVESTING, someTokenAddress, 4, customFeeValidity);
        _feeSettings.setCustomFee(FeeTypes.PRIVATE_OFFER, someTokenAddress, 2, customFeeValidity);

        // check the token fee, private offer fee and crowdinvesting fee are as expected
        assertEq(_feeSettings.tokenFee(10000, someTokenAddress), 3, "Token fee should be 3");
        assertEq(_feeSettings.crowdinvestingFee(10000, someTokenAddress), 4, "Crowdinvesting fee should be 4");
        assertEq(_feeSettings.privateOfferFee(10000, someTokenAddress), 2, "Private offer fee should be 2");

        // remove custom fee entry for this token address
        _feeSettings.removeCustomFee(FeeTypes.TOKEN, someTokenAddress);
        _feeSettings.removeCustomFee(FeeTypes.CROWDINVESTING, someTokenAddress);
        _feeSettings.removeCustomFee(FeeTypes.PRIVATE_OFFER, someTokenAddress);

        // check the token fee, private offer fee and crowdinvesting fee are as expected
        assertEq(_feeSettings.tokenFee(10000, someTokenAddress), 10, "Token fee should be 10");
        assertEq(_feeSettings.crowdinvestingFee(10000, someTokenAddress), 20, "Crowdinvesting fee should be 20");
        assertEq(_feeSettings.privateOfferFee(10000, someTokenAddress), 50, "Private offer fee should be 50");
    }

    function testOnlyManagerCanRemoveCustomFees(address _rando) public {
        address someTokenAddress = address(74);
        vm.assume(feeSettings.managers(_rando) == false);
        vm.assume(_rando != TRUSTED_FORWARDER);
        vm.expectRevert("Only managers can call this function");
        vm.prank(_rando);
        feeSettings.removeCustomFee(FeeTypes.TOKEN, someTokenAddress);
    }

    function testOwnerCanAddManager(address _manager) public {
        vm.assume(_manager != address(0));
        vm.assume(_manager != TRUSTED_FORWARDER);
        vm.assume(_manager != ADMIN);

        assertEq(feeSettings.managers(_manager), false, "Should not be manager yet");

        vm.prank(ADMIN);
        vm.expectEmit(true, true, true, true, address(feeSettings));
        emit ManagerAdded(_manager);
        feeSettings.addManager(_manager);

        assertEq(feeSettings.managers(_manager), true, "Manager should be added");
    }

    function testRandoCanNotAddManager(address _rando) public {
        vm.assume(_rando != address(0));
        vm.assume(_rando != ADMIN);
        vm.assume(_rando != TRUSTED_FORWARDER);

        vm.expectRevert("Ownable: caller is not the owner");
        vm.prank(_rando);
        feeSettings.addManager(_rando);
    }

    function testOwnerCanRemoveManager(address _manager) public {
        vm.assume(_manager != address(0));
        vm.assume(_manager != TRUSTED_FORWARDER);
        vm.assume(_manager != ADMIN);

        vm.prank(ADMIN);
        feeSettings.addManager(_manager);

        assertEq(feeSettings.managers(_manager), true, "Should be manager");

        vm.prank(ADMIN);
        vm.expectEmit(true, true, true, true, address(feeSettings));
        emit ManagerRemoved(_manager);
        feeSettings.removeManager(_manager);

        assertEq(feeSettings.managers(_manager), false, "Manager should be removed");
    }

    function testRandoCanNotRemoveManager(address _rando) public {
        vm.assume(_rando != address(0));
        vm.assume(_rando != ADMIN);
        vm.assume(_rando != TRUSTED_FORWARDER);

        vm.expectRevert("Ownable: caller is not the owner");
        vm.prank(_rando);
        feeSettings.removeManager(_rando);
    }

    function testAddingCustomTokenFeeCollector(address _feeCollector) public {
        vm.assume(_feeCollector != address(0));
        vm.assume(_feeCollector != ADMIN);

        assertEq(
            feeSettings.collectors(FeeTypes.TOKEN, EXAMPLE_TOKEN_ADDRESS),
            address(0),
            "Should not be custom fee collector yet"
        );

        assertEq(
            feeSettings.tokenFeeCollector(EXAMPLE_TOKEN_ADDRESS),
            feeSettings.feeCollector(),
            "Fee collector mismatch between V1 and V2"
        );
        assertEq(feeSettings.tokenFeeCollector(EXAMPLE_TOKEN_ADDRESS), ADMIN, "Fee collector not ADMIN address");

        vm.prank(ADMIN);
        feeSettings.setCustomFeeCollector(FeeTypes.TOKEN, EXAMPLE_TOKEN_ADDRESS, _feeCollector);

        assertEq(
            feeSettings.collectors(FeeTypes.TOKEN, EXAMPLE_TOKEN_ADDRESS),
            _feeCollector,
            "Custom fee collector wrong"
        );
        assertEq(
            feeSettings.tokenFeeCollector(EXAMPLE_TOKEN_ADDRESS),
            _feeCollector,
            "Fee collector wrong with custom fee collector"
        );
        assertEq(ADMIN, feeSettings.feeCollector(), "V1 fee collector should still be default value");
    }

    function testRemovingCustomTokenFeeCollector(address _feeCollector) public {
        vm.assume(_feeCollector != address(0));
        vm.assume(_feeCollector != ADMIN);

        vm.prank(ADMIN);
        feeSettings.setCustomFeeCollector(FeeTypes.TOKEN, EXAMPLE_TOKEN_ADDRESS, _feeCollector);

        assertEq(
            feeSettings.tokenFeeCollector(EXAMPLE_TOKEN_ADDRESS),
            _feeCollector,
            "Fee collector wrong with custom fee collector"
        );

        vm.prank(ADMIN);
        feeSettings.removeCustomFeeCollector(FeeTypes.TOKEN, EXAMPLE_TOKEN_ADDRESS);

        assertEq(
            feeSettings.collectors(FeeTypes.TOKEN, EXAMPLE_TOKEN_ADDRESS),
            address(0),
            "Should not be custom fee collector yet"
        );

        assertEq(
            feeSettings.tokenFeeCollector(EXAMPLE_TOKEN_ADDRESS),
            feeSettings.feeCollector(),
            "Fee collector mismatch between V1 and V2"
        );
        assertEq(feeSettings.tokenFeeCollector(EXAMPLE_TOKEN_ADDRESS), ADMIN, "Fee collector not ADMIN address");
    }

    function testAddingCustomCrowdinvestingFeeCollector(address _feeCollector) public {
        vm.assume(_feeCollector != address(0));
        vm.assume(_feeCollector != ADMIN);

        assertEq(
            feeSettings.collectors(FeeTypes.CROWDINVESTING, EXAMPLE_TOKEN_ADDRESS),
            address(0),
            "Should not be custom fee collector yet"
        );

        assertEq(
            feeSettings.crowdinvestingFeeCollector(EXAMPLE_TOKEN_ADDRESS),
            ADMIN,
            "Fee collector not ADMIN address"
        );

        vm.prank(ADMIN);
        feeSettings.setCustomFeeCollector(FeeTypes.CROWDINVESTING, EXAMPLE_TOKEN_ADDRESS, _feeCollector);

        assertEq(
            feeSettings.collectors(FeeTypes.CROWDINVESTING, EXAMPLE_TOKEN_ADDRESS),
            _feeCollector,
            "Custom fee collector wrong"
        );
        assertEq(
            feeSettings.crowdinvestingFeeCollector(EXAMPLE_TOKEN_ADDRESS),
            _feeCollector,
            "Fee collector wrong with custom fee collector"
        );
    }

    function testRemovingCustomCrowdinvestingFeeCollector(address _feeCollector) public {
        vm.assume(_feeCollector != address(0));
        vm.assume(_feeCollector != ADMIN);

        vm.prank(ADMIN);
        feeSettings.setCustomFeeCollector(FeeTypes.CROWDINVESTING, EXAMPLE_TOKEN_ADDRESS, _feeCollector);

        assertEq(
            feeSettings.crowdinvestingFeeCollector(EXAMPLE_TOKEN_ADDRESS),
            _feeCollector,
            "Fee collector wrong with custom fee collector"
        );

        vm.prank(ADMIN);
        feeSettings.removeCustomFeeCollector(FeeTypes.CROWDINVESTING, EXAMPLE_TOKEN_ADDRESS);

        assertEq(
            feeSettings.collectors(FeeTypes.CROWDINVESTING, EXAMPLE_TOKEN_ADDRESS),
            address(0),
            "Should not be custom fee collector yet"
        );

        assertEq(
            feeSettings.crowdinvestingFeeCollector(EXAMPLE_TOKEN_ADDRESS),
            ADMIN,
            "Fee collector not ADMIN address"
        );
    }

    function testAddingCustomPrivateOfferFeeCollector(address _feeCollector) public {
        vm.assume(_feeCollector != address(0));
        vm.assume(_feeCollector != ADMIN);

        assertEq(
            feeSettings.collectors(FeeTypes.PRIVATE_OFFER, EXAMPLE_TOKEN_ADDRESS),
            address(0),
            "Should not be custom fee collector yet"
        );

        assertEq(feeSettings.privateOfferFeeCollector(EXAMPLE_TOKEN_ADDRESS), ADMIN, "Fee collector not ADMIN address");

        vm.prank(ADMIN);
        feeSettings.setCustomFeeCollector(FeeTypes.PRIVATE_OFFER, EXAMPLE_TOKEN_ADDRESS, _feeCollector);

        assertEq(
            feeSettings.collectors(FeeTypes.PRIVATE_OFFER, EXAMPLE_TOKEN_ADDRESS),
            _feeCollector,
            "Custom fee collector wrong"
        );
        assertEq(
            feeSettings.privateOfferFeeCollector(EXAMPLE_TOKEN_ADDRESS),
            _feeCollector,
            "Fee collector wrong with custom fee collector"
        );
    }

    function testRemovingCustomPrivateOfferFeeCollector(address _feeCollector) public {
        vm.assume(_feeCollector != address(0));
        vm.assume(_feeCollector != ADMIN);

        vm.prank(ADMIN);
        feeSettings.setCustomFeeCollector(FeeTypes.PRIVATE_OFFER, EXAMPLE_TOKEN_ADDRESS, _feeCollector);

        assertEq(
            feeSettings.privateOfferFeeCollector(EXAMPLE_TOKEN_ADDRESS),
            _feeCollector,
            "Fee collector wrong with custom fee collector"
        );

        vm.prank(ADMIN);
        feeSettings.removeCustomFeeCollector(FeeTypes.PRIVATE_OFFER, EXAMPLE_TOKEN_ADDRESS);

        assertEq(
            feeSettings.collectors(FeeTypes.PRIVATE_OFFER, EXAMPLE_TOKEN_ADDRESS),
            address(0),
            "Should not be custom fee collector yet"
        );

        assertEq(feeSettings.privateOfferFeeCollector(EXAMPLE_TOKEN_ADDRESS), ADMIN, "Fee collector not ADMIN address");
    }

    function testManagerCanSetAndRemoveCustomFeeCollector(address _manager, address _customFeeCollector) public {
        vm.assume(_manager != address(0));
        vm.assume(_manager != TRUSTED_FORWARDER);
        vm.assume(_manager != ADMIN);
        vm.assume(_customFeeCollector != address(0));
        vm.assume(_customFeeCollector != ADMIN);

        vm.prank(ADMIN);
        feeSettings.addManager(_manager);

        assertEq(
            feeSettings.collectors(FeeTypes.TOKEN, EXAMPLE_TOKEN_ADDRESS),
            address(0),
            "Should not be custom fee collector yet"
        );
        assertEq(
            feeSettings.collectors(FeeTypes.CROWDINVESTING, EXAMPLE_TOKEN_ADDRESS),
            address(0),
            "Should not be custom fee collector yet"
        );
        assertEq(
            feeSettings.collectors(FeeTypes.PRIVATE_OFFER, EXAMPLE_TOKEN_ADDRESS),
            address(0),
            "Should not be custom fee collector yet"
        );

        vm.startPrank(_manager);
        feeSettings.setCustomFeeCollector(FeeTypes.TOKEN, EXAMPLE_TOKEN_ADDRESS, _customFeeCollector);
        feeSettings.setCustomFeeCollector(FeeTypes.CROWDINVESTING, EXAMPLE_TOKEN_ADDRESS, _customFeeCollector);
        feeSettings.setCustomFeeCollector(FeeTypes.PRIVATE_OFFER, EXAMPLE_TOKEN_ADDRESS, _customFeeCollector);
        vm.stopPrank();

        assertEq(
            feeSettings.collectors(FeeTypes.TOKEN, EXAMPLE_TOKEN_ADDRESS),
            _customFeeCollector,
            "Custom fee collector wrong"
        );
        assertEq(
            feeSettings.collectors(FeeTypes.CROWDINVESTING, EXAMPLE_TOKEN_ADDRESS),
            _customFeeCollector,
            "Custom fee collector wrong"
        );
        assertEq(
            feeSettings.collectors(FeeTypes.PRIVATE_OFFER, EXAMPLE_TOKEN_ADDRESS),
            _customFeeCollector,
            "Custom fee collector wrong"
        );

        vm.startPrank(_manager);
        feeSettings.removeCustomFeeCollector(FeeTypes.TOKEN, EXAMPLE_TOKEN_ADDRESS);
        feeSettings.removeCustomFeeCollector(FeeTypes.CROWDINVESTING, EXAMPLE_TOKEN_ADDRESS);
        feeSettings.removeCustomFeeCollector(FeeTypes.PRIVATE_OFFER, EXAMPLE_TOKEN_ADDRESS);
        vm.stopPrank();

        assertEq(
            feeSettings.collectors(FeeTypes.TOKEN, EXAMPLE_TOKEN_ADDRESS),
            address(0),
            "Should not be custom fee collector yet"
        );
        assertEq(
            feeSettings.collectors(FeeTypes.CROWDINVESTING, EXAMPLE_TOKEN_ADDRESS),
            address(0),
            "Should not be custom fee collector yet"
        );
        assertEq(
            feeSettings.collectors(FeeTypes.PRIVATE_OFFER, EXAMPLE_TOKEN_ADDRESS),
            address(0),
            "Should not be custom fee collector yet"
        );
    }

    function testRandoCanNotSetOrRemoveCustomFeeCollectors(address _rando, address _customFeeCollector) public {
        vm.assume(_rando != address(0));
        vm.assume(_rando != ADMIN);
        vm.assume(_rando != TRUSTED_FORWARDER);
        vm.assume(_customFeeCollector != address(0));
        vm.assume(_customFeeCollector != ADMIN);

        vm.expectRevert("Only managers can call this function");
        vm.prank(_rando);
        feeSettings.setCustomFeeCollector(FeeTypes.TOKEN, EXAMPLE_TOKEN_ADDRESS, _customFeeCollector);

        vm.expectRevert("Only managers can call this function");
        vm.prank(_rando);
        feeSettings.setCustomFeeCollector(FeeTypes.CROWDINVESTING, EXAMPLE_TOKEN_ADDRESS, _customFeeCollector);

        vm.expectRevert("Only managers can call this function");
        vm.prank(_rando);
        feeSettings.setCustomFeeCollector(FeeTypes.PRIVATE_OFFER, EXAMPLE_TOKEN_ADDRESS, _customFeeCollector);

        vm.expectRevert("Only managers can call this function");
        vm.prank(_rando);
        feeSettings.removeCustomFeeCollector(FeeTypes.TOKEN, EXAMPLE_TOKEN_ADDRESS);

        vm.expectRevert("Only managers can call this function");
        vm.prank(_rando);
        feeSettings.removeCustomFeeCollector(FeeTypes.CROWDINVESTING, EXAMPLE_TOKEN_ADDRESS);

        vm.expectRevert("Only managers can call this function");
        vm.prank(_rando);
        feeSettings.removeCustomFeeCollector(FeeTypes.PRIVATE_OFFER, EXAMPLE_TOKEN_ADDRESS);
    }

    function testSettingCustomFeeCollectorFor0AddressReverts() public {
        vm.expectRevert("collector cannot be 0x0");
        vm.prank(ADMIN);
        feeSettings.setCustomFeeCollector(FeeTypes.TOKEN, EXAMPLE_TOKEN_ADDRESS, address(0));

        vm.expectRevert("collector cannot be 0x0");
        vm.prank(ADMIN);
        feeSettings.setCustomFeeCollector(FeeTypes.CROWDINVESTING, EXAMPLE_TOKEN_ADDRESS, address(0));

        vm.expectRevert("collector cannot be 0x0");
        vm.prank(ADMIN);
        feeSettings.setCustomFeeCollector(FeeTypes.PRIVATE_OFFER, EXAMPLE_TOKEN_ADDRESS, address(0));
    }

    function testSettingCustomFeesFor0AddressReverts() public {
        vm.expectRevert("token cannot be 0x0");
        vm.prank(ADMIN);
        feeSettings.setCustomFee(FeeTypes.TOKEN, address(0), 1, uint64(block.timestamp + 100));
    }

    function testCustomFeeCollectorsOnlyApplyToSpecifiedAddress(address specifiedAddress, address someAddress) public {
        vm.assume(specifiedAddress != address(0));
        vm.assume(specifiedAddress != someAddress);

        address customFeeCollector = address(75);
        assertTrue(customFeeCollector != ADMIN);

        vm.startPrank(ADMIN);

        // check token fee collector
        feeSettings.setCustomFeeCollector(FeeTypes.TOKEN, specifiedAddress, customFeeCollector);
        assertEq(
            feeSettings.tokenFeeCollector(specifiedAddress),
            customFeeCollector,
            "Token fee collector wrong for specifiedAddress"
        );
        assertEq(
            feeSettings.crowdinvestingFeeCollector(specifiedAddress),
            ADMIN,
            "Crowdinvesting fee collector wrong for specifiedAddress"
        );
        assertEq(
            feeSettings.privateOfferFeeCollector(specifiedAddress),
            ADMIN,
            "Token fee collector wrong for specifiedAddress"
        );

        assertEq(feeSettings.tokenFeeCollector(someAddress), ADMIN, "Token fee collector wrong");
        assertEq(feeSettings.crowdinvestingFeeCollector(someAddress), ADMIN, "Crowdinvesting fee collector wrong");
        assertEq(feeSettings.privateOfferFeeCollector(someAddress), ADMIN, "Private offer fee collector wrong");

        feeSettings.removeCustomFeeCollector(FeeTypes.TOKEN, specifiedAddress);

        // test crowdinvesting fee collector
        feeSettings.setCustomFeeCollector(FeeTypes.CROWDINVESTING, specifiedAddress, customFeeCollector);
        assertEq(
            feeSettings.tokenFeeCollector(specifiedAddress),
            ADMIN,
            "Token fee collector wrong for specifiedAddress"
        );
        assertEq(
            feeSettings.crowdinvestingFeeCollector(specifiedAddress),
            customFeeCollector,
            "Crowdinvesting fee collector wrong for specifiedAddress"
        );
        assertEq(
            feeSettings.privateOfferFeeCollector(specifiedAddress),
            ADMIN,
            "Token fee collector wrong for specifiedAddress"
        );

        assertEq(feeSettings.tokenFeeCollector(someAddress), ADMIN, "Token fee collector wrong");
        assertEq(feeSettings.crowdinvestingFeeCollector(someAddress), ADMIN, "Crowdinvesting fee collector wrong");
        assertEq(feeSettings.privateOfferFeeCollector(someAddress), ADMIN, "Private offer fee collector wrong");

        feeSettings.removeCustomFeeCollector(FeeTypes.CROWDINVESTING, specifiedAddress);

        // test private offer fee collector
        feeSettings.setCustomFeeCollector(FeeTypes.PRIVATE_OFFER, specifiedAddress, customFeeCollector);
        assertEq(
            feeSettings.tokenFeeCollector(specifiedAddress),
            ADMIN,
            "Token fee collector wrong for specifiedAddress"
        );
        assertEq(
            feeSettings.crowdinvestingFeeCollector(specifiedAddress),
            ADMIN,
            "Crowdinvesting fee collector wrong for specifiedAddress"
        );
        assertEq(
            feeSettings.privateOfferFeeCollector(specifiedAddress),
            customFeeCollector,
            "Token fee collector wrong for specifiedAddress"
        );

        assertEq(feeSettings.tokenFeeCollector(someAddress), ADMIN, "Token fee collector wrong");
        assertEq(feeSettings.crowdinvestingFeeCollector(someAddress), ADMIN, "Crowdinvesting fee collector wrong");
        assertEq(feeSettings.privateOfferFeeCollector(someAddress), ADMIN, "Private offer fee collector wrong");
    }

    function testRemovingCustomFeeFor0AddressReverts() public {
        vm.expectRevert("token cannot be 0x0");
        vm.prank(ADMIN);
        feeSettings.removeCustomFee(FeeTypes.TOKEN, address(0));
    }

    function testRemovingCustomFeeCollectorsFor0AddressReverts() public {
        vm.expectRevert("token cannot be 0x0");
        vm.prank(ADMIN);
        feeSettings.removeCustomFeeCollector(FeeTypes.TOKEN, address(0));

        vm.expectRevert("token cannot be 0x0");
        vm.prank(ADMIN);
        feeSettings.removeCustomFeeCollector(FeeTypes.CROWDINVESTING, address(0));

        vm.expectRevert("token cannot be 0x0");
        vm.prank(ADMIN);
        feeSettings.removeCustomFeeCollector(FeeTypes.PRIVATE_OFFER, address(0));
    }

    function testAllFeeTypesRegisteredWithUniqueSettings() public {
        bytes32[] memory allFeeTypes = new bytes32[](6);
        allFeeTypes[0] = FeeTypes.TOKEN;
        allFeeTypes[1] = FeeTypes.CROWDINVESTING;
        allFeeTypes[2] = FeeTypes.PRIVATE_OFFER;
        allFeeTypes[3] = FeeTypes.SECONDARY_MARKET;
        allFeeTypes[4] = FeeTypes.DISTRIBUTION;
        allFeeTypes[5] = FeeTypes.EXIT;

        FeeSettings.FeeTypeInit[] memory feeTypeInits = new FeeSettings.FeeTypeInit[](allFeeTypes.length);
        for (uint256 i = 0; i < allFeeTypes.length; i++) {
            uint32 maxNumerator = uint32((i + 1) * 100);
            uint32 defaultNumerator = uint32((i + 1) * 50);
            address collector = address(uint160(i + 1));
            feeTypeInits[i] = FeeSettings.FeeTypeInit(allFeeTypes[i], maxNumerator, defaultNumerator, collector);
        }

        FeeSettings logic = new FeeSettings(TRUSTED_FORWARDER);
        FeeSettingsCloneFactory factory = new FeeSettingsCloneFactory(address(logic));
        FeeSettings freshFeeSettings = FeeSettings(
            factory.createFeeSettingsClone("all-types-salt", TRUSTED_FORWARDER, ADMIN, feeTypeInits)
        );

        for (uint256 i = 0; i < allFeeTypes.length; i++) {
            uint32 expectedMax = uint32((i + 1) * 100);
            uint32 expectedDefault = uint32((i + 1) * 50);
            address expectedCollector = address(uint160(i + 1));

            (uint32 actualMax, uint32 actualDefault) = freshFeeSettings.feeTypeConfigs(allFeeTypes[i]);
            assertEq(actualMax, expectedMax, "maxNumerator wrong");
            assertEq(actualDefault, expectedDefault, "defaultNumerator wrong");
            assertEq(freshFeeSettings.feeCollector(allFeeTypes[i], address(0)), expectedCollector, "collector wrong");
        }
    }

    function testFuzz_RegisterFeeTypeRevertsIfMaxNumeratorTooLarge(bytes32 feeType, uint32 maxNumerator) public {
        vm.assume(feeType != bytes32(0));
        vm.assume(maxNumerator >= feeSettings.FEE_DENOMINATOR());

        vm.expectRevert("maxNumerator too large");
        vm.prank(ADMIN);
        feeSettings.registerFeeType(feeType, maxNumerator, 0, ADMIN);
    }

    function testFuzz_UnknownFeeTypeReturnsZeroFee(bytes32 feeType, uint256 amount, address tokenAddress) public {
        // Exclude all fee types that are already registered in setUp
        vm.assume(feeType != FeeTypes.TOKEN);
        vm.assume(feeType != FeeTypes.CROWDINVESTING);
        vm.assume(feeType != FeeTypes.PRIVATE_OFFER);
        vm.assume(feeType != FeeTypes.SECONDARY_MARKET);
        vm.assume(feeType != FeeTypes.DISTRIBUTION);
        vm.assume(feeType != FeeTypes.EXIT);

        assertEq(feeSettings.fee(feeType, amount, tokenAddress), 0, "Unknown fee type must return 0");
    }

    function testFuzz_FeeCalculationAndCollectorReturnedCorrectly(
        bytes32 feeType,
        uint32 maxNumerator,
        uint32 defaultNumerator,
        address collector,
        uint256 amount
    ) public {
        // constraints from _registerFeeType
        vm.assume(feeType != bytes32(0));
        vm.assume(maxNumerator > 0 && maxNumerator < feeSettings.FEE_DENOMINATOR());
        vm.assume(defaultNumerator <= maxNumerator);
        vm.assume(collector != address(0));
        // avoid overflow: amount * maxNumerator must not exceed uint256 max
        vm.assume(amount <= type(uint256).max / feeSettings.FEE_DENOMINATOR());

        // deploy a fresh FeeSettings with no pre-registered fee types
        FeeSettings logic = new FeeSettings(TRUSTED_FORWARDER);
        FeeSettingsCloneFactory factory = new FeeSettingsCloneFactory(address(logic));
        FeeSettings.FeeTypeInit[] memory emptyFeeTypes = new FeeSettings.FeeTypeInit[](0);
        FeeSettings freshFeeSettings = FeeSettings(
            factory.createFeeSettingsClone("fuzz-salt", TRUSTED_FORWARDER, ADMIN, emptyFeeTypes)
        );

        vm.startPrank(ADMIN);
        freshFeeSettings.registerFeeType(feeType, maxNumerator, defaultNumerator, collector);
        vm.stopPrank();

        uint256 expectedFee = (amount * defaultNumerator) / freshFeeSettings.FEE_DENOMINATOR();
        assertEq(freshFeeSettings.fee(feeType, amount, EXAMPLE_TOKEN_ADDRESS), expectedFee, "Fee calculation wrong");
        assertEq(freshFeeSettings.feeCollector(feeType, EXAMPLE_TOKEN_ADDRESS), collector, "Collector wrong");
    }

    function testFeeTypeId() public {
        assertEq(feeSettings.feeTypeId("TOKEN"), FeeTypes.TOKEN, "TOKEN id mismatch");
        assertEq(feeSettings.feeTypeId("CROWDINVESTING"), FeeTypes.CROWDINVESTING, "CROWDINVESTING id mismatch");
        assertEq(feeSettings.feeTypeId("PRIVATE_OFFER"), FeeTypes.PRIVATE_OFFER, "PRIVATE_OFFER id mismatch");
    }

    function testRegisterFeeTypeRevertsIfFeeTypeZero() public {
        vm.prank(ADMIN);
        vm.expectRevert("feeType cannot be 0");
        feeSettings.registerFeeType(bytes32(0), 100, 50, ADMIN);
    }

    function testRegisterFeeTypeRevertsIfMaxNumeratorZero() public {
        vm.prank(ADMIN);
        vm.expectRevert("maxNumerator cannot be 0");
        feeSettings.registerFeeType(keccak256("NEW_FEE_TYPE"), 0, 0, ADMIN);
    }

    function testRegisterFeeTypeRevertsIfAlreadyRegistered() public {
        vm.prank(ADMIN);
        vm.expectRevert("fee type already registered");
        feeSettings.registerFeeType(FeeTypes.TOKEN, 100, 50, ADMIN);
    }

    function testPlanFeeChangeRevertsIfUnknownFeeType() public {
        vm.prank(ADMIN);
        vm.expectRevert("unknown fee type");
        feeSettings.planFeeChange(keccak256("UNKNOWN_FEE_TYPE"), 1, uint64(block.timestamp + 1));
    }

    function testExecuteFeeChangeRevertsIfNoPendingChange() public {
        vm.prank(ADMIN);
        vm.expectRevert("no proposed fee change");
        feeSettings.executeFeeChange(FeeTypes.TOKEN);
    }

    function testSetCustomFeeRevertsIfUnknownFeeType() public {
        vm.prank(ADMIN);
        vm.expectRevert("unknown fee type");
        feeSettings.setCustomFee(
            keccak256("UNKNOWN_FEE_TYPE"),
            EXAMPLE_TOKEN_ADDRESS,
            1,
            uint64(block.timestamp + 1 days)
        );
    }

    function testSetCustomFeeRevertsIfNumeratorExceedsMax() public {
        vm.prank(ADMIN);
        vm.expectRevert("numerator exceeds max");
        feeSettings.setCustomFee(FeeTypes.TOKEN, EXAMPLE_TOKEN_ADDRESS, 501, uint64(block.timestamp + 1 days));
    }

    function testSetCustomFeeRevertsIfValidityDateInPast() public {
        vm.prank(ADMIN);
        vm.expectRevert("validity date must be in the future");
        feeSettings.setCustomFee(FeeTypes.TOKEN, EXAMPLE_TOKEN_ADDRESS, 1, uint64(block.timestamp));
    }

    function testSetDefaultFeeCollectorRevertsIfUnknownFeeType() public {
        vm.prank(ADMIN);
        vm.expectRevert("unknown fee type");
        feeSettings.setDefaultFeeCollector(keccak256("UNKNOWN_FEE_TYPE"), ADMIN);
    }

    function testSetCustomFeeCollectorRevertsIfUnknownFeeType() public {
        vm.prank(ADMIN);
        vm.expectRevert("unknown fee type");
        feeSettings.setCustomFeeCollector(keccak256("UNKNOWN_FEE_TYPE"), EXAMPLE_TOKEN_ADDRESS, ADMIN);
    }

    function testSetCustomFeeCollectorRevertsIfTokenZero() public {
        vm.prank(ADMIN);
        vm.expectRevert("token cannot be 0x0");
        feeSettings.setCustomFeeCollector(FeeTypes.TOKEN, address(0), ADMIN);
    }
}
