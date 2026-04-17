## In scope

The invariants defined in [`docs/invariants.md`](../docs/invariants.md) apply to all contracts listed below and are considered part of the audit scope.

### New Contracts

**`CoinvestedPosition`**
Full review. New contract with non-trivial payout logic (base price, carry split, balance sweep across three distribution paths). Includes timelock integration and `GlobalTokenExitRegistry` interaction.

**`TokenSwapBase`**
Full review. Abstract base extracted from `TokenSwap` and `CoinvestedPosition`. Pay special attention to correctness of the extraction — any logic bugs introduced during refactoring.

**`Distribution`**
Full review. Distributes currency proportional to token snapshot balances. Includes `reassign` recovery function.

**`Exit`**
Full review. Token redemption within a configurable window.

**`GlobalTokenExitRegistry`**
Full review. One-time-per-token registration, dual access control (`DEFAULT_ADMIN_ROLE` / `owner()`), try/catch error handling.

**`TimeLock`**
Full review. Lockup with three claim paths: `drain`, `claimDistribution`, `claimExit`. Exit bypass logic (interaction with `GlobalTokenExitRegistry`).

---

### Updated Contracts

**`TokenSwap`**
Review refactoring to extend `TokenSwapBase`. Confirm no behavioral changes to the external interface. Review new `unpause()` precondition (`tokenPrice != 0`).

**`FeeSettings` (V3)**
Review new `registerFeeType` mechanism, `IFeeSettingsV3` generic accessors, and backwards compatibility with V1/V2 callers. Review fallback logic in `TokenSwap` and `CoinvestedPosition` (V3 detection via `supportsInterface`).

**`IFeeSettingsV3`**, **`IExit`**, **`IDistribution`**
Review interface definitions for correctness and completeness.

---

## Requested Analysis Depth

For all in-scope contracts, we request analysis covering at minimum:

- **Loss of funds** — any path by which user or protocol funds can be stolen, permanently locked, or drained, including reentrancy and incorrect accounting across the three `CoinvestedPosition` payout paths.
- **Privilege escalation / hostile takeover** — unauthorized acquisition of privileged roles, initializer exploits, and ambiguity between dual access-control paths (e.g. `DEFAULT_ADMIN_ROLE` vs `owner()` in `GlobalTokenExitRegistry`).
- **Arithmetic and precision exploits** — rounding manipulation, precision loss, and invariant violations in financial calculations (carry split, proportional distribution, fee computation, redemption rate).
- **Business logic flaws** — deviations from the stated specification, including incorrect interaction sequencing across `TimeLock`, `GlobalTokenExitRegistry`, `CoinvestedPosition`, `Distribution`, and `Exit`.
- **Trust-boundary violations** — privileged actors able to change terms mid-flight in ways that harm counterparties (e.g. redirecting payouts, altering price or window after funds are committed).
- **Denial of service / griefing** — vectors that permanently or temporarily block legitimate claims, redemptions, or distributions.

---

## Fix Review

We expect to address all findings identified during the audit. We request that fixes be reviewed and the results included in the final report.

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
