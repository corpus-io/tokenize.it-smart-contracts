// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.23;

import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import "./Distribution.sol";
import "./Exit.sol";
import "./GlobalTokenExitRegistry.sol";
import "./PrivateOffer.sol";
import "./common/TokenSwapBase.sol";
import "./factories/PrivateOfferFactory.sol";

struct LeadInvestor {
    /// lead investor address that receives carry
    address account;
    /// carry percentage, divided by uint64.max
    uint64 carryFraction;
}

struct CoinvestedPositionInitializerArguments {
    /// Owner of the contract
    address owner;
    /// coinvestor address: receives base price payout and carry dust
    address receiver;
    /// lead investors and their carry fractions
    LeadInvestor[] leadInvestors;
    /// base price per token in bits of baseCurrency
    uint256 basePrice;
    /// currency used for buy() payments. Must have TRUSTED_CURRENCY bit set on the token's allowList.
    IERC20 baseCurrency;
    /// token being held
    Token token;
    /// unix timestamp before which unpause() is blocked; 0 means no lock
    uint64 lockedUntil;
    /// registry contract; if an exit is set for the token, it can be claimed
    GlobalTokenExitRegistry tokenExitRegistry;
}

struct OneTimeSyndicateFeeArguments {
    /// factory used to deploy the PrivateOffer
    PrivateOfferFactory privateOfferFactory;
    /// salt passed to the PrivateOfferFactory for deterministic address derivation
    bytes32 privateOfferSalt;
    /// arguments for the PrivateOffer; currencyPayer and tokenReceiver are overridden to address(this)
    PrivateOfferArguments privateOfferArguments;
    /// one-time fee as a fraction of the investment amount, divided by type(uint64).max; 0 means no fee
    uint64 oneTimeFee;
}

/**
 * @title CoinvestedPosition
 * @author malteish, cjentzsch
 * @notice This contract holds tokens and sells them at a preset price, distributing proceeds
 *      between a coinvestor (receiver) and lead investors.
 *      The coinvestor (receiver) receives basePrice per token sold.
 *      Any remaining proceeds after fees and coinvestor payout are split between coinvestor and
 *      lead investors according to their carry percentages.
 *      If the sale price minus fees is less than the base price, all proceeds go to the coinvestor.
 *      Any trusted currency may be used for exits and dividends; when a currency different from the stored
 *      currency is used, the coinvestor provides an altBasePrice expressing the base price in that
 *      currency's units.
 */
contract CoinvestedPosition is TokenSwapBase {
    using SafeERC20 for IERC20;

    /// lead investors and their carry fractions
    LeadInvestor[] public leadInvestors;
    /// base price per token in bits of the current currency (always expressed in current currency's decimals)
    uint256 public basePrice;
    /// unix timestamp before which unpause() is blocked; 0 means no lock
    uint64 public lockedUntil;
    /// registry contract; if an exit is set for the token, an exit reward can be claimed from that
    /// address even if lockedUntil has not passed yet
    GlobalTokenExitRegistry public tokenExitRegistry;

    /// @notice Emitted when the one-time syndicate fee is charged during initializeWithPrivateOffer.
    event OneTimeSyndicateFeeCharged(uint256 feeAmount);

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
        _initializeCoinvestedPosition(_arguments);
    }

    /**
     * @notice Sets up the CoinvestedPosition and immediately executes a PrivateOffer investment in one transaction.
     *      The receiver must have pre-approved this contract's address for investmentAmount + oneTimeFeeAmount
     *      of baseCurrency before this is called. The token issuer must have pre-approved the PrivateOffer address
     *      (returned by predictCoinvestedPositionAndPrivateOfferAddress) for minting or transfer.
     *      currencyPayer and tokenReceiver in _feeArguments.privateOfferArguments are overridden to address(this).
     * @param _baseArguments Struct containing all base initialization parameters
     * @param _feeArguments Struct containing PrivateOffer parameters and the one-time syndicate fee fraction
     */
    function initializeWithPrivateOffer(
        CoinvestedPositionInitializerArguments memory _baseArguments,
        OneTimeSyndicateFeeArguments memory _feeArguments
    ) external initializer {
        _initializeCoinvestedPosition(_baseArguments);

        require(
            _feeArguments.privateOfferArguments.currency == _baseArguments.baseCurrency,
            "privateOffer currency must match baseCurrency"
        );
        require(
            address(_feeArguments.privateOfferArguments.token) == address(_baseArguments.token),
            "privateOffer token must match token"
        );

        uint256 investmentAmount = Math.ceilDiv(
            _feeArguments.privateOfferArguments.tokenAmount * _feeArguments.privateOfferArguments.tokenPrice,
            10 ** _baseArguments.token.decimals()
        );
        uint256 oneTimeFeeAmount = (uint256(_feeArguments.oneTimeFee) * investmentAmount) / type(uint64).max;

        // Override: this contract is both the currency payer and the token receiver
        _feeArguments.privateOfferArguments.currencyPayer = address(this);
        _feeArguments.privateOfferArguments.tokenReceiver = address(this);

        // Single pull from receiver covering investment and fee
        _baseArguments.baseCurrency.safeTransferFrom(receiver, address(this), investmentAmount + oneTimeFeeAmount);

        if (oneTimeFeeAmount != 0) {
            _distributeOneTimeSyndicateFee(oneTimeFeeAmount, _baseArguments.baseCurrency);
            emit OneTimeSyndicateFeeCharged(oneTimeFeeAmount);
        }

        // Approve the deterministic PrivateOffer address for exactly the investment amount
        address privateOfferAddress = _feeArguments.privateOfferFactory.predictPrivateOfferAddress(
            _feeArguments.privateOfferSalt,
            _feeArguments.privateOfferArguments
        );
        _baseArguments.baseCurrency.approve(privateOfferAddress, investmentAmount);

        // Deploy PrivateOffer: pulls investmentAmount from this contract, delivers tokens here
        _feeArguments.privateOfferFactory.deployPrivateOffer(
            _feeArguments.privateOfferSalt,
            _feeArguments.privateOfferArguments
        );

        require(
            _baseArguments.token.balanceOf(address(this)) == _feeArguments.privateOfferArguments.tokenAmount,
            "token delivery failed"
        );
    }

    /**
     * @notice Shared setup logic called by both initializers.
     */
    function _initializeCoinvestedPosition(CoinvestedPositionInitializerArguments memory _arguments) private {
        _initializeBase(_arguments.owner, 0, _arguments.baseCurrency, _arguments.token, _arguments.receiver);

        require(
            _arguments.token.allowList().map(address(_arguments.baseCurrency)) == TRUSTED_CURRENCY,
            "currency needs to be on the allowlist with TRUSTED_CURRENCY attribute"
        );
        require(_arguments.leadInvestors.length > 0, "There must be at least one lead investor");
        uint64 carryFractionsSum = 0;
        for (uint256 i = 0; i < _arguments.leadInvestors.length; i++) {
            require(_arguments.leadInvestors[i].account != address(0), "lead investor can not be zero address");
            require(_arguments.leadInvestors[i].carryFraction > 0, "lead investor carry fraction can not be zero");
            carryFractionsSum += _arguments.leadInvestors[i].carryFraction; // reverts on overflow, thus avoiding carryFractionsSum > 100%
            leadInvestors.push(_arguments.leadInvestors[i]);
        }
        require(address(_arguments.tokenExitRegistry) != address(0), "tokenExitRegistry can not be zero address");
        basePrice = _arguments.basePrice;
        lockedUntil = _arguments.lockedUntil;
        tokenExitRegistry = _arguments.tokenExitRegistry;

        // Pausing the contract prevents an immediate sell of the tokens. Once they should be sold, update price and unpause.
        _pause();
    }

    /**
     * @notice Distributes feeAmount of feeCurrency among lead investors proportionally by carryFraction.
     *      The full feeAmount is distributed; the last lead investor absorbs any rounding dust.
     * @param feeAmount total fee to distribute, in feeCurrency bits
     * @param feeCurrency the ERC20 token to distribute
     */
    function _distributeOneTimeSyndicateFee(uint256 feeAmount, IERC20 feeCurrency) private {
        uint256 carryFractionsSum = 0;
        for (uint256 i = 0; i < leadInvestors.length; i++) {
            carryFractionsSum += leadInvestors[i].carryFraction;
        }
        uint256 remainingFee = feeAmount;
        for (uint256 i = 0; i < leadInvestors.length - 1; i++) {
            uint256 share = (uint256(leadInvestors[i].carryFraction) * feeAmount) / carryFractionsSum;
            if (share != 0) {
                feeCurrency.safeTransfer(leadInvestors[i].account, share);
                remainingFee -= share;
            }
        }
        if (remainingFee != 0) {
            feeCurrency.safeTransfer(leadInvestors[leadInvestors.length - 1].account, remainingFee);
        }
    }

    /**
     * @notice Unpause the contract. Blocked until lockedUntil has passed.
     */
    function unpause() external override onlyOwner {
        require(tokenPrice != 0, "tokenPrice must be set before unpausing");
        require(block.timestamp >= lockedUntil, "timelock has not expired");
        _unpause();
    }

    /**
     * @notice Change the payment currency and update basePrice to match the new currency's units.
     * @param _currency new currency; must have TRUSTED_CURRENCY bit set on the token's allowList
     * @param _basePrice base price expressed in the new currency's units; must be > 0
     */
    function setCurrency(IERC20 _currency, uint256 _basePrice) external onlyOwner {
        require(block.timestamp >= lockedUntil, "timelock has not expired");
        require(address(_currency) != address(0), "zero address");
        require(address(_currency) != address(token), "currency cannot be the held token");
        require(_basePrice > 0, "altBasePrice must be > 0");
        require(
            token.allowList().map(address(_currency)) == TRUSTED_CURRENCY,
            "currency needs to be on the allowlist with TRUSTED_CURRENCY attribute"
        );
        basePrice = _basePrice;
        currency = _currency;
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
    ) public whenNotPaused nonReentrant {
        // rounding up to the next whole number. Buyer is charged up to one currency bit more in case of a fractional currency bit.
        uint256 currencyAmount = Math.ceilDiv(_tokenAmount * tokenPrice, 10 ** token.decimals());

        require(currencyAmount <= _maxCurrencyAmount, "Purchase more expensive than _maxCurrencyAmount");

        // pull full amount to this contract first, then distribute from here
        currency.safeTransferFrom(_msgSender(), address(this), currencyAmount);

        // collect fee
        (uint256 fee, address feeCollector) = _getFeeAndFeeReceiver(currencyAmount);
        if (fee != 0) {
            currency.safeTransfer(feeCollector, fee);
        }

        uint256 remaining = currencyAmount - fee;

        // calculate carry: surplus above base price. If remaining <= base price, carry is 0 and receiver gets everything.
        uint256 payoutCoinvestor = (basePrice * _tokenAmount) / (10 ** token.decimals());
        uint256 carry = payoutCoinvestor < remaining ? remaining - payoutCoinvestor : 0;

        _settle(carry, currency);

        // transfer tokens from this contract to the buyer's receiver
        token.transfer(_tokenReceiver, _tokenAmount);

        emit TokensBought(_msgSender(), _tokenAmount, currencyAmount);
    }

    /**
     * @notice Distributes `carry` among lead investors by carryFraction, then sweeps the contract's
     *      full remaining balance of `_currency` to receiver. This even includes currency accidentally
     *      sent to the contract.
     * @dev The sweep covers the base price portion and any rounding dust. Pass carry=0 when there is
     *      no surplus above base price; the loop produces no transfers and the full balance goes to receiver.
     * @param carry surplus above base price to split among lead investors
     * @param _currency the ERC20 token to use as currency for the settlement
     */
    function _settle(uint256 carry, IERC20 _currency) internal {
        require(address(_currency) != address(token), "currency cannot be the held token");
        for (uint256 i = 0; i < leadInvestors.length; i++) {
            uint256 share = (uint256(leadInvestors[i].carryFraction) * carry) / type(uint64).max;
            if (share != 0) {
                _currency.safeTransfer(leadInvestors[i].account, share);
            }
        }
        _currency.safeTransfer(receiver, _currency.balanceOf(address(this)));
    }

    /**
     * @notice Claim this contract's eligible dividend share from `_dist` and split it among lead investors.
     * @dev The full received amount is treated as carry and split among lead investors by carryFraction;
     *      remainder goes to receiver. Any trusted currency may be used.
     * @param _dist the Distribution (dividend) contract to claim from
     * @param _minPayout minimum currency the call must receive; passed through to the distribution
     */
    function claimDistribution(Distribution _dist, uint256 _minPayout) external onlyOwner nonReentrant {
        IERC20 dividendCurrency = _dist.currency();
        require(
            token.allowList().map(address(dividendCurrency)) == TRUSTED_CURRENCY,
            "dividend currency must be a trusted currency"
        );
        uint256 before = dividendCurrency.balanceOf(address(this));
        _dist.claim(address(this), _minPayout);
        uint256 received = dividendCurrency.balanceOf(address(this)) - before;
        _settle(received, dividendCurrency);
    }

    /**
     * @notice Claim exit proceeds for this contract's full token balance and split them among the receiver and lead investors.
     * @dev Requires tokenExitRegistry.exit() to be set; that also acts as the unlock signal.
     *      If proceeds < base, receiver gets everything.
     *      Carry is split among lead investors by carryFraction; remainder goes to receiver.
     *      Any currency may be used. When the exit currency differs from the stored currency, provide
     *      _basePrice expressing the base price in the exit currency's units.
     * @param _minCurrencyAmount minimum currency the call must receive; passed through to the exit contract.
     * @param _basePrice base price in exit currency's units; ignored when exit currency matches stored currency
     */
    function claimExit(uint256 _minCurrencyAmount, uint256 _basePrice) external onlyOwner nonReentrant {
        Exit _exit = tokenExitRegistry.exits(token);
        require(address(_exit) != address(0), "no exit set in tokenExitRegistry");
        uint256 tokenBalance = token.balanceOf(address(this));
        require(tokenBalance > 0, "no tokens to claim");

        IERC20 exitCurrency = _exit.currency();
        uint256 effectiveBasePrice;
        if (exitCurrency == currency) {
            effectiveBasePrice = basePrice;
        } else {
            uint256 rate = _exit.referenceToExitRate(currency);
            if (rate > 0) {
                effectiveBasePrice = (basePrice * rate) / 10 ** IERC20Metadata(address(currency)).decimals();
            } else {
                require(_basePrice > 0, "altBasePrice must be > 0");
                effectiveBasePrice = _basePrice;
            }
        }

        uint256 basePayout = (effectiveBasePrice * tokenBalance) / 10 ** token.decimals();

        IERC20(address(token)).approve(address(_exit), tokenBalance);
        uint256 before = exitCurrency.balanceOf(address(this));
        _exit.claim(address(this), _minCurrencyAmount);
        uint256 received = exitCurrency.balanceOf(address(this)) - before;
        uint256 carry = basePayout < received ? received - basePayout : 0;
        _settle(carry, exitCurrency);
    }

    /**
     * @notice Returns the number of lead investors.
     * @return length of the leadInvestors array
     */
    function getLeadInvestorsCount() external view returns (uint256) {
        return leadInvestors.length;
    }
}
