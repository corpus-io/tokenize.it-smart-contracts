// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.23;

import "@openzeppelin/contracts/utils/introspection/ERC165.sol";

interface IFeeSettingsV1 {
    function tokenFee(uint256) external view returns (uint256);

    function crowdinvestingFee(uint256) external view returns (uint256);

    function privateOfferFee(uint256) external view returns (uint256);

    function feeCollector() external view returns (address);

    function owner() external view returns (address);

    function supportsInterface(bytes4) external view returns (bool); //because we inherit from ERC165
}

interface IFeeSettingsV2 {
    function tokenFee(uint256) external view returns (uint256);

    function tokenFeeCollector() external view returns (address);

    function crowdinvestingFee(uint256) external view returns (uint256);

    function crowdinvestingFeeCollector() external view returns (address);

    function privateOfferFee(uint256) external view returns (uint256);

    function privateOfferFeeCollector() external view returns (address);

    function owner() external view returns (address);

    function supportsInterface(bytes4) external view returns (bool); //because we inherit from ERC165
}

struct Fees {
    uint32 tokenFeeNumerator;
    uint32 tokenFeeDenominator;
    uint32 crowdinvestingFeeNumerator;
    uint32 crowdinvestingFeeDenominator;
    uint32 privateOfferFeeNumerator;
    uint32 privateOfferFeeDenominator;
    uint64 time;
}
