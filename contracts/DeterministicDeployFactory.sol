// SPDX-License-Identifier: MIT
// taken from https://docs.alchemy.com/docs/create2-an-alternative-to-deriving-contract-addresses
pragma solidity ^0.8.0;

/*
    One deployment of this contract can be used for deployment of any number of contracts using create2.
*/
contract DeterministicDeployFactory {
    event Deploy(address addr);

    /**
     * @notice Deploys a contract using create2.
     */
    function deploy(bytes memory bytecode, uint _salt) external {
        address addr;
        assembly {
            addr := create2(0, add(bytecode, 0x20), mload(bytecode), _salt)
            if iszero(extcodesize(addr)) {
                revert(0, 0)
            }
        }
        emit Deploy(addr);
    }

    /**
     * @notice Computes the address of a contract to be deployed using create2.
     */
    function getAddress(bytes memory bytecode, uint _salt) external view returns (address) {
        bytes32 salt = bytes32(_salt);
        bytes32 hash = keccak256(abi.encodePacked(bytes1(0xff), address(this), salt, keccak256(bytecode)));
        return address(uint160(uint256(hash)));
    }
}