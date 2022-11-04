// SPDX-License-Identifier: MIT
// taken from https://docs.alchemy.com/docs/create2-an-alternative-to-deriving-contract-addresses
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/metatx/ERC2771Context.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "../contracts/PrivateInvite.sol";


/*
    One deployment of this contract can be used for deployment of any number of PrivateInvites using create2.
*/
contract DeterministicDeployFactory {
    event Deploy(address addr);

    /**
     * @notice Deploys a contract using create2.
     */
    function deploy(bytes32 _salt, address payable buyer, address payable _receiver, uint _amount, uint _tokenPrice, uint _expiration, IERC20 _currency, MintableERC20 _token) external {
        
        // calculate expected address
        //address expectedAddress = getAddress(_salt, buyer, _receiver, _amount, _tokenPrice, _expiration, _currency, _token);
        
        // for syntax, see: https://solidity-by-example.org/app/create2/
        address actualAddress = address(new PrivateInvite{salt: _salt}(buyer, _receiver, _amount, _tokenPrice, _expiration, _currency, _token));
        
        // // make sure some code has been uploaded to the address
        // uint len;
        // assembly { len := extcodesize(actualAddress) }
        // require(len != 0);

        // // make sure actual address matches expected address
        // require(actualAddress == expectedAddress, "Actual address does not match expected address");
        
        emit Deploy(actualAddress);
        //return addr;
    }

    /**
     * @notice Computes the address of a contract to be deployed using create2.
     */
    function getAddress(bytes32 _salt, address payable buyer, address payable _receiver, uint _amount, uint _tokenPrice, uint _expiration, IERC20 _currency, MintableERC20 _token) public view returns (address) {
        bytes memory bytecodeRuntime = getBytecode(buyer, _receiver, _amount, _tokenPrice, _expiration, _currency, _token);
        bytes32 hash = keccak256(abi.encodePacked(bytes1(0xff), address(this), _salt, keccak256(bytecodeRuntime)));
        return address(uint160(uint256(hash)));
    }

    function getBytecode(address payable buyer, address payable _receiver, uint _amount, uint _tokenPrice, uint _expiration, IERC20 _currency, MintableERC20 _token) private pure returns (bytes memory) {
        return abi.encodePacked(type(PrivateInvite).creationCode, abi.encode(buyer, _receiver, _amount, _tokenPrice, _expiration, _currency, _token));
    }
}