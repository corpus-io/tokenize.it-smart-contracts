// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";

struct Fees {
    uint256 tokenFeeDenominator;
    uint256 continuousFundraisungFeeDenominator;
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
    uint256 public continuousFundraisungFeeDenominator;
    /// @notice Denominator to calculate fees paid in all investment contracts
    uint256 public personalInviteFeeDenominator;
    /// @notice address used to pay platform fees to.
    address public feeCollector;

    Fees public proposedFees;

    event SetTokenFeeDenominator(uint256 value);
    event SetContinuousFundraisungFeeDenominator(uint256 value);
    event SetPersonalInviteFeeDenominator(uint256 value);
    event FeeCollectorChanged(address indexed newFeeCollector);
    event ChangeProposed(Fees proposal);

    constructor(
        Fees memory _fees,
        address _feeCollector
    ) {
        checkFeeLimits(_fees);
        tokenFeeDenominator = _fees.tokenFeeDenominator;
        continuousFundraisungFeeDenominator = _fees.continuousFundraisungFeeDenominator;
        personalInviteFeeDenominator = _fees.personalInviteFeeDenominator;
        require(_feeCollector != address(0), "Fee collector cannot be 0x0");
        feeCollector = _feeCollector;
    }

    function planFeeChange(Fees memory _fees) public onlyOwner {
        checkFeeLimits(_fees);
        require(
            _fees.time > block.timestamp + 12 weeks,
            "Fee change must be at least 12 weeks in the future"
        ); // can only be executed in 3 months
        proposedFees = _fees;
        emit ChangeProposed(_fees);
    }

    function executeFeeChange() public onlyOwner {
        require(
            block.timestamp >= proposedFees.time,
            "Fee change must be executed after the change time"
        );
        tokenFeeDenominator = proposedFees.tokenFeeDenominator;
        continuousFundraisungFeeDenominator = proposedFees.continuousFundraisungFeeDenominator;
        personalInviteFeeDenominator = proposedFees.personalInviteFeeDenominator;
        emit SetTokenFeeDenominator(proposedFees.tokenFeeDenominator);
        emit SetContinuousFundraisungFeeDenominator(proposedFees.continuousFundraisungFeeDenominator);
        emit SetPersonalInviteFeeDenominator(proposedFees.personalInviteFeeDenominator);
        delete proposedFees;
    }

    function setFeeCollector(address _feeCollector) public onlyOwner {
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
            _fees.continuousFundraisungFeeDenominator >= 20 || _fees.continuousFundraisungFeeDenominator == 0,
            "Fee must be below 5% or 0"
        );
        require(
            _fees.personalInviteFeeDenominator >= 20 || _fees.personalInviteFeeDenominator == 0,
            "Fee must be below 5% or 0"
        );
    }
}
