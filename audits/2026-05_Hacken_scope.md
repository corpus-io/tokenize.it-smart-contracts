## Audit Scope

The invariants defined in [`docs/invariants.md`](../docs/invariants.md) apply to all contracts listed below and are considered part of this scope.

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

### Out of Scope

- All factory contracts (`contracts/factories/`)
- `Token`
- `Crowdinvesting`
- `PrivateOffer`
- `Vesting`
- `AllowList`
- `PriceLinear`
- `IPriceDynamic`
