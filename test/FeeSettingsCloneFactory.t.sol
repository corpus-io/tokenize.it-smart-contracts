// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import "../lib/forge-std/src/Test.sol";
import "../lib/forge-std/src/console.sol";
import "../contracts/factories/FeeSettingsCloneFactory.sol";
import "../contracts/factories/PrivateOfferFactory.sol";
import "../contracts/factories/CoinvestedPositionCloneFactory.sol";
import "../contracts/common/IFeeSettings.sol";

contract tokenTest is Test {
    FeeSettingsCloneFactory factory;

    bytes32 exampleRawSalt = "salt";
    address public constant EXAMPLE_TOKEN = 0x8109709ecfa91a80626fF3989d68f67F5B1dD128;
    address public constant EXAMPLE_TRUSTED_FORWARDER = 0x9109709EcFA91A80626FF3989D68f67F5B1dD129;
    address public constant EXAMPLE_OWNER = 0x2109709EcFa91a80626Ff3989d68F67F5B1Dd122;
    address public constant EXAMPLE_TOKEN_FEE_COLLECTOR = 0x3109709ECfA91A80626fF3989D68f67F5B1Dd123;
    address public constant EXAMPLE_CROWDINVESTING_FEE_COLLECTOR = 0x4109709eCFa91A80626ff3989d68F67f5b1DD124;
    address public constant EXAMPLE_PRIVATE_OFFER_FEE_COLLECTOR = 0x4109709eCFa91A80626ff3989d68F67f5b1DD124;

    // exampleFees1: tokenFee=1, crowdinvestingFee=2, privateOfferFee=3
    // exampleFees2: tokenFee=70, crowdinvestingFee=80, privateOfferFee=90

    function setUp() public {
        factory = new FeeSettingsCloneFactory(address(new FeeSettings(EXAMPLE_TRUSTED_FORWARDER)));
    }

    function _buildFeeTypes(
        uint32 tokenNum,
        uint32 ciNum,
        uint32 poNum,
        address tokenCollector,
        address ciCollector,
        address poCollector
    ) internal pure returns (FeeSettings.FeeTypeInit[] memory) {
        FeeSettings.FeeTypeInit[] memory feeType = new FeeSettings.FeeTypeInit[](6);
        feeType[0] = FeeSettings.FeeTypeInit(FeeTypes.TOKEN, 500, tokenNum, tokenCollector);
        feeType[1] = FeeSettings.FeeTypeInit(FeeTypes.CROWDINVESTING, 1000, ciNum, ciCollector);
        feeType[2] = FeeSettings.FeeTypeInit(FeeTypes.PRIVATE_OFFER, 500, poNum, poCollector);
        feeType[3] = FeeSettings.FeeTypeInit(FeeTypes.SECONDARY_MARKET, 500, 0, poCollector);
        feeType[4] = FeeSettings.FeeTypeInit(FeeTypes.DISTRIBUTION, 500, 0, poCollector);
        feeType[5] = FeeSettings.FeeTypeInit(FeeTypes.EXIT, 500, 0, poCollector);
        return feeType;
    }

    function _buildFeeTypesAllSame(
        uint32 tokenNum,
        uint32 ciNum,
        uint32 poNum,
        address collector
    ) internal pure returns (FeeSettings.FeeTypeInit[] memory) {
        return _buildFeeTypes(tokenNum, ciNum, poNum, collector, collector, collector);
    }

    function testAddressPrediction(
        bytes32 _rawSalt,
        address _owner,
        address _tokenFeeCollector,
        address _crowdinvestingFeeCollector,
        address _privateOfferFeeCollector
    ) public {
        vm.assume(_owner != address(0));
        vm.assume(_tokenFeeCollector != address(0));
        vm.assume(_crowdinvestingFeeCollector != address(0));
        vm.assume(_privateOfferFeeCollector != address(0));

        FeeSettings.FeeTypeInit[] memory feeTypes = _buildFeeTypes(
            1,
            2,
            3,
            _tokenFeeCollector,
            _crowdinvestingFeeCollector,
            _privateOfferFeeCollector
        );

        bytes32 salt = keccak256(abi.encode(_rawSalt, EXAMPLE_TRUSTED_FORWARDER, _owner, feeTypes));

        address expected1 = factory.predictCloneAddress(salt);
        address expected2 = factory.predictCloneAddress(_rawSalt, EXAMPLE_TRUSTED_FORWARDER, _owner, feeTypes);

        address actual = factory.createFeeSettingsClone(_rawSalt, EXAMPLE_TRUSTED_FORWARDER, _owner, feeTypes);

        assertEq(expected1, expected2, "address prediction with salt and params not equal");
        assertEq(expected1, actual, "address prediction failed");
    }

    function testChangingParametersChangesAddress() public view {
        address someAddress = address(42);

        FeeSettings.FeeTypeInit[] memory baseFeeTypes = _buildFeeTypes(
            1,
            2,
            3,
            EXAMPLE_TOKEN_FEE_COLLECTOR,
            EXAMPLE_CROWDINVESTING_FEE_COLLECTOR,
            EXAMPLE_PRIVATE_OFFER_FEE_COLLECTOR
        );

        address base = factory.predictCloneAddress(
            exampleRawSalt,
            EXAMPLE_TRUSTED_FORWARDER,
            EXAMPLE_OWNER,
            baseFeeTypes
        );

        FeeSettings.FeeTypeInit[] memory changedFeeTypes;

        changedFeeTypes = _buildFeeTypes(
            1,
            2,
            3,
            EXAMPLE_TOKEN_FEE_COLLECTOR,
            EXAMPLE_CROWDINVESTING_FEE_COLLECTOR,
            EXAMPLE_PRIVATE_OFFER_FEE_COLLECTOR
        );
        address changed = factory.predictCloneAddress("0", EXAMPLE_TRUSTED_FORWARDER, EXAMPLE_OWNER, changedFeeTypes);
        assertTrue(base != changed, "addresses equal with raw salt changed");

        changedFeeTypes = _buildFeeTypes(
            70,
            80,
            90,
            EXAMPLE_TOKEN_FEE_COLLECTOR,
            EXAMPLE_CROWDINVESTING_FEE_COLLECTOR,
            EXAMPLE_PRIVATE_OFFER_FEE_COLLECTOR
        );
        changed = factory.predictCloneAddress(
            exampleRawSalt,
            EXAMPLE_TRUSTED_FORWARDER,
            EXAMPLE_OWNER,
            changedFeeTypes
        );
        assertTrue(base != changed, "addresses equal with fees changed");

        changedFeeTypes = _buildFeeTypes(
            1,
            2,
            3,
            EXAMPLE_TOKEN_FEE_COLLECTOR,
            EXAMPLE_CROWDINVESTING_FEE_COLLECTOR,
            EXAMPLE_PRIVATE_OFFER_FEE_COLLECTOR
        );
        changed = factory.predictCloneAddress(exampleRawSalt, someAddress, EXAMPLE_OWNER, changedFeeTypes);
        assertTrue(base != changed, "addresses equal with trustedForwarder changed");

        changedFeeTypes = _buildFeeTypes(
            1,
            2,
            3,
            EXAMPLE_TOKEN_FEE_COLLECTOR,
            EXAMPLE_CROWDINVESTING_FEE_COLLECTOR,
            EXAMPLE_PRIVATE_OFFER_FEE_COLLECTOR
        );
        changed = factory.predictCloneAddress(exampleRawSalt, EXAMPLE_TRUSTED_FORWARDER, someAddress, changedFeeTypes);
        assertTrue(base != changed, "addresses equal with owner changed");

        changedFeeTypes = _buildFeeTypes(
            1,
            2,
            3,
            someAddress,
            EXAMPLE_CROWDINVESTING_FEE_COLLECTOR,
            EXAMPLE_PRIVATE_OFFER_FEE_COLLECTOR
        );
        changed = factory.predictCloneAddress(
            exampleRawSalt,
            EXAMPLE_TRUSTED_FORWARDER,
            EXAMPLE_OWNER,
            changedFeeTypes
        );
        assertTrue(base != changed, "addresses equal with tokenFeeCollector changed");

        changedFeeTypes = _buildFeeTypes(
            1,
            2,
            3,
            EXAMPLE_TOKEN_FEE_COLLECTOR,
            someAddress,
            EXAMPLE_PRIVATE_OFFER_FEE_COLLECTOR
        );
        changed = factory.predictCloneAddress(
            exampleRawSalt,
            EXAMPLE_TRUSTED_FORWARDER,
            EXAMPLE_OWNER,
            changedFeeTypes
        );
        assertTrue(base != changed, "addresses equal with crowdinvestingFeeCollector changed");

        changedFeeTypes = _buildFeeTypes(
            1,
            2,
            3,
            EXAMPLE_TOKEN_FEE_COLLECTOR,
            EXAMPLE_CROWDINVESTING_FEE_COLLECTOR,
            someAddress
        );
        changed = factory.predictCloneAddress(
            exampleRawSalt,
            EXAMPLE_TRUSTED_FORWARDER,
            EXAMPLE_OWNER,
            changedFeeTypes
        );
        assertTrue(base != changed, "addresses equal with privateOfferFeeCollector changed");
    }

    function testSecondDeploymentFails() public {
        FeeSettings.FeeTypeInit[] memory feeTypes = _buildFeeTypes(
            1,
            2,
            3,
            EXAMPLE_TOKEN_FEE_COLLECTOR,
            EXAMPLE_CROWDINVESTING_FEE_COLLECTOR,
            EXAMPLE_PRIVATE_OFFER_FEE_COLLECTOR
        );

        factory.createFeeSettingsClone(exampleRawSalt, EXAMPLE_TRUSTED_FORWARDER, EXAMPLE_OWNER, feeTypes);

        vm.expectRevert("ERC1167: create2 failed");
        factory.createFeeSettingsClone(exampleRawSalt, EXAMPLE_TRUSTED_FORWARDER, EXAMPLE_OWNER, feeTypes);
    }

    function testInitialization(
        address _owner,
        address _tokenFeeCollector,
        address _crowdinvestingFeeCollector,
        address _privateOfferFeeCollector
    ) public {
        vm.assume(_owner != address(0));
        vm.assume(_tokenFeeCollector != address(0));
        vm.assume(_crowdinvestingFeeCollector != address(0));
        vm.assume(_privateOfferFeeCollector != address(0));

        FeeSettings.FeeTypeInit[] memory feeTypes = _buildFeeTypes(
            1,
            2,
            3,
            _tokenFeeCollector,
            _crowdinvestingFeeCollector,
            _privateOfferFeeCollector
        );

        FeeSettings feeSettings = FeeSettings(
            factory.createFeeSettingsClone(exampleRawSalt, EXAMPLE_TRUSTED_FORWARDER, _owner, feeTypes)
        );

        assertEq(feeSettings.owner(), _owner, "owner not set");
        assertEq(feeSettings.tokenFeeCollector(EXAMPLE_TOKEN), _tokenFeeCollector, "tokenFeeCollector not set");
        assertEq(
            feeSettings.crowdinvestingFeeCollector(EXAMPLE_TOKEN),
            _crowdinvestingFeeCollector,
            "crowdinvestingFeeCollector not set"
        );

        assertEq(
            feeSettings.privateOfferFeeCollector(EXAMPLE_TOKEN),
            _privateOfferFeeCollector,
            "privateOfferFeeCollector not set"
        );

        (, uint32 _tokenFeeNumerator) = feeSettings.feeTypeConfigs(FeeTypes.TOKEN);
        (, uint32 _crowdinvestingFeeNumerator) = feeSettings.feeTypeConfigs(FeeTypes.CROWDINVESTING);
        (, uint32 _privateOfferFeeNumerator) = feeSettings.feeTypeConfigs(FeeTypes.PRIVATE_OFFER);

        assertEq(_tokenFeeNumerator, 1, "defaultTokenFeeNumerator not set");
        assertEq(_crowdinvestingFeeNumerator, 2, "defaultCrowdinvestingFeeNumerator not set");
        assertEq(_privateOfferFeeNumerator, 3, "defaultPrivateOfferFeeNumerator not set");
    }

    function testWrongForwarderReverts(address _wrongTrustedForwarder) public {
        vm.assume(_wrongTrustedForwarder != EXAMPLE_TRUSTED_FORWARDER);
        vm.assume(_wrongTrustedForwarder != address(0));

        FeeSettings.FeeTypeInit[] memory feeTypes = _buildFeeTypesAllSame(1, 2, 3, EXAMPLE_TOKEN_FEE_COLLECTOR);

        vm.expectRevert("FeeSettingsCloneFactory: Unexpected trustedForwarder");
        factory.createFeeSettingsClone(bytes32(0), _wrongTrustedForwarder, EXAMPLE_OWNER, feeTypes);
    }

    function testPrivateOfferFactoryRevertsIfTimeLockFactoryZero() public {
        vm.expectRevert(PrivateOfferFactory.ZeroTimeLockCloneFactoryAddress.selector);
        new PrivateOfferFactory(TimeLockCloneFactory(address(0)), CoinvestedPositionCloneFactory(address(1)));
    }
}
