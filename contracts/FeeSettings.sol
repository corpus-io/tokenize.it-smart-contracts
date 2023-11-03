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
contract FeeSettings is Ownable2Step, ERC165, IFeeSettingsV1 {
    uint128 public constant MIN_TOKEN_FEE_DENOMINATOR = 20;
    uint128 public constant MIN_CONTINUOUS_FUNDRAISING_FEE_DENOMINATOR = 10;
    uint128 public constant MIN_PERSONAL_INVITE_FEE_DENOMINATOR = 20;

    /// Numerator to calculate fees paid in Token.sol.
    uint32 public tokenFeeNumerator;
    /// Denominator to calculate fees paid in Token.sol.
    uint32 public tokenFeeDenominator;

    /// Numerator to calculate fees paid in PublicFundraising.sol.
    uint32 public publicFundraisingFeeNumerator;
    /// Denominator to calculate fees paid in PublicFundraising.sol.
    uint32 public publicFundraisingFeeDenominator;

    /// Numerator to calculate fees paid in PrivateOffer.sol.
    uint32 public privateOfferFeeNumerator;
    /// Denominator to calculate fees paid in PrivateOffer.sol.
    uint32 public privateOfferFeeDenominator;

    /// address the token fees have to be paid to
    address public tokenFeeCollector;
    /// address the public fundraising fees have to be paid to
    address public publicFundraisingFeeCollector;

    /// address the private offer fees have to be paid to
    address public privateOfferFeeCollector;

    /// new fee settings that can be activated (after a delay in case of fee increase)
    Fees public proposedFees;

    /**
     * @notice Fee factors have been changed
     * @param tokenFeeNumerator a in fraction a/b that defines the fee paid in Token: fee = amount * a / b
     * @param tokenFeeDenominator b in fraction a/b that defines the fee paid in Token: fee = amount * a / b
     * @param publicFundraisingFeeNumerator a in fraction a/b that defines the fee paid in currency for public fundraising: fee = amount * a / b
     * @param publicFundraisingFeeDenominator b in fraction a/b that defines the fee paid in currency for public fundraising: fee = amount * a / b
     * @param privateOfferFeeNumerator a in fraction a/b that defines the fee paid in currency for private offers: fee = amount * a / b
     * @param privateOfferFeeDenominator b in fraction a/b that defines the fee paid in currency for private offers: fee = amount * a / b
     */
    event SetFeeDenominators(
        uint32 tokenFeeNumerator,
        uint32 tokenFeeDenominator,
        uint32 publicFundraisingFeeNumerator,
        uint32 publicFundraisingFeeDenominator,
        uint32 privateOfferFeeNumerator,
        uint32 privateOfferFeeDenominator
    );

    /**
     * @notice The fee collector has been changed to `newFeeCollector`
     * @param newFeeCollector The new fee collector
     */
    event FeeCollectorChanged(address indexed newFeeCollector);

    /**
     * @notice A fee change has been proposed
     * @param proposal The new fee settings that have been proposed
     */
    event ChangeProposed(Fees proposal);

    /**
     * @notice Initializes the contract with the given fee denominators and fee collector
     * @param _fees The initial fee denominators
     * @param _feeCollector The initial fee collector
     */
    constructor(Fees memory _fees, address _feeCollector) {
        checkFeeLimits(_fees);
        tokenFeeDenominator = _fees.tokenFeeDenominator;
        continuousFundraisingFeeDenominator = _fees.continuousFundraisingFeeDenominator;
        personalInviteFeeDenominator = _fees.personalInviteFeeDenominator;
        require(_feeCollector != address(0), "Fee collector cannot be 0x0");
        feeCollector = _feeCollector;
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
            _fees.continuousFundraisingFeeDenominator < continuousFundraisingFeeDenominator ||
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
        continuousFundraisingFeeDenominator = proposedFees.continuousFundraisingFeeDenominator;
        personalInviteFeeDenominator = proposedFees.personalInviteFeeDenominator;
        emit SetFeeDenominators(tokenFeeDenominator, continuousFundraisingFeeDenominator, personalInviteFeeDenominator);
        delete proposedFees;
    }

    /**
     * @notice Sets a new fee collector
     * @param _feeCollector The new fee collector
     */
    function setFeeCollector(address _feeCollector) external onlyOwner {
        require(_feeCollector != address(0), "Fee collector cannot be 0x0");
        feeCollector = _feeCollector;
        emit FeeCollectorChanged(_feeCollector);
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
            _fees.continuousFundraisingFeeDenominator >= MIN_CONTINUOUS_FUNDRAISING_FEE_DENOMINATOR,
            "ContinuousFundraising fee must be equal or less 10% (denominator must be >= 10)"
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
    function tokenFee(uint256 _tokenAmount) external view returns (uint256) {
        return _tokenAmount / tokenFeeDenominator;
    }

    /**
     * @notice Calculates the fee for a given currency amount in ContinuousFundraising.sol
     * @dev will wrongly return 1 if denominator and amount are both uint256 max
     * @param _currencyAmount The amount of currency to calculate the fee for
     * @return The fee
     */
    function continuousFundraisingFee(uint256 _currencyAmount) external view returns (uint256) {
        return _currencyAmount / continuousFundraisingFeeDenominator;
    }

    /**
     * @notice Calculates the fee for a given currency amount in PersonalInvite.sol
     * @dev will wrongly return 1 if denominator and amount are both uint256 max
     * @param _currencyAmount The amount of currency to calculate the fee for
     * @return The fee
     */
    function personalInviteFee(uint256 _currencyAmount) external view returns (uint256) {
        return _currencyAmount / personalInviteFeeDenominator;
    }

    /**
     * @dev Specify where the implementation of owner() is located
     * @return The owner of the contract
     */
    function owner() public view override(Ownable, IFeeSettingsV1) returns (address) {
        return Ownable.owner();
    }

    /**
     * @notice This contract implements the ERC165 interface in order to enable other contracts to query which interfaces this contract implements.
     * @dev See https://eips.ethereum.org/EIPS/eip-165
     * @return `true` for supported interfaces, otherwise `false`
     */
    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC165, IFeeSettingsV1) returns (bool) {
        return
            interfaceId == type(IFeeSettingsV1).interfaceId || // we implement IFeeSettingsV1
            ERC165.supportsInterface(interfaceId); // default implementation that enables further querying
    }
}
