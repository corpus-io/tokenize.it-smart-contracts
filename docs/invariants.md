# Invariants

The following statements about the smart contracts should always be true

## Token.sol

- Only addresses with minting allowances > 0 or the MINTALLOWER_ROLE are able to mint tokens.
- An address with minting allowance can only mint tokens if the remaining allowance after the mint will be larger or equal to zero.
- An address can only receive tokens at least one of these statements is true:
  - The address fulfills the requirements as proven by the allowList.
  - The address has the TRANSFERER_ROLE.
  - The address is the feeCollector.
  - The address is the 0 address.
- An address can only send their own tokens if at least one of these statements is true:
  - The address fulfills the requirements as proven by the allowList.
  - The address has the TRANSFERER_ROLE.
  - The address has the BURNER_ROLE.
- No transfers (including mints and burns) can be made while the contract is paused.
- Only an address with PAUSER_ROLE can pause or unpause the contract.
- Granting and revoking of roles is possible regardless of the contract being paused or not.
- An address with BURNER_ROLE can burn tokens from any address that holds these tokens any time unless the contract is paused.
- Only addresses with REQUIREMENT_ROLE can set requirements.
- There is no limitation to the content of the requirements, as long as it can be stored in uint256.
- Any role can be granted to multiple addresses.
- Any address can have multiple roles.
- Any role can be renounced.
- All functions can be called directly or as meta transaction using EIP-2771. Both options yield equivalent results given equivalent inputs.
- The token supports permit() as defined in EIP-2612.
- Only the owner of feeSettings can suggest to change feeSettings to another address.
- Only addresses with DEFAULT_ADMIN_ROLE can accept a new feeSettings contract.
- Only addresses that implement the IFeeSettingsV2 interface can be suggested or accepted as feeSettings.

## AllowList.sol

- As long as no value has been set for address, map(address) always returns 0.
- As soon as a value has been set for an address, map(address) always returns this value until a new value is set or remove is called.
- After remove has been called for an address, map(address) returns 0 until a new value is set.
- Only the owner of AllowList can set or remove addresses.
- All functions can be called directly or as meta transaction using EIP-2771. Both options yield equivalent results given equivalent inputs.

## FeeSettings.sol

- Fee types are registered dynamically; each type carries its own hard cap and default numerator.
- A fee type's hard cap is fixed at registration and can never be changed.
- The same fee type cannot be registered more than once.
- Only the owner can register new fee types.
- Only the owner can propose and execute changes to a type's default numerator.
- Increasing a default numerator is only possible with an activation date at least 12 weeks in the future.
- Decreasing a default numerator is possible without delay.
- A default numerator can never exceed the fee type's hard cap.
- No fee collector can ever be the zero address.
- Only the owner can set or change the default fee collector for a fee type.
- Only the owner can appoint or demote managers.
- Custom fees can only be set or removed by managers.
- Custom fees can never be set for token address 0.
- A custom fee numerator can never exceed the fee type's hard cap.
- Custom fees are only applied if they are lower than the default fee at query time.
- Custom fees are only applied before their expiry date.
- Custom fees are only applied to the token they are intended for, identified by its token address.
- Custom fee collectors can only be set or removed by managers.
- Custom fee collectors can never be set for token address 0.
- If a custom fee collector is set for a token, it is used instead of the type-level default.
- Querying fees for token address 0 always returns the default fee.
- Querying fee collectors for token address 0 always returns the default fee collector.
- All functions can be called directly or as meta transaction using EIP-2771. Both options yield equivalent results given equivalent inputs.

## PrivateOffer.sol

- If the buyer has not granted the invite a sufficient allowance in currency, the deploy operation reverts.
- The deal can only be paid for in currency.
- During deployment, the payment after fee deduction is transferred to the receiver.
- During deployment, the fee is deducted from the payment and sent to the feeCollector.
- During deployment, tokens are minted to the buyer.
- During deployment, the payment amount is rounded up by a maximum of 1 currency bit.
- Funds sent to the contract can not be recovered.
- The contract does not offer any functions after deployment is complete.
- Token amount bought is exactly the amount configured.
- receiver address can never be 0.
- buyer address can never be 0.
- tokenPrice can never be 0.
- tokenPrice can never be negative.
- No settings can be updated.
- No settings can be changed before deployment without the contract address changing.
- A private offer that uses a currency that does not have the TRUSTED_CURRENCY attribute on the AllowList will revert during deployment.

## PrivateOfferFactory.sol

- The factory holds no mutable state; the addresses of the TimeLockCloneFactory and CoinvestedPositionCloneFactory are fixed at construction and can never be changed.
- All PrivateOffer contracts are deployed at deterministic addresses using create2.
- Given equal inputs, each address prediction function returns the same address as its corresponding deploy function, regardless of msg.sender.
- The factory can deploy both a PrivateOffer and a TimeLock in one transaction. In this case,the tokens are minted directly into the TimeLock.
- The factory can deploy both a PrivateOffer and a CoinvestedPosition in one transaction. In this case, the tokens are minted directly into the CoinvestedPosition, and only the CoinvestedPosition address is returned.

## Crowdinvesting.sol

- The buy function can be executed many times.
- To execute the buy function, the buyer must have granted the crowdinvesting contract a sufficient allowance in currency.
- The buy can only be paid for in currency.
- During the buy, the fee is deducted from the payment and the remaining payment is immediately transferred to the receiver.
- During the buy, the fee is immediately transferred to the feeCollector.
- During the buy, tokens are minted to the buyer.
- During the buy, the payment amount is rounded up by a maximum of 1 currency bit.
- After the buy, currency received by the receiver and fee received by feeCollector always exactly corresponds to the currency transferred from the buyer.
- The contract address never holds funds during the buy or any other use it was designed for.
- Funds sent to the contract can not be recovered.
- No buys can be executed if the contract is paused.
- No buyer can buy a token amount that would result in their sum of tokens bought from this contract being less than minAmountPerBuyer.
- No token amount that is larger than maxAmountPerBuyer can be bought by one address through this contract. That is still true if multiple buys are executed and tokens are transferred to another address between the calls.
- maxAmountPerBuyer can not be less than minAmountPerBuyer.
- receiver address can never be 0.
- tokenPrice can never be 0.
- tokenPrice can never be negative.
- maxAmountOfTokenToBeSold can never be 0.
- All settings can be updated when the contract is paused.
- Each setting update (re-)starts the cool down period of 24h hours.
- The contract can only be unpaused after the cool down period has passed.
- Only the contract owner can call pause, unpause, or the functions that update settings.
- The contract will never sell tokens after the lastBuyDate has passed, unless lastBuyDate is 0.
- In sum, the contract will never mint more tokens to the buyers than maxAmountOfTokenToBeSold at the time of minting. This does not take into account the tokens minted to feeCollector in Token.sol.
- All functions can be called directly or as meta transaction using EIP-2771. Both options yield equivalent results given equivalent inputs.

- Initialization is only possible with a currency that has the TRUSTED_CURRENCY attribute on the AllowList.
- Setting a new currency is only possible if the new currency has the TRUSTED_CURRENCY attribute on the AllowList.

## Vesting.sol

- Only the owner can make an address a manager.
- Only the owner can remove a manager.
- Only a manager can create a vesting plan directly or commit the hash of a vesting plan.
- Anyone can reveal the vesting plan for a hash that has been committed, if they know the corresponding parameters.
- Revealing a vesting plan for a hash that has not been committed reverts.
- Revealing a vesting plan for a hash that has been committed with different parameters reverts.
- Revealing a vesting plan for a hash that has been committed with the same parameters succeeds.
- Revealing a vesting plan for a hash that has been committed removes the commitment.
- Once tokens from a vesting plan are releasable, they can only be released by the beneficiary.
- Once tokens from a vesting plan are releasable, they can only be released to the beneficiary.
- The beneficiary can only release tokens from a vesting plan if the vesting plan has been revealed.
- The beneficiary can change the beneficiary address of a vesting plan.
- The owner can change the beneficiary address of a vesting plan if the vesting plan has completed at least one year ago.
- The beneficiary can release exactly `allocation` tokens after the vesting duration has passed.
- No tokens are releasable from a plan before the cliff has passed.
- Under no circumstance are more tokens released from a single vesting plan than `allocation`.
- There is no way to prevent a beneficiary from releasing tokens from a vesting plan.
- There is no way to reduce the releasable amount of tokens from a vesting plan, except by releasing them.
- A vesting plan can only be stopped now or in the future. It can not be stopped in the past.
- Only a manager can stop a vesting plan.
- Stopping a vesting plan and revoking a commitment to a vesting plan are equivalent with respect to the token amount the beneficiary can release and the time the beneficiary can release them.
- A beneficiary can never mint or withdraw more tokens than the allocation of the vesting plan.
- Third parties can not mint or withdraw tokens from a vesting plan.
- All functions can be called directly or as meta transaction using EIP-2771. Both options yield equivalent results given equivalent inputs.

## Distribution.sol

- A Distribution contract distributes currency to token holders.
- Eligibility is determined by token balances at a fixed snapshot; token transfers after the snapshot do not affect any holder's share.
- Each holder's gross eligible amount is proportional to their snapshot balance scaled by the price, but can be increased or decreased through reassignments.
- Reassignments leave the total eligible currency in the contract unchanged.
- Reassigning funds reduces the source's remaining gross eligibility and increases the target's by the same amount.
- Only the owner can do reassignments.
- Reassigning funds can only be done after the lock period, except for reassignments applied during initialization itself.
- An address's gross eligible amount minus a fee is that address's net eligible amount.
- The fee is deducted from the payout at claim time.
- The fee is calculated by the fee settings contract, if that contract has the expected interface.
- If the fee settings contract does not expose the expected interface, the fee is set to 0.
- Only trusted currencies can be used.
- The snapshot must have a non-zero total token supply.
- A claim always redeems the caller's entire eligible amount at once; partial claims are not possible.
- Once an address has claimed, its share cannot be claimed again.
- A claim reverts if the net payout would be below the caller-specified minimum.
- The caller specifies the recipient address for the currency payout.
- Only the owner can drain the remaining currency from the contract, and only after the lock period.
- The lock period is configured at initialization.
- Every reassignment is recorded on-chain for auditability.
- All functions can be called directly or as meta transaction using EIP-2771. Both options yield equivalent results given equivalent inputs.

## Exit.sol

- Tokens are transferred from the holder to the Exit contract during a claim.
- Payout per claim depends on token amount, price per token and fee.
- Fees can be deducted from the payment amount.
- If the FeeSettings contract does not support the expected interface, no fee is deducted.
- The currency used must be a trusted currency.
- A claim reverts if the net payout would be below the caller-specified minimum.
- After a lock period defined at contract setup, the unclaimed currency can be drained by the owner.
- Exchange rates from reference currencies to the exit currency can be registered at initialization and are immutable afterwards.
- All registered reference-to-exit exchange rates must be positive.
- All functions can be called directly or as meta transaction using EIP-2771. Both options yield equivalent results given equivalent inputs.

## CoinvestedPosition.sol

- The sum of all lead investors' carry fractions can never be more than 1.
- There must be at least one lead investor.
- No lead investor address can be the zero address.
- No lead investor carry fraction can be zero.
- The contract does not immediately start selling tokens.
- The owner can unpause the contract when ready to sell.
- The owner can change the currency used for selling tokens.
- Only currency with both `TRUSTED_CURRENCY` and `EURO_CURRENCY` attributes can be used for selling tokens or claiming exits.
- During a token sale, after fee deduction, lead investors get their share of the profit proportional to their fraction. The co-investor (receiver) receives all remaining proceeds.
- If net proceeds are less than the scaled base price payout, the co-investor receives all net proceeds and lead investors receive nothing.
- During settlement of buy or claim, the contract's full remaining currency balance is swept to the receiver after lead investor shares, ensuring no dust is left in the contract.
- The sweeping of the contract funds during settlement includes any funds in the currency in use that may have been transferred to the contract.
- Only trusted currencies can be used to sell the tokens.
- When calculating profit, base price in the current currency is used.
- If the currency currently used in the contract differs from the currency of an exit contract that should be used, the exit contract can provide exchange rates for the conversion of base price.
- If the exit contract doesn't provide required exchange rates, a user-provided new base price is used.
- During lockup, only an exit claim or a burn can transfer the tokens out.
- An exit claim reverts if it receives less than the required minimum currency amount.
- All proceeds from dividends are treated as profit.
- All functions can be called directly or as meta transaction using EIP-2771. Both options yield equivalent results given equivalent inputs.

## GlobalTokenExitRegistry.sol

- An exit can only be set for a token if the caller holds the token's `DEFAULT_ADMIN_ROLE` or is the token's `owner()`.
- An exit address can only be set once per token.
- Once an exit address has been set for a token, it cannot be changed again.

## TimeLock.sol

- Only the owner can drain an ERC20 token from the contract.
- Draining any ERC20 token from the contract moves the entire balance at once.
- Draining the tokens from the contract is only possible after the timelock period has passed.
- If the owner is eligible for distribution proceeds, they can claim those proceeds regardless of the timelock period.
- Claiming distribution proceeds does not move the tokens.
- The only option for the owner to transfer the tokens out of the contract during the timelock period is through an Exit.
- An Exit can only be used if it has been registered in the GlobalTokenExitRegistry.
- All functions can be called directly or as meta transaction using EIP-2771. Both options yield equivalent results given equivalent inputs.

## TokenSwap.sol

- One TokenSwap contract represents one limit order to buy or sell tokens at a fixed price.
- The price is set at contract creation and can be changed by the owner.
- The volume is controlled by the allowance granted, which can be increased or decreased by the owner.
- The direction (buy or sell) is determined by setting the holder and receiver addresses.
- The holder address must hold the tokens to be sold when the contract is used as a sell order.
- The holder address must hold the currency to be paid when the contract is used as a buy order.
- The receiver address will receive the tokens to be bought when the contract is used as a buy order.
- The receiver address will receive the currency to be paid when the contract is used as a sell order.
- The receiver address can be equal to the holder address.
- The owner can update the receiver address.
- The owner can update the holder address.
- The owner can update the token price.
- Token is set at contract creation and can not be changed.
- Currency is set at contract creation and can not be changed.
- Currency must have the TRUSTED_CURRENCY attribute on the token's AllowList.
- The contract can be paused and unpausedby the owner.
- No new trades can be made while the contract is paused.
- Buying and selling can be disabled by removing the allowance.
- The contract can be transferred to a new owner by the owner.
- The counterparty decides how many tokens to buy or sell.
- There is no minimum amount of tokens to buy or sell.
- The limit order can be executed partially or completely.
- As long as an allowance remains, the limit order can be executed repeatedly.
- The maximum amount of tokens to buy or sell is determined by the allowance granted.
- Fees are deducted from the currency transferred during the swap.
- Fee amount is determined by the token's fee settings' PrivateOfferFee.
- Fee receiver is determined by the token's fee settings' PrivateOfferFeeCollector.
- No fees are deducted from the tokens transferred during the swap.
- The buyer calling the buy function will pay no more than maxCurrencyAmount, protecting them from frontrunning or other unexpected influences.
- The seller calling the sell function will receive no less than minCurrencyAmount, protecting them from frontrunning or other unexpected influences.
- The buy function rounds up the currency amount, protecting the owner from loss.
- The sell function rounds down the currency amount, protecting the owner from loss.
- It is possible to create a buy AND sell order using one TokenSwap contract, by granting allowances in token and currency. This is not an intended use case as it doesn't benefit the owner.
- All functions can be called directly or as meta transaction using EIP-2771. Both options yield equivalent results given equivalent inputs.
