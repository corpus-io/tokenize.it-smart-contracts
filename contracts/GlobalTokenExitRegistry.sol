// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import "@openzeppelin/contracts-upgradeable/metatx/ERC2771ContextUpgradeable.sol";

import "./Exit.sol";
import "./Token.sol";
import "./common/Errors.sol";

interface IOwnable {
    function owner() external view returns (address);
}

/**
 * @title GlobalTokenExitRegistry
 * @author malteish
 * @notice Stores the authorized exit contract for each token in a single global registry.
 *         Only a token's DEFAULT_ADMIN_ROLE holder or its owner() can register an exit for that token.
 *         Once set, an exit cannot be changed.
 */
contract GlobalTokenExitRegistry is ERC2771ContextUpgradeable {
    /// @notice Reverted when the exit address argument is zero.
    error ZeroExitAddress();

    /// @notice Reverted when the caller holds neither DEFAULT_ADMIN_ROLE nor owner() on the token.
    error NotTokenAdminOrOwner();

    /// @notice Reverted when an exit has already been set for the token and a second set is attempted.
    error ExitAlreadySet();

    /// @notice Reverted when the exit's token() does not match the token being registered.
    error ExitTokenMismatch();

    /// @notice The authorized exit contract per token.
    mapping(Token => Exit) public exits;

    /// @param token The token for which an exit was set.
    /// @param exit The exit contract that has been set.
    event ExitSet(Token indexed token, Exit indexed exit);

    /**
     * @param _trustedForwarder This address can execute transactions in the name of any other address
     */
    constructor(address _trustedForwarder) ERC2771ContextUpgradeable(_trustedForwarder) {}

    /**
     * @notice Set the authorized exit contract for `_token`. Once set, cannot be changed.
     *         Callable only by a token's DEFAULT_ADMIN_ROLE holder or its owner().
     * @param _token the token for which to set the exit
     * @param _exit the exit contract to authorize; must not be zero address
     */
    function setExit(Token _token, Exit _exit) external {
        require(address(_token) != address(0), ZeroTokenAddress());
        require(address(_exit) != address(0), ZeroExitAddress());
        require(address(exits[_token]) == address(0), ExitAlreadySet());
        require(_isTokenAdminOrOwner(_token, _msgSender()), NotTokenAdminOrOwner());
        require(address(_exit.token()) == address(_token), ExitTokenMismatch());
        exits[_token] = _exit;
        emit ExitSet(_token, _exit);
    }

    /**
     * @notice Returns true if `_caller` holds the token's DEFAULT_ADMIN_ROLE or is the token's owner().
     *         Both checks are wrapped in try/catch so the function works with tokens that implement
     *         only one of the two access-control models.
     */
    function _isTokenAdminOrOwner(Token _token, address _caller) internal view returns (bool) {
        // DEFAULT_ADMIN_ROLE is always bytes32(0) in OZ AccessControl; hardcoding avoids an
        // external call that would revert before try/catch can act on tokens without the function.
        try _token.hasRole(bytes32(0), _caller) returns (bool hasAdminRole) {
            if (hasAdminRole) return true;
        } catch {}

        try IOwnable(address(_token)).owner() returns (address tokenOwner) {
            if (tokenOwner == _caller) return true;
        } catch {}

        return false;
    }
}
