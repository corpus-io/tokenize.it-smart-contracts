# Dividends, Distributions and Exit

## Dividend Distribution

Token holders can receive dividend payouts proportional to their token balance at a specific point in time. This is implemented using the [Token.sol](../contracts/Token.sol) snapshot mechanism and the [Distribution.sol](../contracts/Distribution.sol) contract.

### Workflow

1. **Snapshot**: The token admin calls `snapshot()` on the Token contract. This freezes every holder's balance under a `snapshotId`. The timing is critical: it must happen before any tokens change hands in anticipation of the dividend.

2. **Deploy Distribution**: The company (or platform) clones a Distribution contract via `DistributionCloneFactory`, providing:

   - `token` and `snapshotId`
   - `currency`: the ERC-20 token used for payouts (must have `TRUSTED_CURRENCY` on the AllowList)
   - `pricePerToken`: currency payout in smallest currency units per full token unit (same unit convention as `tokenPrice` in TokenSwap)
   - `lockedUntil`: timestamp from which unclaimed funds can be redirected or drained
   - `initialReassignments` (optional): reassignments applied immediately at initialization, bypassing the time restriction

   Optionally, the contract can be funded at initialization by providing a `_currencyProvider` and `_initialFundingAmount`.

3. **Holders claim**: Any holder at snapshot time calls `Distribution.claim(recipient, minPayout)`. Their gross share is `balanceAtSnapshot * pricePerToken / 10**token.decimals()`. The platform fee (`distributionFee`) is deducted per claim, and the net remainder is sent to `recipient`. Smart contract holders (e.g. CoinvestedPosition) can call `claim()` directly or have the owner use `reassign()` to redirect their share.

4. **Reassignment** (recovery): If a holder cannot claim (lost key, broken smart contract), the owner can call `reassign(from, to, amount)` after `lockedUntil` to redirect that share. Every reassignment is recorded on-chain via the `Reassigned` event.

5. **Drain**: After `lockedUntil`, the owner can call `drain(recipient, token)` to recover any ERC-20 tokens held by the contract (including unclaimed currency).

### CoinvestedPosition integration

A `CoinvestedPosition` contract holding tokens at snapshot time can claim its share via `claimDistribution(dist, minPayout)`. The received dividend is treated entirely as carry-eligible profit and credited to the contract's per-recipient pull balances: lead investors get their carry shares, the co-investor gets the remainder. Each recipient withdraws on their own schedule via `withdrawAsLeadInvestor` / `withdrawAsCoinvestor` — see [dev_overview.md](dev_overview.md#coinvestedposition-coinvestedpositionsol) for the pull-payout model.

---

## Exit

When a company is acquired or wound down, it can set up an automated exit contract that lets holders redeem their tokens for a fixed cash payout. This is implemented in [Exit.sol](../contracts/Exit.sol).

### Workflow

1. **Deploy Exit**: The company clones an Exit contract via `ExitCloneFactory`, providing:

   - `token`: the token to be redeemed
   - `currency`: the payout currency (must have `TRUSTED_CURRENCY` on the AllowList — typically EURe)
   - `pricePerToken`: currency payout in smallest currency units per full token unit (same unit convention as `tokenPrice` in TokenSwap)
   - `lockedUntil`: timestamp after which the owner can drain unclaimed funds
   - `referenceCurrencies` / `referenceToExitRates` (optional): exchange rates from reference currencies to the exit currency, used by CoinvestedPosition to convert carry when the position currency differs from the exit currency

   The full `_initialFundingAmount` is transferred from the funder to the Exit contract at initialization (no fee is taken here).

2. **Holders claim**: Any holder calls `claim(recipient, minPayout)`. The contract always redeems the caller's entire token balance. It:

   - Transfers the caller's full token balance to itself (tokens are held, not burned)
   - Calculates gross payout: `tokenBalance * pricePerToken / 10**token.decimals()`
   - Deducts `exitFee` and sends it to the fee collector
   - Sends net payout to `recipient`; reverts if net payout is below `minPayout`

3. **Drain**: After `lockedUntil`, the company can call `drain(recipient, token)` to recover any ERC-20 tokens held by the contract (unclaimed currency, accumulated exit tokens, etc.).

### Security considerations

There is no on-chain enforcement that `initialFundingAmount` equals `totalTokenSupply × pricePerToken`. The exit can therefore be partially funded by design (e.g. if not all holders are expected to claim), but it also means a rogue admin could mint additional tokens after the exit is deployed, and use those to drain the exit contract. The price per token remains fixed — but the currency balance may run out, causing the last claims to revert.

### CoinvestedPosition integration

A `CoinvestedPosition` can participate in an exit via `claimExit(minCurrencyAmount, basePrice)`. It looks up the exit contract for its token in the `GlobalTokenExitRegistry` and reverts if none is registered. It then redeems its full token balance and credits the proceeds to per-recipient pull balances, following the internal accounting logic. Recipients withdraw on their own schedule — see [dev_overview.md](dev_overview.md#coinvestedposition-coinvestedpositionsol) for the pull-payout model.

When the exit currency differs from the position's stored currency, `claimExit` converts the stored `basePrice` using the exchange rate the exit contract provides for that currency pair. If no rate is available, the caller must supply a `basePrice` expressed in the exit currency's units.

---

## GlobalTokenExitRegistry

The [GlobalTokenExitRegistry.sol](../contracts/GlobalTokenExitRegistry.sol) is a singleton contract that maps each token to its authorized `Exit` contract. It allows lockup contracts such as `TimeLock` and `CoinvestedPosition` to look up the exit for a given token at claim time, without needing to know the exit address at deployment.

- Only a token's `DEFAULT_ADMIN_ROLE` holder or its `owner()` can register an exit for that token.
- Once set, the mapping is immutable: the exit cannot be replaced or removed.
- The registry emits an `ExitSet` event for every registration, providing an on-chain audit trail.

Lockup contracts consult the registry when processing an exit claim. If no exit is registered for the token, the claim reverts.

---

## Summary of differences

| Feature                          | Distribution                      | Exit                         |
| -------------------------------- | --------------------------------- | ---------------------------- |
| Snapshot required                | Yes                               | No                           |
| Token fate                       | Held by token holder throughout   | Transferred to Exit contract |
| Recovery mechanism to help users | `reassign()` by owner after delay | mint & burn                  |
