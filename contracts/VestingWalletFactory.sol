// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.23;

// taken from https://docs.alchemy.com/docs/create2-an-alternative-to-deriving-contract-addresses

import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/utils/Create2.sol";
import "@openzeppelin/contracts/finance/VestingWallet.sol";

/**
 * @title VestingWalletFactory
 * @author malteish
 * @notice This contract deploys VestingWallets using create2.
 * @dev One deployment of this contract can be used for deployment of any number of VestingWallets using create2.
 */
contract VestingWalletFactory {
    event Deploy(address indexed addr);

    /**
     * @notice Deploys VestingWallet contract using create2.
     * @param   _salt salt used for privacy. Could be used for vanity addresses, too.
     * @param   _beneficiaryAddress address receiving the tokens
     * @param   _startTimestamp timestamp of when to start releasing tokens linearly
     * @param   _durationSeconds duration of the vesting period in seconds
     */
    function deploy(
        bytes32 _salt,
        address _beneficiaryAddress,
        uint64 _startTimestamp,
        uint64 _durationSeconds
    ) external returns (address) {
        address actualAddress = Create2.deploy(
            0,
            _salt,
            getBytecode(_beneficiaryAddress, _startTimestamp, _durationSeconds)
        );

        emit Deploy(actualAddress);
        return actualAddress;
    }

    /**
     * @notice Computes the address of VestingWallet contract to be deployed using create2.
     * @param   _salt salt for vanity addresses
     * @param   _beneficiaryAddress address receiving the tokens
     * @param   _startTimestamp timestamp of when to start releasing tokens linearly
     * @param   _durationSeconds duration of the vesting period in seconds
     */
    function getAddress(
        bytes32 _salt,
        address _beneficiaryAddress,
        uint64 _startTimestamp,
        uint64 _durationSeconds
    ) external view returns (address) {
        bytes memory bytecode = getBytecode(_beneficiaryAddress, _startTimestamp, _durationSeconds);
        return Create2.computeAddress(_salt, keccak256(bytecode));
    }

    /**
     * @dev Generates the bytecode of the contract to be deployed, using the parameters.
     * @param  _beneficiaryAddress address receiving the tokens
     * @param  _startTimestamp timestamp of when to start releasing tokens linearly
     * @param  _durationSeconds duration of the vesting period in seconds
     * @return _bytecode of the contract to be deployed.
     */
    function getBytecode(
        address _beneficiaryAddress,
        uint64 _startTimestamp,
        uint64 _durationSeconds
    ) private pure returns (bytes memory) {
        return
            abi.encodePacked(
                type(VestingWallet).creationCode,
                abi.encode(_beneficiaryAddress, _startTimestamp, _durationSeconds)
            );
    }
}
