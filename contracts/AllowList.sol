// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";

/*
    The AllowList contract is used to manage a list of addresses and attest each address certain attributes.
    Examples for possible attributes are: is KYCed, is american, is of age, etc.
    One AllowList managed by one entity (e.g. a corpus.io) can manage up to 256 different attributes and can be used by an unlimited number of other corpusTokens.
*/
contract AllowList is Ownable {
    /**
    @dev Attributes are defined as bit mask, with the bit position encoding it's meaning and the bit's value whether this attribute is attested or not. 
        Example:
        - position 0: 1 = has been KYCed (0 = not KYCed)
        - position 1: 1 = is american citizen (0 = not american citizen)
        - position 2: 1 = is a penguin (0 = not a penguin)
        These meanings are not defined within the token contract. They MUST match the definitions used in the corresponding corpusToken contract.
        value 0b0000000000000000000000000000000000000000000000000000000000000101, means "is KYCed and is a penguin"
        value 0b0000000000000000000000000000000000000000000000000000000000000111, means "is KYCed, is american and is a penguin"
        value 0b0000000000000000000000000000000000000000000000000000000000000000, means "has not proven any relevant attributes to the allowList operator" (default value)
     */
    mapping(address => uint256) public map;

    event Set(address indexed key, uint value);

    /**
    @notice sets (or updates) the attributes for an address
    */
    function set(address _addr, uint256 _i) public onlyOwner {
        map[_addr] = _i;
        emit Set(_addr, _i);
    }

    /**
    @notice purges an address from the allowList
    @dev this is a convenience function, it is equivalent to calling set(_addr, 0)
    */
    function remove(address _addr) public onlyOwner {
        delete map[_addr];
        emit Set(_addr, 0);
    }
}