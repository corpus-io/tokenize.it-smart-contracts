// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.23;

import "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/introspection/ERC165Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/metatx/ERC2771ContextUpgradeable.sol";

import "./interfaces/IFeeSettings.sol";

/**
 * @title FeeSettings
 * @author malteish, cjentzsch
 * @notice The FeeSettings contract is used to manage fees paid to the tokenize.it platfom
 */
contract FeeSettings is
    Ownable2StepUpgradeable,
    ERC165Upgradeable,
    ERC2771ContextUpgradeable,
    IFeeSettingsV2,
    IFeeSettingsV1
{
    /// max crowdinvesting fee (paid in token and cash combined) is 15%
    uint32 public constant MAX_TOTAL_CROWDINVESTING_FEE_NUMERATOR = 1500;
    /// max private offer fee (paid in token and cash combined) is 10%
    uint32 public constant MAX_TOTAL_PRIVATE_OFFER_FEE_NUMERATOR = 1000;

    /// Denominator to calculate all fees
    uint32 public constant FEE_DENOMINATOR = 10000;

    /**
     * special fees for specific customers. If a customer has a custom fee, the custom
     * fee is used instead of the default fee.
     * Custom fees can only reduce the fee, not increase it.
     * The key is the customer's token address, e.g. customers are identified by their token.
     * The `time` field is the time up to which the custom fee is valid.
     * Afterwards, standard fees are used.
     */
    mapping(address => Fees) public fees;

    /**
     * if `tokenFeeCollectors[tokenAddress]` is 0x0, the fees must be paid to `tokenFeeCollectors[address(0)]`
     * otherwise, the fees must be paid to `tokenFeeCollectors[tokenAddress]`
     */
    mapping(address => address) public tokenFeeCollectors;
    /**
     * if `crowdinvestingFeeCollectors[tokenAddress]` is 0x0, the fees must be paid to `crowdinvestingFeeCollectors[address(0)]`
     * otherwise, the fees must be paid to `crowdinvestingFeeCollectors[tokenAddress]`
     */
    mapping(address => address) public crowdinvestingFeeCollectors;
    /**
     * if `privateOfferFeeCollectors[tokenAddress]` is 0x0, the fees must be paid to `privateOfferFeeCollectors[address(0)]`
     * otherwise, the fees must be paid to `privateOfferFeeCollectors[tokenAddress]`
     */
    mapping(address => address) public privateOfferFeeCollectors;

    /// new fee settings that can be activated (after a delay in case of fee increase)
    Fees public proposedDefaultFees;

    /// stores who is a manager. Managers can change fees and fee collectors for specific tokens
    mapping(address => bool) public managers;

    /**
     * @notice Default fees have been changed
     * @param tokenFeeNumerator a in fraction a/b that defines the fee paid in Token: fee = amount * a / b
     * @param crowdinvestingFeeNumerator a in fraction a/b that defines the fee paid in currency for crowdinvesting: fee = amount * a / b
     * @param privateOfferFeeNumerator a in fraction a/b that defines the fee paid in currency for private offers: fee = amount * a / b
     */
    event SetFee(uint32 tokenFeeNumerator, uint32 crowdinvestingFeeNumerator, uint32 privateOfferFeeNumerator);

    /**
     * @notice Default fees have been changed
     * @param tokenFeeNumerator a in fraction a/b that defines the fee paid in Token: fee = amount * a / b
     * @param crowdinvestingFeeNumerator a in fraction a/b that defines the fee paid in currency for crowdinvesting: fee = amount * a / b
     * @param privateOfferFeeNumerator a in fraction a/b that defines the fee paid in currency for private offers: fee = amount * a / b
     * @param time The time when the custom fee expires
     */
    event SetCustomFee(
        address indexed token,
        uint32 tokenFeeNumerator,
        uint32 crowdinvestingFeeNumerator,
        uint32 privateOfferFeeNumerator,
        uint256 time
    );

    /// custom fee settings for the given token have been removed
    event RemoveCustomFee(address indexed token);

    /// token fees for `token` must now be paid to `feeCollector`
    event SetCustomTokenFeeCollector(address indexed token, address indexed feeCollector);
    /// crowdinvesting fees for `token` must now be paid to `feeCollector`
    event SetCustomCrowdinvestingFeeCollector(address indexed token, address indexed feeCollector);
    /// private offer fees for `token` must now be paid to `feeCollector`
    event SetCustomPrivateOfferFeeCollector(address indexed token, address indexed feeCollector);

    /// token fees for `token` must now be paid to the default fee collector
    event RemoveCustomTokenFeeCollector(address indexed token);
    /// crowdinvesting fees for `token` must now be paid to the default fee collector
    event RemoveCustomCrowdinvestingFeeCollector(address indexed token);
    /// private offer fees for `token` must now be paid to the default fee collector
    event RemoveCustomPrivateOfferFeeCollector(address indexed token);

    /**
     * @notice The fee collectors have changed
     * @param newTokenFeeCollector The new fee collector for token fees
     * @param newCrowdinvestingFeeCollector The new fee collector for crowdinvesting fees
     * @param newPrivateOfferFeeCollector The new fee collector for private offer fees
     */
    event FeeCollectorsChanged(
        address indexed newTokenFeeCollector,
        address indexed newCrowdinvestingFeeCollector,
        address indexed newPrivateOfferFeeCollector
    );

    /**
     * @notice A fee change has been proposed
     * @param proposal The new fee settings that have been proposed
     */
    event ChangeProposed(Fees proposal);

    /**
     * This constructor deploys a logic contract with no owner, that can be used for cloning.
     * @param _trustedForwarder The trusted forwarder contract to use
     */
    constructor(address _trustedForwarder) ERC2771ContextUpgradeable(_trustedForwarder) {
        _disableInitializers();
    }

    /**
     * @notice Initializes the contract with the given fee denominators and fee collector
     * @param _fees The initial fee denominators
     * @param _tokenFeeCollector The initial fee collector
     * @param _crowdinvestingFeeCollector The initial crowdinvesting fee collector
     * @param _privateOfferFeeCollector The initial private offer fee collector
     */
    function initialize(
        address _owner,
        Fees memory _fees,
        address _tokenFeeCollector,
        address _crowdinvestingFeeCollector,
        address _privateOfferFeeCollector
    ) external initializer {
        require(_owner != address(0), "owner can not be zero address");
        managers[_owner] = true;
        _transferOwnership(_owner);

        checkFeeLimits(_fees);
        fees[address(0)] = _fees;

        require(_tokenFeeCollector != address(0), "Fee collector cannot be 0x0");
        tokenFeeCollectors[address(0)] = _tokenFeeCollector;

        require(_crowdinvestingFeeCollector != address(0), "Fee collector cannot be 0x0");
        crowdinvestingFeeCollectors[address(0)] = _crowdinvestingFeeCollector;

        require(_privateOfferFeeCollector != address(0), "Fee collector cannot be 0x0");
        privateOfferFeeCollectors[address(0)] = _privateOfferFeeCollector;
    }

    /**
     * @notice Adds a manager
     * @param _manager The manager to add
     */
    function addManager(address _manager) external onlyOwner {
        managers[_manager] = true;
    }

    /**
     * @notice Removes a manager
     * @param _manager The manager to remove
     */
    function removeManager(address _manager) external onlyOwner {
        delete managers[_manager];
    }

    /**
     * @notice Prepares a fee change. Fee increases are subject to a minimum delay of 12 weeks, while fee reductions can be executed immediately.
     * @dev reducing fees = increasing the denominator
     * @param _fees The new fee denominators
     */
    function planFeeChange(Fees memory _fees) external onlyOwner {
        checkFeeLimits(_fees);

        // if at least one fee increases, enforce minimum delay
        if (
            _fees.tokenFeeNumerator > fees[address(0)].tokenFeeNumerator || // token fee increases -> important for other products
            _fees.crowdinvestingFeeNumerator + _fees.tokenFeeNumerator >
            fees[address(0)].crowdinvestingFeeNumerator + fees[address(0)].tokenFeeNumerator || // crowdinvesting fee increases
            _fees.privateOfferFeeNumerator + _fees.tokenFeeNumerator >
            fees[address(0)].privateOfferFeeNumerator + fees[address(0)].tokenFeeNumerator // private offer fee increases
        ) {
            require(
                _fees.validityDate > block.timestamp + 12 weeks,
                "Fee change must be at least 12 weeks in the future"
            );
        }
        proposedDefaultFees = _fees;
        emit ChangeProposed(_fees);
    }

    /**
     * @notice Executes a fee change that has been planned before
     */
    function executeFeeChange() external onlyOwner {
        require(
            block.timestamp >= proposedDefaultFees.validityDate,
            "Fee change must be executed after the change time"
        );
        fees[address(0)] = proposedDefaultFees;
        emit SetFee(
            proposedDefaultFees.tokenFeeNumerator,
            proposedDefaultFees.crowdinvestingFeeNumerator,
            proposedDefaultFees.privateOfferFeeNumerator
        );
        delete proposedDefaultFees;
    }

    /**
     * @notice Sets a new fee collector
     * @param _tokenFeeCollector The new fee collector
     */
    function setFeeCollectors(
        address _tokenFeeCollector,
        address _crowdinvestingFeeCollector,
        address _personalOfferFeeCollector
    ) external onlyOwner {
        require(_tokenFeeCollector != address(0), "Fee collector cannot be 0x0");
        tokenFeeCollectors[address(0)] = _tokenFeeCollector;
        require(_crowdinvestingFeeCollector != address(0), "Fee collector cannot be 0x0");
        crowdinvestingFeeCollectors[address(0)] = _crowdinvestingFeeCollector;
        require(_personalOfferFeeCollector != address(0), "Fee collector cannot be 0x0");
        privateOfferFeeCollectors[address(0)] = _personalOfferFeeCollector;
        emit FeeCollectorsChanged(_tokenFeeCollector, _crowdinvestingFeeCollector, _personalOfferFeeCollector);
    }

    /**
     * @notice Checks if the given fee settings are valid
     * @param _fees The fees to check
     */
    function checkFeeLimits(Fees memory _fees) internal pure {
        require(
            _fees.tokenFeeNumerator + _fees.crowdinvestingFeeNumerator <= MAX_TOTAL_CROWDINVESTING_FEE_NUMERATOR,
            "Total Crowdinvesting fee must be <= 15%"
        );
        require(
            _fees.tokenFeeNumerator + _fees.privateOfferFeeNumerator <= MAX_TOTAL_PRIVATE_OFFER_FEE_NUMERATOR,
            "Total PrivateOffer fee must be <= 10%"
        );
    }

    /**
     * @notice Sets a custom fee for a specific token
     * @param _token The token for which the custom fee should be set
     * @param _fees The custom fee
     */
    function setCustomFee(address _token, Fees memory _fees) external onlyManager {
        checkFeeLimits(_fees);
        require(_token != address(0), "Token cannot be 0x0");
        require(_fees.validityDate > block.timestamp, "Custom fee expiry time must be in the future");
        fees[_token] = _fees;
        emit SetCustomFee(
            _token,
            _fees.tokenFeeNumerator,
            _fees.crowdinvestingFeeNumerator,
            _fees.privateOfferFeeNumerator,
            _fees.validityDate
        );
    }

    /**
     * @notice removes a custom fee entry for a specific token
     * @param _token The token for which the custom fee should be removed
     */
    function removeCustomFee(address _token) external onlyManager {
        require(_token != address(0), "Token cannot be 0x0");
        delete fees[_token];
        emit RemoveCustomFee(_token);
    }

    /**
     * set `_feeCollector` as the token fee collector for `_token`
     * @param _token the token for which the fee collector is set
     * @param _feeCollector the address that will receive the token fees
     */
    function setCustomTokenFeeCollector(address _token, address _feeCollector) external onlyManager {
        require(_feeCollector != address(0), "Fee collector cannot be 0x0");
        require(_token != address(0), "Token cannot be 0x0");
        tokenFeeCollectors[_token] = _feeCollector;
        emit SetCustomTokenFeeCollector(_token, _feeCollector);
    }

    /**
     *  set `_feeCollector` as the crowdinvesting fee collector for `_token`
     * @param _token the token for which the fee collector is set
     * @param _feeCollector the address that will receive the crowdinvesting fees
     */
    function setCustomCrowdinvestingFeeCollector(address _token, address _feeCollector) external onlyManager {
        require(_feeCollector != address(0), "Fee collector cannot be 0x0");
        require(_token != address(0), "Token cannot be 0x0");
        crowdinvestingFeeCollectors[_token] = _feeCollector;
        emit SetCustomCrowdinvestingFeeCollector(_token, _feeCollector);
    }

    /**
     * set `_feeCollector` as the private offer fee collector for `_token`
     * @param _token the token for which the fee collector is set
     * @param _feeCollector the address that will receive the private offer fees
     */
    function setCustomPrivateOfferFeeCollector(address _token, address _feeCollector) external onlyManager {
        require(_feeCollector != address(0), "Fee collector cannot be 0x0");
        require(_token != address(0), "Token cannot be 0x0");
        privateOfferFeeCollectors[_token] = _feeCollector;
        emit SetCustomPrivateOfferFeeCollector(_token, _feeCollector);
    }

    /**
     * Reset the token fee collector for `_token` to the default fee collector
     * @param _token the token for which the custom fee collector is removed
     */
    function removeCustomTokenFeeCollector(address _token) external onlyManager {
        require(_token != address(0), "Token cannot be 0x0");
        delete tokenFeeCollectors[_token];
        emit RemoveCustomTokenFeeCollector(_token);
    }

    /**
     * Reset the crowdinvesting fee collector for `_token` to the default fee collector
     * @param _token the token for which the custom fee collector is removed
     */
    function removeCustomCrowdinvestingFeeCollector(address _token) external onlyManager {
        require(_token != address(0), "Token cannot be 0x0");
        delete crowdinvestingFeeCollectors[_token];
        emit RemoveCustomCrowdinvestingFeeCollector(_token);
    }

    /**
     * Reset the private offer fee collector for `_token` to the default fee collector
     * @param _token the token for which the custom fee collector is removed
     */
    function removeCustomPrivateOfferFeeCollector(address _token) external onlyManager {
        require(_token != address(0), "Token cannot be 0x0");
        delete privateOfferFeeCollectors[_token];
        emit RemoveCustomPrivateOfferFeeCollector(_token);
    }

    /**
     * @notice Returns the token fee collector for a given token
     * @param _token The token to return the token fee collector for
     * @return The fee collector
     */
    function tokenFeeCollector(address _token) public view override(IFeeSettingsV2) returns (address) {
        if (tokenFeeCollectors[_token] != address(0)) {
            return tokenFeeCollectors[_token];
        }
        return tokenFeeCollectors[address(0)];
    }

    /**
     * @notice Returns the crowdinvesting fee collector for a given token
     * @param _token The token to return the crowdinvesting fee collector for
     * @return The fee collector
     */
    function crowdinvestingFeeCollector(address _token) public view override(IFeeSettingsV2) returns (address) {
        if (crowdinvestingFeeCollectors[_token] != address(0)) {
            return crowdinvestingFeeCollectors[_token];
        }
        return crowdinvestingFeeCollectors[address(0)];
    }

    /**
     * @notice Returns the private offer fee collector for a given token
     * @param _token The token to return the private offer fee collector for
     * @return The fee collector
     */
    function privateOfferFeeCollector(address _token) public view override(IFeeSettingsV2) returns (address) {
        if (privateOfferFeeCollectors[_token] != address(0)) {
            return privateOfferFeeCollectors[_token];
        }
        return privateOfferFeeCollectors[address(0)];
    }

    /**
     * General linear fee calculation function
     * @param amount how many erc20 tokens are transferred
     * @param numerator fee numerator
     */
    function _fee(uint256 amount, uint32 numerator) internal pure returns (uint256) {
        return (amount * numerator) / FEE_DENOMINATOR;
    }

    /**
     * Calculates the fee for a given amount of tokens.
     * @param amount how many erc20 tokens are transferred
     * @param defaultNumerator default fee numerator
     * @param customNumerator custom fee numerator
     * @param customValidityDate custom fee validity date
     */
    function _customFee(
        uint256 amount,
        uint32 defaultNumerator,
        uint32 customNumerator,
        uint64 customValidityDate
    ) internal view returns (uint256) {
        if (customValidityDate < uint64(block.timestamp)) {
            return _fee(amount, defaultNumerator);
        }
        uint256 defaultFee = _fee(amount, defaultNumerator);
        uint256 customFee = _fee(amount, customNumerator);
        if (customFee < defaultFee) {
            return customFee;
        }
        return defaultFee;
    }

    /**
     * calculates the token fee in tokens for the given token amount
     * @param _tokenAmount number of tokens that are minted
     * @param _token address of the token contract minting the tokens
     */
    function tokenFee(uint256 _tokenAmount, address _token) public view override(IFeeSettingsV2) returns (uint256) {
        return
            _customFee(
                _tokenAmount,
                fees[address(0)].tokenFeeNumerator,
                fees[_token].tokenFeeNumerator,
                fees[_token].validityDate
            );
    }

    /**
     * Calculates the fee for a given currency amount in Crowdinvesting (v5) or ContinuousFundraising (v4)
     * @param _currencyAmount how much currency is raised
     * @param _token the token that is sold through the crowdinvesting
     * @return the fee
     */
    function crowdinvestingFee(
        uint256 _currencyAmount,
        address _token
    ) public view override(IFeeSettingsV2) returns (uint256) {
        return
            _customFee(
                _currencyAmount,
                fees[address(0)].crowdinvestingFeeNumerator,
                fees[_token].crowdinvestingFeeNumerator,
                fees[_token].validityDate
            );
    }

    /**
     * Calculates the fee for a given currency amount in PrivateOffer (v5) or PersonalInvite (v4)
     * @param _currencyAmount how much currency is raised
     * @return the fee
     */
    function privateOfferFee(
        uint256 _currencyAmount,
        address _token
    ) public view override(IFeeSettingsV2) returns (uint256) {
        return
            _customFee(
                _currencyAmount,
                fees[address(0)].privateOfferFeeNumerator,
                fees[_token].privateOfferFeeNumerator,
                fees[_token].validityDate
            );
    }

    /**
     * @dev Specify where the implementation of owner() is located
     * @return The owner of the contract
     */
    function owner() public view override(OwnableUpgradeable, IFeeSettingsV1, IFeeSettingsV2) returns (address) {
        return OwnableUpgradeable.owner();
    }

    modifier onlyManager() {
        require(managers[_msgSender()], "Only managers can call this function");
        _;
    }

    /**
     * @notice This contract implements the ERC165 interface in order to enable other contracts to query which interfaces this contract implements.
     * @dev See https://eips.ethereum.org/EIPS/eip-165
     * @return `true` for supported interfaces, otherwise `false`
     */
    function supportsInterface(
        bytes4 interfaceId
    ) public view virtual override(ERC165Upgradeable, IFeeSettingsV1, IFeeSettingsV2) returns (bool) {
        return
            interfaceId == type(IFeeSettingsV1).interfaceId || // we implement IFeeSettingsV1 for backwards compatibility
            interfaceId == type(IFeeSettingsV2).interfaceId || // we implement IFeeSettingsV2
            ERC165Upgradeable.supportsInterface(interfaceId); // default implementation that enables further querying
    }

    /**
     * @notice Returns the default token fee collector
     * @dev this is a compatibility function for IFeeSettingsV1. It enables older token contracts to use the new fee settings contract.
     * @dev as IFeeSettingsV1 only supports a single fee collector, we can not inquire the token address. Therefore, we return the default fee collector.
     * @return The token fee collector
     */
    function feeCollector() external view override(IFeeSettingsV1) returns (address) {
        return tokenFeeCollectors[address(0)];
    }

    /**
     * @notice Returns the fee for a given token amount
     * @dev Custom fees are only applied correctly when this function is called from the token contract itself.
     * To calculate fees when calling from a different address, use `tokenFee(uint256, address)` instead.
     */
    function tokenFee(uint256 _tokenAmount) external view override(IFeeSettingsV1) returns (uint256) {
        return tokenFee(_tokenAmount, _msgSender());
    }

    /**
     * @notice calculate the fee for a given currency amount in Crowdinvesting (formerly ContinuousFundraising)
     * @dev this is a compatibility function for IFeeSettingsV1. It enables older token contracts to use the new fee settings contract.
     * @param _currencyAmount The amount of currency to calculate the fee for
     */
    function continuousFundraisingFee(
        uint256 _currencyAmount
    ) external view override(IFeeSettingsV1) returns (uint256) {
        return crowdinvestingFee(_currencyAmount, address(0));
    }

    /**
     * @notice calculate the fee for a given currency amount in PrivateOffer (formerly PersonalInvite)
     * @dev this is a compatibility function for IFeeSettingsV1. It enables older token contracts to use the new fee settings contract.
     * @param _currencyAmount The amount of currency to calculate the fee for
     */
    function personalInviteFee(uint256 _currencyAmount) external view override(IFeeSettingsV1) returns (uint256) {
        return privateOfferFee(_currencyAmount, address(0));
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
