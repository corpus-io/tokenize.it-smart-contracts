// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.23;

import "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/introspection/ERC165Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/metatx/ERC2771ContextUpgradeable.sol";

import "./common/IFeeSettings.sol";

/**
 * @title FeeSettings
 * @author malteish, cjentzsch
 * @notice The FeeSettings contract is used to manage fees paid to the tokenize.it platform.
 *      Fee types are registered dynamically, so new fee types can be added without a contract upgrade.
 */
contract FeeSettings is
    Ownable2StepUpgradeable,
    ERC165Upgradeable,
    ERC2771ContextUpgradeable,
    IFeeSettingsV1,
    IFeeSettingsV2,
    IFeeSettingsV3
{
    // -------------------------------------------------------------------------
    // Constants
    // -------------------------------------------------------------------------

    /// Denominator to calculate all fees
    uint32 public constant FEE_DENOMINATOR = 10000;

    // -------------------------------------------------------------------------
    // Structs
    // -------------------------------------------------------------------------

    /**
     * @notice Configuration for a registered fee type.
     * @param maxNumerator     Hard cap — fees above this are rejected.
     * @param defaultNumerator The default numerator used when no active custom fee applies.
     */
    struct FeeTypeConfig {
        uint32 maxNumerator;
        uint32 defaultNumerator;
    }

    /**
     * @notice Initialization data for a single fee type, used in initialize().
     * @param feeType          bytes32 identifier (e.g. FeeTypes.TOKEN)
     * @param maxNumerator     Hard cap for this fee type
     * @param defaultNumerator Initial default numerator; must be <= maxNumerator
     * @param defaultCollector Default fee collector address for this type
     */
    struct FeeTypeInit {
        bytes32 feeType;
        uint32 maxNumerator;
        uint32 defaultNumerator;
        address defaultCollector;
    }

    /**
     * @notice A pending custom discount for a specific token.
     * @param numerator    The discounted fee numerator.
     * @param validityDate Unix timestamp up to which the discount is valid.
     */
    struct CustomFee {
        uint32 numerator;
        uint64 validityDate;
    }

    /**
     * @notice A proposed change to a fee type's default numerator.
     * @param numerator      The proposed new default numerator.
     * @param activationDate Unix timestamp after which the change can be executed.
     */
    struct ProposedFeeChange {
        uint32 numerator;
        uint64 activationDate;
    }

    // -------------------------------------------------------------------------
    // Storage
    // -------------------------------------------------------------------------

    /// stores who is a manager. Managers can set custom fees and custom fee collectors for specific tokens.
    mapping(address => bool) public managers;

    /// registry of all fee types:  feeType => config
    mapping(bytes32 => FeeTypeConfig) public feeTypeConfigs;

    /// per-token custom discounts:  feeType => token => discount
    mapping(bytes32 => mapping(address => CustomFee)) public customFees;

    /// per-token custom collectors:  feeType => token => collector  (address(0) key = default collector for that type)
    mapping(bytes32 => mapping(address => address)) public collectors;

    /// pending default-fee changes:  feeType => proposal
    mapping(bytes32 => ProposedFeeChange) public proposedFeeChanges;

    // -------------------------------------------------------------------------
    // Events
    // -------------------------------------------------------------------------

    /// @notice A manager has been added
    event ManagerAdded(address indexed manager);

    /// @notice A manager has been removed
    event ManagerRemoved(address indexed manager);

    /// @notice A new fee type has been registered
    event FeeTypeRegistered(bytes32 indexed feeType, uint32 maxNumerator, uint32 defaultNumerator);

    /// @notice A default fee change has been proposed
    event FeeChangeProposed(bytes32 indexed feeType, uint32 numerator, uint64 activationDate);

    /// @notice A proposed default fee change has been executed
    event FeeChanged(bytes32 indexed feeType, uint32 numerator);

    /// @notice A custom fee discount has been set for a token
    event CustomFeeSet(bytes32 indexed feeType, address indexed token, uint32 numerator, uint64 validityDate);

    /// @notice A custom fee discount has been removed for a token
    event CustomFeeRemoved(bytes32 indexed feeType, address indexed token);

    /// @notice A new fee collector has been set (either for a specific token or as default)
    event FeeCollectorSet(bytes32 indexed feeType, address indexed token, address indexed collector);

    /// @notice A custom fee collector has been removed for a token (reverts to type default)
    event CustomFeeCollectorRemoved(bytes32 indexed feeType, address indexed token);

    // -------------------------------------------------------------------------
    // Constructor & initializer
    // -------------------------------------------------------------------------

    /**
     * This constructor deploys a logic contract with no owner, that can be used for cloning.
     * @param _trustedForwarder The trusted forwarder contract to use
     */
    constructor(address _trustedForwarder) ERC2771ContextUpgradeable(_trustedForwarder) {
        _disableInitializers();
    }

    /**
     * @notice Initializes a new FeeSettings clone with an arbitrary set of fee types.
     * @param _owner     Owner of this clone
     * @param _feeTypes  Array of fee type configurations to register on deployment
     */
    function initialize(address _owner, FeeTypeInit[] memory _feeTypes) external initializer {
        require(_owner != address(0), "owner can not be zero address");
        managers[_owner] = true;
        _transferOwnership(_owner);

        for (uint256 i = 0; i < _feeTypes.length; i++) {
            FeeTypeInit memory feeType = _feeTypes[i];
            _registerFeeType(feeType.feeType, feeType.maxNumerator, feeType.defaultNumerator, feeType.defaultCollector);
        }
    }

    // -------------------------------------------------------------------------
    // Manager management. Managers can set custom fees for specific tokens.
    // -------------------------------------------------------------------------

    /**
     * @notice Adds a manager
     * @param _manager The manager to add
     */
    function addManager(address _manager) external onlyOwner {
        managers[_manager] = true;
        emit ManagerAdded(_manager);
    }

    /**
     * @notice Removes a manager
     * @param _manager The manager to remove
     */
    function removeManager(address _manager) external onlyOwner {
        delete managers[_manager];
        emit ManagerRemoved(_manager);
    }

    // -------------------------------------------------------------------------
    // Fee type registry
    // -------------------------------------------------------------------------

    /**
     * @notice Registers a new fee type. Reverts if the fee type is already registered.
     * @param _feeType          bytes32 identifier (e.g. keccak256("MY_FEE"))
     * @param _maxNumerator     Hard cap enforced on all numerators for this type
     * @param _defaultNumerator Initial default numerator; must be <= _maxNumerator
     * @param _collector        Default fee collector address for this type
     */
    function registerFeeType(
        bytes32 _feeType,
        uint32 _maxNumerator,
        uint32 _defaultNumerator,
        address _collector
    ) external onlyOwner {
        _registerFeeType(_feeType, _maxNumerator, _defaultNumerator, _collector);
    }

    function _registerFeeType(
        bytes32 _feeType,
        uint32 _maxNumerator,
        uint32 _defaultNumerator,
        address _collector
    ) internal {
        require(_feeType != bytes32(0), "feeType cannot be 0");
        require(_maxNumerator > 0, "maxNumerator cannot be 0");
        require(_maxNumerator < FEE_DENOMINATOR, "maxNumerator too large");
        require(feeTypeConfigs[_feeType].maxNumerator == 0, "fee type already registered");
        require(_defaultNumerator <= _maxNumerator, "default exceeds max");
        require(_collector != address(0), "Fee collector cannot be 0x0");
        feeTypeConfigs[_feeType] = FeeTypeConfig({maxNumerator: _maxNumerator, defaultNumerator: _defaultNumerator});
        collectors[_feeType][address(0)] = _collector;
        emit FeeTypeRegistered(_feeType, _maxNumerator, _defaultNumerator);
    }

    // -------------------------------------------------------------------------
    // Default fee change (with 12-week delay on increases)
    // -------------------------------------------------------------------------

    /**
     * @notice Proposes a new default numerator for a fee type.
     *      If the numerator increases, the activation date must be at least 12 weeks in the future.
     * @param _feeType        The fee type to change
     * @param _numerator      The new default numerator
     * @param _activationDate Unix timestamp after which executeFeeChange can be called
     */
    function planFeeChange(bytes32 _feeType, uint32 _numerator, uint64 _activationDate) external onlyOwner {
        FeeTypeConfig storage config = feeTypeConfigs[_feeType];
        require(config.maxNumerator > 0, "unknown fee type");
        require(_numerator <= config.maxNumerator, "exceeds max numerator");
        if (_numerator > config.defaultNumerator) {
            require(_activationDate > block.timestamp + 12 weeks, "fee increase needs 12 week delay");
        }
        // activationDate=0 means "immediately" — store block.timestamp so executeFeeChange sentinel works
        if (_activationDate == 0) {
            _activationDate = uint64(block.timestamp);
        }
        proposedFeeChanges[_feeType] = ProposedFeeChange({numerator: _numerator, activationDate: _activationDate});
        emit FeeChangeProposed(_feeType, _numerator, _activationDate);
    }

    /**
     * @notice Executes a previously planned default fee change.
     * @param _feeType The fee type to update
     */
    function executeFeeChange(bytes32 _feeType) external onlyOwner {
        ProposedFeeChange memory proposal = proposedFeeChanges[_feeType];
        require(proposal.activationDate != 0, "no proposed fee change");
        require(block.timestamp >= proposal.activationDate, "activation date not reached");
        feeTypeConfigs[_feeType].defaultNumerator = proposal.numerator;
        delete proposedFeeChanges[_feeType];
        emit FeeChanged(_feeType, proposal.numerator);
    }

    // -------------------------------------------------------------------------
    // Custom fees (per-token discounts), manager-only
    // -------------------------------------------------------------------------

    /**
     * @notice Sets a custom fee discount for a specific token on a fee type.
     *      Custom fees can only reduce the effective fee (the min of custom and default is used).
     * @param _feeType      The fee type
     * @param _token        The token address (must not be address(0))
     * @param _numerator    The discounted numerator
     * @param _validityDate Unix timestamp until which the discount is valid
     */
    function setCustomFee(
        bytes32 _feeType,
        address _token,
        uint32 _numerator,
        uint64 _validityDate
    ) external onlyManager {
        require(feeTypeConfigs[_feeType].maxNumerator > 0, "unknown fee type");
        require(_token != address(0), "token cannot be 0x0");
        require(_numerator <= feeTypeConfigs[_feeType].maxNumerator, "numerator exceeds max");
        require(_validityDate > block.timestamp, "validity date must be in the future");
        customFees[_feeType][_token] = CustomFee({numerator: _numerator, validityDate: _validityDate});
        emit CustomFeeSet(_feeType, _token, _numerator, _validityDate);
    }

    /**
     * @notice Removes a custom fee discount for a token, reverting to the type default.
     * @param _feeType The fee type
     * @param _token   The token address
     */
    function removeCustomFee(bytes32 _feeType, address _token) external onlyManager {
        require(_token != address(0), "token cannot be 0x0");
        delete customFees[_feeType][_token];
        emit CustomFeeRemoved(_feeType, _token);
    }

    // -------------------------------------------------------------------------
    // Fee collectors, manager-only
    // -------------------------------------------------------------------------

    /**
     * @notice Sets the default fee collector for a fee type. Owner only.
     * @param _feeType   The fee type
     * @param _collector The collector address (must not be address(0))
     */
    function setDefaultFeeCollector(bytes32 _feeType, address _collector) external onlyOwner {
        require(feeTypeConfigs[_feeType].maxNumerator > 0, "unknown fee type");
        require(_collector != address(0), "collector cannot be 0x0");
        collectors[_feeType][address(0)] = _collector;
        emit FeeCollectorSet(_feeType, address(0), _collector);
    }

    /**
     * @notice Sets a per-token fee collector override for a fee type. Manager only.
     * @param _feeType   The fee type
     * @param _token     The token address (must not be address(0))
     * @param _collector The collector address (must not be address(0))
     */
    function setCustomFeeCollector(bytes32 _feeType, address _token, address _collector) external onlyManager {
        require(feeTypeConfigs[_feeType].maxNumerator > 0, "unknown fee type");
        require(_token != address(0), "token cannot be 0x0");
        require(_collector != address(0), "collector cannot be 0x0");
        collectors[_feeType][_token] = _collector;
        emit FeeCollectorSet(_feeType, _token, _collector);
    }

    /**
     * @notice Removes the per-token fee collector override, reverting to the type default.
     * @param _feeType The fee type
     * @param _token   The token address (must not be address(0))
     */
    function removeCustomFeeCollector(bytes32 _feeType, address _token) external onlyManager {
        require(_token != address(0), "token cannot be 0x0");
        delete collectors[_feeType][_token];
        emit CustomFeeCollectorRemoved(_feeType, _token);
    }

    // -------------------------------------------------------------------------
    // IFeeSettingsV3 generic accessors
    // -------------------------------------------------------------------------

    /**
     * @notice Calculates the fee for a given amount and fee type.
     *      If a non-expired custom discount is set for `_token`, the lower of default and custom is used.
     * @dev A fee type that does not exist will return 0 fee. That is a design choice.
     * @param _feeType The fee type key
     * @param _amount  The base amount
     * @param _token   The token address (used to look up custom discounts)
     */
    function fee(
        bytes32 _feeType,
        uint256 _amount,
        address _token
    ) public view override(IFeeSettingsV3) returns (uint256) {
        FeeTypeConfig storage config = feeTypeConfigs[_feeType];
        CustomFee storage custom = customFees[_feeType][_token];
        return _applyCustomFee(_amount, config.defaultNumerator, custom.numerator, custom.validityDate);
    }

    /**
     * @notice Returns the fee collector for a given fee type and token.
     *      Falls back to the type-level default (key = address(0)) if no per-token entry exists.
     * @param _feeType The fee type key
     * @param _token   The token address
     */
    function feeCollector(bytes32 _feeType, address _token) public view override(IFeeSettingsV3) returns (address) {
        address custom = collectors[_feeType][_token];
        if (custom != address(0)) return custom;
        return collectors[_feeType][address(0)];
    }

    /**
     * @notice Converts a human-readable fee type name to its bytes32 key.
     *      Useful for block explorer users who need the hash to query mappings directly.
     * @param _feeType The fee type name (e.g. "TOKEN", "CROWDINVESTING")
     */
    function feeTypeId(string calldata _feeType) external pure returns (bytes32) {
        return keccak256(bytes(_feeType));
    }

    // -------------------------------------------------------------------------
    // IFeeSettingsV2 named accessors (backwards-compat wrappers over V3 generics)
    // -------------------------------------------------------------------------

    /// @dev V2 wrapper
    function tokenFee(uint256 _tokenAmount, address _token) public view override(IFeeSettingsV2) returns (uint256) {
        return fee(FeeTypes.TOKEN, _tokenAmount, _token);
    }

    /// @dev V2 wrapper
    function tokenFeeCollector(address _token) public view override(IFeeSettingsV2) returns (address) {
        return feeCollector(FeeTypes.TOKEN, _token);
    }

    /// @dev V2 wrapper
    function crowdinvestingFee(
        uint256 _currencyAmount,
        address _token
    ) public view override(IFeeSettingsV2) returns (uint256) {
        return fee(FeeTypes.CROWDINVESTING, _currencyAmount, _token);
    }

    /// @dev V2 wrapper
    function crowdinvestingFeeCollector(address _token) public view override(IFeeSettingsV2) returns (address) {
        return feeCollector(FeeTypes.CROWDINVESTING, _token);
    }

    /// @dev V2 wrapper
    function privateOfferFee(
        uint256 _currencyAmount,
        address _token
    ) public view override(IFeeSettingsV2) returns (uint256) {
        return fee(FeeTypes.PRIVATE_OFFER, _currencyAmount, _token);
    }

    /// @dev V2 wrapper
    function privateOfferFeeCollector(address _token) public view override(IFeeSettingsV2) returns (address) {
        return feeCollector(FeeTypes.PRIVATE_OFFER, _token);
    }

    // -------------------------------------------------------------------------
    // IFeeSettingsV1 named accessors (backwards-compatible wrappers, no token address needed)
    // -------------------------------------------------------------------------

    /**
     * @notice Returns the default token fee collector.
     * @dev V1 wrapper — V1 has no concept of per-token collectors, so we return the type default.
     */
    function feeCollector() external view override(IFeeSettingsV1) returns (address) {
        return collectors[FeeTypes.TOKEN][address(0)];
    }

    /**
     * @notice Returns the fee for a given token amount.
     * @dev V1 wrapper — caller is assumed to be the token contract.
     */
    function tokenFee(uint256 _tokenAmount) external view override(IFeeSettingsV1) returns (uint256) {
        return fee(FeeTypes.TOKEN, _tokenAmount, _msgSender());
    }

    /// @dev V1 wrapper
    function continuousFundraisingFee(
        uint256 _currencyAmount
    ) external view override(IFeeSettingsV1) returns (uint256) {
        return fee(FeeTypes.CROWDINVESTING, _currencyAmount, address(0));
    }

    /// @dev V1 wrapper
    function personalInviteFee(uint256 _currencyAmount) external view override(IFeeSettingsV1) returns (uint256) {
        return fee(FeeTypes.PRIVATE_OFFER, _currencyAmount, address(0));
    }

    // -------------------------------------------------------------------------
    // Misc
    // -------------------------------------------------------------------------

    /**
     * @dev Specify where the implementation of owner() is located
     */
    function owner() public view override(OwnableUpgradeable, IFeeSettingsV1, IFeeSettingsV2) returns (address) {
        return OwnableUpgradeable.owner();
    }

    modifier onlyManager() {
        require(managers[_msgSender()], "Only managers can call this function");
        _;
    }

    /**
     * @notice ERC165 interface detection.
     */
    function supportsInterface(
        bytes4 interfaceId
    ) public view virtual override(ERC165Upgradeable, IFeeSettingsV1, IFeeSettingsV2, IFeeSettingsV3) returns (bool) {
        return
            interfaceId == type(IFeeSettingsV1).interfaceId ||
            interfaceId == type(IFeeSettingsV2).interfaceId ||
            interfaceId == type(IFeeSettingsV3).interfaceId ||
            ERC165Upgradeable.supportsInterface(interfaceId);
    }

    // -------------------------------------------------------------------------
    // Internal fee math
    // -------------------------------------------------------------------------

    function _fee(uint256 amount, uint32 numerator) internal pure returns (uint256) {
        return (amount * numerator) / FEE_DENOMINATOR;
    }

    /**
     * Returns the lower of the default fee and the custom fee, if the custom fee is still valid.
     * Custom fees can only discount, never increase.
     */
    function _applyCustomFee(
        uint256 amount,
        uint32 defaultNumerator,
        uint32 customNumerator,
        uint64 customValidityDate
    ) internal view returns (uint256) {
        if (customValidityDate < uint64(block.timestamp)) {
            return _fee(amount, defaultNumerator);
        }
        return _fee(amount, customNumerator < defaultNumerator ? customNumerator : defaultNumerator);
    }

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
