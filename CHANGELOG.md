# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [7.1.0] - 2026-07-15

This release adds a payout layer (dividends and exits), a co-investment vehicle with profit-sharing, a minimal timelock that participates correctly in payouts, and a fully generalized fee system. The new contracts were audited by Hacken; the final report is included in `audits/2026-07_Hacken.pdf`.

### Added

- **`Distribution.sol`** — proportional dividend distribution against an ERC20 snapshot. Cloneable, fee-aware, supports `claim()` and `reassign()` of unclaimed funds after a cooldown. Accepts `initialReassignments` at init so operators can resolve legacy lockups upfront without waiting for the cooldown.
- **`Exit.sol`** — fixed-price token redemption. Holders send tokens and receive currency at a configured rate; tokens are retained (not burned). Configurable claim window with `drain()` afterward. Supports currency conversion rates, so the exit currency may differ from the base price currency.
- **`GlobalTokenExitRegistry.sol`** — write-once map of `token → authorized Exit`. The authoritative source for which `Exit` is valid for a token; consulted by lockup contracts. Supports `Ownable` tokens as registrants.
- **`CoinvestedPosition.sol`** — holds tokens on behalf of a co-investor and splits sale proceeds between lead investors (profit fraction) and the co-investor. Starts paused, unpauses only after `lockedUntil`. Participates in `Distribution` and `Exit` while locked.
- **`TimeLock.sol`** — minimal contract holding ERC20 tokens until `lockedUntil`. Can `claimDistribution()` and `claimExit()` while locked; `drain()` is blocked until unlock. Replaces the prior pattern of using `Vesting.sol` as a timelock, which couldn't claim distributions.
- **`FeeDistributor.sol`** — splits incoming fees across multiple recipients.
- Each new contract ships with a matching clone factory.
- Dedicated fee types for **Distribution** and **Exit** in `FeeSettings`.

### Changed

- **FeeSettings — dynamic fee types (BREAKING)**: the three hardcoded fee types (TOKEN, CROWDINVESTING, PRIVATE_OFFER) with fixed caps (5% / 10% / 5%) are gone. Fee types are now `bytes32` keys registered with configurable caps and defaults, and new product lines can be added without an upgrade.
  - Custom per-token discounts and collector overrides are now keyed by `(feeType, token)`.
  - The 12-week activation delay for fee increases is preserved, per type.
  - V1 and V2 read interfaces (`tokenFee`, `crowdinvestingFee`, `privateOfferFee`, matching collectors) still work. ERC-165 reports V1, V2, and the new V3.
  - **Breaking for tooling**: `planFeeChange(Fees)`, `executeFeeChange()`, `setCustomFee(address, Fees)`, and the six per-type collector setters/removers are replaced by generic functions taking `bytes32 feeType` as the first argument. Events change accordingly. Hardcoded fee constants are removed.
- **PrivateOfferFactory (BREAKING)**: `deployPrivateOfferWithTimeLock` no longer takes five vesting-specific parameters — only `lockedUntil` and `timeLockOwner`. A new entry point deploys a `PrivateOffer` together with a `CoinvestedPosition`.
- **Custom errors (BREAKING)**: all contracts now revert with Solidity custom errors instead of string messages. Generic errors (`ZeroAddress`, `ZeroAmount`, `UntrustedCurrency`, …) are exported from `contracts/common/Errors.sol`; contract-specific errors are declared inside the contract that throws them. Off-chain code that matched on revert strings needs to be updated to decode error selectors.
- **Solidity upgraded from 0.8.23 to 0.8.34** (latest stable at the time; fixes an IR-pipeline bug relevant to via-ir builds).
- `SafeERC20` is now used for all token transfers, including the protocol's own token.
- **Burn semantics**: `Token` burn permission no longer allows arbitrary destruction; the scope is reduced. Existing fee-collector compliance bypass is closed.
- **Crowdinvesting purchase limit** now enforced per buyer rather than per receiver.
- **Crowdinvesting price/currency updates** are no longer asymmetric — a currency change must be paired with a synchronized price update; new prices are not effective immediately when the prior parameters allowed a shorter window.
- **PriceLinear** rejects zero prices and validates the base price at initialization.
- **Vesting.commit** no longer overwrites an existing commitment (including revoked or already-revealed hashes).
- **Ownership transfers** are now two-step (`Ownable2Step`) on contracts that previously used single-step transfer.
- **Renames**: `FeeSplitter` → `FeeDistributor` (contract and factory); `Exit.claimEnd` → `Exit.drainStart`.

### Removed

- `contracts/interfaces/` directory — `IFeeSettings.sol` and `IPriceDynamic.sol` are now under `contracts/common/`. Update imports.

### Security

- Reentrancy guards added on payout paths (`Distribution`, `Exit`, `TimeLock`).
- `Distribution._reassign` rejects self-reassignment.

### Fixed

- Since 7.1.0-beta1: **`CoinvestedPosition.claimExit`** — when the exit currency differs from the position's stored currency, the base portion is now converted to the exit currency on the aggregate value instead of on the per-token price. The old per-token conversion floored the price to whole exit-currency units before multiplying by the balance, which understated the base portion (and thus overstated lead-investor carry) whenever the stored currency had more decimals than the exit currency. Thanks to @dieking2000 for flagging this issue.

### Migration notes

- **FeeSettings consumers**: switch tooling to the V3 generic functions (`bytes32 feeType` first arg). V1/V2 read interfaces continue to work.
- **PrivateOffer + lockup**: move from `deployPrivateOfferWithTimeLock(...vesting args...)` to the simplified `(lockedUntil, timeLockOwner)` signature, or use `CoinvestedPosition` for co-investment.
- **Legacy `Vesting`-locked balances in a distribution**: use `initialReassignments` at `Distribution` init to resolve affected holders upfront, instead of post-hoc `reassign()` per distribution.
- **Exit eligibility lookups**: query `GlobalTokenExitRegistry` instead of any per-token mechanism.

## [7.0.0-alpha3] - 2026-04-20

- Solidity upgraded from 0.8.23 to 0.8.34.
- Custom error reverts instead of string reverts.
- `SafeERC20` used everywhere, including the protocol's own token.
- Renamed `FeeSplitter` to `FeeDistributor`; extended its documentation.

## [7.0.0-alpha] - 2026-04-17

First preview of dynamic fee types, syndicates (co-investment), and payouts for token holders (distributions and exits).

## [6.1.0] - 2025-12-19

### Added

- `PrivateOffer` and `Crowdinvesting` can now transfer existing tokens to the buyer instead of minting new ones.
- **`TokenSwap.sol`** — dedicated secondary-market contract representing a buy or sell offer that others can accept.

### Changed

- Incorporated changes from the Hacken audit.
- Since 6.0.0-beta: `TokenSwap` no longer has `setHolder`.

## [6.0.0-beta] - 2025-11-07

Preview of transfer-on-buy for `PrivateOffer` / `Crowdinvesting` and the new `TokenSwap` contract. Updated Foundry, Hardhat, and forge-std.

## [5.0.2] - 2024-03-14

### Changed

- Updated OpenZeppelin dependencies (fixes an encoding issue).
- Division by zero now reverts explicitly.
- Added Gnosis Chain deployment support and documented the Crowdinvesting deployment.

## [5.0.1] - 2024-01-05

### Changed

- Factory implementation addresses are now public.
- Vesting lockup creation moved from `PrivateOfferFactory` to `VestingCloneFactory`, so it can be used independently of `PrivateOffer`.

## [5.0.0] - 2023-12-14

Audited by [ConsenSys Diligence](https://consensys.io/diligence/audits/2023/12/tokenize-it/).

### Added

- `Token` balance snapshots.
- `Token` is now upgradeable via UUPS proxy (`createTokenProxy` replaces `createTokenClone`).
- **`Vesting.sol`** replaces the previous vesting contracts for employee participation.
- More powerful factories, e.g. `PrivateOfferFactory.deployPrivateOfferWithTimeLock` deploys an offer with lockup in one transaction.
- `AllowList`: ERC-2771 support, clone factory, batch add/remove of addresses (including clone-and-fill in one transaction).
- `FeeSettings`: managers can be added/removed and can set or remove custom fees and custom fee collectors.
- `Crowdinvesting`: dynamic pricing (`PriceLinear`) and auto stop date (`lastBuyDate`).

### Changed

- Contracts renamed: `ContinuousFundraising` → `Crowdinvesting`, `PersonalInvite` → `PrivateOffer`.
- Some function arguments are now passed as structs.

## [5.0.0-beta0] - 2023-12-08

Minor fixes and internal refactorings on the way to 5.0.0.

## [4.2.1] - 2023-11-07

### Added

- Naive `TokenFactory.sol` capable of deterministic CREATE2 deployments.
- Constructor arguments file for verification.

### Changed

- Higher fee ceiling for `ContinuousFundraising`.
- Backported fee numerator handling and zero-denominator check from the v5 line.
- Extended natspec documentation; dependency bumps.

## [4.2.0-beta.0] - 2023-08-17

Adds a naive token factory `TokenFactory.sol`, capable of deterministic deployments via CREATE2.

## [4.0] - 2023-03-23

### Added

- npm package [`@tokenize.it/contracts`](https://www.npmjs.com/package/@tokenize.it/contracts) for deploying and interacting with the contracts.
- DAI as supported currency.

### Changed

- **BREAKING**: `ContinuousFundraising.buy()` and `PersonalInvite` now support two separate investor addresses — a currency payer and a token receiver.
- License changed to AGPL-3.0-only.

## [3.1] - 2022-12-20

### Added

- ERC-165 support in `FeeSettings`.
- `DeployPlatform` script and documentation.

### Security

- Fee updates from 0 to a non-zero value now require the activation delay.
- Reduced fee collector rights.

## [3.0] - 2022-12-09

### Changed

- Incorporated Hacken audit findings.
- `Ownable` → `Ownable2Step`.
- Minting reverts instead of returning `false` on failure.
- Minting allowances can be increased/decreased instead of only set.
- Restructured fee calculation; reduced external calls.

## [2.4] - 2022-11-28

Typo fixes.

## [2.3] - 2022-11-28

Use `_msgSender()` consistently; typo fixes.

## [2.2] - 2022-11-27

Removed the minter role; documentation updates and minor improvements.

## [2.1] - 2022-11-23

Freeze for audit (same content as 2.0, prettified).

## [2.0] - 2022-11-23

Freeze for audit.

### Added

- Meta-transactions with EIP-2771 and EIP-2612 (permit).
- `PersonalInvite` reworked to use CREATE2.
- Fee collection.
- `SafeERC20`; reentrancy guard instead of `bool active`.
- Mainnet fork tests with WETH, WBTC, USDC, EUROC.

## [1.0] - 2022-10-13

First freeze for pre-audit.

[unreleased]: https://github.com/corpus-io/tokenize.it-smart-contracts/compare/v7.1.0...HEAD
[7.1.0]: https://github.com/corpus-io/tokenize.it-smart-contracts/compare/v6.1.0...v7.1.0
[7.0.0-alpha3]: https://github.com/corpus-io/tokenize.it-smart-contracts/compare/v7.0.0-alpha...v7.0.0-alpha3
[7.0.0-alpha]: https://github.com/corpus-io/tokenize.it-smart-contracts/compare/v6.1.0...v7.0.0-alpha
[6.1.0]: https://github.com/corpus-io/tokenize.it-smart-contracts/compare/v6.0.0-beta...v6.1.0
[6.0.0-beta]: https://github.com/corpus-io/tokenize.it-smart-contracts/compare/v5.0.2...v6.0.0-beta
[5.0.2]: https://github.com/corpus-io/tokenize.it-smart-contracts/compare/v5.0.1...v5.0.2
[5.0.1]: https://github.com/corpus-io/tokenize.it-smart-contracts/compare/v5.0.0...v5.0.1
[5.0.0]: https://github.com/corpus-io/tokenize.it-smart-contracts/compare/v4.2.1...v5.0.0
[5.0.0-beta0]: https://github.com/corpus-io/tokenize.it-smart-contracts/compare/v4.2.1...v5.0.0-beta0
[4.2.1]: https://github.com/corpus-io/tokenize.it-smart-contracts/compare/v4.0...v4.2.1
[4.2.0-beta.0]: https://github.com/corpus-io/tokenize.it-smart-contracts/compare/v4.0...v4.2.0-beta.0
[4.0]: https://github.com/corpus-io/tokenize.it-smart-contracts/compare/v3.1...v4.0
[3.1]: https://github.com/corpus-io/tokenize.it-smart-contracts/compare/v3.0...v3.1
[3.0]: https://github.com/corpus-io/tokenize.it-smart-contracts/compare/v2.4...v3.0
[2.4]: https://github.com/corpus-io/tokenize.it-smart-contracts/compare/v2.3...v2.4
[2.3]: https://github.com/corpus-io/tokenize.it-smart-contracts/compare/v2.2...v2.3
[2.2]: https://github.com/corpus-io/tokenize.it-smart-contracts/compare/v2.1...v2.2
[2.1]: https://github.com/corpus-io/tokenize.it-smart-contracts/compare/v2.0...v2.1
[2.0]: https://github.com/corpus-io/tokenize.it-smart-contracts/compare/v1.0...v2.0
[1.0]: https://github.com/corpus-io/tokenize.it-smart-contracts/releases/tag/v1.0
