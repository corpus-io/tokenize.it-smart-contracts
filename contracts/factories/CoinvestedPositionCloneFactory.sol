// SPDX-License-Identifier: AGPL-3.0-only

pragma solidity 0.8.23;

import "@openzeppelin/contracts/proxy/Clones.sol";

import "../CoinvestedPosition.sol";
import "./CloneFactory.sol";
import "./PrivateOfferFactory.sol";

/**
 * @title CoinvestedPositionCloneFactory
 * @author malteish
 * @notice Use this contract to create deterministic clones of CoinvestedPosition contracts
 */
contract CoinvestedPositionCloneFactory is CloneFactory {
    constructor(address _implementation) CloneFactory(_implementation) {}

    /**
     * @notice Create a new CoinvestedPosition clone and initialize it.
     * @param _rawSalt influences the address of the clone, but not the initialization
     * @param _trustedForwarder can not be changed, but is checked for security
     * @param _arguments struct with all the initialization parameters
     */
    function createCoinvestedPositionClone(
        bytes32 _rawSalt,
        address _trustedForwarder,
        CoinvestedPositionInitializerArguments memory _arguments
    ) external returns (address) {
        bytes32 salt = _getSalt(_rawSalt, _trustedForwarder, _arguments);
        CoinvestedPosition clone = CoinvestedPosition(Clones.cloneDeterministic(implementation, salt));
        require(
            clone.isTrustedForwarder(_trustedForwarder),
            "CoinvestedPositionCloneFactory: Unexpected trustedForwarder"
        );
        clone.initialize(_arguments);
        emit NewClone(address(clone));
        return address(clone);
    }

    /**
     * @notice Return the address a clone would have if it was created with these parameters.
     * @param _rawSalt influences the address of the clone, but not the initialization
     * @param _trustedForwarder can not be changed, but is checked for security
     * @param _arguments struct with all the initialization parameters
     */
    function predictCloneAddress(
        bytes32 _rawSalt,
        address _trustedForwarder,
        CoinvestedPositionInitializerArguments memory _arguments
    ) external view returns (address) {
        bytes32 salt = _getSalt(_rawSalt, _trustedForwarder, _arguments);
        return Clones.predictDeterministicAddress(implementation, salt);
    }

    /**
     * @notice Create a new CoinvestedPosition clone and immediately execute a PrivateOffer investment.
     *      The coinvestor (receiver) must have pre-approved the predicted CoinvestedPosition address for
     *      investmentAmount + oneTimeFeeAmount of baseCurrency. The token issuer must have pre-approved
     *      the predicted PrivateOffer address for minting or transfer.
     *      Use predictCoinvestedPositionAndPrivateOfferAddress to obtain both addresses beforehand.
     * @param _rawSalt influences the address of the clone, but not the initialization
     * @param _trustedForwarder can not be changed, but is checked for security
     * @param _coinvestedPositionArgs struct with all base initialization parameters
     * @param _feeArgs struct with PrivateOffer parameters and the one-time syndicate fee fraction
     * @return coinvestedPositionAddress address of the deployed CoinvestedPosition clone
     * @return privateOfferAddress address of the deployed PrivateOffer
     */
    function createCoinvestedPositionWithPrivateOffer(
        bytes32 _rawSalt,
        address _trustedForwarder,
        CoinvestedPositionInitializerArguments memory _coinvestedPositionArgs,
        OneTimeSyndicateFeeArguments memory _feeArgs
    ) external returns (address coinvestedPositionAddress, address privateOfferAddress) {
        bytes32 salt = _getCombinedSalt(_rawSalt, _trustedForwarder, _coinvestedPositionArgs, _feeArgs);
        CoinvestedPosition clone = CoinvestedPosition(Clones.cloneDeterministic(implementation, salt));
        require(
            clone.isTrustedForwarder(_trustedForwarder),
            "CoinvestedPositionCloneFactory: Unexpected trustedForwarder"
        );

        // Override before passing to initializeWithPrivateOffer so the PrivateOffer address prediction
        // inside the initializer matches the address prediction here.
        _feeArgs.privateOfferArguments.currencyPayer = address(clone);
        _feeArgs.privateOfferArguments.tokenReceiver = address(clone);

        privateOfferAddress = _feeArgs.privateOfferFactory.predictPrivateOfferAddress(
            _feeArgs.privateOfferSalt,
            _feeArgs.privateOfferArguments
        );

        clone.initializeWithPrivateOffer(_coinvestedPositionArgs, _feeArgs);
        emit NewClone(address(clone));

        return (address(clone), privateOfferAddress);
    }

    /**
     * @notice Predicts the addresses of the CoinvestedPosition clone and the PrivateOffer that would be
     *      deployed with the given parameters. Use these addresses to set up the required approvals before
     *      calling createCoinvestedPositionWithPrivateOffer:
     *        - coinvestor approves coinvestedPositionAddress for investmentAmount + oneTimeFeeAmount
     *        - token issuer approves privateOfferAddress for minting or transfer
     * @param _rawSalt influences the address of the clone, but not the initialization
     * @param _trustedForwarder can not be changed, but is checked for security
     * @param _coinvestedPositionArgs struct with all base initialization parameters
     * @param _feeArgs struct with PrivateOffer parameters and the one-time syndicate fee fraction
     * @return coinvestedPositionAddress predicted address of the CoinvestedPosition clone
     * @return privateOfferAddress predicted address of the PrivateOffer
     */
    function predictCoinvestedPositionAndPrivateOfferAddress(
        bytes32 _rawSalt,
        address _trustedForwarder,
        CoinvestedPositionInitializerArguments memory _coinvestedPositionArgs,
        OneTimeSyndicateFeeArguments memory _feeArgs
    ) external view returns (address coinvestedPositionAddress, address privateOfferAddress) {
        bytes32 salt = _getCombinedSalt(_rawSalt, _trustedForwarder, _coinvestedPositionArgs, _feeArgs);
        coinvestedPositionAddress = Clones.predictDeterministicAddress(implementation, salt);

        _feeArgs.privateOfferArguments.currencyPayer = coinvestedPositionAddress;
        _feeArgs.privateOfferArguments.tokenReceiver = coinvestedPositionAddress;
        privateOfferAddress = _feeArgs.privateOfferFactory.predictPrivateOfferAddress(
            _feeArgs.privateOfferSalt,
            _feeArgs.privateOfferArguments
        );
    }

    /**
     * @notice generates a salt from all input parameters
     * @param _rawSalt The salt used to deterministically generate the clone address
     * @param _trustedForwarder The trustedForwarder that will be used to initialize the clone
     * @param _arguments The arguments that will be used to initialize the clone
     * @return salt to be used for clone generation
     */
    function _getSalt(
        bytes32 _rawSalt,
        address _trustedForwarder,
        CoinvestedPositionInitializerArguments memory _arguments
    ) internal pure returns (bytes32) {
        return keccak256(abi.encode(_rawSalt, _trustedForwarder, _arguments));
    }

    /**
     * @notice generates a salt incorporating both base and fee arguments, ensuring the clone address
     *      is unique across all parameters including PrivateOffer terms and the one-time fee.
     */
    function _getCombinedSalt(
        bytes32 _rawSalt,
        address _trustedForwarder,
        CoinvestedPositionInitializerArguments memory _coinvestedPositionArgs,
        OneTimeSyndicateFeeArguments memory _feeArgs
    ) internal pure returns (bytes32) {
        return keccak256(abi.encode(_rawSalt, _trustedForwarder, _coinvestedPositionArgs, _feeArgs));
    }
}
