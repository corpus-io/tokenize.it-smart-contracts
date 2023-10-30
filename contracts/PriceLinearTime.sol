// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.17;

import "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/metatx/ERC2771ContextUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "./interfaces/IPriceDynamic.sol";

struct Linear {
    uint64 slopeEnumerator;
    uint64 slopeDenominator;
    uint64 startTime;
}

/**
 * @title PublicFundraising
 * @author malteish, cjentzsch
 * @notice This contract represents the offer to buy an amount of tokens at a preset price. It can be used by anyone and there is no limit to the number of times it can be used.
 *      The buyer can decide how many tokens to buy, but has to buy at least minAmount and can buy at most maxAmount.
 *      The currency the offer is denominated in is set at creation time and can be updated later.
 *      The contract can be paused at any time by the owner, which will prevent any new deals from being made. Then, changes to the contract can be made, like changing the currency, price or requirements.
 *      The contract can be unpaused after "delay", which will allow new deals to be made again.
 *      A company will create only one PublicFundraising contract for their token (or one for each currency if they want to accept multiple currencies).
 * @dev The contract inherits from ERC2771Context in order to be usable with Gas Station Network (GSN) https://docs.opengsn.org/faq/troubleshooting.html#my-contract-is-using-openzeppelin-how-do-i-add-gsn-support
 */
contract PriceLinearTime is
    ERC2771ContextUpgradeable,
    Ownable2StepUpgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable,
    IPriceDynamic
{
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
        uint64 _startTime
    ) external initializer {
        require(_owner != address(0), "owner can not be zero address");
        __Ownable2Step_init(); // sets msgSender() as owner
        _transferOwnership(_owner); // sets owner as owner
        require(_slopeEnumerator != 0, "slopeEnumerator can not be zero");
        require(_slopeDenominator != 0, "slopeDenominator can not be zero");
        require(_startTime > block.timestamp, "startTime must be in the future");
        parameters = Linear(_slopeEnumerator, _slopeDenominator, _startTime);
    }

    function getPrice(uint256 basePrice) public view returns (uint256) {
        if (block.timestamp > parameters.startTime) {
            return
                basePrice +
                ((block.timestamp - parameters.startTime) * parameters.slopeEnumerator) /
                parameters.slopeDenominator;
        }

        return basePrice;
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
