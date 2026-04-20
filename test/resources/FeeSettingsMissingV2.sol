// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

/**
 * @notice Stub FeeSettings that passes Token's 3-step ERC165 check for IFeeSettingsV2
 *         (supportsInterface returns true for every interfaceId except 0xffffffff),
 *         but does NOT implement any IFeeSettingsV2 functions.
 *         Used to verify that Token initialization succeeds while minting reverts.
 */
contract FeeSettingsMissingV2 {
    uint32 public constant FEE_DENOMINATOR = 10_000;
    uint32 public constant DEFAULT_FEE_NUMERATOR = 100;
    address private immutable _feeCollector;

    constructor(address feeCollector_) {
        _feeCollector = feeCollector_;
    }

    // Returns true for every interface ID except the ERC165 reserved invalid marker.
    // Passes the three-step ERC165 check Token uses for IFeeSettingsV2.
    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId != 0xffffffff;
    }

    // IFeeSettingsV1 functions (implemented so old V1 callers don't break)
    function tokenFee(uint256 amount) external pure returns (uint256) {
        return (amount * DEFAULT_FEE_NUMERATOR) / FEE_DENOMINATOR;
    }

    function continuousFundraisingFee(uint256 amount) external pure returns (uint256) {
        return (amount * DEFAULT_FEE_NUMERATOR) / FEE_DENOMINATOR;
    }

    function personalInviteFee(uint256 amount) external pure returns (uint256) {
        return (amount * DEFAULT_FEE_NUMERATOR) / FEE_DENOMINATOR;
    }

    function feeCollector() external view returns (address) {
        return _feeCollector;
    }

    function owner() external pure returns (address) {
        return address(0);
    }

    // IFeeSettingsV3 functions (implemented)
    function fee(bytes32, uint256 amount, address) external pure returns (uint256) {
        return (amount * DEFAULT_FEE_NUMERATOR) / FEE_DENOMINATOR;
    }

    function feeCollector(bytes32, address) external view returns (address) {
        return _feeCollector;
    }

    // IFeeSettingsV2 functions INTENTIONALLY ABSENT:
    //   tokenFee(uint256, address), tokenFeeCollector(address),
    //   crowdinvestingFee(uint256, address), crowdinvestingFeeCollector(address),
    //   privateOfferFee(uint256, address), privateOfferFeeCollector(address)
}
