// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";

struct Change {
    uint tokenFeeDenominator;
    uint investmentFeeDenominator;
    uint time;
}

/*
    This FeeSettings contract is used to manage fees paid to the tokenize.it platfom
*/
contract FeeSettings is Ownable {
    /// @notice Denominator to calculate fees paid Token.sol
    uint256 public tokenFeeDenominator;
    /// @notice Denominator to calculate fees paid in all investment contracts
    uint256 public investmentFeeDenominator;
    /// @notice address used to pay platform fees to. 
    address public feeCollector;

    Change public change;

    event SetTokenFeeDenominator(uint256 value);
    event SetInvestmentFeeDenominator(uint256 value);
    event FeeCollectorChanged(address indexed newFeeCollector);
    event ChangeProposed(Change proposal);

    constructor(
        uint256 _tokenFeeDenominator,
        uint256 _investmentFeeDenominator,
        address _feeCollector
    ) {
        require(
            _tokenFeeDenominator >= 20 || _tokenFeeDenominator == 0,
            "Fee must be below 5% or 0"
        );
        tokenFeeDenominator = _tokenFeeDenominator;
        require(
            _investmentFeeDenominator >= 20 || _investmentFeeDenominator == 0,
            "Fee must be below 5% or 0"
        );
        investmentFeeDenominator = _investmentFeeDenominator;
        require(_feeCollector != address(0), "Fee collector cannot be 0x0");
        feeCollector = _feeCollector;
    }

    function planFeeChange(Change memory _change) public onlyOwner {
        require(
            _change.tokenFeeDenominator >= 20 ||
                _change.tokenFeeDenominator == 0,
            "Fee must be below 5% or 0"
        );
        require(
            _change.investmentFeeDenominator >= 20 ||
                _change.investmentFeeDenominator == 0,
            "Fee must be below 5% or 0"
        );
        require(
            _change.time > block.timestamp + 7884000,
            "Fee change must be at least 3 months in the future"
        ); // can only be executed in 3 months
        change = _change;
        emit ChangeProposed(_change);
    }

    function executeFeeChange() public onlyOwner {
        require(
            block.timestamp >= change.time,
            "Fee change must be executed after the change time"
        );
        tokenFeeDenominator = change.tokenFeeDenominator;
        investmentFeeDenominator = change.investmentFeeDenominator;
        emit SetTokenFeeDenominator(change.tokenFeeDenominator);
        emit SetInvestmentFeeDenominator(change.investmentFeeDenominator);
        delete change;
    }

    function setFeeCollector(address _feeCollector) public onlyOwner {
        require(_feeCollector != address(0), "Fee collector cannot be 0x0");
        feeCollector = _feeCollector;
        emit FeeCollectorChanged(_feeCollector);
    }
}
