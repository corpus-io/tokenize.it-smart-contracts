// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.23;

import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/utils/math/SafeCast.sol";
import "@openzeppelin/contracts/utils/Create2.sol";
import "../PrivateOffer.sol";
import "./VestingCloneFactory.sol";

/**
 * @title PrivateOfferCloneFactory
 * @author malteish
 * @notice This contract deploys PrivateOffers using create2. It is used to deploy PrivateOffers with a deterministic address.
 * @dev One deployment of this contract can be used for deployment of any number of PrivateOffers using create2.
 */
contract PrivateOfferFactory {
    event NewPrivateOfferWithLockup(address privateOffer, address vesting);
    event Deploy(address indexed addr);
    VestingCloneFactory public immutable vestingCloneFactory;

    constructor(VestingCloneFactory _vestingCloneFactory) {
        require(_vestingCloneFactory != address(0), "VestingCloneFactory must not be 0");
        vestingCloneFactory = _vestingCloneFactory;
    }

    function createPrivateOfferClone(
        bytes32 _rawSalt,
        PrivateOfferArguments calldata _arguments
    ) external returns (address) {
        return _deployPrivateOffer(_rawSalt, _arguments);
    }

    function executePrivateOfferWithTimeLock(
        bytes32 _rawSalt,
        PrivateOfferArguments calldata _arguments,
        uint256 _vestingStart,
        uint256 _vestingCliff,
        uint256 _vestingDuration,
        address _vestingContractOwner,
        address trustedForwarder
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
        Vesting vesting = vestingCloneFactory.createVestingClone(
            salt,
            trustedForwarder,
            address(this),
            address(_arguments.token)
        );

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
        PrivateOfferArguments memory calldataArguments = _arguments;
        calldataArguments.tokenReceiver = address(vesting);
        // update currency receiver to be the vesting contract

        address privateOffer = _deployPrivateOffer(_rawSalt, calldataArguments);

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
        address _vestingContractOwner,
        address trustedForwarder
    ) public view returns (address, address) {
        address vestingAddress = vestingCloneFactory.predictCloneAddress(
            _rawSalt,
            trustedForwarder,
            address(this),
            address(_arguments.token)
        );

        // since the vesting contracts address will be used as the token receiver, we need to use it for the prediction
        PrivateOfferArguments memory arguments = _arguments;
        arguments.tokenReceiver = vestingAddress;
        address privateOfferAddress = predictPrivateOfferAddress(_rawSalt, arguments);

        return (privateOfferAddress, vestingAddress);
    }

    function predictPrivateOfferAddress(
        bytes32 _salt,
        PrivateOfferArguments memory _arguments
    ) public view returns (address) {
        bytes memory bytecode = _getBytecode(_arguments);
        return Create2.computeAddress(_salt, keccak256(bytecode));
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

    /**
     * @dev Generates the bytecode of the contract to be deployed, using the parameters.
     * @return bytecode of the contract to be deployed.
     */
    function _getBytecode(PrivateOfferArguments memory _arguments) private pure returns (bytes memory) {
        return abi.encodePacked(type(PrivateOffer).creationCode, abi.encode(_arguments));
    }

    function _deployPrivateOffer(bytes32 _rawSalt, PrivateOfferArguments memory _arguments) private returns (address) {
        address privateOffer = Create2.deploy(0, _rawSalt, _getBytecode(_arguments));

        emit Deploy(privateOffer);
        return privateOffer;
    }
}
