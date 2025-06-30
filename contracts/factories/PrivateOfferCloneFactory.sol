// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.23;

import "@openzeppelin/contracts/utils/Create2.sol";
import "../PrivateOffer.sol";
import "./CloneFactory.sol";
import "./VestingCloneFactory.sol";

/**
 * @title PrivateOfferCloneFactory
 * @author malteish, cjentzsch
 * @notice This contract deploys PrivateOffers using create2. It is used to deploy PrivateOffers with a deterministic address.
 * It also deploys the vesting contracts used for token lockup.
 * @dev One deployment of this contract can be used for deployment of any number of PrivateOffers using create2.
 */
contract PrivateOfferCloneFactory is CloneFactory {
    event NewPrivateOfferWithLockup(address privateOffer, address vesting);

    VestingCloneFactory public immutable vestingCloneFactory;

    constructor(address _implementation, VestingCloneFactory _vestingCloneFactory) CloneFactory(_implementation) {
        require(address(_vestingCloneFactory) != address(0), "VestingCloneFactory must not be 0");
        vestingCloneFactory = _vestingCloneFactory;
    }

    /**
     * @notice Deploys a contract using create2. During the deployment, `_currencyPayer` pays `_currencyReceiver` for the purchase of `_tokenAmount` tokens at `_tokenPrice` per token.
     *      The tokens are minted to `_tokenReceiver`. The token is deployed at `_token` and the currency is `_currency`.
     */
    function createPrivateOfferClone(
        bytes32 _rawSalt,
        PrivateOfferFixedArguments calldata _fixedArguments,
        PrivateOfferVariableArguments calldata _variableArguments
    ) external returns (address) {
        PrivateOffer privateOffer = PrivateOffer(Clones.cloneDeterministic(implementation, _rawSalt));
        privateOffer.initialize(_fixedArguments, _variableArguments);
        return address(privateOffer);
    }

    /**
     * @notice Deploys a contract using create2. During the deployment, `_currencyPayer` pays `_currencyReceiver` for the purchase of `_tokenAmount` tokens at `_tokenPrice` per token.
     *      The tokens are minted to `_tokenReceiver`. The token is deployed at `_token` and the currency is `_currency`.
     * @param _rawSalt Value influencing the addresses of the deployed contract, but nothing else.
     * @param _fixedArguments Arguments for the PrivateOffer contract.
     * @param _vestingStart The start of the vesting period.
     * @param _vestingCliff The cliff of the vesting period.
     * @param _vestingDuration The duration of the vesting period.
     * @param _vestingContractOwner The owner of the vesting contract.
     */
    function createPrivateOfferCloneWithTimeLock(
        bytes32 _rawSalt,
        PrivateOfferArguments calldata _fixedArguments,
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

        // deploy the private offer
        address privateOffer = createPrivateOfferClone(_rawSalt, _fixedArguments, variableArguments);

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
     * @param trustedForwarder ERC2771 trusted forwarder address
     * @return privateOfferAddress The address of the PrivateOffer contract that would be deployed.
     * @return vestingAddress The address of the Vesting contract that would be deployed.
     */
    function predictPrivateOfferCloneWithTimeLockAddress(
        bytes32 _rawSalt,
        PrivateOfferArguments calldata _fixedArguments,
        uint64 _vestingStart,
        uint64 _vestingCliff,
        uint64 _vestingDuration,
        address _vestingContractOwner,
        address trustedForwarder
    ) public view returns (address) {
        // vesting address can not be predicted, as it depends on the token amount and token receiver. But the private offer address should
        // change if the vesting conditions change.
        // # todo: mix vesting conditions into private offer address calculation for security

        address privateOfferAddress = predictCloneAddress(
            _getSaltWithVesting(
                _rawSalt,
                _fixedArguments,
                _vestingStart,
                _vestingCliff,
                _vestingDuration,
                _vestingContractOwner
            ),
            _fixedArguments
        );

        return (privateOfferAddress);
    }

    /**
     * @notice Predicts the address of the PrivateOffer contract that would be deployed with the given parameters.
     * @param _salt Value influencing the addresses of the deployed contract, but nothing else.
     * @param _fixedArguments Parameters for the PrivateOffer contract (which also influence the address of the deployed contract)
     */
    function predictCloneAddress(
        bytes32 _salt,
        PrivateOfferFixedArguments memory _fixedArguments
    ) public view returns (address) {
        bytes32 salt = _getSalt(_rawSalt, _fixedArguments);
        return Clones.predictDeterministicAddress(implementation, salt);
    }

    /**
     * Calculates a salt from all input parameters.
     * @param _rawSalt Value influencing the addresses of the deployed contract, but nothing else.
     * @param _fixedArguments Arguments for the PrivateOffer contract.
     * @param _vestingStart Begin of the vesting period.
     * @param _vestingCliff Cliff duration.
     * @param _vestingDuration Total vesting duration.
     * @param _vestingContractOwner Address that will own the vesting contract (note: this is not the token receiver or the beneficiary, but rather the company admin)
     */
    function _getSaltWithVesting(
        bytes32 _rawSalt,
        PrivateOfferFixedArguments calldata _fixedArguments,
        uint64 _vestingStart,
        uint64 _vestingCliff,
        uint64 _vestingDuration,
        address _vestingContractOwner
    ) private pure returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    _rawSalt,
                    _fixedArguments,
                    _vestingStart,
                    _vestingCliff,
                    _vestingDuration,
                    _vestingContractOwner
                )
            );
    }

    function _getSalt(
        bytes32 _rawSalt,
        PrivateOfferFixedArguments calldata _fixedArguments
    ) private pure returns (bytes32) {
        return keccak256(abi.encode(_rawSalt, _fixedArguments));
    }

    /**
     * Creates a PrivateOffer contract using create2.
     * @param _rawSalt Value influencing the addresses of the deployed contract, but nothing else.
     * @param _fixedArguments Parameters for the PrivateOffer contract (which also influence the address of the deployed contract)
     * @param _variableArguments Parameters for the PrivateOffer contract (which don't influence the address of the deployed contract)
     */
    function _createPrivateOfferClone(
        bytes32 _rawSalt,
        PrivateOfferFixedArguments memory _fixedArguments,
        PrivateOfferVariableArguments memory _variableArguments
    ) private returns (address) {
        bytes32 salt = _getSalt(_rawSalt, _fixedArguments);
        address clone = Clones.cloneDeterministic(implementation, salt);
        PrivateOffer(clone).initialize(_fixedArguments, _variableArguments);
        emit NewClone(clone);
        return clone;
    }
}
