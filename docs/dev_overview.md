## Token.sol

The [token contract](./contracts/Token.sol) is based on the OpenZeppelin ERC20 contract using the AccessControl extension. It also implements meta transactions following [EIP-2771](https://eips.ethereum.org/EIPS/eip-2771) and [EIP-2612](https://eips.ethereum.org/EIPS/eip-2612).
Beyond being an ERC20 token, it has fine grained access control to:

- define who can grant and revoke roles
- define who can set requirements which a user has to meet in order to transact
- define burning rights (only company admin)
- define who is allowed to transfer the token
- define who is allowed to pause the contract
- define minting rights (through increaseMintingAllowance and decreaseMintingAllowance functions)

Also, this is the only contract in this repository that is deployed using an ERC1967-proxy. This means that it can be upgraded. Since this token is legally bound to the company, we want to make sure that we can offer our customers options if a security issue arises or regulation enforces changes.

### Minting

Minting is very central to the usage of this contract. The MintAllower role (see [access control](https://docs.openzeppelin.com/contracts/4.x/access-control)) can give an address a minting allowance. For example the admin (or CEO) of the company might need a minting allowance to create new shares. Each investment or vesting contract also needs a minting allowance in order to function.
The allowances are stored in the map `mintingAllowance`.
Addresses with the MintAllower role can mint tokens regardless of their own allowance (since they can change it at any time, enforcing the minting allowance would be pointless).

### Requirements

We expect that the companies issuing a token through tokenize.it need control about who can transact with the token for compliance reasons.
There are two ways to control who can transact with the token:

1. The `TransfererRoleAdmin` can give the `Transferer`-role to individual addresses
2. We as tokenize.it will maintain a list of addresses with fine-grained properties. The `Requirement`-role can then choose which requirements are necessary to transfer the tokens. In case they set requirements to 0, everyone can freely use the token.

## Investments

Please read the [supported currencies](../README.md#supported-currencies) section first.
Remember that extra tokens will be minted to cover [fees](fees.md), and fees will also be deducted from the payment, unless the fee is set to 0.

There are 2 investment contracts:

### 1. Private offer (PrivateOffer.sol)

This is a personal investment invite allowing a particular investor (represented by their ethereum address) to buy newly issued tokens at a fixed price. The contract is deployed using CREATE2, and the investment is executed during deployment. [Read this](./using_the_contracts.md#personal-invites) for more information.

Lockup periods can be realized through the combination of [PrivateOffer.sol](../contracts/PrivateOffer.sol) and [Vesting.sol](../contracts/Vesting.sol) through the [PrivateOfferFactory.sol](../contracts/factories/PrivateOfferFactory.sol).

### 2. Crowdinvesting (Crowdinvesting.sol)

This contract allows everyone who has the `Transferer`-role on the `token` contract or who is certified by the allow-list to meet the requirements set in the `token` contract to buy newly issued tokens at a fixed price. The number of tokens that can be minted in this way can be limited to `maxAmountOfTokenToBeSold`, which is the maximal amount of token to be sold in this fundraising round.

Furthermore, this contract can be paused by the owner to change the parameters. After any parameter change, a delay of 1 hour is enforced before the contract can be unpaused again. This is to prevent frontrunning attacks.

## Secondary Market Trading

### TokenSwapBase (TokenSwapBase.sol)

`TokenSwapBase` is an abstract base contract that provides shared state, fee handling, price management, and pause controls. It is not deployed directly; both `TokenSwap` and `CoinvestedPosition` extend it.

**Shared state:**

- `tokenPrice`: amount of currency bits per main token unit
- `currency`: ERC-20 payment token
- `token`: the Token being traded
- `receiver`: destination for currency (sell) or tokens (buy)

**Shared capabilities:** owner-controlled price updates, pause/unpause, ERC-2771 meta-transaction support, reentrancy protection, and a unified fee-lookup helper (`_getFeeAndFeeReceiver`).

### TokenSwap (TokenSwap.sol)

The TokenSwap contract enables secondary market trading where investors can buy or sell existing tokens between each other. Unlike the primary market contracts (PrivateOffer and Crowdinvesting) which mint new tokens, TokenSwap facilitates peer-to-peer transfers of already-issued tokens.

**Note:** This contract has been developed by simplifying Crowdinvesting and IS NOT AUDITED YET (2025-11-06). It is intended to be used for limited liquidity and limited time, thus limited risk. The idea is to decide whether to audit it or switch to Uniswap soon.

**Key features:**

- **No minting**: Transfers existing tokens rather than minting new ones
- **Reusable**: Can be used multiple times as a standing buy or sell order
- **Dual functionality**: Can act as either a buy order or sell order depending on who grants allowances
- **Pausable**: Owner can pause to update price, currency, or holder settings
- **Fee collection**: Charges crowdinvesting fees according to FeeSettings, similar to primary market contracts

**Setup:**

- `holder`: The address holding tokens (for sell orders) or currency (for buy orders)
- `receiver`: The address receiving payments (for sell orders) or tokens (for buy orders)
- `tokenPrice`: Fixed price per token
- `currency`: Payment token (must be on allowlist with TRUSTED_CURRENCY attribute)

**As a sell order:**

1. Token holder creates contract and grants it allowance to transfer their tokens
2. Any eligible buyer can call `buy()` to purchase tokens at the preset price
3. Tokens flow from holder to buyer, currency flows from buyer to receiver

**As a buy order:**

1. Prospective buyer creates contract and grants it allowance in payment currency
2. Any token holder can call `sell()` to sell tokens at the preset price
3. Tokens flow from seller to receiver, currency flows from holder to seller

The contract validates that the currency is trusted (via AllowList) and collects fees according to FeeSettings.

## Dividends, Distributions and Exit

### Distribution (Distribution.sol)

Distributes a fixed pot of currency to token holders proportional to a prior snapshot of the Token contract.

**Key details:**

- At initialization, the contract pulls `initialFundingAmount` from `_currencyProvider` and deducts a platform fee using `privateOfferFee`. Only the net amount after fees is actually available for claims.
- `eligible(address)` returns a holder's unclaimed amount: `initialFundingAmount * balanceOfAt(snapshotId) / totalSupplyAt(snapshotId) + extraCredit - paidOut`.
- `claim(address recipient)` transfers the caller's eligible amount, marked via `paidOut`.
- `reassign(from, to, amount)` lets the owner redirect unclaimed funds (e.g. for a holder who lost their key, or a non-mintable vesting contract or similar), available only after `reassignAfter`. Emits `Reassigned` for on-chain auditability.
- Currency must have `TRUSTED_CURRENCY` attribute on the token's AllowList.

### Exit (Exit.sol)

Automated exit redemption: holders send tokens and receive a fixed currency payout.

**Key details:**

- At initialization, the contract is funded with the full payout amount in currency (no fee deducted at init; per-claim fee is deducted at `claim()` time using `privateOfferFee`).
- Currency must have both `TRUSTED_CURRENCY` and `EURO_CURRENCY` attributes on the token's AllowList.
- `claim(tokenAmount, recipient)` is valid only between `claimStart` and `drainStart`. It transfers tokens from the caller to the Exit contract (tokens are held, not burned) and sends `tokenAmount * pricePerToken / 10**token.decimals() - fee` currency to the recipient.
- `drain(recipient)` can be called by the owner after `drainStart` to recover unclaimed currency.

### CoinvestedPosition (CoinvestedPosition.sol)

Extends `TokenSwapBase`. Holds tokens for a co-investor and manages carry distributions to lead investors.

**Key details:**

- Initialized paused; the owner unpauses when ready to sell (allowing `buy()` price to be set first).
- `basePrice` is set in the smallest units of `baseCurrency` at initialization.
- `leadInvestors`: array of `{account, carryFraction}`. `carryFraction` documents who is eligible to how much of the carry. The fractions are scaled with uint64max, so uint64max == 1 == 100% of carry.
- `setCurrency(currency, basePrice)` lets the owner switch the reference currency after the timelock has expired; the caller must supply the new `basePrice` expressed in the new currency's units.

**Effective base price in `claimExit()`**

Two distinct base price values appear here:

- `basePrice` — the storage variable, refers to `baseCurrency`. Can only be updated after timelock has expired.
- `_basePrice` — the `claimExit()` parameter, expressed in bits of the **exit** currency. Only used as a fallback (see below); pass `0` when auto-conversion applies.

`claimExit()` derives the effective base price in priority order:

1. **Same currency**: if the exit currency matches the stored `currency`, `basePrice` is used directly.
2. **Auto-conversion via `referenceToExitRate`**: if the Exit contract has a rate set for the stored `currency` (see `referenceToExitRate` in [Exit.sol](../contracts/Exit.sol)), `basePrice` is converted to exit-currency units automatically:
   ```
   effectiveBasePrice = basePrice * rate / 10**baseCurrency.decimals()
   ```
   The rate convention is the same as `tokenPrice` (see [price.md](price.md)): exit-currency bits per `10**referenceCurrency.decimals()` reference-currency bits.
3. **Caller-supplied fallback**: if neither of the above applies, `claimExit()` requires a non-zero `_basePrice` parameter, which the caller must express in exit-currency units.

- Three payout paths all funnel into `_settle(carry, currency)`:
  1. `buy()`: buyer purchases tokens; fee deducted; co-investor gets base price portion; lead investors split carry.
  2. `claimDistribution(dist, minPayout)`: claims from a `Distribution` contract; all received currency treated as carry.
  3. `claimExit(minCurrencyAmount, basePrice)`: redeems full token balance via an `Exit` contract, carry is calculated from proceeds, tokenAmount and basePrice.
- `_settle()` sweeps the contract's full balance of `_currency` to `receiver` after lead investor shares are distributed, covering both the base price portion and any rounding dust, as well currency the contract may have held before settlement.

## Employee participation

In case there is no vesting, tokens can directly be issued through minting as described when setting up a new company.

For vesting the [Vesting.sol](../contracts/Vesting.sol) contract is used.

The contract needs to be given a minting allowance of maximum amount of tokens to be vested in the company token contract by calling `increaseMintingAllowance(contractAddress, amount)` from an address which has the MintAllower role.

## Factories

All of the contracts in this repository are deployed using factory contracts. This has two reasons:

1. Deterministic addresses. We can tell our customers which address their contract will have before it is deployed. This is important for the customer to be able to prepare their legal documents, which often require the address of the contract. Then, once the legal work is done (which can take days or even weeks), we can deploy the contract to the address we told them.
2. Gas efficiency. Instead of deploying full contracts, we deploy clones or proxies when possible. This saves a lot of gas, especially when deploying many contracts.
