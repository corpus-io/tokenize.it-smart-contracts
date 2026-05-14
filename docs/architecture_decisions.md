# Architecture Decisions

This document records the reasons why certain approaches have been taken or rejected. It serves as a reference for understanding the rationale behind design choices, so that future contributors can make informed decisions and avoid revisiting already-resolved trade-offs.

---

## Lockups: One Contract per Lockup

**Decision:** Each lockup is managed by its own dedicated contract, rather than having a single contract manage multiple lockups.

**Rationale:** A single contract managing multiple lockups must maintain internal accounting (e.g. tracking how many tokens belong to each beneficiary). This accounting can silently diverge from the contract's actual token balance if tokens are added externally, burned, never added despite a lockup being created, or otherwise transferred outside the expected flow. Such discrepancies are hard to detect and can lead to incorrect releases or locked funds.

By giving each lockup its own contract, the token balance of that contract _is_ the lockup balance — no internal bookkeeping is required, and any unexpected change in balance is immediately visible and attributable.

---

## GlobalTokenExitRegistry: Centralized Exit Signal for Lockups

**Decision:** A single global `GlobalTokenExitRegistry` contract maps each token to its authorized `Exit` contract. `CoinvestedPosition` and `TimeLock` contracts consult this registry to determine whether an exit is in progress, and if so, allow beneficiaries to claim their proceeds regardless of any remaining lock period.

**Rationale:** In an exit scenario, beneficiaries must be able to receive their exit proceeds even if their tokens are still subject to a time lock or vesting schedule. The registry does not unlock tokens — it signals that an exit has been authorized for a given token, which is a distinct concept. Lockup contracts read this signal and bypass their time constraints only when routing proceeds to the exit contract, not when releasing tokens freely.

A single global registry is preferable to per-token or per-lockup registries because it requires no coordination at lockup deployment time: any lockup contract can look up the exit for its token at claim time without needing to know the exit address in advance.

The mapping is write-once: once an exit is registered for a token it cannot be changed. This prevents a compromised or reassigned admin from redirecting exit proceeds after beneficiaries have already begun to rely on the registered exit.

The authorization check accepts either the token's `DEFAULT_ADMIN_ROLE` holder or its `owner()`, wrapped in try/catch, so the registry works with both OZ `AccessControl`-based tokens (including the current `Token` contract) and simpler `Ownable`-only tokens without requiring changes to either.

---

## ERC2771Context: Duplicate Overrides in Every Contract

**Decision:** Each contract that uses `ERC2771ContextUpgradeable` alongside any other `ContextUpgradeable`-derived contract (e.g. `OwnableUpgradeable`, `AccessControlUpgradeable`) explicitly re-declares the three `_msgSender`, `_msgData`, and `_contextSuffixLength` overrides.

**Rationale:** Solidity's override resolution rule fires whenever multiple inheritance paths lead to the same function. An abstract base contract _can_ eliminate the per-contract boilerplate, but only if it inherits **all** the `ContextUpgradeable`-derived bases that the concrete contract uses — so that there is only one path to `ContextUpgradeable` and the base's non-virtual override is the unambiguous winner. The 10 affected contracts split across too many distinct combinations to make this viable:

| Combination                                                                                                | Contracts                                               |
| ---------------------------------------------------------------------------------------------------------- | ------------------------------------------------------- |
| `Ownable2StepUpgradeable`                                                                                  | PriceLinear, AllowList, Distribution, Exit, FeeSettings |
| `Ownable2StepUpgradeable` + `PausableUpgradeable`                                                          | Crowdinvesting                                          |
| `OwnableUpgradeable`                                                                                       | TimeLock, Vesting                                       |
| `OwnableUpgradeable` + `PausableUpgradeable`                                                               | TokenSwapBase                                           |
| `ERC20PermitUpgradeable` + `ERC20SnapshotUpgradeable` + `PausableUpgradeable` + `AccessControlUpgradeable` | Token                                                   |

Two base contracts would cover 7 of the 10 cases, but the saving is marginal and the indirection adds complexity. The overrides are therefore repeated in every affected contract by necessity, not by oversight.

---

## Clone Factories: Post-Deploy trustedForwarder Verification

**Decision:** After deploying a clone, each factory explicitly calls `isTrustedForwarder(_trustedForwarder)` on the new clone and reverts if the result is false.

**Rationale:** The `trustedForwarder` is an extremely privileged position: it can impersonate any address when calling contracts that implement ERC2771. If the logic contract were deployed with the wrong forwarder set (e.g. due to a misconfiguration or a compromised implementation), every clone created from it would silently inherit that wrong forwarder — giving an attacker the ability to act as any user across all deployed instances. The post-deploy check catches this at deployment time and prevents a bad clone from ever being returned to the caller.

---

## CoinvestedPosition: Pull Payouts and Owner-Driven Recovery

**Decision:** `CoinvestedPosition` never pushes currency to lead investors or to the co-investor. Each credit-side action (`buy`, `claimDistribution`, `claimExit`) adds to per-recipient pull balances; recipients withdraw on their own schedule. Additionally, the owner may rotate a lead investor's slot if that lead investor's `recoveryArmedAt` has been set for at least `LEAD_INVESTOR_RECOVERY_TIMEOUT` (90 days) without any withdrawal or self-rotation.

**Rationale:**

The contract is designed to support currencies like USDC / USDT / EURC that enforce blacklists inside the token contract. With a push model, a single blacklisted recipient would cause every credit-side action to revert: one bad address could indefinitely stall buys, dividend claims, and exit redemptions for everyone else on the contract. Pull payouts decouple the credit event from the transfer, so a revert affects only the recipient who attempts it. The co-investor (contract owner) additionally picks the destination at withdrawal time, so if their primary address gets blacklisted they can route to a fresh address without any contract intervention.

A lead investor who loses their keys can never claim, and their carry sits in the contract indefinitely. The owner-recovery mechanism addresses this and is gated by three properties to keep it from being easily exploitable by the owner:

1. **Per-lead-investor recovery timer (`recoveryArmedAt`)** armed only when that specific lead investor receives non-zero carry, and disarmed immediately by any withdrawal (in any currency) or self-rotation. The owner cannot manufacture the right to rotate by withholding claims — only credit events arm the timer, and the lead investor controls the disarm.
2. **A long minimum wait** (`LEAD_INVESTOR_RECOVERY_TIMEOUT`, 90 days). The window is large enough that a live lead investor has ample opportunity to respond. Legal teams pick the literal pre-deployment.
3. **No post-deploy mutability of the timeout.** The constant is `public constant`, not a storage value, so the owner cannot shrink it before rotating.

A simpler design was considered and rejected: a single global activity timer over all credit-side actions. That fails because most credit events are `onlyOwner` (`claimDistribution`, `claimExit`), so the owner could trivially game it by suppressing claims. The per-lead-investor timer ties the recovery right to a signal the owner does not control.
