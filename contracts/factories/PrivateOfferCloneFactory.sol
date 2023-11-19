// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.23;

import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/utils/math/SafeCast.sol";
import "../PrivateOffer.sol";
import "../Vesting.sol";
import "./CloneFactory.sol";

/**
 * @title PrivateOfferCloneFactory
 * @author malteish
 * @notice This contract deploys PrivateOffers using create2. It is used to deploy PrivateOffers with a deterministic address.
 * @dev One deployment of this contract can be used for deployment of any number of PrivateOffers using create2.
 */
contract PrivateOfferCloneFactory is CloneFactory {
    event NewPrivateOfferWithLockup(address privateOffer, address vesting);
    address public immutable vestingImplementation;

    constructor(
        address _privateOfferImplementation,
        address _vestingWalletImplementation
    ) CloneFactory(_privateOfferImplementation) {
        require(_vestingWalletImplementation != address(0), "VestingWallet implementation address must not be 0");
        vestingImplementation = _vestingWalletImplementation;
    }

    function createPrivateOfferClone(
        bytes32 _rawSalt,
        address _currencyPayer,
        address _tokenReceiver,
        address _currencyReceiver,
        uint256 _tokenAmount,
        uint256 _tokenPrice,
        uint256 _expiration,
        IERC20 _currency,
        Token _token
    ) external returns (address) {
        bytes32 salt = _getSalt(
            _rawSalt,
            _currencyPayer,
            _tokenReceiver,
            _currencyReceiver,
            _tokenAmount,
            _tokenPrice,
            _expiration,
            _currency,
            _token
        );
        PrivateOffer privateOffer = PrivateOffer(Clones.cloneDeterministic(implementation, salt));
        privateOffer.initialize(
            _currencyPayer,
            _tokenReceiver,
            _currencyReceiver,
            _tokenAmount,
            _tokenPrice,
            _expiration,
            _currency,
            _token
        );
        emit NewClone(address(privateOffer));
        return address(privateOffer);
    }

    function executePrivateOfferWithTimeLock(
        bytes32 _rawSalt,
        PrivateOfferArguments calldata _arguments,
        uint256 _vestingStart,
        uint256 _vestingCliff,
        uint256 _vestingDuration,
        address _vestingContractOwner
    ) external returns (address) {
        bytes32 salt = _getSalt(
            _rawSalt,
            _arguments,
            _vestingStart,
            _vestingCliff,
            _vestingDuration,
            _vestingContractOwner
        );

        // deploy the vesting contract
        Vesting vesting = Vesting(Clones.cloneDeterministic(vestingImplementation, salt));
        vesting.initialize(address(this), address(_arguments.token));

        // create the vesting plan
        vesting.createVesting(
            _arguments.tokenAmount,
            _arguments.tokenReceiver,
            SafeCast.toUint64(_vestingStart),
            SafeCast.toUint64(_vestingCliff),
            SafeCast.toUint64(_vestingDuration),
            false
        ); // this plan is not mintable

        // transfer ownership of the vesting contract
        vesting.transferOwnership(_vestingContractOwner);

        // deploy the private offer
        PrivateOffer privateOffer = PrivateOffer(Clones.cloneDeterministic(implementation, salt));
        // update currency receiver to be the vesting contract
        PrivateOfferArguments memory updatedArguments = _arguments;
        updatedArguments.tokenReceiver = address(vesting);
        privateOffer.initializeFast(updatedArguments);

        require(_arguments.token.balanceOf(address(vesting)) == _arguments.tokenAmount, "Execution failed");
        emit NewPrivateOfferWithLockup(address(privateOffer), address(vesting));
        return address(vesting);
    }

    function predictPrivateOfferAndTimeLockAddress(
        bytes32 _rawSalt,
        PrivateOfferArguments calldata _arguments,
        uint256 _vestingStart,
        uint256 _vestingCliff,
        uint256 _vestingDuration,
        address _vestingContractOwner
    ) public view returns (address, address) {
        bytes32 salt = _getSalt(
            _rawSalt,
            _arguments,
            _vestingStart,
            _vestingCliff,
            _vestingDuration,
            _vestingContractOwner
        );

        address privateOfferAddress = Clones.predictDeterministicAddress(implementation, salt);
        address vestingAddress = Clones.predictDeterministicAddress(vestingImplementation, salt);

        return (privateOfferAddress, vestingAddress);
    }

    function predictPrivateOfferAddress(
        bytes32 _rawSalt,
        address _currencyPayer,
        address _tokenReceiver,
        address _currencyReceiver,
        uint256 _amount,
        uint256 _tokenPrice,
        uint256 _expiration,
        IERC20 _currency,
        Token _token
    ) external view returns (address) {
        bytes32 salt = _getSalt(
            _rawSalt,
            _currencyPayer,
            _tokenReceiver,
            _currencyReceiver,
            _amount,
            _tokenPrice,
            _expiration,
            _currency,
            _token
        );
        return Clones.predictDeterministicAddress(implementation, salt);
    }

    // todo: remove this
    function predictCloneAddress(
        bytes32 _rawSalt,
        address _currencyPayer,
        address _tokenReceiver,
        address _currencyReceiver,
        uint256 _amount,
        uint256 _tokenPrice,
        uint256 _expiration,
        IERC20 _currency,
        Token _token
    ) external view returns (address) {
        bytes32 salt = _getSalt(
            _rawSalt,
            _currencyPayer,
            _tokenReceiver,
            _currencyReceiver,
            _amount,
            _tokenPrice,
            _expiration,
            _currency,
            _token
        );
        return Clones.predictDeterministicAddress(implementation, salt);
    }

    function predictVestingAddress(
        bytes32 _rawSalt,
        PrivateOfferArguments calldata _arguments,
        uint256 _vestingStart,
        uint256 _vestingCliff,
        uint256 _vestingDuration,
        address _vestingContractOwner
    ) external view returns (address) {
        bytes32 salt = _getSalt(
            _rawSalt,
            _arguments,
            _vestingStart,
            _vestingCliff,
            _vestingDuration,
            _vestingContractOwner
        );
        return Clones.predictDeterministicAddress(vestingImplementation, salt);
    }

    function _getSalt(
        bytes32 _rawSalt,
        PrivateOfferArguments calldata _arguments,
        uint256 _vestingStart,
        uint256 _vestingCliff,
        uint256 _vestingDuration,
        address _vestingContractOwner
    ) private pure returns (bytes32) {
        return
            keccak256(
                abi.encode(_rawSalt, _arguments, _vestingStart, _vestingCliff, _vestingDuration, _vestingContractOwner)
            );
    }

    function _getSalt(
        bytes32 _rawSalt,
        address _currencyPayer,
        address _tokenReceiver,
        address _currencyReceiver,
        uint256 _amount,
        uint256 _tokenPrice,
        uint256 _expiration,
        IERC20 _currency,
        Token _token
    ) private pure returns (bytes32) {
        return
            keccak256(
                abi.encodePacked(
                    _rawSalt,
                    _currencyPayer,
                    _tokenReceiver,
                    _currencyReceiver,
                    _amount,
                    _tokenPrice,
                    _expiration,
                    _currency,
                    _token
                )
            );
    }
}
