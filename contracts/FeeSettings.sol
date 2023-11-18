// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.23;

import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import "./interfaces/IFeeSettings.sol";

/**
 * @title FeeSettings
 * @author malteish, cjentzsch
 * @notice The FeeSettings contract is used to manage fees paid to the tokenize.it platfom
 */
contract FeeSettings is Ownable2Step, ERC165, IFeeSettingsV2, IFeeSettingsV1 {
    /// max token fee is 5%
    uint32 public constant MAX_TOKEN_FEE_NUMERATOR = 1;
    uint32 public constant MAX_TOKEN_FEE_DENOMINATOR = 20;
    /// max crowdinvesting fee is 10%
    uint32 public constant MAX_CONTINUOUS_FUNDRAISING_FEE_NUMERATOR = 1;
    uint32 public constant MAX_CONTINUOUS_FUNDRAISING_FEE_DENOMINATOR = 10;
    /// max private offer fee is 5%
    uint32 public constant MAX_PERSONAL_INVITE_FEE_NUMERATOR = 1;
    uint32 public constant MAX_PERSONAL_INVITE_FEE_DENOMINATOR = 20;

    /// Numerator to calculate fees paid in Token.sol.
    uint32 public tokenFeeNumerator;
    /// Denominator to calculate fees paid in Token.sol.
    uint32 public tokenFeeDenominator;

    /// Numerator to calculate fees paid in Crowdinvesting.sol.
    uint32 public crowdinvestingFeeNumerator;
    /// Denominator to calculate fees paid in Crowdinvesting.sol.
    uint32 public crowdinvestingFeeDenominator;

    /// Numerator to calculate fees paid in PrivateOffer.sol.
    uint32 public privateOfferFeeNumerator;
    /// Denominator to calculate fees paid in PrivateOffer.sol.
    uint32 public privateOfferFeeDenominator;

    /// address the token fees have to be paid to
    address public tokenFeeCollector;
    /// address the crowdinvesting fees have to be paid to
    address public crowdinvestingFeeCollector;

    /// address the private offer fees have to be paid to
    address public privateOfferFeeCollector;

    /// new fee settings that can be activated (after a delay in case of fee increase)
    Fees public proposedFees;

    /**
     * @notice Fee factors have been changed
     * @param tokenFeeNumerator a in fraction a/b that defines the fee paid in Token: fee = amount * a / b
     * @param tokenFeeDenominator b in fraction a/b that defines the fee paid in Token: fee = amount * a / b
     * @param crowdinvestingFeeNumerator a in fraction a/b that defines the fee paid in currency for crowdinvesting: fee = amount * a / b
     * @param crowdinvestingFeeDenominator b in fraction a/b that defines the fee paid in currency for crowdinvesting: fee = amount * a / b
     * @param privateOfferFeeNumerator a in fraction a/b that defines the fee paid in currency for private offers: fee = amount * a / b
     * @param privateOfferFeeDenominator b in fraction a/b that defines the fee paid in currency for private offers: fee = amount * a / b
     */
    event SetFee(
        uint32 tokenFeeNumerator,
        uint32 tokenFeeDenominator,
        uint32 crowdinvestingFeeNumerator,
        uint32 crowdinvestingFeeDenominator,
        uint32 privateOfferFeeNumerator,
        uint32 privateOfferFeeDenominator
    );

    /**
     * @notice The fee collector has been changed to `newFeeCollector`
     * @param newFeeCollector The new fee collector
     */
    event FeeCollectorsChanged(
        address indexed newFeeCollector,
        address indexed newCrowdinvestingFeeCollector,
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
     * @param _crowdinvestingFeeCollector The initial crowdinvesting fee collector
     * @param _privateOfferFeeCollector The initial private offer fee collector
     */
    constructor(
        Fees memory _fees,
        address _tokenFeeCollector,
        address _crowdinvestingFeeCollector,
        address _privateOfferFeeCollector
    ) {
        checkFeeLimits(_fees);
        tokenFeeNumerator = _fees.tokenFeeNumerator;
        tokenFeeDenominator = _fees.tokenFeeDenominator;
        crowdinvestingFeeNumerator = _fees.crowdinvestingFeeNumerator;
        crowdinvestingFeeDenominator = _fees.crowdinvestingFeeDenominator;
        privateOfferFeeNumerator = _fees.privateOfferFeeNumerator;
        privateOfferFeeDenominator = _fees.privateOfferFeeDenominator;
        require(_tokenFeeCollector != address(0), "Fee collector cannot be 0x0");
        tokenFeeCollector = _tokenFeeCollector;
        require(_crowdinvestingFeeCollector != address(0), "Fee collector cannot be 0x0");
        crowdinvestingFeeCollector = _crowdinvestingFeeCollector;
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
            _isFractionAGreater(
                _fees.tokenFeeNumerator,
                _fees.tokenFeeDenominator,
                tokenFeeNumerator,
                tokenFeeDenominator
            ) ||
            _isFractionAGreater(
                _fees.crowdinvestingFeeNumerator,
                _fees.crowdinvestingFeeDenominator,
                crowdinvestingFeeNumerator,
                crowdinvestingFeeDenominator
            ) ||
            _isFractionAGreater(
                _fees.privateOfferFeeNumerator,
                _fees.privateOfferFeeDenominator,
                privateOfferFeeNumerator,
                privateOfferFeeDenominator
            )
        ) {
            require(_fees.time > block.timestamp + 12 weeks, "Fee change must be at least 12 weeks in the future");
        }
        proposedFees = _fees;
        emit ChangeProposed(_fees);
    }

    /**
     * @notice Executes a fee change that has been planned before
     */
    function executeFeeChange() external onlyOwner {
        require(block.timestamp >= proposedFees.time, "Fee change must be executed after the change time");
        tokenFeeNumerator = proposedFees.tokenFeeNumerator;
        tokenFeeDenominator = proposedFees.tokenFeeDenominator;
        crowdinvestingFeeNumerator = proposedFees.crowdinvestingFeeNumerator;
        crowdinvestingFeeDenominator = proposedFees.crowdinvestingFeeDenominator;
        privateOfferFeeNumerator = proposedFees.privateOfferFeeNumerator;
        privateOfferFeeDenominator = proposedFees.privateOfferFeeDenominator;
        emit SetFee(
            tokenFeeNumerator,
            tokenFeeDenominator,
            crowdinvestingFeeNumerator,
            crowdinvestingFeeDenominator,
            privateOfferFeeNumerator,
            privateOfferFeeDenominator
        );
        delete proposedFees;
    }

    /**
     * @notice Sets a new fee collector
     * @param _tokenFeeCollector The new fee collector
     */
    function setFeeCollectors(
        address _tokenFeeCollector,
        address _crowdinvestingFeeCollector,
        address _personalOfferFeeCollector
    ) external onlyOwner {
        require(_tokenFeeCollector != address(0), "Fee collector cannot be 0x0");
        tokenFeeCollector = _tokenFeeCollector;
        require(_crowdinvestingFeeCollector != address(0), "Fee collector cannot be 0x0");
        crowdinvestingFeeCollector = _crowdinvestingFeeCollector;
        require(_personalOfferFeeCollector != address(0), "Fee collector cannot be 0x0");
        privateOfferFeeCollector = _personalOfferFeeCollector;
        emit FeeCollectorsChanged(_tokenFeeCollector, _crowdinvestingFeeCollector, _personalOfferFeeCollector);
    }

    /**
     * Compares two fractions and returns true if the first one is greater than the second one
     * @param aNumerator numerator in fraction aNumerator/aDenominator
     * @param aDenominator denominator in fraction aNumerator/aDenominator
     * @param bNumerator numerator in fraction bNumerator/bDenominator
     * @param bDenominator denominator in fraction bNumerator/bDenominator
     */
    function _isFractionAGreater(
        uint32 aNumerator,
        uint32 aDenominator,
        uint32 bNumerator,
        uint32 bDenominator
    ) internal pure returns (bool) {
        return uint256(aNumerator) * bDenominator > uint256(bNumerator) * aDenominator;
    }

    /**
     * @notice Checks if the given fee settings are valid
     * @param _fees The fees to check
     */
    function checkFeeLimits(Fees memory _fees) internal pure {
        require(
            _fees.tokenFeeDenominator > 0 &&
                _fees.crowdinvestingFeeDenominator > 0 &&
                _fees.privateOfferFeeDenominator > 0,
            "Denominator cannot be 0"
        );
        require(
            !_isFractionAGreater(
                _fees.tokenFeeNumerator,
                _fees.tokenFeeDenominator,
                MAX_TOKEN_FEE_NUMERATOR,
                MAX_TOKEN_FEE_DENOMINATOR
            ),
            "Token fee must be equal or less 5%"
        );
        require(
            !_isFractionAGreater(
                _fees.crowdinvestingFeeNumerator,
                _fees.crowdinvestingFeeDenominator,
                MAX_CONTINUOUS_FUNDRAISING_FEE_NUMERATOR,
                MAX_CONTINUOUS_FUNDRAISING_FEE_DENOMINATOR
            ),
            "Crowdinvesting fee must be equal or less 10%"
        );
        require(
            !_isFractionAGreater(
                _fees.privateOfferFeeNumerator,
                _fees.privateOfferFeeDenominator,
                MAX_PERSONAL_INVITE_FEE_NUMERATOR,
                MAX_PERSONAL_INVITE_FEE_DENOMINATOR
            ),
            "PrivateOffer fee must be equal or less 5%"
        );
    }

    /**
     * @notice Returns the fee for a given token amount
     * @dev will wrongly return 1 if denominator and amount are both uint256 max
     */
    function tokenFee(uint256 _tokenAmount) external view override(IFeeSettingsV1, IFeeSettingsV2) returns (uint256) {
        return (_tokenAmount * tokenFeeNumerator) / tokenFeeDenominator;
    }

    /**
     * @notice Calculates the fee for a given currency amount in Crowdinvesting.sol
     * @dev will wrongly return 1 if denominator and amount are both uint256 max
     * @param _currencyAmount The amount of currency to calculate the fee for
     * @return The fee
     */
    function crowdinvestingFee(uint256 _currencyAmount) external view override(IFeeSettingsV2) returns (uint256) {
        return _crowdinvestingFee(_currencyAmount);
    }

    function _crowdinvestingFee(uint256 _currencyAmount) internal view returns (uint256) {
        return (_currencyAmount * crowdinvestingFeeNumerator) / crowdinvestingFeeDenominator;
    }

    /**
     * @notice Calculates the fee for a given currency amount in PrivateOffer.sol
     * @dev will wrongly return 1 if denominator and amount are both uint256 max
     * @param _currencyAmount The amount of currency to calculate the fee for
     * @return The fee
     */
    function privateOfferFee(uint256 _currencyAmount) external view override(IFeeSettingsV2) returns (uint256) {
        return _privateOfferFee(_currencyAmount);
    }

    function _privateOfferFee(uint256 _currencyAmount) internal view returns (uint256) {
        return (_currencyAmount * privateOfferFeeNumerator) / privateOfferFeeDenominator;
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

    /**
     * @notice calculate the fee for a given currency amount in Crowdinvesting (formerly ContinuousFundraising)
     * @dev this is a compatibility function for IFeeSettingsV1. It enables older token contracts to use the new fee settings contract.
     * @param _currencyAmount The amount of currency to calculate the fee for
     */
    function continuousFundraisingFee(
        uint256 _currencyAmount
    ) external view override(IFeeSettingsV1) returns (uint256) {
        return _crowdinvestingFee(_currencyAmount);
    }

    /**
     * @notice calculate the fee for a given currency amount in PrivateOffer (formerly PersonalInvite)
     * @dev this is a compatibility function for IFeeSettingsV1. It enables older token contracts to use the new fee settings contract.
     * @param _currencyAmount The amount of currency to calculate the fee for
     */
    function personalInviteFee(uint256 _currencyAmount) external view override(IFeeSettingsV1) returns (uint256) {
        return _privateOfferFee(_currencyAmount);
    }
}
