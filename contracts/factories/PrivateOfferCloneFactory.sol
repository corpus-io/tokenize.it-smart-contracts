// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.23;

import "../PrivateOffer.sol";
import "./CloneFactory.sol";
import "./VestingCloneFactory.sol";

/**
 * @title PrivateOfferCloneFactory
 * @author malteish, cjentzsch
 * @notice This contract deploys PrivateOffer clones to a deterministic address.
 * It also deploys the vesting contracts used for token lockup.
 * @dev One deployment of this contract can be used for deployment of any number of PrivateOffer clones.
 */
contract PrivateOfferCloneFactory is CloneFactory {
    /// Emitted when a PrivateOffer contract is deployed with a vesting contract.
    event NewPrivateOfferWithLockup(address privateOffer, address vesting);

    /// The factory for the Vesting contract.
    VestingCloneFactory public immutable vestingCloneFactory;

    /**
     * @notice Constructor.
     * @param _implementation The implementation of the PrivateOffer contract.
     * @param _vestingCloneFactory The factory for the Vesting contract.
     */
    constructor(address _implementation, VestingCloneFactory _vestingCloneFactory) CloneFactory(_implementation) {
        require(address(_vestingCloneFactory) != address(0), "VestingCloneFactory must not be 0");
        vestingCloneFactory = _vestingCloneFactory;
    }

    /**
     * @notice Deploys a private offer clone. During the deployment, `_currencyPayer` pays `_currencyReceiver` for the purchase of `_tokenAmount` tokens at `_tokenPrice` per token.
     *      The tokens are minted or transferred to `_tokenReceiver`. The token used is `_token` and the currency is `_currency`.
     * @param _rawSalt Value influencing the addresses of the deployed contract, but nothing else.
     * @param _fixedArguments Arguments for the PrivateOffer contract.
     * @param _variableArguments Arguments for the PrivateOffer contract.
     * @return privateOfferAddress The address of the PrivateOffer contract that was deployed.
     */
    function createPrivateOfferClone(
        bytes32 _rawSalt,
        PrivateOfferFixedArguments calldata _fixedArguments,
        PrivateOfferVariableArguments calldata _variableArguments
    ) external returns (address) {
        bytes32 salt = _getSalt(_rawSalt, _fixedArguments);
        PrivateOffer privateOffer = PrivateOffer(Clones.cloneDeterministic(implementation, salt));
        privateOffer.initialize(_fixedArguments, _variableArguments);
        emit NewClone(address(privateOffer));
        return address(privateOffer);
    }

    /**
     * @notice Deploys a private offer clone with a vesting contract. During the deployment, `_currencyPayer` pays `_currencyReceiver` for the purchase of `_tokenAmount` tokens at `_tokenPrice` per token.
     *      The tokens are minted or transferred to `_tokenReceiver`. The token used is `_token` and the currency is `_currency`.
     * @param _rawSalt Value influencing the addresses of the deployed contract, but nothing else.
     * @param _fixedArguments Arguments for the PrivateOffer contract.
     * @param _vestingStart The start of the vesting period.
     * @param _vestingCliff The cliff of the vesting period.
     * @param _vestingDuration The duration of the vesting period.
     * @param _vestingContractOwner The owner of the vesting contract.
     */
    function createPrivateOfferCloneWithTimeLock(
        bytes32 _rawSalt,
        PrivateOfferFixedArguments calldata _fixedArguments,
        PrivateOfferVariableArguments calldata _variableArguments,
        uint64 _vestingStart,
        uint64 _vestingCliff,
        uint64 _vestingDuration,
        address _vestingContractOwner,
        address trustedForwarder
    ) external returns (address) {
        // deploy the vesting contract
        Vesting vesting = Vesting(
            vestingCloneFactory.createVestingCloneWithLockupPlan(
                _rawSalt,
                trustedForwarder,
                _vestingContractOwner,
                address(_fixedArguments.token),
                _variableArguments.tokenAmount,
                _variableArguments.tokenReceiver,
                _vestingStart,
                _vestingCliff,
                _vestingDuration
            )
        );

        // update currency receiver to be the vesting contract
        PrivateOfferVariableArguments memory variableArguments = _variableArguments;
        variableArguments.tokenReceiver = address(vesting);

        // get the salt for private offer with time lock
        bytes32 salt = _getSaltWithVesting(_rawSalt, address(vesting));

        // deploy the private offer
        address privateOffer = _createPrivateOfferClone(salt, _fixedArguments, variableArguments);

        require(
            _fixedArguments.token.balanceOf(address(vesting)) == _variableArguments.tokenAmount,
            "Execution failed"
        );
        emit NewPrivateOfferWithLockup(address(privateOffer), address(vesting));
        return address(vesting);
    }

    /**
     * @notice Predicts the addresses of the PrivateOffer and Vesting contracts that would be deployed with the given parameters.
     * @param _rawSalt Value influencing the addresses of the deployed contracts, but nothing else.
     * @param _fixedArguments Arguments for the PrivateOffer contract.
     * @param _vestingStart Begin of the vesting period.
     * @param _vestingCliff Cliff duration.
     * @param _vestingDuration Total vesting duration.
     * @param _vestingContractOwner Address that will own the vesting contract (note: this is not the token receiver or the beneficiary, but rather the company admin)
     * @return privateOfferAddress The address of the PrivateOffer contract that would be deployed.
     * @return vestingAddress The address of the Vesting contract that would be deployed.
     */
    function predictPrivateOfferCloneWithTimeLockAddress(
        bytes32 _rawSalt,
        PrivateOfferFixedArguments calldata _fixedArguments,
        address _trustedForwarder,
        uint64 _vestingStart,
        uint64 _vestingCliff,
        uint64 _vestingDuration,
        address _vestingContractOwner
    ) public view returns (address, address) {
        // predict the vesting address
        address vestingAddress = vestingCloneFactory.predictCloneAddressWithLockupPlan(
            _rawSalt,
            _trustedForwarder,
            _vestingContractOwner,
            address(_fixedArguments.token),
            _vestingStart,
            _vestingCliff,
            _vestingDuration
        );

        // predict the private offer address
        address privateOfferAddress = predictCloneAddress(
            _getSaltWithVesting(_rawSalt, vestingAddress),
            _fixedArguments
        );

        return (privateOfferAddress, vestingAddress);
    }

    /**
     * @notice Predicts the address of the PrivateOffer contract that would be deployed with the given parameters.
     * @param _salt Value influencing the addresses of the deployed contract, but nothing else.
     * @param _fixedArguments Parameters for the PrivateOffer contract (which also influence the address of the deployed contract)
     */
    function predictCloneAddress(
        bytes32 _salt,
        PrivateOfferFixedArguments calldata _fixedArguments
    ) public view returns (address) {
        bytes32 salt = _getSalt(_salt, _fixedArguments);
        return Clones.predictDeterministicAddress(implementation, salt);
    }

    /**
     * Calculates a salt from all input parameters.
     * @param _rawSalt Value influencing the addresses of the deployed contract, but nothing else.
     * @param _vestingAddress Address of the vesting contract.
     * @return salt The salt that would be used to deploy a PrivateOffer contract with the given vesting contract.
     */
    function _getSaltWithVesting(bytes32 _rawSalt, address _vestingAddress) private pure returns (bytes32) {
        return keccak256(abi.encode(_rawSalt, _vestingAddress));
    }

    /**
     * Calculates a salt from all input parameters.
     * @param _rawSalt Value influencing the addresses of the deployed contract, but nothing else.
     * @param _fixedArguments Parameters for the PrivateOffer contract (which also influence the address of the deployed contract)
     * @return salt The salt that would be used to deploy a PrivateOffer contract with the given parameters.
     */
    function _getSalt(
        bytes32 _rawSalt,
        PrivateOfferFixedArguments calldata _fixedArguments
    ) private pure returns (bytes32) {
        return keccak256(abi.encode(_rawSalt, _fixedArguments));
    }

    /**
     * Creates a PrivateOffer contract clone.
     * @param _rawSalt Value influencing the addresses of the deployed contract, but nothing else.
     * @param _fixedArguments Parameters for the PrivateOffer contract (which also influence the address of the deployed contract)
     * @param _variableArguments Parameters for the PrivateOffer contract (which don't influence the address of the deployed contract)
     */
    function _createPrivateOfferClone(
        bytes32 _rawSalt,
        PrivateOfferFixedArguments calldata _fixedArguments,
        PrivateOfferVariableArguments memory _variableArguments
    ) private returns (address) {
        bytes32 salt = _getSalt(_rawSalt, _fixedArguments);
        address clone = Clones.cloneDeterministic(implementation, salt);
        PrivateOffer(clone).initialize(_fixedArguments, _variableArguments);
        emit NewClone(clone);
        return clone;
    }
}
