// SPDX-License-Identifier: MIT
// taken from https://docs.alchemy.com/docs/create2-an-alternative-to-deriving-contract-addresses
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/utils/Create2.sol";
import "../contracts/PersonalInvite.sol";

/*
    One deployment of this contract can be used for deployment of any number of PersonalInvites using create2.
*/
contract PersonalInviteFactory {
    event Deploy(address addr);

    /**
     * @notice Deploys a contract using create2.
     */
    function deploy(
        bytes32 _salt,
        address buyer,
        address _receiver,
        uint256 _amount,
        uint256 _tokenPrice,
        uint256 _expiration,
        IERC20 _currency,
        IERC20 _token
    ) external returns (address) {
        // for syntax, see: https://solidity-by-example.org/app/create2/
        //address actualAddress = address(new PersonalInvite{salt: _salt}(buyer, _receiver, _amount, _tokenPrice, _expiration, _currency, _token));
        address actualAddress = Create2.deploy(
            0,
            _salt,
            getBytecode(
                buyer,
                _receiver,
                _amount,
                _tokenPrice,
                _expiration,
                _currency,
                _token
            )
        );

        emit Deploy(actualAddress);
        return actualAddress;
    }

    /**
     * @notice Computes the address of a contract to be deployed using create2.
     */
    function getAddress(
        bytes32 _salt,
        address buyer,
        address _receiver,
        uint256 _amount,
        uint256 _tokenPrice,
        uint256 _expiration,
        IERC20 _currency,
        IERC20 _token
    ) public view returns (address) {
        bytes memory bytecode = getBytecode(
            buyer,
            _receiver,
            _amount,
            _tokenPrice,
            _expiration,
            _currency,
            _token
        );
        //bytes32 hash = keccak256(abi.encodePacked(bytes1(0xff), address(this), _salt, keccak256(bytecode)));
        //return address(uint160(uint256(hash)));
        return Create2.computeAddress(_salt, keccak256(bytecode));
    }

    function getBytecode(
        address buyer,
        address _receiver,
        uint256 _amount,
        uint256 _tokenPrice,
        uint256 _expiration,
        IERC20 _currency,
        IERC20 _token
    ) private pure returns (bytes memory) {
        return
            abi.encodePacked(
                type(PersonalInvite).creationCode,
                abi.encode(
                    buyer,
                    _receiver,
                    _amount,
                    _tokenPrice,
                    _expiration,
                    _currency,
                    _token
                )
            );
    }
}
