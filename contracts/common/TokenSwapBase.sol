// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/metatx/ERC2771ContextUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

import "../Token.sol";
import "./Errors.sol";

/**
 * @title TokenSwapBase
 * @author malteish, cjentzsch
 * @notice Abstract base contract for token swap variants. Contains shared state,
 *      initialization logic, fee handling, price management, and pause controls.
 * @dev Uses clone/proxy pattern. Constructor disables initializers, children call _initializeBase().
 */
abstract contract TokenSwapBase is
    ERC2771ContextUpgradeable,
    Ownable2StepUpgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable
{
    using SafeERC20 for IERC20;

    /// The price of a token, expressed as amount of bits of currency per main unit token (e.g.: 2 USDC (6 decimals) per TOK (18 decimals) => price = 2*10^6 ).
    /// @dev units: [tokenPrice] = [currency_bits]/[token], so for above example: [tokenPrice] = [USDC_bits]/[TOK]
    uint256 public tokenPrice;
    /// currency used to pay for the token purchase. Must be ERC20, so ether can only be used as wrapped ether (WETH)
    IERC20 public currency;
    /// token to be transferred
    Token public token;

    /// @notice Price changed.
    /// @param newTokenPrice new price of a token, expressed as amount of bits of currency per main unit token (e.g.: 2 USDC (6 decimals) per TOK (18 decimals) => price = 2*10^6 ).
    event TokenPriceChanged(uint256 newTokenPrice);

    /**
     * @notice `buyer` bought `tokenAmount` tokens for `currencyAmount` currency.
     * @param buyer Address that bought the tokens
     * @param tokenAmount Amount of tokens bought
     * @param currencyAmount Amount of currency paid
     */
    event TokensBought(address indexed buyer, uint256 tokenAmount, uint256 currencyAmount);

    /**
     * This constructor creates a logic contract that is used to clone new contracts.
     * It has no owner, and can not be used directly.
     * @param _trustedForwarder This address can execute transactions in the name of any other address
     */
    constructor(address _trustedForwarder) ERC2771ContextUpgradeable(_trustedForwarder) {
        _disableInitializers();
    }

    /**
     * @notice Shared initialization logic for all TokenSwap variants.
     * @param _owner Owner of the contract
     * @param _tokenPrice price of a token in currency bits per main unit token
     * @param _currency currency used for payment
     * @param _token token being swapped
     */
    function _initializeBase(
        address _owner,
        uint256 _tokenPrice,
        IERC20 _currency,
        Token _token
    ) internal onlyInitializing {
        require(_owner != address(0), ZeroOwnerAddress());
        __Ownable2Step_init();
        __Pausable_init();
        __ReentrancyGuard_init();
        _transferOwnership(_owner);
        require(address(_currency) != address(0), ZeroCurrencyAddress());
        require(address(_token) != address(0), ZeroTokenAddress());
        require(_token.allowList().map(address(_currency)) == TRUSTED_CURRENCY, UntrustedCurrency());
        tokenPrice = _tokenPrice;
        currency = _currency;
        token = _token;
    }

    /**
     * @notice Retrieves the fee amount and the fee receiver for a token swap transaction.
     * @dev Uses IFeeSettingsV3.fee(FeeTypes.SECONDARY_MARKET, ...) when the fee settings
     *      contract supports V3; falls back to privateOfferFee for V2-only deployments.
     * @param _currencyAmount The total currency amount involved in the swap transaction, in bits (smallest subunit of currency)
     * @return The fee amount to be collected, in bits (smallest subunit of currency)
     * @return The address that will receive the collected fees
     */
    function _getFeeAndFeeReceiver(uint256 _currencyAmount) internal view returns (uint256, address) {
        IFeeSettingsV2 feeSettingsV2 = token.feeSettings();
        if (feeSettingsV2.supportsInterface(type(IFeeSettingsV3).interfaceId)) {
            IFeeSettingsV3 feeSettingsV3 = IFeeSettingsV3(address(feeSettingsV2));
            return (
                feeSettingsV3.fee(FeeTypes.SECONDARY_MARKET, _currencyAmount, address(token)),
                feeSettingsV3.feeCollector(FeeTypes.SECONDARY_MARKET, address(token))
            );
        }
        // V2 fallback: use privateOfferFee until the fee settings contract is upgraded
        return (
            feeSettingsV2.privateOfferFee(_currencyAmount, address(token)),
            feeSettingsV2.privateOfferFeeCollector(address(token))
        );
    }

    /**
     * @notice change tokenPrice to `_tokenPrice`
     * @param _tokenPrice new tokenPrice
     */
    function setTokenPrice(uint256 _tokenPrice) external onlyOwner {
        require(_tokenPrice != 0, ZeroPrice());
        tokenPrice = _tokenPrice;
        emit TokenPriceChanged(_tokenPrice);
    }

    /**
     * @notice pause the contract
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @notice unpause the contract
     */
    function unpause() external virtual;

    /**
     * @dev both Ownable and ERC2771Context have a _msgSender() function, so we need to override and select which one to use.
     */
    function _msgSender() internal view override(ContextUpgradeable, ERC2771ContextUpgradeable) returns (address) {
        return ERC2771ContextUpgradeable._msgSender();
    }

    /**
     * @dev both Ownable and ERC2771Context have a _msgData() function, so we need to override and select which one to use.
     */
    function _msgData() internal view override(ContextUpgradeable, ERC2771ContextUpgradeable) returns (bytes calldata) {
        return ERC2771ContextUpgradeable._msgData();
    }

    /**
     * @dev both Ownable and ERC2771Context have a _contextSuffixLength() function, so we need to override and select which one to use.
     */
    function _contextSuffixLength()
        internal
        view
        virtual
        override(ContextUpgradeable, ERC2771ContextUpgradeable)
        returns (uint256)
    {
        return ERC2771ContextUpgradeable._contextSuffixLength();
    }
}
