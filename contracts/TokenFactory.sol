// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.17;

// taken from https://docs.alchemy.com/docs/create2-an-alternative-to-deriving-contract-addresses

import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/utils/Create2.sol";
import "./Token.sol";

/**
 * @title TokenFactory
 * @author malteish
 * @notice This contract deploys Tokens using create2.
 * @dev One deployment of this contract can be used for deployment of any number of Tokens using create2.
 */
contract TokenFactory {
    event Deploy(address indexed addr);

    /**
     * @notice Deploys Token contract using create2.
     * @param   _trustedForwarder address of the trusted forwarder
     * @param   _feeSettings address of the fee settings contract
     * @param   _admin address of the admin who controls the token
     * @param   _allowList address of the allow list contract
     * @param   _requirements requirements an address has to fulfill to be able to send or receive tokens
     * @param   _name name of the token
     * @param   _symbol symbol of the token
     * @return  address of the deployed contract.
     */
    function deploy(
        bytes32 _salt,
        address _trustedForwarder,
        IFeeSettingsV1 _feeSettings,
        address _admin,
        AllowList _allowList,
        uint256 _requirements,
        string memory _name,
        string memory _symbol
    ) external returns (address) {
        address actualAddress = Create2.deploy(
            0,
            _salt,
            getBytecode(_trustedForwarder, _feeSettings, _admin, _allowList, _requirements, _name, _symbol)
        );

        emit Deploy(actualAddress);
        return actualAddress;
    }

    /**
     * @notice Computes the address of Token contract to be deployed using create2.
     * @param   _trustedForwarder address of the trusted forwarder
     * @param   _feeSettings address of the fee settings contract
     * @param   _admin address of the admin who controls the token
     * @param   _allowList address of the allow list contract
     * @param   _requirements requirements an address has to fulfill to be able to send or receive tokens
     * @param   _name name of the token
     * @param   _symbol symbol of the token
     * @return  address these settings would result in
     */
    function getAddress(
        bytes32 _salt,
        address _trustedForwarder,
        IFeeSettingsV1 _feeSettings,
        address _admin,
        AllowList _allowList,
        uint256 _requirements,
        string memory _name,
        string memory _symbol
    ) external view returns (address) {
        bytes memory bytecode = getBytecode(
            _trustedForwarder,
            _feeSettings,
            _admin,
            _allowList,
            _requirements,
            _name,
            _symbol
        );
        return Create2.computeAddress(_salt, keccak256(bytecode));
    }

    /**
     * @dev Generates the bytecode of the contract to be deployed, using the parameters.
     * @param   _trustedForwarder address of the trusted forwarder
     * @param   _feeSettings address of the fee settings contract
     * @param   _admin address of the admin who controls the token
     * @param   _allowList address of the allow list contract
     * @param   _requirements requirements an address has to fulfill to be able to send or receive tokens
     * @param   _name name of the token
     * @param   _symbol symbol of the token
     * @return  bytecode of the contract to be deployed.
     */
    function getBytecode(
        address _trustedForwarder,
        IFeeSettingsV1 _feeSettings,
        address _admin,
        AllowList _allowList,
        uint256 _requirements,
        string memory _name,
        string memory _symbol
    ) private pure returns (bytes memory) {
        return
            abi.encodePacked(
                type(Token).creationCode,
                abi.encode(_trustedForwarder, _feeSettings, _admin, _allowList, _requirements, _name, _symbol)
            );
    }
}
