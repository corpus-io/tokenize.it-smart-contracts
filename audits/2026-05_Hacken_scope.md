# Commit to audit

Tag: [`v7.0.0-alpha`](https://github.com/corpus-io/tokenize.it-smart-contracts/releases/tag/v7.0.0-alpha)
Commit: `2ea57fe2c58069c48ff35eea2e149c1ced228a31`

---

# Scope

## In scope

The invariants defined in [`docs/invariants.md`](../docs/invariants.md) apply to all contracts listed below and are considered part of the audit scope.

### New Contracts

These need a full review:

- `CoinvestedPosition`
- `TokenSwapBase`
- `PayoutBase`
- `Distribution`
- `Exit`
- `GlobalTokenExitRegistry`
- `TimeLock`

---

### Updated Contracts

- `TokenSwap`: Review refactoring to extend `TokenSwapBase`.
- `FeeSettings` (V3): Review new inner architecture, and backwards compatibility with V1/V2 callers.
- `PrivateOfferFactory`: Review deployments of `CoinvestedPosition` with `PrivateOffer`.

---

## Out of Scope

- All factory contracts (`contracts/factories/`)
- docs (in `docs/`), except for `docs/invariants.md`
- `Token`
- `Crowdinvesting`
- `PrivateOffer`
- `Vesting`
- `AllowList`
- `PriceLinear`
- `IPriceDynamic`
- `FeeSplitter`

# Requested Analysis Depth

For all in-scope contracts, we request analysis covering at minimum:

- **Loss of funds** — any path by which user or protocol funds can be stolen, permanently locked, or drained, including reentrancy and incorrect accounting across the three `CoinvestedPosition` payout paths.
- **Privilege escalation / hostile takeover** — unauthorized acquisition of privileged roles, initializer exploits, and ambiguity between dual access-control paths (e.g. `DEFAULT_ADMIN_ROLE` vs `owner()` in `GlobalTokenExitRegistry`).
- **Arithmetic and precision exploits** — rounding manipulation, precision loss, and invariant violations in financial calculations (carry split, proportional distribution, fee computation, redemption rate).
- **Business logic flaws** — deviations from the stated specification, including incorrect interaction sequencing across `TimeLock`, `GlobalTokenExitRegistry`, `CoinvestedPosition`, `Distribution`, and `Exit`.
- **Trust-boundary violations** — privileged actors able to change terms mid-flight in ways that harm counterparties (e.g. redirecting payouts, altering price or window after funds are committed).
- **Denial of service / griefing** — vectors that permanently or temporarily block legitimate claims, redemptions, or distributions.

---

# Fix Review

We expect to address all findings identified during the audit. We request that fixes be reviewed and the results included in the final report.
