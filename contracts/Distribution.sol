// SPDX-License-Identifier: MIT

pragma solidity 0.8.23;

import "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/metatx/ERC2771ContextUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "./Token.sol";
import "./common/IFeeSettings.sol";

struct Reassignment {
    address from;
    address to;
    uint256 amount;
}

struct DistributionInitializerArguments {
    /// @notice Owner of the contract
    address owner;
    /// @notice Token whose snapshot determines distribution shares
    Token token;
    /// @notice Snapshot id that determines distribution shares
    uint256 snapshotId;
    /// @notice ERC20 token used for distribution payouts; must have TRUSTED_CURRENCY bit set on the token's allowList
    IERC20 currency;
    /// @notice Currency amount (in smallest currency units) per 10**token.decimals() token units
    uint256 pricePerToken;
    /// @notice Earliest timestamp at which the owner can reassign unclaimed funds or drain the contract
    uint64 reassignOrDrainAfter;
    /// @notice Reassignments to apply immediately at initialization, bypassing the time restriction
    Reassignment[] initialReassignments;
}

/**
 * @title tokenize.it Distribution
 * @author malteish, cjentzsch
 * @notice This contract implements the distribution of any proceeds (e.g. Dividends)
 *      based on a snapshot of Token.sol
 */
contract Distribution is ERC2771ContextUpgradeable, Ownable2StepUpgradeable, ReentrancyGuardUpgradeable {
    using SafeERC20 for IERC20;

    Token public token;
    uint256 public snapshotId;
    IERC20 public currency;
    /// @notice Currency amount (in smallest currency units) per 10**token.decimals() token units
    uint256 public pricePerToken;
    mapping(address => uint256) public paidOut;
    /// @notice Extra currency credit assigned to an address via reassign(), analogous to token reissuance after key loss
    mapping(address => uint256) public extraCredit;
    uint64 public reassignOrDrainAfter;

    /// @notice Emitted when the owner reassigns unclaimed distribution funds from one address to another
    event Reassigned(address indexed from, address indexed to, uint256 amount);

    /**
     * This constructor creates a logic contract that is used to clone new distribution contracts.
     * It has no owner, and can not be used directly.
     * @param _trustedForwarder This address can execute transactions in the name of any other address
     */
    constructor(address _trustedForwarder) ERC2771ContextUpgradeable(_trustedForwarder) {
        _disableInitializers();
    }

    /**
     * @notice Initializes the distribution contract with the given parameters and optionally funds it.
     * @param _arguments Struct containing all initialization parameters
     * @param _currencyProvider Address from which the initial funding amount is transferred
     * @param _initialFundingAmount Amount of currency to transfer from _currencyProvider; may be zero
     */
    function initialize(
        DistributionInitializerArguments memory _arguments,
        address _currencyProvider,
        uint256 _initialFundingAmount
    ) external initializer {
        require(_arguments.pricePerToken > 0, "price must be positive");
        __ReentrancyGuard_init();
        __Ownable2Step_init();
        _transferOwnership(_arguments.owner);
        token = _arguments.token;
        snapshotId = _arguments.snapshotId;
        // totalSupply 0 would make every claim revert
        require(token.totalSupplyAt(snapshotId) > 0, "snapshot has no tokens");
        currency = _arguments.currency;
        require(address(_arguments.currency) != address(_arguments.token), "currency and token must be different");
        require(
            token.allowList().map(address(_arguments.currency)) == TRUSTED_CURRENCY,
            "currency needs to be on the allowlist with TRUSTED_CURRENCY attribute"
        );
        pricePerToken = _arguments.pricePerToken;
        reassignOrDrainAfter = _arguments.reassignOrDrainAfter;
        if (_initialFundingAmount > 0) {
            _arguments.currency.safeTransferFrom(_currencyProvider, address(this), _initialFundingAmount);
        }
        for (uint256 i = 0; i < _arguments.initialReassignments.length; i++) {
            Reassignment memory reassignment = _arguments.initialReassignments[i];
            _reassign(reassignment.from, reassignment.to, reassignment.amount);
        }
    }

    /**
     * @notice Returns the gross eligible amount for a holder before fees, accounting for prior payouts
     *  and any extra credit assigned via reassign().
     * @param _holder Address of the token holder
     * @return Gross currency amount eligible for payout
     */
    function _grossEligible(address _holder) internal view returns (uint256) {
        return
            (token.balanceOfAt(_holder, snapshotId) * pricePerToken) /
            (10 ** token.decimals()) +
            extraCredit[_holder] -
            paidOut[_holder];
    }

    /**
     * @notice Returns the fee amount and fee collector address for the given amount.
     * @param _amount Amount to compute the fee on
     * @return fee Fee amount
     * @return feeCollector Address that receives the fee
     */
    function _feeInfo(uint256 _amount) internal view returns (uint256 fee, address feeCollector) {
        IFeeSettingsV3 feeSettings = IFeeSettingsV3(address(token.feeSettings()));
        if (feeSettings.supportsInterface(type(IFeeSettingsV3).interfaceId)) {
            fee = feeSettings.fee(FeeTypes.DISTRIBUTION, _amount, address(token));
            feeCollector = feeSettings.feeCollector(FeeTypes.DISTRIBUTION, address(token));
        }
        // if v3 is not supported, fee stays 0 and feeCollector stays address(0)
    }

    /**
     * @notice Returns the net currency payout a holder would receive if they claimed now.
     * @param _holder Address of the token holder
     * @return Net currency amount after fees
     */
    function eligible(address _holder) public view returns (uint256) {
        uint256 gross = _grossEligible(_holder);
        (uint256 fee, ) = _feeInfo(gross);
        return gross - fee;
    }

    /**
     * @notice Reassigns (unclaimed) distribution funds from one address to another. This is used to fix
     *  holders in the snapshot not being able to claim their funds. It can be audited because the
     *  reassignment is emitted on-chain. Some cases that could lead to this being needed:
     *      - holder losing their key and only noticing after the snapshot
     *      - a smart contract holder that cannot execute the claim for any reason, e.g. a Vesting contract
     * @dev onlyOwner, matching the requirements of calling Token.burn+mint to fix an issue with
     *  current token holders.
     * @param _from address that will receive less
     * @param _to address that will receive more
     * @param _amount amount of currency to reassign; must not exceed eligible(_from)
     */
    function reassign(address _from, address _to, uint256 _amount) external onlyOwner {
        require(block.timestamp >= reassignOrDrainAfter, "reassignment not yet available");
        _reassign(_from, _to, _amount);
    }

    /**
     * @dev Internal implementation of reassign(); does not check the time restriction.
     * @param _from Address whose gross eligibility is reduced
     * @param _to Address that receives extra credit
     * @param _amount Amount of currency to reassign
     */
    function _reassign(address _from, address _to, uint256 _amount) internal {
        require(_to != address(0), "to can not be zero address");
        require(_amount > 0, "amount must be positive");
        require(_amount <= _grossEligible(_from), "amount exceeds eligible");
        paidOut[_from] += _amount;
        extraCredit[_to] += _amount;
        emit Reassigned(_from, _to, _amount);
    }

    /**
     * @notice Claims the caller's full distribution share and sends it to _recipient.
     * @param _recipient Address that receives the currency payout
     * @param _minPayout Minimum net payout required; reverts if not met
     */
    function claim(address _recipient, uint256 _minPayout) external nonReentrant {
        uint256 gross = _grossEligible(_msgSender());
        require(gross > 0, "nothing to claim");
        paidOut[_msgSender()] += gross;
        (uint256 fee, address feeCollector) = _feeInfo(gross);
        uint256 net = gross - fee;
        require(net >= _minPayout, "payout below minimum");
        if (fee != 0) {
            currency.safeTransfer(feeCollector, fee);
        }
        currency.safeTransfer(_recipient, net);
    }

    /**
     * @notice Transfers the entire balance of _currency held by this contract to _recipient.
     *  Can only be called by the owner after reassignOrDrainAfter has passed.
     *  Intended to recover any erc20 tokens held by the contract.
     * @param _recipient Address that receives the token balance
     * @param _currency ERC20 token to recover
     */
    function drain(address _recipient, IERC20 _currency) external onlyOwner nonReentrant {
        require(block.timestamp >= reassignOrDrainAfter, "drain not yet available");
        _currency.safeTransfer(_recipient, _currency.balanceOf(address(this)));
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
