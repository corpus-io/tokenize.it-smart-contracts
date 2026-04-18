// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "./CoinvestedPosition.sol";
import "./common/Errors.sol";

/**
 * @title FeeSplitter
 * @author malteish
 * @notice Pulls a one-time syndicate fee from a payer and distributes it proportionally among the
 *      lead investors of a CoinvestedPosition according to their carry fractions.
 * @dev Uses clone/proxy pattern for deterministic address derivation. payFee() can only succeed
 *      once per clone because the feePayer's allowance is consumed on the first call.
 */
contract FeeSplitter {
    using SafeERC20 for IERC20;

    /// @notice Reverted when the feePayer address argument is zero.
    error ZeroFeePayerAddress();

    /// @notice Reverted when the coinvestedPosition address argument is zero.
    error ZeroCoinvestedPositionAddress();

    /// @notice Emitted once when the fee has been pulled and distributed.
    event FeeDistributed(address indexed feePayer, address indexed currency, uint256 feeAmount);

    /**
     * @notice Pulls feeAmount of currency from feePayer and distributes it proportionally among the
     *      lead investors of coinvestedPosition by their carry fractions. The first lead investor
     *      absorbs any rounding dust so the full feeAmount is always distributed.
     *      feePayer must have pre-approved this contract's address for at least feeAmount of currency.
     * @param feePayer address from which the fee is pulled; must have pre-approved this contract
     * @param currency ERC20 token in which the fee is denominated
     * @param feeAmount total fee to distribute, in currency bits
     * @param coinvestedPosition source of lead investor accounts and carry fractions
     */
    function payFee(
        address feePayer,
        IERC20 currency,
        uint256 feeAmount,
        CoinvestedPosition coinvestedPosition
    ) external {
        require(feePayer != address(0), ZeroFeePayerAddress());
        require(address(currency) != address(0), ZeroCurrencyAddress());
        require(feeAmount != 0, ZeroAmount());
        require(address(coinvestedPosition) != address(0), ZeroCoinvestedPositionAddress());

        uint256 investorCount = coinvestedPosition.getLeadInvestorsCount();
        require(investorCount > 0, NoLeadInvestors());

        currency.safeTransferFrom(feePayer, address(this), feeAmount);

        // sum carry fractions to use as the denominator for proportional distribution
        uint256 profitFractionsSum = 0;
        for (uint256 i = 0; i < investorCount; i++) {
            (, uint64 profitFraction) = coinvestedPosition.leadInvestors(i);
            profitFractionsSum += profitFraction;
        }

        // distribute proportionally; last investor absorbs rounding dust
        uint256 remainingFee = feeAmount;
        for (uint256 i = 0; i < investorCount - 1; i++) {
            (address account, uint64 profitFraction) = coinvestedPosition.leadInvestors(i);
            uint256 share = (uint256(profitFraction) * feeAmount) / profitFractionsSum;
            if (share != 0) {
                currency.safeTransfer(account, share);
                remainingFee -= share;
            }
        }
        // send the last leadInvestor's share along with any rounding dust
        if (remainingFee != 0) {
            (address lastAccount, ) = coinvestedPosition.leadInvestors(investorCount - 1);
            currency.safeTransfer(lastAccount, remainingFee);
        }

        emit FeeDistributed(feePayer, address(currency), feeAmount);
    }
}
