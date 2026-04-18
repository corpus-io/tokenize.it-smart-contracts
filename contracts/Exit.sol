// SPDX-License-Identifier: MIT

pragma solidity 0.8.34;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "./Token.sol";
import "./common/IFeeSettings.sol";
import "./common/PayoutBase.sol";

struct ExitInitializerArguments {
    /// @notice Owner of the contract
    address owner;
    /// @notice Token holders will return in exchange for exit proceeds
    Token token;
    /// @notice ERC20 token used for exit payouts; must have TRUSTED_CURRENCY bit set on the token's allowList
    IERC20 currency;
    /// @notice Currency amount (in smallest currency units) per 10**token.decimals() token units
    uint256 pricePerToken;
    /// @notice Timestamp at which the owner can drain the contract
    uint64 lockedUntil;
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
 *  Received tokens are held in this contract and can either be burned or extracted by the
 *  owner after lockedUntil.
 */
contract Exit is PayoutBase {
    /// @notice Reverted when a reference currency equals the exit currency.
    error ReferenceCurrencyEqualsExitCurrency();
    using SafeERC20 for IERC20;

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
    constructor(address _trustedForwarder) PayoutBase(_trustedForwarder) {}

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
        require(_arguments.pricePerToken > 0, ZeroPrice());
        require(_arguments.lockedUntil > block.timestamp, LockedUntilNotInFuture());
        require(address(_arguments.currency) != address(_arguments.token), CurrencyEqualsToken());
        require(
            _arguments.token.allowList().map(address(_arguments.currency)) == TRUSTED_CURRENCY,
            UntrustedCurrency()
        );
        __PayoutBase_init(
            _arguments.owner,
            _arguments.token,
            _arguments.currency,
            _arguments.pricePerToken,
            _arguments.lockedUntil
        );
        require(_arguments.referenceCurrencies.length == _arguments.referenceToExitRates.length, ArrayLengthMismatch());
        for (uint256 i = 0; i < _arguments.referenceCurrencies.length; i++) {
            require(address(_arguments.referenceCurrencies[i]) != address(0), ZeroCurrencyAddress());
            require(
                address(_arguments.referenceCurrencies[i]) != address(_arguments.currency),
                ReferenceCurrencyEqualsExitCurrency()
            );
            require(_arguments.referenceToExitRates[i] > 0, ZeroPrice());
            referenceToExitRate[_arguments.referenceCurrencies[i]] = _arguments.referenceToExitRates[i];
        }
        _arguments.currency.safeTransferFrom(_currencyProvider, address(this), _initialFundingAmount);
    }

    /**
     * @notice Returns the net currency payout a holder would receive if they claimed their entire balance now.
     * @param _holder Address of the token holder
     * @return Net currency amount after fees
     */
    function eligible(address _holder) public view override returns (uint256) {
        uint256 gross = (token.balanceOf(_holder) * pricePerToken) / 10 ** token.decimals();
        (uint256 fee, ) = _feeInfo(FeeTypes.EXIT, gross);
        return gross - fee;
    }

    /**
     * @notice Exchanges the caller's entire token balance for exit proceeds,
     * which are then sent to _recipient.
     * @param _recipient Address that receives the currency payout
     * @param _minPayout Minimum net payout required; reverts if not met
     */
    function claim(address _recipient, uint256 _minPayout) external override nonReentrant {
        uint256 tokenAmount = token.balanceOf(_msgSender());
        require(tokenAmount > 0, NothingToClaim());
        IERC20(address(token)).safeTransferFrom(_msgSender(), address(this), tokenAmount);
        uint256 currencyAmount = (tokenAmount * pricePerToken) / 10 ** token.decimals();
        (uint256 fee, address feeCollector) = _feeInfo(FeeTypes.EXIT, currencyAmount);
        require(currencyAmount - fee >= _minPayout, PayoutBelowMinimum());
        if (fee != 0) {
            currency.safeTransfer(feeCollector, fee);
        }
        currency.safeTransfer(_recipient, currencyAmount - fee);
    }
}
