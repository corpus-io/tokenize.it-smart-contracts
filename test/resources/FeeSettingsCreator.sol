// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import "../../lib/forge-std/src/Test.sol";
import "../../contracts/factories/FeeSettingsCloneFactory.sol";

function buildFeeTypes(
    uint32 _tokenFeeNumerator,
    uint32 _crowdinvestingFeeNumerator,
    uint32 _privateOfferFeeNumerator,
    address _tokenFeeCollector,
    address _crowdinvestingFeeCollector,
    address _privateOfferFeeCollector
) pure returns (FeeSettings.FeeTypeInit[] memory) {
    FeeSettings.FeeTypeInit[] memory feeTypes = new FeeSettings.FeeTypeInit[](6);
    feeTypes[0] = FeeSettings.FeeTypeInit(FeeTypes.TOKEN, 500, _tokenFeeNumerator, _tokenFeeCollector);
    feeTypes[1] = FeeSettings.FeeTypeInit(
        FeeTypes.CROWDINVESTING,
        1000,
        _crowdinvestingFeeNumerator,
        _crowdinvestingFeeCollector
    );
    feeTypes[2] = FeeSettings.FeeTypeInit(
        FeeTypes.PRIVATE_OFFER,
        500,
        _privateOfferFeeNumerator,
        _privateOfferFeeCollector
    );
    feeTypes[3] = FeeSettings.FeeTypeInit(
        FeeTypes.SECONDARY_MARKET,
        500,
        _privateOfferFeeNumerator,
        _privateOfferFeeCollector
    );
    feeTypes[4] = FeeSettings.FeeTypeInit(
        FeeTypes.DISTRIBUTION,
        500,
        _privateOfferFeeNumerator,
        _privateOfferFeeCollector
    );
    feeTypes[5] = FeeSettings.FeeTypeInit(FeeTypes.EXIT, 500, _privateOfferFeeNumerator, _privateOfferFeeCollector);
    return feeTypes;
}

function createFeeSettings(
    address _trustedForwarder,
    address _owner,
    FeeSettings.FeeTypeInit[] memory _feeTypes
) returns (FeeSettings) {
    FeeSettings logicContract = new FeeSettings(_trustedForwarder);
    FeeSettingsCloneFactory factory = new FeeSettingsCloneFactory(address(logicContract));
    FeeSettings clone = FeeSettings(factory.createFeeSettingsClone("someSalt", _trustedForwarder, _owner, _feeTypes));

    return clone;
}
