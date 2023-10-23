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
    uint256 public tokenFeeDenominator;
    /// address the token fees have to be paid to
    address public tokenFeeCollector;

    /// Denominator to calculate fees paid in PublicOffer.sol. UINT256_MAX means no fees.
    uint256 public publicOfferFeeDenominator;
    /// address the continuous fundraising fees have to be paid to
    address public publicOfferFeeCollector;

    /// Denominator to calculate fees paid in PersonalInvite.sol. UINT256_MAX means no fees.
    uint256 public personalInviteFeeDenominator;
    /// address the personal invite fees have to be paid to
    address public personalInviteFeeCollector;

    /// new fee settings that can be activated (after a delay in case of fee increase)
    Fees public proposedFees;

    /**
     * @notice Fee denominators have been set to the following values: `tokenFeeDenominator`, `publicOfferFeeDenominator`, `personalInviteFeeDenominator`
     * @param tokenFeeDenominator Defines the fee paid in Token.sol. UINT256_MAX means no fees.
     * @param publicOfferFeeDenominator Defines the fee paid in PublicOffer.sol. UINT256_MAX means no fees.
     * @param personalInviteFeeDenominator Defines the fee paid in PersonalInvite.sol. UINT256_MAX means no fees.
     */
    event SetFeeDenominators(
        uint256 tokenFeeDenominator,
        uint256 publicOfferFeeDenominator,
        uint256 personalInviteFeeDenominator
    );

    /**
     * @notice The fee collector has been changed to `newFeeCollector`
     * @param newFeeCollector The new fee collector
     */
    event FeeCollectorsChanged(
        address indexed newFeeCollector,
        address indexed newPublicOfferFeeCollector,
        address indexed newPersonalInviteFeeCollector
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
     * @param _publicOfferFeeCollector The initial continuous fundraising fee collector
     * @param _personalInviteFeeCollector The initial personal invite fee collector
     */
    constructor(
        Fees memory _fees,
        address _tokenFeeCollector,
        address _publicOfferFeeCollector,
        address _personalInviteFeeCollector
    ) {
        checkFeeLimits(_fees);
        tokenFeeDenominator = _fees.tokenFeeDenominator;
        publicOfferFeeDenominator = _fees.publicOfferFeeDenominator;
        personalInviteFeeDenominator = _fees.personalInviteFeeDenominator;
        require(_tokenFeeCollector != address(0), "Fee collector cannot be 0x0");
        tokenFeeCollector = _tokenFeeCollector;
        require(_publicOfferFeeCollector != address(0), "Fee collector cannot be 0x0");
        publicOfferFeeCollector = _publicOfferFeeCollector;
        require(_personalInviteFeeCollector != address(0), "Fee collector cannot be 0x0");
        personalInviteFeeCollector = _personalInviteFeeCollector;
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
            _fees.tokenFeeDenominator < tokenFeeDenominator ||
            _fees.publicOfferFeeDenominator < publicOfferFeeDenominator ||
            _fees.personalInviteFeeDenominator < personalInviteFeeDenominator
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
        tokenFeeDenominator = proposedFees.tokenFeeDenominator;
        publicOfferFeeDenominator = proposedFees.publicOfferFeeDenominator;
        personalInviteFeeDenominator = proposedFees.personalInviteFeeDenominator;
        emit SetFeeDenominators(tokenFeeDenominator, publicOfferFeeDenominator, personalInviteFeeDenominator);
        delete proposedFees;
    }

    /**
     * @notice Sets a new fee collector
     * @param _tokenFeeCollector The new fee collector
     */
    function setFeeCollectors(
        address _tokenFeeCollector,
        address _publicOfferFeeCollector,
        address _personalOfferFeeCollector
    ) external onlyOwner {
        require(_tokenFeeCollector != address(0), "Fee collector cannot be 0x0");
        tokenFeeCollector = _tokenFeeCollector;
        require(_publicOfferFeeCollector != address(0), "Fee collector cannot be 0x0");
        publicOfferFeeCollector = _publicOfferFeeCollector;
        require(_personalOfferFeeCollector != address(0), "Fee collector cannot be 0x0");
        personalInviteFeeCollector = _personalOfferFeeCollector;
        emit FeeCollectorsChanged(_tokenFeeCollector, _publicOfferFeeCollector, _personalOfferFeeCollector);
    }

    /**
     * @notice Checks if the given fee settings are valid
     * @param _fees The fees to check
     */
    function checkFeeLimits(Fees memory _fees) internal pure {
        require(
            _fees.tokenFeeDenominator >= MIN_TOKEN_FEE_DENOMINATOR,
            "Fee must be equal or less 5% (denominator must be >= 20)"
        );
        require(
            _fees.publicOfferFeeDenominator >= MIN_CONTINUOUS_FUNDRAISING_FEE_DENOMINATOR,
            "PublicOffer fee must be equal or less 10% (denominator must be >= 10)"
        );
        require(
            _fees.personalInviteFeeDenominator >= MIN_PERSONAL_INVITE_FEE_DENOMINATOR,
            "Fee must be equal or less 5% (denominator must be >= 20)"
        );
    }

    /**
     * @notice Returns the fee for a given token amount
     * @dev will wrongly return 1 if denominator and amount are both uint256 max
     */
    function tokenFee(uint256 _tokenAmount) external view override(IFeeSettingsV1, IFeeSettingsV2) returns (uint256) {
        return _tokenAmount / tokenFeeDenominator;
    }

    /**
     * @notice Calculates the fee for a given currency amount in PublicOffer.sol
     * @dev will wrongly return 1 if denominator and amount are both uint256 max
     * @param _currencyAmount The amount of currency to calculate the fee for
     * @return The fee
     */
    function publicOfferFee(
        uint256 _currencyAmount
    ) external view override(IFeeSettingsV1, IFeeSettingsV2) returns (uint256) {
        return _currencyAmount / publicOfferFeeDenominator;
    }

    /**
     * @notice Calculates the fee for a given currency amount in PersonalInvite.sol
     * @dev will wrongly return 1 if denominator and amount are both uint256 max
     * @param _currencyAmount The amount of currency to calculate the fee for
     * @return The fee
     */
    function personalInviteFee(
        uint256 _currencyAmount
    ) external view override(IFeeSettingsV1, IFeeSettingsV2) returns (uint256) {
        return _currencyAmount / personalInviteFeeDenominator;
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
