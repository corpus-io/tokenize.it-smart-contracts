// SPDX-License-Identifier: MIT

pragma solidity 0.8.34;

import "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/metatx/ERC2771ContextUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "../Token.sol";
import "./IFeeSettings.sol";

/**
 * @title tokenize.it PayoutBase
 * @author malteish, cjentzsch
 * @notice Abstract base for contracts that hold currency and pay it out to token holders.
 *      Provides common state (token, currency, pricePerToken, lockedUntil), fee computation,
 *      and the drain function.
 */
abstract contract PayoutBase is ERC2771ContextUpgradeable, Ownable2StepUpgradeable, ReentrancyGuardUpgradeable {
    using SafeERC20 for IERC20;

    Token public token;
    IERC20 public currency;
    /// @notice Currency amount (in smallest currency units) per 10**token.decimals() token units
    uint256 public pricePerToken;
    /// @notice Earliest timestamp at which the owner can drain the contract (and, in Distribution, reassign funds)
    uint64 public lockedUntil;

    /**
     * This constructor creates a logic contract that is used to clone new contracts.
     * It has no owner, and can not be used directly.
     * @param _trustedForwarder This address can execute transactions in the name of any other address
     */
    constructor(address _trustedForwarder) ERC2771ContextUpgradeable(_trustedForwarder) {
        _disableInitializers();
    }

    /**
     * @notice Initializes the common payout state.
     */
    function __PayoutBase_init(
        address _owner,
        Token _token,
        IERC20 _currency,
        uint256 _pricePerToken,
        uint64 _lockedUntil
    ) internal onlyInitializing {
        __ReentrancyGuard_init();
        __Ownable2Step_init();
        _transferOwnership(_owner);
        token = _token;
        currency = _currency;
        pricePerToken = _pricePerToken;
        lockedUntil = _lockedUntil;
    }

    /// @notice Returns the net currency payout a holder would receive if they claimed now.
    function eligible(address _holder) public view virtual returns (uint256);

    /// @notice Claims the caller's payout and sends it to _recipient.
    /// @param _recipient Address that receives the currency payout
    /// @param _minPayout Minimum net payout required; reverts if not met
    function claim(address _recipient, uint256 _minPayout) external virtual;

    /**
     * @notice Returns the fee amount and fee collector address for the given fee type and amount.
     * @param _feeType Fee type identifier (use FeeTypes library constants)
     * @param _amount Amount to compute the fee on
     * @return fee Fee amount
     * @return feeCollector Address that receives the fee
     */
    function _feeInfo(bytes32 _feeType, uint256 _amount) internal view returns (uint256 fee, address feeCollector) {
        IFeeSettingsV3 feeSettings = IFeeSettingsV3(address(token.feeSettings()));
        if (feeSettings.supportsInterface(type(IFeeSettingsV3).interfaceId)) {
            fee = feeSettings.fee(_feeType, _amount, address(token));
            feeCollector = feeSettings.feeCollector(_feeType, address(token));
        }
        // if v3 is not supported, fee stays 0 and feeCollector stays address(0)
    }

    /**
     * @notice Transfers the entire balance of _erc20 held by this contract to _recipient.
     *  Can only be called by the owner after lockedUntil has passed.
     *  Intended to recover any erc20 tokens held by the contract.
     * @param _recipient Address that receives the token balance
     * @param _erc20 ERC20 token to recover
     */
    function drain(address _recipient, IERC20 _erc20) external onlyOwner nonReentrant {
        require(block.timestamp >= lockedUntil, "drain not yet available");
        _erc20.safeTransfer(_recipient, _erc20.balanceOf(address(this)));
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
