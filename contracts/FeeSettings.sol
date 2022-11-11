// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";

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

    event SetTokenFeeDenominator(uint256 value);
    event SetInvestmentFeeDenominator(uint256 value);
    event FeeCollectorChanged(address indexed newFeeCollector);

    /**
    @notice sets (or updates) the tokenFeeDenominator
    */
    function setTokenFeeDenominator(uint256 _tokenFeeDenominator) public onlyOwner {
        tokenFeeDenominator = _tokenFeeDenominator;
        emit SetTokenFeeDenominator(_tokenFeeDenominator);
    }

    /**
    @notice sets (or updates) the tokenFeeDenominator
    */
    function setInvestmentFeeDenominator(uint256 _investmentFeeDenominator) public onlyOwner {
        investmentFeeDenominator = _investmentFeeDenominator;
        emit SetInvestmentFeeDenominator(_investmentFeeDenominator);
    }

    function setFeeCollector(
        address _feeCollector
    ) public onlyOwner {
        feeCollector = _feeCollector;
        emit FeeCollectorChanged(_feeCollector);
    }
}
