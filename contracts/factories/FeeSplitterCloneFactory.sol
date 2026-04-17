// SPDX-License-Identifier: AGPL-3.0-only

pragma solidity 0.8.34;

import "@openzeppelin/contracts/proxy/Clones.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "../CoinvestedPosition.sol";
import "../FeeSplitter.sol";
import "./CloneFactory.sol";

/**
 * @title FeeSplitterCloneFactory
 * @author malteish
 * @notice Use this contract to create deterministic clones of FeeSplitter contracts.
 *      Each clone pulls a one-time fee from a payer and distributes it among the lead investors
 *      of a CoinvestedPosition. The clone address is fully determined by the initialization
 *      parameters, allowing the feePayer to pre-approve the predicted address before deployment.
 */
contract FeeSplitterCloneFactory is CloneFactory {
    constructor(address _implementation) CloneFactory(_implementation) {}

    /**
     * @notice Create a new FeeSplitter clone and initialize it. The clone immediately pulls
     *      feeAmount of currency from feePayer and distributes it among the lead investors of
     *      coinvestedPosition. feePayer must have pre-approved this clone's address before calling.
     *      Use predictCloneAddress to obtain the address beforehand.
     * @param _rawSalt influences the address of the clone, but not the initialization
     * @param _feePayer address from which the fee is pulled; must have pre-approved the clone
     * @param _currency ERC20 token in which the fee is denominated
     * @param _feeAmount total fee to distribute, in currency bits
     * @param _coinvestedPosition source of lead investor accounts and carry fractions
     */
    function createFeeSplitterClone(
        bytes32 _rawSalt,
        address _feePayer,
        IERC20 _currency,
        uint256 _feeAmount,
        CoinvestedPosition _coinvestedPosition
    ) external returns (address) {
        bytes32 salt = _getSalt(_rawSalt, _feePayer, _currency, _feeAmount, _coinvestedPosition);
        FeeSplitter clone = FeeSplitter(Clones.cloneDeterministic(implementation, salt));
        clone.payFee(_feePayer, _currency, _feeAmount, _coinvestedPosition);
        emit NewClone(address(clone));
        return address(clone);
    }

    /**
     * @notice Return the address a clone would have if it was created with these parameters.
     * @param _rawSalt influences the address of the clone, but not the initialization
     * @param _feePayer address from which the fee is pulled
     * @param _currency ERC20 token in which the fee is denominated
     * @param _feeAmount total fee to distribute, in currency bits
     * @param _coinvestedPosition source of lead investor accounts and carry fractions
     */
    function predictCloneAddress(
        bytes32 _rawSalt,
        address _feePayer,
        IERC20 _currency,
        uint256 _feeAmount,
        CoinvestedPosition _coinvestedPosition
    ) external view returns (address) {
        bytes32 salt = _getSalt(_rawSalt, _feePayer, _currency, _feeAmount, _coinvestedPosition);
        return Clones.predictDeterministicAddress(implementation, salt);
    }

    /**
     * @notice generates a salt from all input parameters
     */
    function _getSalt(
        bytes32 _rawSalt,
        address _feePayer,
        IERC20 _currency,
        uint256 _feeAmount,
        CoinvestedPosition _coinvestedPosition
    ) internal pure returns (bytes32) {
        return keccak256(abi.encode(_rawSalt, _feePayer, _currency, _feeAmount, _coinvestedPosition));
    }
}
