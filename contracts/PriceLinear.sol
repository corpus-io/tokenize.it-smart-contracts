// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.17;

import "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/metatx/ERC2771ContextUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "./interfaces/IPriceDynamic.sol";

struct Linear {
    /// numerator of slope of linear function, e.g. a where slope == a/b
    uint64 slopeEnumerator;
    /// denominator of slope of linear function, , e.g. b where slope == a/b
    uint64 slopeDenominator;
    /// start time as unix timestamp or start block number
    uint64 start;
    /// step width in seconds or blocks
    uint32 stepDuration;
    /// if 0: `stepDuration` is in seconds and `start` is an epoch
    /// if 1: `stepDuration` is in blocks and `start` is a block number
    bool isBlockBased;
    /// if 0 price is falling, if 1 price is rising
    bool isRising;
}

/**
 * @title Linear price function, with option for stepping, based on time or block count
 * @author malteish
 * @notice This contract implements a linear
 * @dev The contract inherits from ERC2771Context in order to be usable with Gas Station Network (GSN) https://docs.opengsn.org/faq/troubleshooting.html#my-contract-is-using-openzeppelin-how-do-i-add-gsn-support
 */
contract PriceLinear is ERC2771ContextUpgradeable, Ownable2StepUpgradeable, IPriceDynamic {
    Linear public parameters;

    /**
     * This constructor creates a logic contract that is used to clone new fundraising contracts.
     * It has no owner, and can not be used directly.
     * @param _trustedForwarder This address can execute transactions in the name of any other address
     */
    constructor(address _trustedForwarder) ERC2771ContextUpgradeable(_trustedForwarder) {
        _disableInitializers();
    }

    /**
     * @notice Sets up the PublicFundraising. The contract is usable immediately after deployment, but does need a minting allowance for the token.
     * @dev Constructor that passes the trusted forwarder to the ERC2771Context constructor
     */
    function initialize(
        address _owner,
        uint64 _slopeEnumerator,
        uint64 _slopeDenominator,
        uint64 _startTimeOrBlockNumber,
        uint32 _stepDuration,
        bool _isBlockBased,
        bool _isRising
    ) external initializer {
        require(_owner != address(0), "owner can not be zero address");
        __Ownable2Step_init(); // sets msgSender() as owner
        _transferOwnership(_owner); // sets owner as owner
        _updateParameters(
            _slopeEnumerator,
            _slopeDenominator,
            _startTimeOrBlockNumber,
            _stepDuration,
            _isBlockBased,
            _isRising
        );
    }

    /**
     * Update the parameters of the linear price function
     */
    function updateParameters(
        uint64 _slopeEnumerator,
        uint64 _slopeDenominator,
        uint64 _startTimeOrBlockNumber,
        uint32 _stepDuration,
        bool _isBlockBased,
        bool _isRising
    ) external onlyOwner {
        _updateParameters(
            _slopeEnumerator,
            _slopeDenominator,
            _startTimeOrBlockNumber,
            _stepDuration,
            _isBlockBased,
            _isRising
        );
    }

    function _updateParameters(
        uint64 _slopeEnumerator,
        uint64 _slopeDenominator,
        uint64 _startTimeOrBlockNumber,
        uint32 _stepDuration,
        bool _isBlockBased,
        bool _isRising
    ) internal {
        require(_slopeEnumerator != 0, "slopeEnumerator can not be zero");
        require(_slopeDenominator != 0, "slopeDenominator can not be zero");
        require(_startTimeOrBlockNumber > block.timestamp, "startTime must be in the future");
        require(_stepDuration != 0, "stepDuration can not be zero");
        parameters = Linear({
            slopeEnumerator: _slopeEnumerator,
            slopeDenominator: _slopeDenominator,
            start: _startTimeOrBlockNumber,
            stepDuration: _stepDuration,
            isBlockBased: _isBlockBased,
            isRising: _isRising
        });
    }

    function getPrice(uint256 basePrice) public view returns (uint256) {
        Linear memory _parameters = parameters;
        uint256 current = _parameters.isBlockBased ? block.number : block.timestamp;

        if (current <= _parameters.start) {
            return basePrice;
        }

        /// @dev note that the division is rounded down, generating a step function if stepDuration > 1
        uint256 change = (((current - _parameters.start) / _parameters.stepDuration) *
            _parameters.stepDuration *
            _parameters.slopeEnumerator) / _parameters.slopeDenominator;

        //uint256 change = uint256((current - parameters.start) / parameters.stepDuration) * parameters.slopeEnumerator;

        // if price is rising, add change, else subtract change
        if (_parameters.isRising) {
            // prevent overflow
            if (type(uint256).max - basePrice <= change) {
                return type(uint256).max;
            }
            return basePrice + change;
        } else {
            // prevent underflow
            return basePrice <= change ? 0 : basePrice - change;
        }
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
}
