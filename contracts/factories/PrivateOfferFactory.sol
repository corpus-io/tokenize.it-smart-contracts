// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.23;

// taken from https://docs.alchemy.com/docs/create2-an-alternative-to-deriving-contract-addresses

import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/utils/Create2.sol";
import "../PrivateOffer.sol";

/**
 * @title PrivateOfferFactory
 * @author malteish, cjentzsch
 * @notice This contract deploys PrivateOffers using create2. It is used to deploy PrivateOffers with a deterministic address.
 * @dev One deployment of this contract can be used for deployment of any number of PrivateOffers using create2.
 */
contract PrivateOfferFactory {
    event Deploy(address indexed addr);

    /**
     * @notice Deploys a contract using create2. During the deployment, `_currencyPayer` pays `_currencyReceiver` for the purchase of `_tokenAmount` tokens at `_tokenPrice` per token.
     *      The tokens are minted to `_tokenReceiver`. The token is deployed at `_token` and the currency is `_currency`.
     * @param _salt salt used for privacy. Could be used for vanity addresses, too.
     * @param _currencyPayer address holding the currency. Must have given sufficient allowance to this contract.
     * @param _tokenReceiver address receiving the tokens
     * @param _currencyReceiver address receiving the currency
     * @param _tokenAmount amount of tokens to be minted
     * @param _tokenPrice price of one token in currency, see docs/price.md.
     * @param _expiration timestamp after which the contract is no longer valid
     * @param _currency address of the currency
     * @param _token address of the token
     * @return address of the deployed contract
     */
    function deploy(
        bytes32 _salt,
        address _currencyPayer,
        address _tokenReceiver,
        address _currencyReceiver,
        uint256 _tokenAmount,
        uint256 _tokenPrice,
        uint256 _expiration,
        IERC20 _currency,
        IERC20 _token
    ) external returns (address) {
        address actualAddress = Create2.deploy(
            0,
            _salt,
            getBytecode(
                _currencyPayer,
                _tokenReceiver,
                _currencyReceiver,
                _tokenAmount,
                _tokenPrice,
                _expiration,
                _currency,
                _token
            )
        );

        emit Deploy(actualAddress);
        return actualAddress;
    }

    /**
     * @notice Computes the address of a contract to be deployed using create2.
     * @param _salt salt used for privacy. Could be used for vanity addresses, too.
     * @param _currencyPayer address holding the currency. Must have given sufficient allowance to this contract.
     * @param _tokenReceiver address receiving the tokens
     * @param _currencyReceiver address receiving the currency
     * @param _amount amount of tokens to be minted
     * @param _tokenPrice price of one token in currency
     * @param _expiration timestamp after which the contract is no longer valid
     * @param _currency address of the currency
     * @param _token address of the token
     * @return address of the contract to be deployed
     */
    function getAddress(
        bytes32 _salt,
        address _currencyPayer,
        address _tokenReceiver,
        address _currencyReceiver,
        uint256 _amount,
        uint256 _tokenPrice,
        uint256 _expiration,
        IERC20 _currency,
        IERC20 _token
    ) external view returns (address) {
        bytes memory bytecode = getBytecode(
            _currencyPayer,
            _tokenReceiver,
            _currencyReceiver,
            _amount,
            _tokenPrice,
            _expiration,
            _currency,
            _token
        );
        return Create2.computeAddress(_salt, keccak256(bytecode));
    }

    /**
     * @dev Generates the bytecode of the contract to be deployed, using the parameters.
     * @return bytecode of the contract to be deployed.
     */
    function getBytecode(
        address _currencyPayer,
        address _tokenReceiver,
        address _currencyReceiver,
        uint256 _amount,
        uint256 _tokenPrice,
        uint256 _expiration,
        IERC20 _currency,
        IERC20 _token
    ) private pure returns (bytes memory) {
        return
            abi.encodePacked(
                type(PrivateOffer).creationCode,
                abi.encode(
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
