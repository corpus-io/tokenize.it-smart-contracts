// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.17;

import "@openzeppelin/contracts/utils/introspection/ERC165.sol";

interface IFeeSettingsV1 {
    function tokenFee(uint256) external view returns (uint256);

    function publicFundraisingFee(uint256) external view returns (uint256);

    function privateOfferFee(uint256) external view returns (uint256);

    function feeCollector() external view returns (address);

    function owner() external view returns (address);

    function supportsInterface(bytes4) external view returns (bool); //because we inherit from ERC165
}

interface IFeeSettingsV2 {
    function tokenFee(uint256) external view returns (uint256);

    function tokenFeeCollector() external view returns (address);

    function publicFundraisingFee(uint256) external view returns (uint256);

    function publicFundraisingFeeCollector() external view returns (address);

    function privateOfferFee(uint256) external view returns (uint256);

    function privateOfferFeeCollector() external view returns (address);

    function owner() external view returns (address);

    function supportsInterface(bytes4) external view returns (bool); //because we inherit from ERC165
}

/**
 * @title FeeFactor struct
 * @notice FeeFactor is a struct used to represent a fee factor, split into a numerator and a denominator
 * @dev The fee factor is calculated as `numerator / denominator`
 * @dev As fees over 100% don't make sense, the denominator will almost always be greater than or equal to the numerator
 */
struct FeeFactor {
    uint128 numerator;
    uint128 denominator;
}

struct Fees {
    FeeFactor tokenFeeFactor;
    FeeFactor publicFundraisingFeeFactor;
    FeeFactor privateOfferFeeFactor;
    uint256 time;
}
