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

/// @notice Reverted when a price or rate argument that must be positive is zero.
error ZeroPrice();

/// @notice Reverted when a currency is not on the token's allowList with the TRUSTED_CURRENCY attribute.
error UntrustedCurrency();

/// @notice Reverted when a currency argument equals the token address (they must differ).
error CurrencyEqualsToken();

/// @notice Reverted when a lockedUntil timestamp is not strictly in the future.
error LockedUntilNotInFuture();
