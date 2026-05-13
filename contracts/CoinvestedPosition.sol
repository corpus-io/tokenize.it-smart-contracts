// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import "./Distribution.sol";
import "./Exit.sol";
import "./GlobalTokenExitRegistry.sol";
import "./common/TokenSwapBase.sol";

struct LeadInvestor {
    /// lead investor address that receives carry
    address account;
    /// profit fraction this lead investor receives, divided by uint64.max
    uint64 profitFraction;
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
    /// unix timestamp before which unpause() is blocked; must be non-zero
    uint64 lockedUntil;
    /// registry contract; if an exit is set for the token, it can be claimed
    GlobalTokenExitRegistry tokenExitRegistry;
}

/**
 * @title CoinvestedPosition
 * @author malteish, cjentzsch
 * @notice This contract holds tokens and sells them at a preset price, distributing proceeds
 *      between the coinvestor (owner) and lead investors.
 *      The coinvestor receives basePrice per token sold.
 *      Any remaining proceeds after fees and coinvestor payout are the profit. Each lead investor
 *      receives their carry (profitFraction); the remainder goes to the coinvestor.
 *      If the sale price minus fees is less than the base price, all proceeds go to the coinvestor.
 *      Any trusted currency may be used for exits and dividends; when a currency different from the stored
 *      currency is used, the coinvestor provides an altBasePrice expressing the base price in that
 *      currency's units.
 * @dev Payouts are pull-based. Each lead investor calls `withdrawAsLeadInvestor` for their slot.
 *      The owner (coinvestor) calls `withdrawAsCoinvestor` with an explicit destination address.
 *      Any accidentally-sent currency (balance above `totalCredit`) is swept to the
 *      coinvestor at withdrawal time.
 */
contract CoinvestedPosition is TokenSwapBase {
    using SafeERC20 for IERC20;

    error ZeroLeadInvestorAddress();
    error ZeroLeadInvestorProfitFraction();
    error NotLeadInvestor();
    error ZeroLockedUntil();

    event CurrencyChanged(address indexed currency, uint256 basePrice);
    event DistributionClaimed(address indexed distribution, address indexed currency, uint256 amount);
    event ExitClaimed(address indexed exit, address indexed currency, uint256 received);

    /// lead investors and their carry fractions
    LeadInvestor[] public leadInvestors;
    /// base price per token in bits of the current currency (always expressed in current currency's decimals)
    uint256 public basePrice;
    /// unix timestamp before which unpause() is blocked; must be non-zero
    uint64 public lockedUntil;
    /// registry contract; if an exit is set for the token, an exit reward can be claimed from that
    /// address even if lockedUntil has not passed yet
    GlobalTokenExitRegistry public tokenExitRegistry;

    /// Pending pull-payout for a lead investor, keyed by their array index and currency.
    /// @dev Index-keyed (not address-keyed) so rotating an investor's address via
    ///      setLeadInvestorAccount automatically redirects pending credit to the new address.
    mapping(uint256 => mapping(IERC20 => uint256)) public leadInvestorCredit;
    /// Pending pull-payout for the coinvestor (owner), keyed by currency.
    mapping(IERC20 => uint256) public coinvestorCredit;
    /// Sum of `coinvestorCredit[c] + Σ leadInvestorCredit[i][c]`. The contract's actual balance
    /// of currency `c` may exceed this (accidentally-sent currency is "untracked"); the difference
    /// is swept into the coinvestor share when `withdrawAsCoinvestor` is called.
    mapping(IERC20 => uint256) public totalCredit;

    /// @notice A lead investor's carry was credited to their pull-payout balance.
    event LeadInvestorCredited(uint256 indexed index, IERC20 indexed currency, uint256 amount);
    /// @notice The coinvestor's share was credited to their pull-payout balance.
    event CoinvestorCredited(IERC20 indexed currency, uint256 amount);
    /// @notice A lead investor withdrew their pending credit.
    event LeadInvestorWithdrawn(uint256 indexed index, IERC20 indexed currency, uint256 amount);
    /// @notice The coinvestor withdrew their pending credit to `to` (credit portion only).
    event CoinvestorWithdrawn(IERC20 indexed currency, address indexed to, uint256 amount);
    /// @notice Untracked balance (currency on the contract above `totalCredit`) was swept to the
    ///         coinvestor `to` during a coinvestor withdrawal. Emitted only when the surplus is non-zero,
    ///         so credit-side numbers stay clean for consumers that sum {CoinvestorCredited} amounts.
    event CoinvestorSwept(IERC20 indexed currency, address indexed to, uint256 amount);
    /// @notice A lead investor rotated their own address.
    event LeadInvestorAccountChanged(uint256 indexed index, address indexed oldAccount, address indexed newAccount);

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
        uint64 profitFractionsSum = 0;
        for (uint256 i = 0; i < _arguments.leadInvestors.length; i++) {
            require(_arguments.leadInvestors[i].account != address(0), ZeroLeadInvestorAddress());
            require(_arguments.leadInvestors[i].profitFraction > 0, ZeroLeadInvestorProfitFraction());
            profitFractionsSum += _arguments.leadInvestors[i].profitFraction; // reverts on overflow, thus avoiding profitFractionsSum > 100%
            leadInvestors.push(_arguments.leadInvestors[i]);
        }
        require(address(_arguments.tokenExitRegistry) != address(0), ZeroTokenExitRegistryAddress());
        require(_arguments.lockedUntil > 0, ZeroLockedUntil());
        require(_arguments.basePrice > 0, ZeroPrice());
        basePrice = _arguments.basePrice;
        lockedUntil = _arguments.lockedUntil;
        tokenExitRegistry = _arguments.tokenExitRegistry;

        // Pausing the contract prevents an immediate sell of the tokens. Once they should be sold, update price and unpause.
        _pause();
    }

    /**
     * @notice Unpause the contract. Blocked until lockedUntil has passed.
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
        emit CurrencyChanged(address(_currency), _basePrice);
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

        uint256 payoutCoinvestor = (basePrice * _tokenAmount) / (10 ** token.decimals());
        _credit(remaining, payoutCoinvestor, currency);

        // transfer tokens from this contract to the buyer's receiver
        IERC20(address(token)).safeTransfer(_tokenReceiver, _tokenAmount);

        emit TokensBought(_msgSender(), _tokenAmount, currencyAmount);
    }

    /**
     * @notice Splits `gross` between lead investors (their carry of profit) and the coinvestor
     *      (base portion + remainder of profit). Funds are credited to pull-payout balances rather
     *      than transferred — so a single bad recipient cannot block the calling flow.
     * @dev `profit = max(gross - basePortion, 0)`. Each lead investor receives `profitFraction × profit`.
     *      The coinvestor receives everything else (`gross - Σ carries`), which is the dominant share
     *      whenever lead investors collectively hold a small profit fraction. Accidentally-sent currency
     *      (balance above `totalCredit`) is left untracked here and swept into the coinvestor share at
     *      withdrawAsCoinvestor time.
     * @param gross total amount of `_currency` to distribute (must already be on the contract)
     * @param basePortion coinvestor's base-price share before carry; 0 for dividends
     * @param _currency the ERC20 currency to credit
     */
    function _credit(uint256 gross, uint256 basePortion, IERC20 _currency) internal {
        require(address(_currency) != address(token), CurrencyEqualsToken());
        uint256 profit = gross > basePortion ? gross - basePortion : 0;
        uint256 totalCarry;
        uint256 leadInvestorsLength = leadInvestors.length;
        for (uint256 i = 0; i < leadInvestorsLength; i++) {
            uint256 carry = (uint256(leadInvestors[i].profitFraction) * profit) / type(uint64).max;
            if (carry != 0) {
                leadInvestorCredit[i][_currency] += carry;
                totalCarry += carry;
                emit LeadInvestorCredited(i, _currency, carry);
            }
        }
        uint256 coinvestorShare = gross - totalCarry;
        if (coinvestorShare != 0) {
            coinvestorCredit[_currency] += coinvestorShare;
            emit CoinvestorCredited(_currency, coinvestorShare);
        }
        totalCredit[_currency] += gross;
    }

    /**
     * @notice Claim this contract's eligible dividend share from `_dist` and split it among lead investors.
     * @dev The full received amount is treated as profit. Each lead investor receives their carry (profitFraction
     *      of profit); remainder goes to receiver. Any trusted currency may be used.
     * @param _dist the Distribution (dividend) contract to claim from
     * @param _minPayout minimum currency the call must receive; passed through to the distribution
     */
    function claimDistribution(Distribution _dist, uint256 _minPayout) external onlyOwner nonReentrant {
        IERC20 dividendCurrency = _dist.currency();
        require(token.allowList().map(address(dividendCurrency)) == TRUSTED_CURRENCY, UntrustedCurrency());
        uint256 before = dividendCurrency.balanceOf(address(this));
        _dist.claim(address(this), _minPayout);
        uint256 received = dividendCurrency.balanceOf(address(this)) - before;
        // basePortion = 0: dividends have no base portion; all of `received` is carry-eligible.
        _credit(received, 0, dividendCurrency);
        emit DistributionClaimed(address(_dist), address(dividendCurrency), received);
    }

    /**
     * @notice Claim exit proceeds for this contract's full token balance and split them among the receiver and lead investors.
     * @dev Requires tokenExitRegistry.exit() to be set; that also acts as the unlock signal.
     *      If proceeds < base, receiver gets everything.
     *      Profit (proceeds minus base price payout) is split: each lead investor receives their carry
     *      (profitFraction of profit); remainder goes to receiver.
     *      Any currency may be used. When the exit currency differs from the stored currency, provide
     *      _basePrice expressing the base price in the exit currency's units.
     * @param _minCurrencyAmount minimum currency the call must receive; passed through to the exit contract.
     * @param _basePrice base price in exit currency's units; ignored when exit currency matches stored currency
     */
    function claimExit(uint256 _minCurrencyAmount, uint256 _basePrice) external onlyOwner nonReentrant {
        Exit _exit = tokenExitRegistry.exits(token);
        require(address(_exit) != address(0), NoExitSet());
        uint256 tokenBalance = token.balanceOf(address(this));
        require(tokenBalance > 0, ZeroAmount());

        IERC20 exitCurrency = _exit.currency();
        uint256 effectiveBasePrice;
        if (address(exitCurrency) == address(currency)) {
            effectiveBasePrice = basePrice;
        } else {
            uint256 rate = _exit.referenceToExitRate(currency);
            if (rate > 0) {
                effectiveBasePrice = (basePrice * rate) / 10 ** IERC20Metadata(address(currency)).decimals();
            } else {
                require(_basePrice > 0, ZeroPrice());
                effectiveBasePrice = _basePrice;
            }
        }

        uint256 basePayout = (effectiveBasePrice * tokenBalance) / 10 ** token.decimals();

        IERC20(address(token)).approve(address(_exit), tokenBalance);
        uint256 before = exitCurrency.balanceOf(address(this));
        _exit.claim(address(this), _minCurrencyAmount);
        uint256 received = exitCurrency.balanceOf(address(this)) - before;
        _credit(received, basePayout, exitCurrency);
        emit ExitClaimed(address(_exit), address(exitCurrency), received);
    }

    /**
     * @notice Rotate the address that controls a given lead-investor slot. Callable only by
     *      the current account at that slot — typically used for blacklist recovery (a
     *      blacklisted address is still able to sign this transaction, since blacklisting
     *      is enforced inside the currency contract, not at the EVM level).
     * @dev Index-keyed pull credit means any pending balances automatically follow the new
     *      address; no migration step is needed.
     * @param index lead investor index in the `leadInvestors` array
     * @param newAccount new address for this slot; must be non-zero
     */
    function setLeadInvestorAccount(uint256 index, address newAccount) external {
        require(newAccount != address(0), ZeroLeadInvestorAddress());
        address oldAccount = leadInvestors[index].account;
        require(_msgSender() == oldAccount, NotLeadInvestor());
        leadInvestors[index].account = newAccount;
        emit LeadInvestorAccountChanged(index, oldAccount, newAccount);
    }

    /**
     * @notice Withdraw a lead investor's accumulated credit in `_currency` to their account.
     * @param index lead investor index
     * @param _currency currency to withdraw
     */
    function withdrawAsLeadInvestor(uint256 index, IERC20 _currency) external nonReentrant {
        address account = leadInvestors[index].account;
        require(_msgSender() == account, NotLeadInvestor());
        uint256 amount = leadInvestorCredit[index][_currency];
        require(amount != 0, ZeroAmount());
        leadInvestorCredit[index][_currency] = 0;
        totalCredit[_currency] -= amount;
        _currency.safeTransfer(account, amount);
        emit LeadInvestorWithdrawn(index, _currency, amount);
    }

    /**
     * @notice Withdraw the coinvestor's accumulated credit in `_currency` to `to`. Also sweeps
     *      any "untracked" balance of `_currency` (e.g. accidentally-transferred funds) into the
     *      same withdrawal — preserving the original "settle sweeps the contract balance" semantics.
     * @dev The coinvestor is the contract owner; the destination is chosen at withdraw time
     *      so the owner can route around currency-level blacklists on any single address.
     * @param _currency currency to withdraw
     * @param to destination address; must be non-zero
     */
    function withdrawAsCoinvestor(IERC20 _currency, address to) external onlyOwner nonReentrant {
        require(to != address(0), ZeroReceiverAddress());
        require(address(_currency) != address(token), CurrencyEqualsToken());
        uint256 owed = coinvestorCredit[_currency];
        uint256 untracked = _currency.balanceOf(address(this)) - totalCredit[_currency];
        uint256 amount = owed + untracked;
        require(amount != 0, ZeroAmount());
        coinvestorCredit[_currency] = 0;
        totalCredit[_currency] -= owed; // untracked was never in totalCredit
        _currency.safeTransfer(to, amount);
        // Emit credit and surplus separately so consumers can reconcile {CoinvestorCredited}
        // numbers against {CoinvestorWithdrawn} without surplus dust polluting the math.
        if (owed != 0) emit CoinvestorWithdrawn(_currency, to, owed);
        if (untracked != 0) emit CoinvestorSwept(_currency, to, untracked);
    }

    /**
     * @notice Returns the number of lead investors.
     * @return length of the leadInvestors array
     */
    function getLeadInvestorsCount() external view returns (uint256) {
        return leadInvestors.length;
    }
}
