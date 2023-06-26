// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.17;

// taken from https://docs.alchemy.com/docs/create2-an-alternative-to-deriving-contract-addresses

import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "../contracts/PersonalInviteCloneable.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";

/**
 * @title PersonalInviteFactory
 * @author malteish, cjentzsch
 * @notice This contract deploys PersonalInvites using create2. It is used to deploy PersonalInvites with a deterministic address.
 * @dev One deployment of this contract can be used for deployment of any number of PersonalInvites using create2.
 */
contract PersonalInviteCloneFactory {
    event Deploy(address indexed addr);

    /// The address of the implementation to clone
    address immutable implementation;

    constructor(address _implementation) {
        require(_implementation != address(0), "DssVestCloneFactory/null-implementation");
        implementation = _implementation;
    }

    function predictCloneAddress(bytes32 _hash) public view returns (address) {
        return Clones.predictDeterministicAddress(implementation, _hash);
    }

    function createPersonalInvite(
        bytes32 _hash,
        address _currencyPayer,
        address _tokenReceiver,
        address _currencyReceiver,
        uint256 _tokenAmount,
        uint256 _tokenPrice,
        uint256 _expiration,
        IERC20 _currency,
        Token _token
    ) external returns (address) {
        address clone = Clones.cloneDeterministic(implementation, _hash);

        // this force-connects the address to the investment terms
        require(
            _hash ==
                keccak256(
                    abi.encodePacked(
                        _currencyPayer,
                        _tokenReceiver,
                        _currencyReceiver,
                        _tokenAmount,
                        _tokenPrice,
                        _expiration,
                        _currency,
                        _token
                    )
                ),
            "PersonalInviteCloneFactory/hash-mismatch"
        );

        PersonalInviteCloneable(clone).initialize(
            _currencyPayer,
            _tokenReceiver,
            _currencyReceiver,
            _tokenAmount,
            _tokenPrice,
            _expiration,
            _currency,
            _token
        );

        return clone;
    }
}
