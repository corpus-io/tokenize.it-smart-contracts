# Fee settings and fee collection

## Structure

### Who pays fees

Tokenize.it will collect fees from it's users. There are 2 types of users and 2 types of assets on the platform:

- users
  1.  founders
  2.  investors
- assets
  1.  currencies (WETH, WBTC, USDC, EUROC)
  2.  tokens of companies

Fees are collected during investments and token minting, but from founders only. They are paid both in the investment currency (-> see continuousFundraisingFeeDenominator and personalInviteFeeDenominator in [FeeSettings.sol](../contracts/FeeSettings.sol)) and the token minted (-> see tokenFeeDenominator in [FeeSettings.sol](../contracts/FeeSettings.sol)).

**Example**:
Investor buys X tokens for Y USDC through the ContinuousFundraising contract.

- X tokens are minted to the investor
- X/tokenFeeDenominator tokens are minted to the feeCollector
- So the company mints a total of X + X/tokenFeeDenominator tokens in this transaction
- Investor pays Y USDC
- Y/continuousFundraisingFeeDenominator USDC goes to the feeCollector
- So the company receives Y - Y/continuousFundraisingFeeDenominator USDC in this transaction
- In total, the company minted X + X/tokenFeeDenominator tokens and received Y - Y/continuousFundraisingFeeDenominator USDC. It paid fees both in token and currency.
- The investor pays Y USDC for X tokens, like they expected. They did not pay fees.

### Fee limits

The minimum fee is 0.

Maximum fees are:

- 5% of tokens minted
- 5% of currency paid when using PersonalInvite
- 10% of currency paid when using ContinuousFundraising

## Fee collectors

The three fee types can be collected by different addresses, the fee collectors. The fee collectors are set by tokenize.it and can be changed by tokenize.it.

### Splitting fees

In case the fees collected must be split between multiple parties, one or more fee collector addresses can be set to one or more [PaymentSplitter](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/release-v4.9/contracts/finance/PaymentSplitter.sol) contracts. This contract will then receive the fees and send each beneficiary their share. The payout can be triggered by anyone.

There is a limitation we are very unlikely to ever experience: if `totalAmountOfTokensReceived * highestShareNumber` overflows, the contract will not release these funds anymore. As we are using it for fees, which are just a small fraction of the total amount of tokens or currency, we should not see this happening in practice. Choosing the number of shares as low as possible is recommended to be even safer. See `testLockingFunds` in [the PaymentSplitter tests](./test/PaymentSplitter.t.sol) for a demonstration of this limitation.

The PaymentSplitter contract will be removed in Openzeppelin contracts 5.0, but an updated version should be introduced in a later version. Until then, the 4.9.x version can be used. See [this PR](https://github.com/OpenZeppelin/openzeppelin-contracts/pull/4276).

## Implementation

### Fee settings

Tokenize.it will deploy and manage at least one [fee settings contract](../contracts/FeeSettings.sol). This contract implements the IFeeSettingsV2 interface and thus can be queried for:

- fee calculation:
  - `tokenFee(uint256 tokenBuyAmount)`
  - `continuousFundraisingFee(uint256 paymentAmount)`
  - `personalInviteFee(uint256 paymentAmount)`
- feeCollector addresses
  - `tokenFeeCollector()`
  - `continuousFundraisingFeeCollector()`
  - `personalInviteFeeCollector()`

These values can be changed by tokenize.it. Fee changes are subject to a delay of at least 12 weeks.

All fees are calculated as follows:

```solidity
fee = amount / feeDenominator
```

### Token contracts

- Each [token contract](../contracts/Token.sol) is connected to a [fee settings contract](../contracts/FeeSettings.sol).
- When X tokens are minted, the fee is X/tokenFeeDenominator tokens. These are minted ON TOP of the X tokens requested, and are transferred to the feeCollector.
- The fee settings contract used by token can be changed only by the owner of the current fee settings contract in collaboration with the token's DEFAULT_ADMIN_ROLE.

### Investment contracts

- The investment contracts [PersonalInvite](../contracts/PersonalInvite.sol) and [ContinuousFundraising](../contracts/ContinuousFundraising.sol) both access the fee setting through the token contracts they are connected to.
- ContinuousFundraising: When Y currency is paid, the fee is Y/continuousFundraisingFeeDenominator. This fee is DEDUCTED from the Y currency paid and transferred to the feeCollector.
- PersonalInvite: When Y currency is paid, the fee is Y/personalInviteFeeDenominator. This fee is DEDUCTED from the Y currency paid and transferred to the feeCollector.
