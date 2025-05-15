// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

contract TokenSale is Ownable, ReentrancyGuard {
    // Core state variables
    uint208 public hardcap;         // Maximum amount that can be invested
    address public beneficiary;      // Address that receives the invested funds
    address public allowanceSigner;  // Address that signs allowance messages to authorize investments
    uint48 public startTimestamp;   // Start timestamp
    uint48 public endTimestamp;     // End timestamp
    uint208 public totalInvested;   // Total amount invested so far
    uint48 public investmentId = 1;     // Incremental ID for each investment
    
    // Stores block numbers for every 1000th investment for pagination purposes
    uint256[] public paginationBlocksBy1000;

    error NoDirectDepositsAllowed();
    error ZeroAddressForbidden();
    error PaymentTooSmall();
    error SaleHasNotStarted();
    error SaleHasEnded();
    error SaleIsFull();
    error OnlyFutureEndTimestampAllowed();
    error StartTimestampMustBeBeforeEndTimestamp();
    error HardcapMustBeGreaterThanZero();
    error HardcapMustBeGreaterThanTotalInvested();
    error InvalidAllowanceSignature();
    error RefundTransferFailed();
    error BeneficiaryTransferFailed();

    event Investment(bytes16 indexed userId, uint208 investedAmount, uint208 saleProgressBefore, uint48 investmentId, uint48 timestamp);

    constructor(address beneficiary_, address owner_, address allowanceSigner_, uint48 startTimestamp_, uint48 endTimestamp_, uint208 hardcap_) Ownable(owner_) {
        require(beneficiary_ != address(0), ZeroAddressForbidden());
        require(allowanceSigner_ != address(0), ZeroAddressForbidden());
        require(endTimestamp_ > block.timestamp, OnlyFutureEndTimestampAllowed());
        require(startTimestamp_ < endTimestamp_, StartTimestampMustBeBeforeEndTimestamp());
        require(hardcap_ > 0, HardcapMustBeGreaterThanZero());

        beneficiary = beneficiary_;
        allowanceSigner = allowanceSigner_;
        startTimestamp = startTimestamp_;
        endTimestamp = endTimestamp_;
        hardcap = hardcap_;
    }

    // Prevent accidental direct transfers to the contract
    receive() external payable {
        revert NoDirectDepositsAllowed();
    }

    fallback() external payable {
        revert NoDirectDepositsAllowed();
    }

    function invest(bytes16 userId, bytes memory allowanceSignature) external payable nonReentrant {
        require(msg.value >= 10**15, PaymentTooSmall());
        require(block.timestamp >= startTimestamp, SaleHasNotStarted());
        require(block.timestamp <= endTimestamp, SaleHasEnded());

        // Verify the signature that authorizes this user to invest
        bytes32 messageHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n16", userId));
        address signer = ECDSA.recover(messageHash, allowanceSignature);
        require(signer == allowanceSigner, InvalidAllowanceSignature());

        // Calculate how much of the investment can be accepted
        uint208 acceptedAmount = 0;
        uint208 availableSpace = hardcap - totalInvested;

        // Accept either the full amount or remaining space up to hardcap
        if (msg.value > availableSpace) {
            acceptedAmount = availableSpace;
        } else {
            acceptedAmount = uint208(msg.value);
        }
        require(acceptedAmount > 0, SaleIsFull());

        // Handle refunds and transfers
        // Refund excess if any
        uint256 refundAmount = msg.value - acceptedAmount;
        if (refundAmount > 0) {
            (bool refundSuccess, ) = msg.sender.call{value: refundAmount}("");
            require(refundSuccess, RefundTransferFailed());
        }

        // Transfer accepted amount to beneficiary
        (bool success, ) = beneficiary.call{value: uint256(acceptedAmount)}("");
        require(success, BeneficiaryTransferFailed());

        // Store block number for every 1000th investment for pagination
        if (investmentId % 1000 == 0) {
            paginationBlocksBy1000.push(block.number);
        }

        emit Investment(userId, acceptedAmount, totalInvested, investmentId, uint48(block.timestamp));

        totalInvested += acceptedAmount;
        investmentId++;
    }

    // Admin functions to update contract parameters
    // All require controller access and include reentrancy protection
    function setBeneficiary(address newBeneficiary) external onlyOwner {
        require(newBeneficiary != address(0), ZeroAddressForbidden());
        beneficiary = newBeneficiary;
    }

    function setAllowanceSigner(address newAllowanceSigner) external onlyOwner {
        require(newAllowanceSigner != address(0), ZeroAddressForbidden());
        allowanceSigner = newAllowanceSigner;
    }

    function setStartAndEndTimestamp(uint48 newStartTimestamp, uint48 newEndTimestamp) external onlyOwner {
        require(newStartTimestamp < newEndTimestamp, StartTimestampMustBeBeforeEndTimestamp());
        startTimestamp = newStartTimestamp;
        endTimestamp = newEndTimestamp;
    }

    function setHardcap(uint208 newHardcap) external onlyOwner {
        require(newHardcap >= totalInvested, HardcapMustBeGreaterThanTotalInvested());
        hardcap = newHardcap;
    }
}
