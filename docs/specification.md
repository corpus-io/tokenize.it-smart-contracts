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
- All functions can be called directly or as meta transaction using EIP-2771.
- Calling a function directly or through EIP-2771 yield equivalent results given equivalent inputs.
- The token supports permit() as defined in EIP-2612.
- Only the owner of feeSettings can suggest to change feeSettings to another address.
- Only addresses with DEFAULT_ADMIN_ROLE can accept a new feeSettings contract.
- Only addresses that implement the IFeeSettingsV2 interface can be suggested or accepted as feeSettings.

## AllowList.sol

- As long as no value has been set for address, map(address) always returns 0.
- As soon as a value has been set for an address, map(address) always returns this value until a new value is set or remove is called.
- After remove has been called for an address, map(address) returns 0 until a new value is set.
- Only the owner of AllowList can set or remove addresses.
- All functions can be called directly or as meta transaction using EIP-2771.
- Calling a function directly or through EIP-2771 yield equivalent results given equivalent inputs.

## FeeSettings.sol

- TokenFees are always less or equal to 5%.
- CrowdinvestingFees are always less or equal to 10%.
- PrivateOfferFees are awlays less or equal to 5%.
- The feeCollector can never be 0.
- Only owner can change feeCollector and all fee default numerators and default denominators.
- Increasing fees is only possible with a delay of at least 12 weeks.
- Decreasing fees is possible without delay.
- Only owner can appoint or demote managers.
- Custom fees can only be set by managers.
- Custom fees can only be removed by managers.
- Custom fees can never be set for token address 0.
- Custom fees are only applied if they are lower than the default fee.
- Custom fees are only applied before their expiry date.
- Custom fees are only applied to the customers they are intended for, identified by their token address.
- Custom fee collectors can only be set by managers.
- Custom fee collectors can only be removed by managers.
- If a custom fee collector is set, it is used instead of the default fee collector in the appropriate view functions.
- Custom fee collectors can never be set for token address 0.
- Querying fees for token address 0 always returns the default fee.
- Querying fee collectors for token address 0 always returns the default fee collector.
- All functions can be called directly or as meta transaction using EIP-2771.
- Calling a function directly or through EIP-2771 yield equivalent results given equivalent inputs.

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

## PrivateOfferFactory.sol

- Contract state cannot be changed.
- Given equal inputs, getAddress() and deploy() return the same address.
- Given equal inputs, getAddress() returns the same address regardless of msg.sender.
- Deploy() returns the address the PrivateOffer contract was deployed to.

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
- All functions can be called directly or as meta transaction using ERC2771.
- Calling a function directly or through ERC2771 yield equivalent results given equivalent inputs.

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
