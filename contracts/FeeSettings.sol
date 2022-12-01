// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "@openzeppelin/contracts/access/Ownable.sol";

struct Fees {
    uint256 tokenFeeDenominator;
    uint256 continuousFundraisingFeeDenominator;
    uint256 personalInviteFeeDenominator;
    uint256 time;
}

/*
    This FeeSettings contract is used to manage fees paid to the tokenize.it platfom
*/
contract FeeSettings is Ownable {
    /// @notice Denominator to calculate fees paid Token.sol
    uint256 public tokenFeeDenominator;
    /// @notice Denominator to calculate fees paid in all investment contracts
    uint256 public continuousFundraisingFeeDenominator;
    /// @notice Denominator to calculate fees paid in all investment contracts
    uint256 public personalInviteFeeDenominator;
    /// @notice address used to pay platform fees to.
    address public feeCollector;

    Fees public proposedFees;

    event SetFeeDenominators(
        uint256 tokenFeeDenominator,
        uint256 continuousFundraisingFeeDenominator,
        uint256 personalInviteFeeDenominator
    );
    event FeeCollectorChanged(address indexed newFeeCollector);
    event ChangeProposed(Fees indexed proposal);

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
        require(
            _fees.time > block.timestamp + 12 weeks,
            "Fee change must be at least 12 weeks in the future"
        ); // can only be executed in 3 months
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
            _fees.tokenFeeDenominator >= 20 || _fees.tokenFeeDenominator == 0,
            "Fee must be below 5% or 0"
        );
        require(
            _fees.continuousFundraisingFeeDenominator >= 20 ||
                _fees.continuousFundraisingFeeDenominator == 0,
            "Fee must be below 5% or 0"
        );
        require(
            _fees.personalInviteFeeDenominator >= 20 ||
                _fees.personalInviteFeeDenominator == 0,
            "Fee must be below 5% or 0"
        );
    }
}
