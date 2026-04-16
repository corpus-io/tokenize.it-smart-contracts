// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.23;

import "@openzeppelin/contracts/utils/Create2.sol";
import "../PrivateOffer.sol";
import "../GlobalTokenExitRegistry.sol";
import "./CoinvestedPositionCloneFactory.sol";
import "./TimeLockCloneFactory.sol";

/**
 * @title PrivateOfferFactory
 * @author malteish, cjentzsch
 * @notice This contract deploys PrivateOffers using create2. It is used to deploy PrivateOffers with a deterministic address.
 * It also deploys the TimeLock contracts used for token lockup.
 * @dev One deployment of this contract can be used for deployment of any number of PrivateOffers using create2.
 */
contract PrivateOfferFactory {
    event Deploy(address indexed privateOffer);
    event NewPrivateOfferWithTimeLock(address privateOffer, address timeLock);
    event NewPrivateOfferWithCoinvestedPosition(address privateOffer, address coinvestedPosition);

    TimeLockCloneFactory public immutable timeLockCloneFactory;
    CoinvestedPositionCloneFactory public immutable coinvestedPositionCloneFactory;

    constructor(
        TimeLockCloneFactory _timeLockCloneFactory,
        CoinvestedPositionCloneFactory _coinvestedPositionCloneFactory
    ) {
        require(address(_timeLockCloneFactory) != address(0), "TimeLockCloneFactory must not be 0");
        require(address(_coinvestedPositionCloneFactory) != address(0), "CoinvestedPositionCloneFactory must not be 0");
        timeLockCloneFactory = _timeLockCloneFactory;
        coinvestedPositionCloneFactory = _coinvestedPositionCloneFactory;
    }

    /**
     * @notice Deploys a PrivateOffer using create2. During the deployment, `_currencyPayer` pays `_currencyReceiver`
     *      for the purchase of `_tokenAmount` tokens at `_tokenPrice` per token.
     *      The tokens are minted to `_tokenReceiver`.
     */
    function deployPrivateOffer(
        bytes32 _rawSalt,
        PrivateOfferArguments calldata _arguments
    ) external returns (address) {
        return _deployPrivateOffer(_rawSalt, _arguments);
    }

    /**
     * @notice Deploys a PrivateOffer and a TimeLock in one transaction. Tokens are minted directly into the
     *      TimeLock and can be drained to any recipient by the TimeLock owner after _lockedUntil has passed.
     * @param _rawSalt Value influencing the addresses of the deployed contracts, but nothing else.
     * @param _arguments Arguments for the PrivateOffer contract.
     * @param _lockedUntil Unix timestamp before which the TimeLock's drain() is blocked.
     * @param _timeLockOwner Owner of the TimeLock contract.
     * @param _tokenExitRegistry Global registry contract; setting an exit for the token bypasses lockedUntil.
     */
    function deployPrivateOfferWithTimeLock(
        bytes32 _rawSalt,
        PrivateOfferArguments calldata _arguments,
        uint64 _lockedUntil,
        address _timeLockOwner,
        GlobalTokenExitRegistry _tokenExitRegistry,
        address _trustedForwarder
    ) external returns (address) {
        // deploy the time lock contract
        TimeLock timeLock = TimeLock(
            timeLockCloneFactory.createTimeLockClone(
                _rawSalt,
                _trustedForwarder,
                _timeLockOwner,
                _lockedUntil,
                _tokenExitRegistry
            )
        );

        // route token delivery through the time lock
        PrivateOfferArguments memory arguments = _arguments;
        arguments.tokenReceiver = address(timeLock);

        // deploy the private offer, which mints tokens directly into the time lock
        address privateOffer = _deployPrivateOffer(_rawSalt, arguments);

        require(_arguments.token.balanceOf(address(timeLock)) == _arguments.tokenAmount, "Execution failed");
        emit NewPrivateOfferWithTimeLock(privateOffer, address(timeLock));
        return address(timeLock);
    }

    /**
     * @notice Predicts the addresses of the PrivateOffer and TimeLock contracts that would be deployed
     *      with the given parameters.
     * @param _rawSalt Value influencing the addresses of the deployed contracts, but nothing else.
     * @param _arguments Arguments for the PrivateOffer contract.
     * @param _lockedUntil Unix timestamp before which the TimeLock's drain() is blocked.
     * @param _timeLockOwner Owner of the TimeLock contract.
     * @param _tokenExitRegistry Global registry contract; setting an exit for the token bypasses lockedUntil.
     * @return privateOfferAddress The address of the PrivateOffer contract that would be deployed.
     * @return timeLockAddress The address of the TimeLock contract that would be deployed.
     */
    function predictPrivateOfferAndTimeLockAddress(
        bytes32 _rawSalt,
        PrivateOfferArguments calldata _arguments,
        uint64 _lockedUntil,
        address _timeLockOwner,
        GlobalTokenExitRegistry _tokenExitRegistry,
        address _trustedForwarder
    ) public view returns (address privateOfferAddress, address timeLockAddress) {
        timeLockAddress = timeLockCloneFactory.predictCloneAddress(
            _rawSalt,
            _trustedForwarder,
            _timeLockOwner,
            _lockedUntil,
            _tokenExitRegistry
        );

        PrivateOfferArguments memory arguments = _arguments;
        arguments.tokenReceiver = timeLockAddress;
        privateOfferAddress = predictPrivateOfferAddress(_rawSalt, arguments);
    }

    /**
     * @notice Predicts the address of a PrivateOffer contract that would be deployed with the given parameters.
     * @param _salt Value influencing the address of the deployed contract, but nothing else.
     * @param _arguments Parameters for the PrivateOffer contract.
     */
    function predictPrivateOfferAddress(
        bytes32 _salt,
        PrivateOfferArguments memory _arguments
    ) public view returns (address) {
        bytes memory bytecode = _getBytecode(_arguments);
        return Create2.computeAddress(_salt, keccak256(bytecode));
    }

    /**
     * @notice Deploys a CoinvestedPosition clone and a PrivateOffer in one transaction. Tokens are
     *      delivered directly into the CoinvestedPosition.
     *      Use predictPrivateOfferAndCoinvestedPositionAddress to obtain both addresses beforehand.
     * @param _rawSalt Value influencing the addresses of the deployed contracts, but nothing else.
     * @param _trustedForwarder Trusted forwarder for the CoinvestedPosition clone; checked for security.
     * @param _arguments Arguments for the PrivateOffer contract; tokenReceiver is overridden to the
     *      CoinvestedPosition address.
     * @param _coinvestedPositionArgs Arguments for the CoinvestedPosition clone.
     * @return privateOfferAddress The address of the deployed PrivateOffer contract.
     * @return coinvestedPositionAddress The address of the deployed CoinvestedPosition clone.
     */
    function deployPrivateOfferWithCoinvestedPosition(
        bytes32 _rawSalt,
        address _trustedForwarder,
        PrivateOfferArguments calldata _arguments,
        CoinvestedPositionInitializerArguments calldata _coinvestedPositionArgs
    ) external returns (address privateOfferAddress, address coinvestedPositionAddress) {
        // deploy the coinvested position clone
        coinvestedPositionAddress = coinvestedPositionCloneFactory.createCoinvestedPositionClone(
            _rawSalt,
            _trustedForwarder,
            _coinvestedPositionArgs
        );

        // route token delivery to the coinvested position
        PrivateOfferArguments memory arguments = _arguments;
        arguments.tokenReceiver = coinvestedPositionAddress;

        // deploy the private offer, which delivers tokens into the coinvested position
        privateOfferAddress = _deployPrivateOffer(_rawSalt, arguments);

        require(
            _arguments.token.balanceOf(coinvestedPositionAddress) == _arguments.tokenAmount,
            "token delivery failed"
        );
        emit NewPrivateOfferWithCoinvestedPosition(privateOfferAddress, coinvestedPositionAddress);
    }

    /**
     * @notice Predicts the addresses of the PrivateOffer and CoinvestedPosition contracts that would be
     *      deployed with the given parameters.
     * @param _rawSalt Value influencing the addresses of the deployed contracts, but nothing else.
     * @param _trustedForwarder Trusted forwarder for the CoinvestedPosition clone.
     * @param _arguments Arguments for the PrivateOffer contract.
     * @param _coinvestedPositionArgs Arguments for the CoinvestedPosition clone.
     * @return privateOfferAddress The address of the PrivateOffer contract that would be deployed.
     * @return coinvestedPositionAddress The address of the CoinvestedPosition clone that would be deployed.
     */
    function predictPrivateOfferAndCoinvestedPositionAddress(
        bytes32 _rawSalt,
        address _trustedForwarder,
        PrivateOfferArguments memory _arguments,
        CoinvestedPositionInitializerArguments memory _coinvestedPositionArgs
    ) public view returns (address privateOfferAddress, address coinvestedPositionAddress) {
        coinvestedPositionAddress = coinvestedPositionCloneFactory.predictCloneAddress(
            _rawSalt,
            _trustedForwarder,
            _coinvestedPositionArgs
        );

        _arguments.tokenReceiver = coinvestedPositionAddress;
        privateOfferAddress = predictPrivateOfferAddress(_rawSalt, _arguments);
    }

    /**
     * @dev Generates the bytecode of the PrivateOffer contract to be deployed.
     */
    function _getBytecode(PrivateOfferArguments memory _arguments) private pure returns (bytes memory) {
        return abi.encodePacked(type(PrivateOffer).creationCode, abi.encode(_arguments));
    }

    /**
     * @dev Deploys a PrivateOffer contract using create2.
     */
    function _deployPrivateOffer(bytes32 _rawSalt, PrivateOfferArguments memory _arguments) private returns (address) {
        address privateOffer = Create2.deploy(0, _rawSalt, _getBytecode(_arguments));
        emit Deploy(privateOffer);
        return privateOffer;
    }
}
