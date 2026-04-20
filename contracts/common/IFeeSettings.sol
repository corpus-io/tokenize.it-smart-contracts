// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import "@openzeppelin/contracts/utils/introspection/ERC165.sol";

/**
 * @title IFeeSettingsV1
 * @author malteish
 * @notice This is the interface for the FeeSettings contract in v4 of the tokenize.it contracts. The token contract
 * and the investment contracts will use this interface to get the fees for the different actions, as well as the address
 * of the fee collector.
 */
interface IFeeSettingsV1 {
    function tokenFee(uint256) external view returns (uint256);

    function continuousFundraisingFee(uint256) external view returns (uint256);

    function personalInviteFee(uint256) external view returns (uint256);

    function feeCollector() external view returns (address);

    function owner() external view returns (address);

    function supportsInterface(bytes4) external view returns (bool); //because we inherit from ERC165
}

/**
 * @title IFeeSettingsV2
 * @author malteish
 * @notice This is the interface for the FeeSettings contract in v5 of the tokenize.it contracts.
 * From v4 to v5, the contract names have changed and instead of one fee collector, there are now three.
 */
interface IFeeSettingsV2 {
    function tokenFee(uint256, address) external view returns (uint256);

    function tokenFeeCollector(address) external view returns (address);

    function crowdinvestingFee(uint256, address) external view returns (uint256);

    function crowdinvestingFeeCollector(address) external view returns (address);

    function privateOfferFee(uint256, address) external view returns (uint256);

    function privateOfferFeeCollector(address) external view returns (address);

    function owner() external view returns (address);

    function supportsInterface(bytes4) external view returns (bool); //because we inherit from ERC165
}

/**
 * @notice Central registry of well-known fee type identifiers.
 *      Import this library alongside IFeeSettingsV3 to avoid re-declaring the same keccak constants
 *      in every consuming contract.
 */
library FeeTypes {
    bytes32 internal constant TOKEN = keccak256("TOKEN");
    bytes32 internal constant CROWDINVESTING = keccak256("CROWDINVESTING");
    bytes32 internal constant PRIVATE_OFFER = keccak256("PRIVATE_OFFER");
    bytes32 internal constant SECONDARY_MARKET = keccak256("SECONDARY_MARKET");
    bytes32 internal constant DISTRIBUTION = keccak256("DISTRIBUTION");
    bytes32 internal constant EXIT = keccak256("EXIT");
}

/**
 * @title IFeeSettingsV3
 * @author malteish
 * @notice Generic, extendable fee interface.
 */
interface IFeeSettingsV3 {
    /**
     * @notice Calculates the fee for a given amount and fee type.
     * @param feeType  bytes32 key identifying the fee type (use FeeTypes library constants)
     * @param amount   The base amount to calculate the fee on
     * @param token    The token address — used to look up any custom discount for that token
     * @return         The fee amount
     */
    function fee(bytes32 feeType, uint256 amount, address token) external view returns (uint256);

    /**
     * @notice Returns the fee collector for a given fee type and token.
     *      Falls back to the default collector for that fee type if no custom one is set.
     * @param feeType  bytes32 key identifying the fee type
     * @param token    The token address
     * @return         The fee collector address
     */
    function feeCollector(bytes32 feeType, address token) external view returns (address);

    function supportsInterface(bytes4) external view returns (bool);
}
