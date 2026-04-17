// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/metatx/ERC2771ContextUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "./Distribution.sol";
import "./Exit.sol";
import "./GlobalTokenExitRegistry.sol";

/**
 * @title TimeLock
 * @author malteish
 * @notice Blocks ERC20 token withdrawals until a given timestamp. The owner can drain any
 *      token to any recipient after lockedUntil has passed.
 * @dev Uses clone/proxy pattern. Constructor disables initializers, separate initialize().
 */
contract TimeLock is Initializable, OwnableUpgradeable, ERC2771ContextUpgradeable, ReentrancyGuardUpgradeable {
    /// @notice Reverted when the tokenExitRegistry address argument is zero.
    error ZeroTokenExitRegistryAddress();

    /// @notice Reverted when claimExit() is called but no exit is set in tokenExitRegistry for the token.
    error NoExitSet();

    /// @notice Reverted when claimExit() is called but this contract holds no tokens.
    error NoTokensToExit();

    /// @notice Reverted when drain() is called before lockedUntil has elapsed.
    error TimeLockNotExpired();

    /// @notice Reverted when drain() is called but this contract holds no tokens.
    error NoTokensToDrain();
    using SafeERC20 for IERC20;

    /// unix timestamp before which drain() is blocked
    uint64 public lockedUntil;
    /// registry contract; if an exit is set for the token, it can be claimed
    GlobalTokenExitRegistry public tokenExitRegistry;

    event Drained(IERC20 indexed token, address indexed recipient, uint256 amount);
    event DividendsDistributed(Distribution indexed distribution, address indexed recipient);
    event ExitDistributed(Exit indexed exit, address indexed recipient, uint256 tokenAmount);

    /**
     * This contract will be used through clones, so the constructor only initializes
     * the logic contract.
     * @param _trustedForwarder This address can execute transactions in the name of any other address
     */
    constructor(address _trustedForwarder) ERC2771ContextUpgradeable(_trustedForwarder) {
        _disableInitializers();
    }

    /**
     * @notice Sets up the TimeLock.
     * @param _owner owner of the contract
     * @param _lockedUntil unix timestamp before which drain() is blocked; 0 means no lock
     * @param _tokenExitRegistry registry contract; setting exit on it bypasses lockedUntil
     */
    function initialize(
        address _owner,
        uint64 _lockedUntil,
        GlobalTokenExitRegistry _tokenExitRegistry
    ) public initializer {
        require(_owner != address(0), ZeroOwnerAddress());
        require(_lockedUntil > block.timestamp, LockedUntilNotInFuture());
        require(address(_tokenExitRegistry) != address(0), ZeroTokenExitRegistryAddress());
        __Ownable_init();
        __ReentrancyGuard_init();
        _transferOwnership(_owner);
        lockedUntil = _lockedUntil;
        tokenExitRegistry = _tokenExitRegistry;
    }

    /**
     * @notice Claim this contract's eligible share from _dist and forward the received currency to _recipient.
     * @param _dist the Distribution contract to claim from
     * @param _recipient address to forward the received currency to
     */
    function claimDistribution(
        Distribution _dist,
        address _recipient,
        uint256 _minPayout
    ) external onlyOwner nonReentrant {
        require(_recipient != address(0), ZeroReceiverAddress());
        _dist.claim(_recipient, _minPayout);
        emit DividendsDistributed(_dist, _recipient);
    }

    /**
     * @notice Claim exit proceeds for this contract's full balance of `_token` and forward to _recipient.
     * @dev Requires an exit to be set for `_token` in tokenExitRegistry. Approves the exit contract,
     *      calls claim(), and forwards all received currency to _recipient.
     * @param _token the token to exit
     * @param _recipient address to receive the exit proceeds
     */
    function claimExit(Token _token, address _recipient, uint256 _minPayout) external onlyOwner nonReentrant {
        Exit exit = tokenExitRegistry.exits(_token);
        require(address(exit) != address(0), NoExitSet());
        require(_recipient != address(0), ZeroReceiverAddress());
        uint256 tokenBalance = _token.balanceOf(address(this));
        require(tokenBalance > 0, NoTokensToExit());
        IERC20(address(_token)).approve(address(exit), tokenBalance);
        exit.claim(_recipient, _minPayout);
        emit ExitDistributed(exit, _recipient, tokenBalance);
    }

    /**
     * @notice Transfer the full balance of _token to _recipient. Blocked until lockedUntil has passed.
     * @param _token ERC20 token to drain
     * @param _recipient address to send the tokens to
     */
    function drain(IERC20 _token, address _recipient) external onlyOwner {
        require(block.timestamp >= lockedUntil, TimeLockNotExpired());
        require(_recipient != address(0), ZeroReceiverAddress());
        uint256 balance = _token.balanceOf(address(this));
        require(balance > 0, NoTokensToDrain());
        _token.safeTransfer(_recipient, balance);
        emit Drained(_token, _recipient, balance);
    }

    function _msgSender() internal view override(ContextUpgradeable, ERC2771ContextUpgradeable) returns (address) {
        return ERC2771ContextUpgradeable._msgSender();
    }

    function _msgData() internal view override(ContextUpgradeable, ERC2771ContextUpgradeable) returns (bytes calldata) {
        return ERC2771ContextUpgradeable._msgData();
    }

    function _contextSuffixLength()
        internal
        view
        override(ContextUpgradeable, ERC2771ContextUpgradeable)
        returns (uint256)
    {
        return ERC2771ContextUpgradeable._contextSuffixLength();
    }
}
