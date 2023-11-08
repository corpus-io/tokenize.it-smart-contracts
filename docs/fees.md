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

Fees are collected during investments and token minting. They are paid both in the investment currency (-> see publicFundraisingFeeDenominator and privateOfferFeeDenominator in [FeeSettings.sol](../contracts/FeeSettings.sol)) and the token minted (-> see tokenFeeDenominator in [FeeSettings.sol](../contracts/FeeSettings.sol)).

**Example**:
Investor buys X tokens for Y USDC through the PublicFundraising contract.

- X tokens are minted to the investor
- X/tokenFeeDenominator tokens are minted to the feeCollector
- So the company mints a total of X + X/tokenFeeDenominator tokens in this transaction
- Investor pays Y USDC
- Y/publicFundraisingFeeDenominator USDC goes to the feeCollector
- So the company receives Y - Y/publicFundraisingFeeDenominator USDC in this transaction
- In total, the company minted X + X/tokenFeeDenominator tokens and received Y - Y/publicFundraisingFeeDenominator USDC. It paid fees both in token and currency.
- The investor pays Y USDC for X tokens, like they expected. They did not pay fees.

### Interpretation

The smart contracts assume that the fees are paid by the company. The company will receive less currency and mint more tokens than the investor pays for. The investor will receive the tokens they paid for, and will not pay fees.

It is, however, possible to interpret the fees as paid by the investor. In this case, the relative fee and the price have to be adapted and do not refer to the price the company offers the investor on a 1:1 base anymore.

### Fee limits

The minimum fee is 0.

Maximum fees are:

- 5% of tokens minted
- 5% of currency paid when using PrivateOffer
- 10% of currency paid when using PublicFundraising

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
  - `publicFundraisingFee(uint256 paymentAmount)`
  - `privateOfferFee(uint256 paymentAmount)`
- feeCollector addresses
  - `tokenFeeCollector()`
  - `publicFundraisingFeeCollector()`
  - `privateOfferFeeCollector()`

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

- The investment contracts [PrivateOffer](../contracts/PrivateOffer.sol) and [PublicFundraising](../contracts/PublicFundraising.sol) both access the fee setting through the token contracts they are connected to.
- PublicFundraising: When Y currency is paid, the fee is Y/publicFundraisingFeeDenominator. This fee is DEDUCTED from the Y currency paid and transferred to the feeCollector.
- PrivateOffer: When Y currency is paid, the fee is Y/privateOfferFeeDenominator. This fee is DEDUCTED from the Y currency paid and transferred to the feeCollector.

## Discounts

Fee discounts can be realized in two ways, which will be explained in the next paragraphs.

### On-chain discounts

The platform can deploy a new FeeSettings contract for a founder or a group of founders. If a new token is deployed, it can use the new FeeSettings contract straight away. Existing tokens can switch to the new FeeSettings contract when the platform proposes the switch and the founder accepts it.

The new FeeSettings contract can provide reduced fees, for example 0.5% instead of 1%.

If the discount should only be valid for a certain duration, the platform can update the parameters of the FeeSettings contract after the discount period has ended. The new parameters can be the same as those of the old FeeSettings contract. In this case, the founders would not benefit from a discount anymore.

If the platform wants to encourage the founders to switch back to the old FeeSettings contract, it can do so by increasing the fees in the new contract beyond the settings in the old one and proposing a switch back to the old contract. The founders can then accept the switch back to the old contract and benefit from the lower fees again.

### Off-chain discounts

The platform can also offer discounts off-chain. For example, the platform can offer a discount to a founder for a certain duration and refund the difference between the discounted fee and the regular fee to the founder.

The refund can be executed on-chain or off-chain.

This approach is more flexible than the on-chain approach, and provides better privacy.
