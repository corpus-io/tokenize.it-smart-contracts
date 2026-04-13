// SPDX-License-Identifier: MIT

pragma solidity 0.8.23;

import "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/metatx/ERC2771ContextUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "./Token.sol";
import "./common/IFeeSettings.sol";

struct ExitInitializerArguments {
    /// @notice Owner of the contract
    address owner;
    /// @notice Token holders will return in exchange for exit proceeds
    Token token;
    /// @notice ERC20 token used for exit payouts; must have TRUSTED_CURRENCY bit set on the token's allowList
    IERC20 currency;
    /// @notice Currency amount (in smallest currency units) per 10**token.decimals() token units
    uint256 pricePerToken;
    /// @notice Timestamp from which claims are valid
    uint64 claimStart;
    /// @notice Timestamp after which claims expire
    uint64 drainStart;
    /// @notice Currencies that CoinvestedPositions may have been denominated in (parallel array with referenceToExitRates).
    ///         See referenceToExitRates for the rate convention.
    IERC20[] referenceCurrencies;
    /// @notice Exchange rates from each reference currency to the exit currency, expressed using the same
    ///         convention as tokenPrice (see docs/price.md):
    ///             exitCurrencyBits = referenceCurrencyBits * rate / 10**referenceCurrency.decimals()
    ///         Example: exit currency is USDC (6 decimals), reference currency is EURe (18 decimals),
    ///         1 EURe = 5 USDC. Then rate = 5e6, because:
    ///             5e6 USDC bits = 1e18 EURe bits * 5e6 / 10**18
    ///         This rate is used by CoinvestedPosition to convert a carry amount denominated in the
    ///         reference currency into the exit currency so carry splits can be calculated correctly.
    uint256[] referenceToExitRates;
}

/**
 * @title tokenize.it Exit
 * @author malteish, cjentzsch
 * @notice This contract implements the automated exit: token holders call the claim function,
 *  thus transferring their tokens to the contract and receiving exit proceeds in return.
 *  The price is fixed at deployment.
 *  Claims are only valid within the exit window set at initialization.
 *  Received tokens are held in this contract and can either be burned or extracted by the
 *  owner after the exit window closes.
 */
contract Exit is ERC2771ContextUpgradeable, Ownable2StepUpgradeable, ReentrancyGuardUpgradeable {
    using SafeERC20 for IERC20;

    Token public token;
    IERC20 public currency;
    /// @notice Currency amount (in smallest currency units) per 10**token.decimals() token units
    uint256 public pricePerToken;
    uint64 public claimStart;
    uint64 public drainStart;
    /// @notice Exchange rate from a reference currency to the exit currency.
    ///         Expressed as exit-currency bits per 10**referenceCurrency.decimals() reference-currency bits —
    ///         the same convention as tokenPrice (see docs/price.md):
    ///             exitCurrencyBits = referenceCurrencyBits * referenceToExitRate[ref] / 10**ref.decimals()
    ///         Example: exit currency is USDC (6 decimals), reference currency is EURe (18 decimals),
    ///         1 EURe = 5 USDC → referenceToExitRate[EURe] = 5e6
    ///         Used by CoinvestedPosition to convert a carry threshold denominated in the position's
    ///         base currency into the exit currency when the two differ.
    mapping(IERC20 => uint256) public referenceToExitRate;

    /**
     * This constructor creates a logic contract that is used to clone new exit contracts.
     * It has no owner, and can not be used directly.
     * @param _trustedForwarder This address can execute transactions in the name of any other address
     */
    constructor(address _trustedForwarder) ERC2771ContextUpgradeable(_trustedForwarder) {
        _disableInitializers();
    }

    /**
     * @notice Initializes the exit contract with the given parameters and funds it with currency.
     * @param _arguments Struct containing all initialization parameters
     * @param _currencyProvider Address from which the initial currency amount is transferred
     * @param _initialFundingAmount Amount of currency to transfer from _currencyProvider to this contract
     */
    function initialize(
        ExitInitializerArguments memory _arguments,
        address _currencyProvider,
        uint256 _initialFundingAmount
    ) external initializer {
        require(_arguments.pricePerToken > 0, "price must be positive");
        require(_arguments.claimStart > 0, "claimStart must be set");
        require(_arguments.drainStart > _arguments.claimStart, "drainStart must be after claimStart");
        require(address(_arguments.currency) != address(_arguments.token), "currency and token must be different");
        __ReentrancyGuard_init();
        __Ownable2Step_init();
        _transferOwnership(_arguments.owner);
        token = _arguments.token;
        require(
            token.allowList().map(address(_arguments.currency)) == TRUSTED_CURRENCY,
            "currency needs to be on the allowlist with TRUSTED_CURRENCY attribute"
        );
        currency = _arguments.currency;
        pricePerToken = _arguments.pricePerToken;
        claimStart = _arguments.claimStart;
        drainStart = _arguments.drainStart;
        require(
            _arguments.referenceCurrencies.length == _arguments.referenceToExitRates.length,
            "referenceCurrencies and referenceToExitRates must have the same length"
        );
        for (uint256 i = 0; i < _arguments.referenceCurrencies.length; i++) {
            require(
                address(_arguments.referenceCurrencies[i]) != address(0),
                "referenceCurrency can not be zero address"
            );
            require(
                _arguments.referenceCurrencies[i] != _arguments.currency,
                "referenceCurrency can not be the exit currency"
            );
            require(_arguments.referenceToExitRates[i] > 0, "referenceToExitRate must be positive");
            referenceToExitRate[_arguments.referenceCurrencies[i]] = _arguments.referenceToExitRates[i];
        }
        _arguments.currency.safeTransferFrom(_currencyProvider, address(this), _initialFundingAmount);
    }

    /**
     * @notice Returns the fee amount and fee collector address for the given amount.
     * @param _amount Gross amount to compute the fee on
     * @return fee Fee amount
     * @return feeCollector Address that receives the fee
     */
    function _feeInfo(uint256 _amount) internal view returns (uint256 fee, address feeCollector) {
        IFeeSettingsV3 feeSettings = IFeeSettingsV3(address(token.feeSettings()));
        if (feeSettings.supportsInterface(type(IFeeSettingsV3).interfaceId)) {
            fee = feeSettings.fee(FeeTypes.EXIT, _amount, address(token));
            feeCollector = feeSettings.feeCollector(FeeTypes.EXIT, address(token));
        }
        // if v3 is not supported, fee stays 0 and feeCollector stays address(0)
    }

    /**
     * @notice Returns the net currency payout a holder would receive if they claimed their entire balance now.
     * @param _holder Address of the token holder
     * @return Net currency amount after fees
     */
    function eligible(address _holder) public view returns (uint256) {
        uint256 gross = (token.balanceOf(_holder) * pricePerToken) / 10 ** token.decimals();
        (uint256 fee, ) = _feeInfo(gross);
        return gross - fee;
    }

    /**
     * @notice Exchanges tokens for exit proceeds. Transfers _tokenAmount tokens from the caller to this
     *  contract and sends the corresponding currency payout to _recipient.
     * @param _tokenAmount Amount of tokens to exchange for exit proceeds
     * @param _recipient Address that receives the currency payout
     * @param _minPayout Minimum net payout required; reverts if not met
     */
    function claim(uint256 _tokenAmount, address _recipient, uint256 _minPayout) external nonReentrant {
        require(block.timestamp >= claimStart, "exit not yet started");
        IERC20(address(token)).safeTransferFrom(_msgSender(), address(this), _tokenAmount);
        uint256 currencyAmount = (_tokenAmount * pricePerToken) / 10 ** token.decimals();
        (uint256 fee, address feeCollector) = _feeInfo(currencyAmount);
        require(currencyAmount - fee >= _minPayout, "payout below minimum");
        if (fee != 0) {
            currency.safeTransfer(feeCollector, fee);
        }
        currency.safeTransfer(_recipient, currencyAmount - fee);
    }

    /**
     * @notice Transfers the entire balance of _token held by this contract to _recipient.
     *  Can only be called by the owner after drainStart has passed.
     *  Intended to recover any erc20 tokens held by the contract.
     * @param _recipient Address that receives the token balance
     * @param _token ERC20 token to recover
     */
    function drain(address _recipient, IERC20 _token) external onlyOwner nonReentrant {
        require(block.timestamp > drainStart, "exit window not yet closed");
        _token.safeTransfer(_recipient, _token.balanceOf(address(this)));
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
