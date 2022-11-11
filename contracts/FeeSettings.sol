// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";

/*
    The AllowList contract is used to manage a list of addresses and attest each address certain attributes.
    Examples for possible attributes are: is KYCed, is american, is of age, etc.
    One AllowList managed by one entity (e.g. tokenize.it) can manage up to 252 different attributes, and one tier with 5 levels, and can be used by an unlimited number of other Tokens.
*/
contract FeeSettings is Ownable {
    /**
    @dev Attributes are defined as bit mask, with the bit position encoding it's meaning and the bit's value whether this attribute is attested or not. 
     */

    uint256 public tokenFeeDenominator;
    uint256 public investmentFeeDenominator;
    /// @notice address used to pay platform fees to. Also used as the address having the FEE_COLLECTOR_ROLE, given the ability to change this address.
    address public feeCollector;

    event SetTokenFeeDenominator(uint256 value);
    event SetInvestmentFeeDenominator(uint256 value);
    event FeeCollectorChanged(address indexed newFeeCollector);

    /**
    @notice sets (or updates) the tokenFeeDenominator
    */
    function setTokenFeeDenominator(
        uint256 _tokenFeeDenominator
    ) public onlyOwner {
        tokenFeeDenominator = _tokenFeeDenominator;
        emit SetTokenFeeDenominator(_tokenFeeDenominator);
    }

    /**
    @notice sets (or updates) the tokenFeeDenominator
    */
    function setInvestmentFeeDenominator(
        uint256 _investmentFeeDenominator
    ) public onlyOwner {
        investmentFeeDenominator = _investmentFeeDenominator;
        emit SetInvestmentFeeDenominator(_investmentFeeDenominator);
    }

    function setFeeCollector(address _feeCollector) public onlyOwner {
        feeCollector = _feeCollector;
        emit FeeCollectorChanged(_feeCollector);
    }
}
