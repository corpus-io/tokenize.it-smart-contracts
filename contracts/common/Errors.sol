// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

/// @notice Reverted when an owner address argument is zero.
error ZeroOwnerAddress();

/// @notice Reverted when a token address argument is zero.
error ZeroTokenAddress();

/// @notice Reverted when a currency address argument is zero.
error ZeroCurrencyAddress();

/// @notice Reverted when a receiver/recipient address argument is zero.
error ZeroReceiverAddress();

/// @notice Reverted when an amount argument that must not be zero is zero.
error ZeroAmount();

/// @notice Reverted when two array arguments that must have the same length do not.
error ArrayLengthMismatch();
