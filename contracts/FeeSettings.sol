// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "@openzeppelin/contracts/access/Ownable2Step.sol";

struct Fees {
    uint256 tokenFeeDenominator;
    uint256 continuousFundraisingFeeDenominator;
    uint256 personalInviteFeeDenominator;
    uint256 time;
}

/*
    This FeeSettings contract is used to manage fees paid to the tokenize.it platfom
*/
contract FeeSettings is Ownable2Step {
    /// @notice Denominator to calculate fees paid in Token.sol. UINT256_MAX means no fees.
    uint256 public tokenFeeDenominator;
    /// @notice Denominator to calculate fees paid in ContinuousFundraising.sol. UINT256_MAX means no fees.
    uint256 public continuousFundraisingFeeDenominator;
    /// @notice Denominator to calculate fees paid in PersonalInvite.sol. UINT256_MAX means no fees.
    uint256 public personalInviteFeeDenominator;
    /// @notice address the fees have to be paid to
    address public feeCollector;
    /// @notice new fee settings that can be activated (after a delay in case of fee increase)
    Fees public proposedFees;

    event SetFeeDenominators(
        uint256 tokenFeeDenominator,
        uint256 continuousFundraisingFeeDenominator,
        uint256 personalInviteFeeDenominator
    );
    event FeeCollectorChanged(address indexed newFeeCollector);
    event ChangeProposed(Fees proposal);

    constructor(Fees memory _fees, address _feeCollector) {
        checkFeeLimits(_fees);
        tokenFeeDenominator = _fees.tokenFeeDenominator;
        continuousFundraisingFeeDenominator = _fees
            .continuousFundraisingFeeDenominator;
        personalInviteFeeDenominator = _fees.personalInviteFeeDenominator;
        require(_feeCollector != address(0), "Fee collector cannot be 0x0");
        feeCollector = _feeCollector;
    }

    function planFeeChange(Fees memory _fees) external onlyOwner {
        checkFeeLimits(_fees);
        // Reducing fees is possible immediately. Increasing fees can only be executed after a minimum of 12 weeks.
        // Beware: reducing fees = increasing the denominator

        // if at least one fee increases, enforce minimum delay
        if (
            _fees.tokenFeeDenominator < tokenFeeDenominator ||
            _fees.continuousFundraisingFeeDenominator <
            continuousFundraisingFeeDenominator ||
            _fees.personalInviteFeeDenominator < personalInviteFeeDenominator
        ) {
            require(
                _fees.time > block.timestamp + 12 weeks,
                "Fee change must be at least 12 weeks in the future"
            );
        }
        proposedFees = _fees;
        emit ChangeProposed(_fees);
    }

    function executeFeeChange() external onlyOwner {
        require(
            block.timestamp >= proposedFees.time,
            "Fee change must be executed after the change time"
        );
        tokenFeeDenominator = proposedFees.tokenFeeDenominator;
        continuousFundraisingFeeDenominator = proposedFees
            .continuousFundraisingFeeDenominator;
        personalInviteFeeDenominator = proposedFees
            .personalInviteFeeDenominator;
        emit SetFeeDenominators(
            tokenFeeDenominator,
            continuousFundraisingFeeDenominator,
            personalInviteFeeDenominator
        );
        delete proposedFees;
    }

    function setFeeCollector(address _feeCollector) external onlyOwner {
        require(_feeCollector != address(0), "Fee collector cannot be 0x0");
        feeCollector = _feeCollector;
        emit FeeCollectorChanged(_feeCollector);
    }

    function checkFeeLimits(Fees memory _fees) internal pure {
        require(
            _fees.tokenFeeDenominator >= 20,
            "Fee must be equal or less 5% (denominator must be >= 20)"
        );
        require(
            _fees.continuousFundraisingFeeDenominator >= 20,
            "Fee must be equal or less 5% (denominator must be >= 20)"
        );
        require(
            _fees.personalInviteFeeDenominator >= 20,
            "Fee must be equal or less 5% (denominator must be >= 20)"
        );
    }

    /**
    @notice Returns the fee for a given token amount
    @dev will wrongly return 1 if denominator and amount are both uint256 max
     */
    function tokenFee(uint256 _tokenAmount) external view returns (uint256) {
        return _tokenAmount / tokenFeeDenominator;
    }

    /**
    @notice Returns the fee for a given currency amount
    @dev will wrongly return 1 if denominator and amount are both uint256 max
     */
    function continuousFundraisingFee(
        uint256 _currencyAmount
    ) external view returns (uint256) {
        return _currencyAmount / continuousFundraisingFeeDenominator;
    }

    /** 
    @notice Returns the fee for a given currency amount
    @dev will wrongly return 1 if denominator and amount are both uint256 max
     */
    function personalInviteFee(
        uint256 _currencyAmount
    ) external view returns (uint256) {
        return _currencyAmount / personalInviteFeeDenominator;
    }
}
