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

Fees are collected during investments and token minting, but from founders only. They are paid both in the investment currency (-> see investmentFeeDenominator in [FeeSettings.sol](../contracts/FeeSettings.sol)) and the token minted (-> see tokenFeeDenominator in [FeeSettings.sol](../contracts/FeeSettings.sol)).

**Example**:
Investor buys X tokens for Y USDC through the ContinuousFundraising contract.

- X tokens are minted to the investor
- X/tokenFeeDenominator tokens are minted to the feeCollector
- So the company mints a total of X + X/tokenFeeDenominator tokens in this transaction
- Investor pays Y USDC
- Y/investmentFeeDenominator USDC goes to the feeCollector
- So the company receives Y - Y/investmentFeeDenominator USDC in this transaction
- In total, the company minted X + X/tokenFeeDenominator tokens and received Y - Y/investmentFeeDenominator USDC. It paid fees both in token and currency.
- The investor pays Y USDC for X tokens, like they expected. They did not pay fees.

### Fee limits

Maximum fee is 5%, minimum fee is 0.

## Implementation

### Fee settings

Tokenize.it will deploy and manage at least one [fee settings contract](../contracts/FeeSettings.sol). This contract can be queried for:

- investmentFeeDenominator
- tokenFeeDenominator
- feeCollector address

These values can be changed by tokenize.it. Fee changes are subject to a delay of at least 12 weeks.

Both fees are calculated as follows:

```solidity
if (feeDenominator == UINT256_MAX) {
   fee = 0;
}
else {
   fee    = amount / feeDenominator
}
```

Taking into account the [limits](#fee-limits), the following is enforced for all denominators:

```solidity
denominator >= 20
```

### Token contracts

- Each [token contract](../contracts/Token.sol) is connected to a [fee settings contract](../contracts/FeeSettings.sol).
- When X tokens are minted, the fee is X/tokenFeeDenominator tokens. These are minted ON TOP of the X tokens requested, and are transferred to the feeCollector.
- The fee settings contract used by token can be changed only by the owner of the current fee settings contract.

### Investment contracts

- The investment contracts [PersonalInvite](../contracts/PersonalInvite.sol) and [ContinuousFundraising](../contracts/ContinuousFundraising.sol) both access the fee setting through the token contracts they are connected to.
- When Y currency is paid, the fee is Y/investmentFeeDenominator. This fee is DEDUCTED from the Y currency paid and transferred to the feeCollector.
