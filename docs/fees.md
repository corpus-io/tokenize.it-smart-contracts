# Fee settings and fee collection

## Structure

### Who pays fees

Tokenize.it will collect fees from it's users. There are 3 types of users and 2 types of assets on the platform:

- users
  1.  founders
  2.  investors
  3.  employees
- assets
  1.  currencies (WETH, WBTC, USDC, EUROC, EURe)
  2.  tokens of companies

Currency fees are collected during investments and token swaps (-> see `crowdinvestingFee()` and `privateOfferFee()` in [FeeSettings.sol](../contracts/FeeSettings.sol)).

Token fees are deducted during token minting (-> see `tokenFee` in [FeeSettings.sol](../contracts/FeeSettings.sol)).

**Example**:
Investor buys X tokens for Y USDC through the Crowdinvesting contract.

- X tokens are minted to the investor
- X\*tokenFeeNumerator/tokenFeeDenominator tokens are minted to the feeCollector
- So the company mints a total of X + X\*tokenFeeNumerator/tokenFeeDenominator tokens in this transaction
- Investor pays Y USDC
- Y\*crowdinvestingFeeNumerator/crowdinvestingFeeDenominator USDC goes to the feeCollector
- So the company receives Y - Y\*crowdinvestingFeeNumerator/crowdinvestingFeeDenominator USDC in this transaction
- In total, the company minted X + X\*tokenFeeNumerator/tokenFeeDenominator tokens and received Y - Y\*crowdinvestingFeeNumerator/crowdinvestingFeeDenominator USDC. It paid fees both in token and currency.
- The investor pays Y USDC for X tokens, like they expected. They did not pay fees.

### Interpretation

The smart contracts assume that the fees are paid by the company. The company will receive less currency and mint more tokens than the investor pays for. The investor will receive the tokens they paid for, and will not pay fees.

It is, however, possible to interpret the fees as paid by the investor. In this case, the relative fee and the price have to be adapted and do not refer to the price the company offers the investor on a 1:1 base anymore.

### Fee limits

The minimum fee is 0.

Maximum fees are defined for each FeeType at initialization.

## Fee collectors

Each fee type has its own fee collector address. The fee collectors are set by tokenize.it and can be changed by tokenize.it.

### Splitting fees

In case the fees collected must be split between multiple parties, one or more fee collector addresses can be set to one or more [PaymentSplitter](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/release-v4.9/contracts/finance/PaymentSplitter.sol) contracts. This contract will then receive the fees and send each beneficiary their share. The payout can be triggered by anyone.

There is a limitation we are very unlikely to ever experience: if `totalAmountOfTokensReceived * highestShareNumber` overflows, the contract will not release these funds anymore. As we are using it for fees, which are just a small fraction of the total amount of tokens or currency, we should not see this happening in practice. Choosing the number of shares as low as possible is recommended to be even safer. See `testLockingFunds` in [the PaymentSplitter tests](./test/PaymentSplitter.t.sol) for a demonstration of this limitation.

The PaymentSplitter contract will be removed in Openzeppelin contracts 5.0, but an updated version should be introduced in a later version. Until then, the 4.9.x version can be used. See [this PR](https://github.com/OpenZeppelin/openzeppelin-contracts/pull/4276).

## Implementation

### Fee settings

Tokenize.it will deploy and manage at least one [fee settings contract](../contracts/FeeSettings.sol). The current implementation supports IFeeSettingsV3, which is generic and extensible: any fee type can be queried with `fee(bytes32 feeType, uint256 amount, address token)` and `feeCollector(bytes32 feeType, address token)`. Fee type identifiers are keccak256 hashes of their names; the `feeTypeId(string)` helper on FeeSettings returns the bytes32 for any name.

The named V2 wrappers (`tokenFee`, `crowdinvestingFee`, `privateOfferFee`, etc.) are still available for backward compatibility with older contracts that detect V2 only.

Default fees can be changed by tokenize.it. Fee increases are subject to a delay of at least 12 weeks.

All fees are calculated as follows:

```solidity
fee = amount * feeNumerator / feeDenominator
```

### Token contracts

- Each [token contract](../contracts/Token.sol) is connected to a [fee settings contract](../contracts/FeeSettings.sol).
- When X tokens are minted, the fee is X\*tokenFeeNumerator/tokenFeeDenominator tokens. These are minted ON TOP of the X tokens requested, and are transferred to the feeCollector.
- The fee settings contract used by token can be changed only by the owner of the current fee settings contract in collaboration with the token's DEFAULT_ADMIN_ROLE.

### Investment contracts

- The investment contracts [PrivateOffer](../contracts/PrivateOffer.sol) and [Crowdinvesting](../contracts/Crowdinvesting.sol) both access the fee setting through the token contracts they are connected to.
- Crowdinvesting: When Y currency is paid, the fee is Y\*crowdinvestingFeeNumerator/crowdinvestingFeeDenominator. This fee is DEDUCTED from the Y currency paid and transferred to the feeCollector.
- PrivateOffer: When Y currency is paid, the fee is Y\*privateOfferFeeNumerator/privateOfferFeeDenominator. This fee is DEDUCTED from the Y currency paid and transferred to the feeCollector.

### Distribution contracts

[Distribution](../contracts/Distribution.sol) and [Exit](../contracts/Exit.sol) can both collect fees. The Fee is deducted **per claim** at `claim()` time.

[TokenSwap](../contracts/TokenSwap.sol) uses the `SECONDARY_MARKET` fee type (via IFeeSettingsV3). On older deployments where the fee settings contract does not support V3, it falls back to `privateOfferFee`.

## Discounts

### Per-token custom fees

The most direct way to give a specific token a reduced fee is a custom fee set by a manager. Managers are appointed by the platform owner and can call `setCustomFee(feeType, token, numerator, validityDate)` to register a time-limited discount for any token. When a custom fee is active and lower than the current default, it takes precedence — custom fees can only discount, never increase. A matching `setCustomFeeCollector()` can redirect the fee proceeds for that token to a different collector address.

This mechanism works without any action from the token's owner and without deploying a new contract.

### Separate FeeSettings contract

For cases where an entire group of tokens should share reduced rates, or where a more visible on-chain record of the discount is desirable, the platform can deploy a dedicated FeeSettings contract with lower defaults and connect tokens to it. Existing tokens can switch to a new FeeSettings contract when the platform proposes the change and the token's DEFAULT_ADMIN_ROLE holder accepts it.

If the discount should only be valid for a certain duration, the platform can raise the fees in the new contract after the discount period ends, or propose a switch back to the standard contract.

### Off-chain discounts

The platform can also offer discounts off-chain. For example, the platform can offer a discount to a founder for a certain duration and refund the difference between the discounted fee and the regular fee to the founder.

The refund can be executed on-chain or off-chain.

This approach is more flexible than the on-chain approach, and provides better privacy.
