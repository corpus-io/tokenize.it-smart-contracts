# Invariants

The following statements about the smart contracts should always be true

## Token.sol

- Only addresses with minting allowances are able to mint tokens.
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
- No transfers can be made while the contract is paused.
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
- Only the owner of feeSettings can change feeSettings to another address.

## AllowList.sol

- As long as no value has been set for address, map(address) always returns 0.
- As soon as a value has been set for an address, map(address) always returns this value until a new value is set or remove is called.
- After remove has been called for an address, map(address) returns 0 until a new value is set.
- Only the owner of AllowList can set or remove addresses.

## FeeSettings.sol

- TokenFeeDenominator must always be equal to zero or greater equal 20.
- InvestmentFeeDenominator must always be equal to zero or greater equal 20.
- The feeCollector can never be 0.
- Only owner can change feeCollector, tokenFeeDenominator and investmentFeeDenominator.
- Changes to tokenFeeDenominator and or investmentFeeDenominator take at least 12 weeks.
- Charging 0 fees is possible.
- Charging a fee higher than 5% is not possible.

## PersonalInvite.sol

- If the buyer has not granted the invite a sufficient allowance in currency, the deploy operation reverts.
- The deal can only be paid for in currency.
- During deployment, the payment after fee deduction is transferred to the receiver.
- During deployment, the fee is deducted from the payment and sent to the feeCollector.
- During deployment, tokens are minted to the buyer.
- After deployment, the currency sent by the buyer and the tokens minted to the buyer always exactly correspond to the price set during deployment of the contract.
- Funds sent to the contract can not be recovered.
- The contract does not offer any functions after deployment is complete.
- Token amount bought is exactly the amount configured.
- receiver address can never be 0.
- buyer address can never be 0.
- tokenPrice can never be 0.
- tokenPrice can never be negative.
- No settings can be updated.
- No settings can be changed before deployment without the contract address changing.

## PersonalInviteFactory.sol

- Contract state cannot be changed.
- Given equal inputs, getAddress() and deploy() return the same address.
- Given equal inputs, getAddress() returns the same address regardless of msg.sender.
- Deploy() returns the address the PersonalInvite contract was deployed to.

## ContinuousFundraising.sol

- Any address can execute the buy function.
- The buy function can be executed many times.
- To execute the buy function, the buyer must have granted the invite a sufficient allowance in currency.
- The buy can only be paid for in currency.
- During the buy, the payment is immediately transferred to the receiver.
- During the buy, tokens are minted to the buyer.
- After the buy, the currency transferred from the buyer and the tokens minted to the buyer always exactly correspond to the price.
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
- Pausing the contracts starts the cool down period of 24h.
- Each setting update (re-)starts the cool down period of 24h hours.
- The contract can only be unpaused after the cool down period has passed.
- Only the contract owner can call pause, unpause, or the functions that update settings.
- In sum, the contract will never mint more tokens to the buyers than maxAmountOfTokenToBeSold at the time of minting. This does not take into account the tokens minted to feeCollector.
- All functions can be called directly or as meta transaction using ERC2771.
- Calling a function directly or through ERC2771 yield equivalent results given equivalent inputs.
