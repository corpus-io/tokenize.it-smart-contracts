// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.17;

import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import "./interfaces/IFeeSettings.sol";

/**
 * @title FeeSettings
 * @author malteish, cjentzsch
 * @notice The FeeSettings contract is used to manage fees paid to the tokenize.it platfom
 */
contract FeeSettings is Ownable2Step, ERC165, IFeeSettingsV2, IFeeSettingsV1 {
    uint128 public constant MIN_TOKEN_FEE_DENOMINATOR = 20;
    uint128 public constant MIN_CONTINUOUS_FUNDRAISING_FEE_DENOMINATOR = 10;
    uint128 public constant MIN_PERSONAL_INVITE_FEE_DENOMINATOR = 20;

    /// Denominator to calculate fees paid in Token.sol. UINT256_MAX means no fees.
    FeeFactor public tokenFeeFactor;
    /// address the token fees have to be paid to
    address public tokenFeeCollector;

    /// Denominator to calculate fees paid in PublicFundraising.sol. UINT256_MAX means no fees.
    FeeFactor public publicFundraisingFeeFactor;
    /// address the public fundraising fees have to be paid to
    address public publicFundraisingFeeCollector;

    /// Denominator to calculate fees paid in PrivateOffer.sol. UINT256_MAX means no fees.
    FeeFactor public privateOfferFeeFactor;
    /// address the private offer fees have to be paid to
    address public privateOfferFeeCollector;

    /// new fee settings that can be activated (after a delay in case of fee increase)
    Fees public proposedFees;

    /**
     * @notice Fee denominators have been set to the following values: `tokenFeeFactor`, `publicFundraisingFeeFactor`, `privateOfferFeeFactor`
     * @param tokenFee Defines the fee paid in Token.sol. UINT256_MAX means no fees.
     * @param publicFundraisingFee Defines the fee paid in PublicFundraising.sol. UINT256_MAX means no fees.
     * @param privateOfferFee Defines the fee paid in PrivateOffer.sol. UINT256_MAX means no fees.
     */
    event SetFeeFactors(FeeFactor tokenFee, FeeFactor publicFundraisingFee, FeeFactor privateOfferFee);

    /**
     * @notice The fee collector has been changed to `newFeeCollector`
     * @param newFeeCollector The new fee collector
     */
    event FeeCollectorsChanged(
        address indexed newFeeCollector,
        address indexed newPublicFundraisingFeeCollector,
        address indexed newPrivateOfferFeeCollector
    );

    /**
     * @notice A fee change has been proposed
     * @param proposal The new fee settings that have been proposed
     */
    event ChangeProposed(Fees proposal);

    /**
     * @notice Initializes the contract with the given fee denominators and fee collector
     * @param _fees The initial fee denominators
     * @param _tokenFeeCollector The initial fee collector
     * @param _publicFundraisingFeeCollector The initial public fundraising fee collector
     * @param _privateOfferFeeCollector The initial private offer fee collector
     */
    constructor(
        Fees memory _fees,
        address _tokenFeeCollector,
        address _publicFundraisingFeeCollector,
        address _privateOfferFeeCollector
    ) {
        checkFeeLimits(_fees);
        tokenFeeFactor = _fees.tokenFeeFactor;
        publicFundraisingFeeFactor = _fees.publicFundraisingFeeFactor;
        privateOfferFeeFactor = _fees.privateOfferFeeFactor;
        require(_tokenFeeCollector != address(0), "Fee collector cannot be 0x0");
        tokenFeeCollector = _tokenFeeCollector;
        require(_publicFundraisingFeeCollector != address(0), "Fee collector cannot be 0x0");
        publicFundraisingFeeCollector = _publicFundraisingFeeCollector;
        require(_privateOfferFeeCollector != address(0), "Fee collector cannot be 0x0");
        privateOfferFeeCollector = _privateOfferFeeCollector;
    }

    /**
     * @notice Prepares a fee change. Fee increases are subject to a minimum delay of 12 weeks, while fee reductions can be executed immediately.
     * @dev reducing fees = increasing the denominator
     * @param _fees The new fee denominators
     */
    function planFeeChange(Fees memory _fees) external onlyOwner {
        checkFeeLimits(_fees);

        // if at least one fee increases, enforce minimum delay
        if (
            _isFractionAGreater(_fees.tokenFeeFactor, tokenFeeFactor) ||
            _isFractionAGreater(_fees.publicFundraisingFeeFactor, publicFundraisingFeeFactor) ||
            _isFractionAGreater(_fees.privateOfferFeeFactor, privateOfferFeeFactor)
        ) {
            require(_fees.time > block.timestamp + 12 weeks, "Fee change must be at least 12 weeks in the future");
        }
        proposedFees = _fees;
        emit ChangeProposed(_fees);
    }

    /**
     * Compares two fractions and returns true if the first one is greater than the second one
     * @param _a input fraction a
     * @param _b input fraction b
     */
    function _isFractionAGreater(FeeFactor memory _a, FeeFactor memory _b) internal pure returns (bool) {
        return _a.numerator * _b.denominator > _b.numerator * _a.denominator;
    }

    /**
     * @notice Executes a fee change that has been planned before
     */
    function executeFeeChange() external onlyOwner {
        require(block.timestamp >= proposedFees.time, "Fee change must be executed after the change time");
        tokenFeeFactor = proposedFees.tokenFeeFactor;
        publicFundraisingFeeFactor = proposedFees.publicFundraisingFeeFactor;
        privateOfferFeeFactor = proposedFees.privateOfferFeeFactor;
        emit SetFeeFactors(tokenFeeFactor, publicFundraisingFeeFactor, privateOfferFeeFactor);
        delete proposedFees;
    }

    /**
     * @notice Sets a new fee collector
     * @param _tokenFeeCollector The new fee collector
     */
    function setFeeCollectors(
        address _tokenFeeCollector,
        address _publicFundraisingFeeCollector,
        address _personalOfferFeeCollector
    ) external onlyOwner {
        require(_tokenFeeCollector != address(0), "Fee collector cannot be 0x0");
        tokenFeeCollector = _tokenFeeCollector;
        require(_publicFundraisingFeeCollector != address(0), "Fee collector cannot be 0x0");
        publicFundraisingFeeCollector = _publicFundraisingFeeCollector;
        require(_personalOfferFeeCollector != address(0), "Fee collector cannot be 0x0");
        privateOfferFeeCollector = _personalOfferFeeCollector;
        emit FeeCollectorsChanged(_tokenFeeCollector, _publicFundraisingFeeCollector, _personalOfferFeeCollector);
    }

    /**
     * @notice Checks if the given fee settings are valid
     * @param _fees The fees to check
     */
    function checkFeeLimits(Fees memory _fees) internal pure {
        require(
            _fees.tokenFeeFactor.denominator / _fees.tokenFeeFactor.numerator >= MIN_TOKEN_FEE_DENOMINATOR,
            "Fee must be equal or less 5% (denominator must be >= 20)"
        );
        require(
            _fees.publicFundraisingFeeFactor.denominator / _fees.publicFundraisingFeeFactor.numerator >=
                MIN_CONTINUOUS_FUNDRAISING_FEE_DENOMINATOR,
            "PublicFundraising fee must be equal or less 10% (denominator must be >= 10)"
        );
        require(
            _fees.privateOfferFeeFactor.denominator / _fees.privateOfferFeeFactor.numerator >=
                MIN_PERSONAL_INVITE_FEE_DENOMINATOR,
            "Fee must be equal or less 5% (denominator must be >= 20)"
        );
    }

    /**
     * @notice Returns the fee for a given token amount
     * @dev will wrongly return 1 if denominator and amount are both uint256 max
     */
    function tokenFee(uint256 _tokenAmount) external view override(IFeeSettingsV1, IFeeSettingsV2) returns (uint256) {
        return (_tokenAmount * tokenFeeFactor.numerator) / tokenFeeFactor.denominator;
    }

    /**
     * @notice Calculates the fee for a given currency amount in PublicFundraising.sol
     * @dev will wrongly return 1 if denominator and amount are both uint256 max
     * @param _currencyAmount The amount of currency to calculate the fee for
     * @return The fee
     */
    function publicFundraisingFee(
        uint256 _currencyAmount
    ) external view override(IFeeSettingsV1, IFeeSettingsV2) returns (uint256) {
        return (_currencyAmount * publicFundraisingFeeFactor.numerator) / publicFundraisingFeeFactor.denominator;
    }

    /**
     * @notice Calculates the fee for a given currency amount in PrivateOffer.sol
     * @dev will wrongly return 1 if denominator and amount are both uint256 max
     * @param _currencyAmount The amount of currency to calculate the fee for
     * @return The fee
     */
    function privateOfferFee(
        uint256 _currencyAmount
    ) external view override(IFeeSettingsV1, IFeeSettingsV2) returns (uint256) {
        return (_currencyAmount * privateOfferFeeFactor.denominator) / privateOfferFeeFactor.denominator;
    }

    /**
     * @dev Specify where the implementation of owner() is located
     * @return The owner of the contract
     */
    function owner() public view override(Ownable, IFeeSettingsV1, IFeeSettingsV2) returns (address) {
        return Ownable.owner();
    }

    /**
     * @notice This contract implements the ERC165 interface in order to enable other contracts to query which interfaces this contract implements.
     * @dev See https://eips.ethereum.org/EIPS/eip-165
     * @return `true` for supported interfaces, otherwise `false`
     */
    function supportsInterface(
        bytes4 interfaceId
    ) public view virtual override(ERC165, IFeeSettingsV1, IFeeSettingsV2) returns (bool) {
        return
            interfaceId == type(IFeeSettingsV1).interfaceId || // we implement IFeeSettingsV1 for backwards compatibility
            interfaceId == type(IFeeSettingsV2).interfaceId || // we implement IFeeSettingsV2
            ERC165.supportsInterface(interfaceId); // default implementation that enables further querying
    }

    /**
     * @notice Returns the token fee collector
     * @dev this is a compatibility function for IFeeSettingsV1. It enables older token contracts to use the new fee settings contract.
     * @return The token fee collector
     */
    function feeCollector() external view override(IFeeSettingsV1) returns (address) {
        return tokenFeeCollector;
    }
}
