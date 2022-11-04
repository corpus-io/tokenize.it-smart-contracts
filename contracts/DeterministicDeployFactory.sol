// SPDX-License-Identifier: MIT
// taken from https://docs.alchemy.com/docs/create2-an-alternative-to-deriving-contract-addresses
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/metatx/ERC2771Context.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "../contracts/PrivateInvite.sol";


// interface MintableERC20 is IERC20Metadata {
//     function mint(address, uint256) external returns (bool);
// }

/*
    One deployment of this contract can be used for deployment of any number of contracts using create2.
*/
contract DeterministicDeployFactory {
    event Deploy(address addr);

    /**
     * @notice Deploys a contract using create2.
     */
    function deploy(bytes memory bytecode, bytes32 _salt, address payable buyer, address payable _receiver, uint _amount, uint _tokenPrice, uint _expiration, IERC20 _currency, MintableERC20 _token) external {
        // for syntax, see: https://solidity-by-example.org/app/create2/
        address addr = address(new PrivateInvite{salt: _salt}(buyer, _receiver, _amount, _tokenPrice, _expiration, _currency, _token));
        // assembly {
        //     addr := create2(0, add(bytecode, 0x20), mload(bytecode), _salt)
        //     if iszero(extcodesize(addr)) {
        //         revert(0, 0)
        //     }
        // }
        emit Deploy(addr);
        //return addr;
    }

    /**
     * @notice Computes the address of a contract to be deployed using create2.
     */
    function getAddress(bytes memory bytecode, bytes32 _salt) external view returns (address) {
        bytes32 hash = keccak256(abi.encodePacked(bytes1(0xff), address(this), _salt, keccak256(bytecode)));
        return address(uint160(uint256(hash)));
    }
}