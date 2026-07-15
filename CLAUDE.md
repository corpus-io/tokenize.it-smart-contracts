# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

```bash
# Build
export FOUNDRY_PROFILE=fastDev && forge build   # fast dev build (via-ir=false)
FOUNDRY_PROFILE=fastDev yarn build                                        # hardhat build + TypeScript types

# Test
FOUNDRY_PROFILE=fastDev yarn test                # all tests except mainnet fork tests
FOUNDRY_PROFILE=fastDev forge test --no-match-test Mainnet               # same, direct forge invocation
FOUNDRY_PROFILE=fastDev forge test --match-test Mainnet --fork-url <rpc> # mainnet fork tests (need Infura/Alchemy RPC)
FOUNDRY_PROFILE=fastDev forge test --match-path test/Foo.t.sol           # single test file
FOUNDRY_PROFILE=fastDev forge test --match-test testFoo                  # single test by name

# Backwards-compatibility tests
make test-backwards-compatibility                # installs old npm packages and runs legacy tests

# Format
yarn prettier                                    # Solidity + TS + markdown (auto-format on save in VSCode)

# Coverage
FOUNDRY_PROFILE=fastDev yarn coverage                                    # generates HTML coverage report
```

**Always use `FOUNDRY_PROFILE=fastDev`** for development builds and tests — it disables `via-ir` and is dramatically faster. The default profile (`via-ir=true`) is for production builds only.

## Foundry Profiles

| Profile                   | via-ir | Use for                    |
| ------------------------- | ------ | -------------------------- |
| `default`                 | true   | Production / CI            |
| `fastDev`                 | false  | All local development      |
| `release`                 | true   | Deployment artifacts       |
| `backwards-compatibility` | false  | Legacy compatibility tests |

## Architecture

The protocol enables compliant, tokenized equity issuance. There are four main layers:

### Token Layer

- **Token.sol** — ERC20 with UUPS proxy (the _only_ upgradeable contract). Uses `AccessControl` with roles: `MINTALLOWER_ROLE`, `BURNER_ROLE`, `REQUIREMENT_ROLE`, `PAUSER_ROLE`, `TRANSFERERADMIN_ROLE`, `TRANSFERER_ROLE`, `SNAPSHOTCREATOR_ROLE`. Transfer gating via `AllowList`.
- **AllowList.sol** — Maps addresses to bitmask requirements for compliance gating.
- **FeeSettings.sol** — Manages platform fees per fee type. Default numerators have a 12-week activation delay for increases. Per-token custom fees can override defaults if lower.
- **GlobalTokenExitRegistry.sol** — Write-once map of token → authorized `Exit` contract. Used by lockup contracts to discover exit eligibility.

### Investment Layer

- **PrivateOffer.sol** — Single-investor offering at fixed price, deployed via CREATE2. Can be combined with `TimeLock` or `CoinvestedPosition`.
- **Crowdinvesting.sol** — Open fundraising at fixed price. Pausable with a 1-hour unpause delay (frontrunning protection). Cap via `maxAmountOfTokenToBeSold`.

### Secondary Market / Lockup Layer

- **TokenSwap.sol** / **TokenSwapBase.sol** — Secondary market trades (no minting). `TokenSwapBase` is the abstract base shared by `TokenSwap` and `CoinvestedPosition`.
- **CoinvestedPosition.sol** — Holds co-investor tokens. Initialized paused; unpauses only after `lockedUntil`. Supports carry distribution to lead investors via `profitFraction`. Lead investors list stored inside the contract.
- **TimeLock.sol** — Holds tokens until `lockedUntil`. Allows `claimDistribution()` and `claimExit()` during lock but blocks `drain()`.
- **Vesting.sol** — Linear vesting (largely superseded by `TimeLock` for new work).

### Payout Layer

- **Distribution.sol** — Distributes currency proportional to an ERC20 snapshot. Supports `reassign()` after lockup for unclaimed funds.
- **Exit.sol** — Fixed-price token redemption. Holders send tokens, receive currency; tokens held (not burned).

### Factories

Every contract is deployed through a factory (clone or UUPS proxy pattern — `Token` is the only UUPS proxy). Factories live in `contracts/factories/`. All factories verify `isTrustedForwarder()` post-deploy to guard against bytecode misconfiguration.

### Common Infrastructure

- `contracts/common/Errors.sol` — Generic top-level errors (`ZeroAddress`, `ZeroAmount`, `UntrustedCurrency`, etc.)
- `contracts/common/IFeeSettings.sol` — V1/V2/V3 fee settings interfaces with fallback compatibility
- `contracts/common/TokenSwapBase.sol` — Shared state and logic for `TokenSwap` / `CoinvestedPosition`
- `contracts/common/PayoutBase.sol` — Shared logic for `Distribution` / `Exit`

### ERC-2771 Meta-Transactions

All contracts accept a `trustedForwarder` in their constructor (immutable). Because of OZ's multiple-inheritance diamond, every contract that uses ERC2771 must explicitly re-declare `_msgSender`, `_msgData`, and `_contextSuffixLength` overrides — this is intentional and documented in `docs/architecture_decisions.md`.

## Code Style

- Solidity version: `pragma solidity 0.8.34;` — pinned, no `^` or `~`
- License: `AGPL-3.0-only`
- Line width: 120 characters
- Double quotes in Solidity strings
- **No shorthand variable names** — use full descriptive names (`leadInvestor`, not `li`; `feeSettings`, not `fs`)
- **Custom errors**: generic errors → `contracts/common/Errors.sol`; contract-specific errors → inside the contract; never in interfaces
- Use `require(condition, CustomError(args))` syntax
- Ownership: `Ownable2Step` (two-step transfers); never mix `Ownable` and `AccessControl` in the same contract
- All natspec on public contracts, functions, events, and errors

## Testing Conventions

- No empty `vm.expectRevert()` — always specify the error selector or encoded error
- Parameter-less errors: `vm.expectRevert(MyContract.MyError.selector)`
- Errors with parameters: `vm.expectRevert(abi.encodeWithSelector(MyContract.MyError.selector, arg))`
- `setUp()` initializes logic contracts, clone factories, and instances
- Shared setup base contracts and mocks live in `test/resources/`
- Use simple salts in tests (`0`, `"1"`, `"2"`) unless the test requires a specific value

## Documentation

The `docs/` folder contains detailed design documents:

- `bestpractices.md` — naming, natspec, custom errors, architecture rules
- `architecture_decisions.md` — rationale for key design choices
- `dev_overview.md` — in-depth walkthrough of all contracts
- `invariants.md` — formal per-contract invariants
- `testing.md` — test organization, mainnet fork testing, backwards-compatibility approach
- `fees.md`, `dividends_and_exit.md`, `price.md` — domain-specific mechanics
