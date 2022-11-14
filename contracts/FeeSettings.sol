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
    /// @notice address used to pay platform fees to. Also used as the address having the FEE_COLLECTOR_ROLE, given the ability to change this address.
    address public feeCollector;

    Change public change;

    event SetTokenFeeDenominator(uint256 value);
    event SetInvestmentFeeDenominator(uint256 value);
    event FeeCollectorChanged(address indexed newFeeCollector);
    event ChangeProposed(Change proposal);

    constructor(uint256 _tokenFeeDenominator, uint256 _investmentFeeDenominator, address _feeCollector) {
        require(_tokenFeeDenominator >= 20 || _tokenFeeDenominator == 0, "Fee must be below 5% or 0");
        tokenFeeDenominator = _tokenFeeDenominator;
        require(_investmentFeeDenominator >= 20 || _investmentFeeDenominator == 0, "Fee must be below 5% or 0");
        investmentFeeDenominator = _investmentFeeDenominator;
        feeCollector = _feeCollector;
    }

    function planFeeChange(Change memory _change) public onlyOwner {
        require(_change.tokenFeeDenominator >= 20|| _change.tokenFeeDenominator == 0, "Fee must be below 5% or 0");
        require(_change.investmentFeeDenominator >= 20 || _change.investmentFeeDenominator == 0, "Fee must be below 5% or 0");
        require(_change.time > block.timestamp + 7884000); // can only be executed in 3 months
        change = _change;
        emit ChangeProposed(_change);
    }

    function executeFeeChange() public onlyOwner {
        require(block.timestamp >= change.time);
        setTokenFeeDenominator(change.tokenFeeDenominator);
        setInvestmentFeeDenominator(change.investmentFeeDenominator);
        delete change;
    }

    function setFeeCollector(address _feeCollector) public onlyOwner {
        feeCollector = _feeCollector;
        emit FeeCollectorChanged(_feeCollector);
    }

    /**
    @notice sets (or updates) the tokenFeeDenominator
    */
    function setTokenFeeDenominator(
        uint256 _tokenFeeDenominator
    ) internal {
        tokenFeeDenominator = _tokenFeeDenominator;
        emit SetTokenFeeDenominator(tokenFeeDenominator);
    }

    /**
    @notice sets (or updates) the tokenFeeDenominator
    */
    function setInvestmentFeeDenominator(
        uint256 _investmentFeeDenominator
    ) internal {
        investmentFeeDenominator = _investmentFeeDenominator;
        emit SetInvestmentFeeDenominator(_investmentFeeDenominator);
    }
}
