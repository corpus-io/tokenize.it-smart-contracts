// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.23;

import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/utils/Create2.sol";
import "../PrivateOffer.sol";
import "./CloneFactory.sol";

/**
 * @title PrivateOfferCloneFactory
 * @author malteish
 * @notice This contract deploys PrivateOffers using create2. It is used to deploy PrivateOffers with a deterministic address.
 * @dev One deployment of this contract can be used for deployment of any number of PrivateOffers using create2.
 */
contract PrivateOfferCloneFactory is CloneFactory {
    event Deploy(address indexed addr);
    address public immutable vestingWalletImplementation;

    constructor(
        address _privateOfferImplementation,
        address _vestingWalletImplementation
    ) CloneFactory(_privateOfferImplementation) {
        require(_vestingWalletImplementation != address(0), "VestingWallet implementation address must not be 0");
        vestingWalletImplementation = _vestingWalletImplementation;
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
        IERC20 _token
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

    function predictCloneAddress(
        bytes32 _rawSalt,
        address _currencyPayer,
        address _tokenReceiver,
        address _currencyReceiver,
        uint256 _amount,
        uint256 _tokenPrice,
        uint256 _expiration,
        IERC20 _currency,
        IERC20 _token
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

    function _getSalt(
        bytes32 _rawSalt,
        address _currencyPayer,
        address _tokenReceiver,
        address _currencyReceiver,
        uint256 _amount,
        uint256 _tokenPrice,
        uint256 _expiration,
        IERC20 _currency,
        IERC20 _token
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
