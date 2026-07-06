// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import "./Distribution.sol";
import "./Exit.sol";
import "./GlobalTokenExitRegistry.sol";
import "./common/TokenSwapBase.sol";

struct LeadInvestor {
    /// account authorized to pull this slot's carry (destination is chosen at withdraw time)
    address account;
    /// profit fraction this lead investor receives, divided by uint32.max
    uint32 profitFraction;
    /// Owner-recovery timer. 0 = disarmed (initial state, or after the lead investor
    /// proved liveness by pulling credit or self-rotating). Otherwise the unix timestamp
    /// of the most recent credit event for this lead investor: the owner may rotate this
    /// slot via ownerRotateLeadInvestorAccount once block.timestamp is at least
    /// `recoveryArmedAt + LEAD_INVESTOR_RECOVERY_TIMEOUT`. Initialized to 0.
    uint64 recoveryArmedAt;
}

struct CoinvestedPositionInitializerArguments {
    /// Owner of the contract. Also the coinvestor — the owner pulls the coinvestor share
    /// via withdrawAsCoinvestor and provides a destination at withdraw time.
    address owner;
    /// lead investors and their carry fractions
    LeadInvestor[] leadInvestors;
    /// base price per token in bits of baseCurrency
    uint256 basePrice;
    /// currency used for buy() payments. Must have TRUSTED_CURRENCY bit set on the token's allowList.
    IERC20 baseCurrency;
    /// token being held
    Token token;
    /// Unix timestamp before which `unpause()` and `setCurrency()` are blocked. Unpausing is what
    /// enables the position to be sold via `buy()`, so this acts as a "no-selling-before" gate.
    /// The timelock is OPTIONAL — many deployments don't need one. Must be non-zero; we reject `0`
    /// so a deployer who forgot to set this field gets a loud revert instead of a silent "no lock".
    /// Pass `1` (or any past timestamp) to explicitly opt out — the gate
    /// `block.timestamp >= lockedUntil` is then already satisfied at deploy time.
    uint64 lockedUntil;
    /// registry contract; if an exit is set for the token, it can be claimed
    GlobalTokenExitRegistry tokenExitRegistry;
}

/**
 * @title CoinvestedPosition
 * @author malteish, cjentzsch
 * @notice This contract holds tokens and credits sale, dividend, and exit proceeds to the
 *      coinvestor (owner) and lead investors via pull-payouts.
 *      Profit = max(gross − base portion, 0), where gross is proceeds after fees and base portion
 *      is basePrice × tokens (0 for dividends). Each lead investor receives carry = profitFraction × profit;
 *      the coinvestor receives the rest (base portion + profit − Σ carries). When gross ≤ base portion,
 *      profit is 0 and the coinvestor receives everything.
 * @dev Payouts are pull-based. Each lead investor calls `withdrawAsLeadInvestor` for their slot.
 *      The owner (coinvestor) calls `withdrawAsCoinvestor` with an explicit destination address.
 */
contract CoinvestedPosition is TokenSwapBase {
    using SafeERC20 for IERC20;

    error ZeroLeadInvestorAddress();
    error ZeroLeadInvestorProfitFraction();
    error NotLeadInvestor();
    error ZeroLockedUntil();
    error LeadInvestorRecoveryLocked();

    /// @notice The payment currency, base price, and token price were updated to a new denomination.
    event CurrencyChanged(address indexed currency, uint256 basePrice, uint256 tokenPrice);
    /// @notice This contract claimed its share of a dividend distribution.
    event DistributionClaimed(address indexed distribution, address indexed currency, uint256 amount);
    /// @notice This contract claimed exit proceeds for its full token balance.
    event ExitClaimed(address indexed exit, address indexed currency, uint256 received);
    /// @notice A lead investor's carry was credited to their pull-payout balance.
    event LeadInvestorCredited(uint256 indexed index, IERC20 indexed currency, uint256 amount);
    /// @notice The coinvestor's share was credited to their pull-payout balance.
    event CoinvestorCredited(IERC20 indexed currency, uint256 amount);
    /// @notice A lead investor withdrew their pending credit. `receiver` is the chosen destination,
    ///         which may differ from the slot's current account (e.g. when routing around a
    ///         currency-level blacklist on the registered address).
    event LeadInvestorWithdrawn(
        uint256 indexed index,
        IERC20 indexed currency,
        address indexed receiver,
        uint256 amount
    );
    /// @notice The coinvestor withdrew their pending credit to `receiver`.
    event CoinvestorWithdrawn(IERC20 indexed currency, address indexed receiver, uint256 amount);
    /// @notice A lead investor rotated their own slot's account via rotateLeadInvestorAccount.
    event LeadInvestorAccountRotated(uint256 indexed index, address indexed oldAccount, address indexed newAccount);
    /// @notice The owner exercised the recovery path and rotated a lead investor slot's account
    ///         via ownerRotateLeadInvestorAccount. Distinct from LeadInvestorAccountRotated so
    ///         indexers can attribute the action to the owner rather than the lead investor.
    event LeadInvestorAccountRecovered(uint256 indexed index, address indexed oldAccount, address indexed newAccount);

    /// @notice Duration after the most recent unclaimed credit event for a given lead investor
    ///         after which the owner may rotate that slot via ownerRotateLeadInvestorAccount.
    ///         Designed to recover stranded carry when a lead investor has lost access to their keys.
    uint64 public constant LEAD_INVESTOR_RECOVERY_TIMEOUT = 90 days;

    /// lead investors, their carry fractions and recovery timers
    LeadInvestor[] public leadInvestors;
    /// base price per token in bits of the current currency (always expressed in current currency's decimals)
    uint256 public basePrice;
    /// Unix timestamp before which `unpause()` and `setCurrency()` are blocked. Unpausing is what
    /// enables the position to be sold via `buy()`, so this acts as a "no-selling-before" gate.
    /// The timelock is OPTIONAL — many deployments don't need one. Must be non-zero; we reject `0`
    /// so a deployer who forgot to set this field gets a loud revert instead of a silent "no lock".
    /// Pass `1` (or any past timestamp) to explicitly opt out — the gate is then satisfied at deploy time.
    uint64 public lockedUntil;
    /// registry mapping each token to its Exit contract (if any). When an Exit is registered,
    /// `claimExit` may be called even before `lockedUntil` — the company exit itself is the unlock signal.
    GlobalTokenExitRegistry public tokenExitRegistry;

    /// Pending pull-payout for a lead investor, keyed by their array index and currency.
    /// @dev Index-keyed (not address-keyed) so rotating an investor's address via
    ///      rotateLeadInvestorAccount automatically redirects pending credit to the new address.
    mapping(uint256 => mapping(IERC20 => uint256)) public leadInvestorCredit;
    /// Pending pull-payout for the coinvestor (owner), keyed by currency.
    mapping(IERC20 => uint256) public coinvestorCredit;

    /**
     * This constructor creates a logic contract that is used to clone new contracts.
     * It has no owner, and can not be used directly.
     * @param _trustedForwarder This address can execute transactions in the name of any other address
     */
    constructor(address _trustedForwarder) TokenSwapBase(_trustedForwarder) {
        _disableInitializers();
    }

    /**
     * @notice Sets up the CoinvestedPosition. The contract is usable immediately after being initialized.
     * @param _arguments Struct containing all arguments for the initializer
     */
    function initialize(CoinvestedPositionInitializerArguments memory _arguments) external initializer {
        _initializeBase(_arguments.owner, 0, _arguments.baseCurrency, _arguments.token);

        require(_arguments.leadInvestors.length > 0, NoLeadInvestors());
        uint32 profitFractionsSum = 0;
        for (uint256 i = 0; i < _arguments.leadInvestors.length; i++) {
            require(_arguments.leadInvestors[i].account != address(0), ZeroLeadInvestorAddress());
            require(_arguments.leadInvestors[i].profitFraction > 0, ZeroLeadInvestorProfitFraction());
            profitFractionsSum += _arguments.leadInvestors[i].profitFraction; // reverts on overflow, thus avoiding profitFractionsSum > 100%
            leadInvestors.push(
                LeadInvestor({
                    account: _arguments.leadInvestors[i].account,
                    profitFraction: _arguments.leadInvestors[i].profitFraction,
                    recoveryArmedAt: 0
                })
            );
        }
        require(address(_arguments.tokenExitRegistry) != address(0), ZeroTokenExitRegistryAddress());
        require(_arguments.lockedUntil > 0, ZeroLockedUntil());
        require(_arguments.basePrice > 0, ZeroPrice());
        basePrice = _arguments.basePrice;
        lockedUntil = _arguments.lockedUntil;
        tokenExitRegistry = _arguments.tokenExitRegistry;

        // Pausing the contract prevents an immediate sell of the tokens. Once ready to sell, set tokenPrice via setCurrency and unpause.
        _pause();
    }

    /**
     * @notice Unpause the contract, enabling `buy()` so the position can be sold. Blocked until
     *      `lockedUntil` has passed. When no timelock was configured (`lockedUntil` set to `1` or any
     *      past timestamp at init), this is callable immediately. Requires `tokenPrice != 0`, so
     *      `setCurrency` must be called at least once first — the initializer leaves `tokenPrice` at 0.
     */
    function unpause() external override onlyOwner {
        require(tokenPrice != 0, ZeroPrice());
        require(block.timestamp >= lockedUntil, TimeLockNotExpired());
        _unpause();
    }

    /**
     * @notice Change the payment currency and atomically update basePrice and tokenPrice to match the new currency's units.
     * @param _currency new currency; must have TRUSTED_CURRENCY bit set on the token's allowList
     * @param _basePrice base price expressed in the new currency's units; must be > 0
     * @param _tokenPrice new token price expressed in the new currency's bits per main-unit token; must be > 0
     */
    function setCurrency(IERC20 _currency, uint256 _basePrice, uint256 _tokenPrice) external onlyOwner {
        require(block.timestamp >= lockedUntil, TimeLockNotExpired());
        require(address(_currency) != address(0), ZeroCurrencyAddress());
        require(address(_currency) != address(token), CurrencyEqualsToken());
        require(_basePrice > 0, ZeroPrice());
        require(_tokenPrice > 0, ZeroPrice());
        require(token.allowList().map(address(_currency)) == TRUSTED_CURRENCY, UntrustedCurrency());
        basePrice = _basePrice;
        tokenPrice = _tokenPrice;
        currency = _currency;
        emit CurrencyChanged(address(_currency), _basePrice, _tokenPrice);
    }

    /**
     * @notice Buy `_tokenAmount` tokens and transfer them to `_tokenReceiver`.
     * @param _tokenAmount amount of tokens to buy, in bits (smallest subunit of token)
     * @param _maxCurrencyAmount maximum amount of currency to spend, in bits (smallest subunit of currency)
     * @param _tokenReceiver address the tokens should be transferred to
     */
    function buy(
        uint256 _tokenAmount,
        uint256 _maxCurrencyAmount,
        address _tokenReceiver
    ) external whenNotPaused nonReentrant {
        // rounding up to the next whole number. Buyer is charged up to one currency bit more in case of a fractional currency bit.
        uint256 currencyAmount = Math.ceilDiv(_tokenAmount * tokenPrice, 10 ** token.decimals());

        require(currencyAmount <= _maxCurrencyAmount, PurchaseTooExpensive());

        // pull full amount to this contract first, then distribute from here
        currency.safeTransferFrom(_msgSender(), address(this), currencyAmount);

        // collect fee
        (uint256 fee, address feeCollector) = _getFeeAndFeeReceiver(currencyAmount);
        if (fee != 0) {
            currency.safeTransfer(feeCollector, fee);
        }

        uint256 remaining = currencyAmount - fee;

        uint256 basePortion = (basePrice * _tokenAmount) / (10 ** token.decimals());
        _credit(remaining, basePortion, currency);

        // transfer tokens to _tokenReceiver
        IERC20(address(token)).safeTransfer(_tokenReceiver, _tokenAmount);

        emit TokensBought(_msgSender(), _tokenAmount, currencyAmount);
    }

    /**
     * @notice Splits `gross` between lead investors (their carry of profit) and the coinvestor
     *      (base portion + remainder of profit). Funds are credited to pull-payout balances rather
     *      than transferred — so a single bad recipient cannot block the calling flow.
     * @dev `profit = max(gross - basePortion, 0)`. Each lead investor receives `profitFraction × profit`.
     *      The coinvestor receives everything else (`gross - Σ carries`), which is the dominant share
     *      in most cases.
     * @param gross total amount of `_currency` to distribute (must already be on the contract)
     * @param basePortion threshold below which all of `gross` goes to the coinvestor; 0 for dividends
     * @param _currency the ERC20 currency to credit
     */
    function _credit(uint256 gross, uint256 basePortion, IERC20 _currency) internal {
        require(address(_currency) != address(token), CurrencyEqualsToken());
        uint256 profit = gross > basePortion ? gross - basePortion : 0;
        uint256 totalCarry;
        uint256 leadInvestorsLength = leadInvestors.length;
        for (uint256 i = 0; i < leadInvestorsLength; i++) {
            uint256 carry = (uint256(leadInvestors[i].profitFraction) * profit) / type(uint32).max;
            if (carry != 0) {
                leadInvestorCredit[i][_currency] += carry;
                totalCarry += carry;
                // (Re-)arm the recovery timer for this lead investor; overwritten on every new credit
                // so protection always runs from the most recent credit event.
                leadInvestors[i].recoveryArmedAt = uint64(block.timestamp);
                emit LeadInvestorCredited(i, _currency, carry);
            }
        }
        uint256 coinvestorShare = gross - totalCarry;
        if (coinvestorShare != 0) {
            coinvestorCredit[_currency] += coinvestorShare;
            emit CoinvestorCredited(_currency, coinvestorShare);
        }
    }

    /**
     * @notice Claim this contract's eligible dividend share from `_distribution` and credit it to the coinvestor and lead investors.
     * @dev The full received amount is treated as profit. Each lead investor receives their carry (profitFraction
     *      of profit); remainder goes to the coinvestor. Any trusted currency may be used.
     * @param _distribution the Distribution (dividend) contract to claim from
     * @param _minPayout minimum currency the call must receive; passed through to the distribution
     */
    function claimDistribution(Distribution _distribution, uint256 _minPayout) external onlyOwner nonReentrant {
        IERC20 dividendCurrency = _distribution.currency();
        require(token.allowList().map(address(dividendCurrency)) == TRUSTED_CURRENCY, UntrustedCurrency());
        uint256 before = dividendCurrency.balanceOf(address(this));
        _distribution.claim(address(this), _minPayout);
        uint256 received = dividendCurrency.balanceOf(address(this)) - before;
        // basePortion = 0: dividends have no base portion; all of `received` is carry-eligible.
        _credit(received, 0, dividendCurrency);
        emit DistributionClaimed(address(_distribution), address(dividendCurrency), received);
    }

    /**
     * @notice Claim exit proceeds for this contract's full token balance and credit them to the coinvestor and lead investors.
     * @dev Requires tokenExitRegistry.exit() to be set; that also acts as the unlock signal.
     *      If proceeds < base portion, the coinvestor gets everything.
     *      Profit (proceeds minus base portion) is split: each lead investor receives their carry
     *      (profitFraction of profit); remainder goes to the coinvestor.
     *      Any currency the Exit contract uses is accepted — no TRUSTED_CURRENCY check here, since the Exit contract is itself authorized via `tokenExitRegistry`.
     *      When the exit currency differs from the stored currency, `_basePrice` may be needed; see below.
     * @param _minCurrencyAmount minimum currency the call must receive; passed through to the exit contract.
     * @param _basePrice base price in the exit currency's units. Only consulted when the exit currency
     *      differs from the stored currency AND the Exit contract reports no reference rate from the
     *      stored currency (`referenceToExitRate` returns 0); ignored otherwise.
     */
    function claimExit(uint256 _minCurrencyAmount, uint256 _basePrice) external onlyOwner nonReentrant {
        Exit _exit = tokenExitRegistry.exits(token);
        require(address(_exit) != address(0), NoExitSet());
        uint256 tokenBalance = token.balanceOf(address(this));
        require(tokenBalance > 0, ZeroAmount());

        IERC20 exitCurrency = _exit.currency();
        // Aggregate base value for the full balance, expressed in the stored currency's units.
        uint256 basePortion = (basePrice * tokenBalance) / 10 ** token.decimals();
        if (address(exitCurrency) != address(currency)) {
            // Converting basePrice instead of basePortion would introduce larger rounding errors.
            uint256 rate = _exit.referenceToExitRate(currency);
            if (rate > 0) {
                basePortion = (basePortion * rate) / 10 ** IERC20Metadata(address(currency)).decimals();
            } else {
                // No on-chain rate: the caller supplies the base price already in the exit currency's units.
                require(_basePrice > 0, ZeroPrice());
                basePortion = (_basePrice * tokenBalance) / 10 ** token.decimals();
            }
        }

        IERC20(address(token)).approve(address(_exit), tokenBalance);
        uint256 before = exitCurrency.balanceOf(address(this));
        _exit.claim(address(this), _minCurrencyAmount);
        uint256 received = exitCurrency.balanceOf(address(this)) - before;
        _credit(received, basePortion, exitCurrency);
        emit ExitClaimed(address(_exit), address(exitCurrency), received);
    }

    /**
     * @notice Rotate the address that controls a given lead-investor slot. Callable only by
     *      the current account at that slot.
     * @dev Index-keyed pull credit means any pending balances automatically follow the new
     *      address; no migration step is needed. Also disarms the owner-recovery timer:
     *      a rotation, even to the same address, proves the lead investor still holds their keys.
     * @param index lead investor index in the `leadInvestors` array
     * @param newAccount new address for this slot; must be non-zero
     */
    function rotateLeadInvestorAccount(uint256 index, address newAccount) external {
        require(newAccount != address(0), ZeroLeadInvestorAddress());
        LeadInvestor memory leadInvestor = leadInvestors[index];
        require(_msgSender() == leadInvestor.account, NotLeadInvestor());
        address oldAccount = leadInvestor.account;
        leadInvestor.account = newAccount;
        leadInvestor.recoveryArmedAt = 0;
        leadInvestors[index] = leadInvestor;
        emit LeadInvestorAccountRotated(index, oldAccount, newAccount);
    }

    /**
     * @notice Owner-driven recovery: rotate the address of a lead-investor slot whose holder has
     *      not pulled their credit within `LEAD_INVESTOR_RECOVERY_TIMEOUT` after the most recent
     *      credit event. Designed for the case where a lead investor has lost access to their keys.
     * @dev Only callable when `recoveryArmedAt != 0` (a credit accrued and has not yet been pulled or
     *      otherwise acknowledged) AND `block.timestamp >= recoveryArmedAt + LEAD_INVESTOR_RECOVERY_TIMEOUT`.
     *      Any liveness signal from the lead investor (`withdrawAsLeadInvestor` or
     *      `rotateLeadInvestorAccount`) disarms the timer, blocking this path. The new account starts
     *      disarmed — the owner cannot immediately re-rotate; another credit event plus the full
     *      timeout is required.
     *      Trust note: once the timeout has elapsed, the owner may rotate to any non-zero address
     *      (including their own). Lead investors must monitor `recoveryArmedAt` and disarm via
     *      withdrawal or self-rotation if they wish to keep their slot.
     * @param index lead investor slot to rotate
     * @param newAccount new address for the slot; must be non-zero
     */
    function ownerRotateLeadInvestorAccount(uint256 index, address newAccount) external onlyOwner {
        require(newAccount != address(0), ZeroLeadInvestorAddress());
        LeadInvestor memory leadInvestor = leadInvestors[index];
        require(leadInvestor.recoveryArmedAt != 0, LeadInvestorRecoveryLocked());
        require(
            block.timestamp >= uint256(leadInvestor.recoveryArmedAt) + LEAD_INVESTOR_RECOVERY_TIMEOUT,
            LeadInvestorRecoveryLocked()
        );
        address oldAccount = leadInvestor.account;
        leadInvestor.account = newAccount;
        leadInvestor.recoveryArmedAt = 0;
        leadInvestors[index] = leadInvestor;
        emit LeadInvestorAccountRecovered(index, oldAccount, newAccount);
    }

    /**
     * @notice Withdraw a lead investor's accumulated credit in `_currency` to `_receiver`.
     * @dev Only callable by the slot's current account. Disarms the owner-recovery timer.
     * @param index lead investor index
     * @param _currency currency to withdraw
     * @param _receiver destination address; must be non-zero
     */
    function withdrawAsLeadInvestor(uint256 index, IERC20 _currency, address _receiver) external nonReentrant {
        require(_receiver != address(0), ZeroReceiverAddress());
        require(_msgSender() == leadInvestors[index].account, NotLeadInvestor());
        uint256 amount = leadInvestorCredit[index][_currency];
        require(amount != 0, ZeroAmount());
        leadInvestorCredit[index][_currency] = 0;
        // a successful pull proves the lead investor holds keys; disarm the recovery timer.
        leadInvestors[index].recoveryArmedAt = 0;
        _currency.safeTransfer(_receiver, amount);
        emit LeadInvestorWithdrawn(index, _currency, _receiver, amount);
    }

    /**
     * @notice Withdraw the coinvestor's accumulated credit in `_currency` to `_receiver`.
     * @dev The coinvestor is the contract owner; the destination is chosen at withdraw time
     *      so the owner can route around currency-level blacklists on any single address.
     * @param _currency currency to withdraw
     * @param _receiver destination address; must be non-zero
     */
    function withdrawAsCoinvestor(IERC20 _currency, address _receiver) external onlyOwner nonReentrant {
        require(_receiver != address(0), ZeroReceiverAddress());
        require(address(_currency) != address(token), CurrencyEqualsToken());
        uint256 amount = coinvestorCredit[_currency];
        require(amount != 0, ZeroAmount());
        coinvestorCredit[_currency] = 0;
        _currency.safeTransfer(_receiver, amount);
        emit CoinvestorWithdrawn(_currency, _receiver, amount);
    }

    /**
     * @notice Returns the number of lead investors.
     * @return length of the leadInvestors array
     */
    function getLeadInvestorsCount() external view returns (uint256) {
        return leadInvestors.length;
    }
}
