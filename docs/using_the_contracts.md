# Create new company

## Prerequisites

Tokenize.it has already deployed these contracts:

1. [AllowListFactory](../contracts/AllowListCloneFactory.sol)
2. [FeeSettingsFactory](../contracts/FeeSettingsCloneFactory.sol)
3. [TokenFactory](../contracts/TokenProxyFactory.sol)
4. [PrivateOfferFactory](../contracts/PrivateOfferFactory.sol)
5. [CrowdinvestingFactory](../contracts/CrowdinvestingCloneFactory.sol)
6. [TokenSwapFactory](../contracts/factories/TokenSwapCloneFactory.sol)
7. [VestingFactory](../contracts/VestingCloneFactory.sol)
8. [PriceLinearFactory](../contracts/PriceLinearCloneFactory.sol) or other dynamic pricing factories
9. [allowList](../contracts/AllowList.sol)
10. [feeSettings](../contracts/FeeSettings.sol)

These will be used for the next steps. The factories will not be explained in detail here, but can be found in the [contracts](../contracts) folder. They provide functions to calculate the future address of a contract, and deploy it using [CREATE2](https://docs.openzeppelin.com/cli/2.8/deploying-with-create2).

## Setting up the token contract

Deploy Token Contract using the token factory:

```solidity
factory.createTokenProxy(
    bytes32 _rawSalt,
    address _trustedForwarder,
    IFeeSettingsV2 _feeSettings,
    address _admin,
    AllowList _allowList,
    uint256 _requirements,
    string memory _name,
    string memory _symbol
)
```

- `_rawSalt`: a random number that influences the future contract address
- `_trustedForwarder`: used for meta transactions following [EIP-2771](../README.md#eip-2771)
- `_feeSettings`: defines which fees have to be paid to the platform
- `_admin` : address of the administrator. Be careful, they have all the power in the beginning. They can do everything, and can give permissions (aka roles as defined in the OpenZeppelin AccessControl module).
- `_allowList` : Allow list from tokenize.it.
- `_requirements`: requirements addresses need to fulfill in order to send and receive tokens
- `_name` : Name of the Token (e.g. PiedPiperToken)
- `_symbol` : Ticker of the Token (e.g. PPT)

## Enabling addresses to receive tokens

**All addresses which will receive tokens, through direct minting, investing or vesting, must be given the right to do so**, by either:

1. The `TransfererRoleAdmin` can give the `Transferer` -role to individual addresses
2. Tokenize.it will maintain an [allowList](../contracts/AllowList.sol), a list of addresses with fine-grained properties. The `Requirement`-role can then choose which requirements are necessary to transfer the tokens. In case they set requirements to 0, everyone can freely use the token.

# Investments

## Private Offers

In order to create a personal investment invite this [contract](../contracts/PrivateOffer.sol) needs to be used. It is created through the private offer factory.

```solidity
factory.deployPrivateOffer(
    bytes32 _rawSalt,
    PrivateOfferArguments calldata _arguments
)
```

Where `PrivateOfferArguments` contains:

- `currencyPayer`: address of the investor that has granted the allowance in the currency contract
- `tokenReceiver`: address of the investor that shall receive the tokens
- `currencyReceiver`: address of the recipient of the payment
- `tokenAmount`: amount of tokens to buy, in [bits](price.md#terms-used) (smallest subunit of the token, e.g. the equivalent of WEI for Ether)
- `tokenPrice`: price per token denoted in the currency defined below, and denominated in [bits](price.md#terms-used). Please refer to the [price explanation](price.md) for more details.
- `expiration`: Unix timestamp at which the offer expires
- `currency`: ERC20 token used for the payment
- `token`: address of the token deployed when creating the new company
- `tokenHolder`: if set, tokens are transferred from this address instead of being minted; if zero address, tokens are minted from the token contract

The investment is executed during deployment of the contract. Therefore, the following steps are necessary BEFORE deployment, or the deployment transaction will revert:

- All arguments must be agreed upon to calculate the future address of the contract.
- If `tokenHolder` is zero (minting): the future contract address needs to be given a minting right in the company token contract by calling `increaseMintingAllowance` from an address with the Minter Admin role. This step signals the offering company's invitation.
- If `tokenHolder` is set (transfer): the `tokenHolder` must give a sufficient token allowance to the future contract address.
- The investor needs to give a sufficient allowance in the currency contract to the future address of the contract. The required currency amount is `ceil(tokenAmount * tokenPrice / 10**token.decimals())`. This step signals the investor's commitment to the offer.

Once these steps have been completed, the Private Offer contract can be deployed by anyone (either of the two parties or a third party) with [CREATE2](https://docs.openzeppelin.com/cli/2.8/deploying-with-create2), through the Private Offer Factory's `deployPrivateOffer()` function.

The factory also provides `deployPrivateOfferWithTimeLock()`, which deploys both a PrivateOffer and a TimeLock in one transaction — tokens are minted directly into the TimeLock and can only be withdrawn after a specified unlock timestamp.

## Crowdinvesting / Starting an open round

Deploy the [contract](../contracts/Crowdinvesting.sol) using the factory.

```solidity
factory.createCrowdinvestingClone(
    bytes32 _rawSalt,
    address _trustedForwarder,
    CrowdinvestingInitializerArguments memory _arguments
)
```

Where `CrowdinvestingInitializerArguments` contains:

- `owner`: address of the owner of the fundraising contract. This address can change the parameters of the fundraising contract, and can pause it.
- `currencyReceiver`: address of the recipient of the payment
- `minAmountPerReceiver`: minimum cumulative tokens a single receiver address must receive from this contract, in [bits](price.md#terms-used). Tracked per token receiver address, not per transaction originator.
- `maxAmountPerReceiver`: maximum cumulative tokens a single receiver address may receive from this contract in total (can be the same as `minAmountPerReceiver`), in [bits](price.md#terms-used). Tracked per token receiver address, not per transaction originator.
- `tokenPrice`: price per token denoted in `currency`, and denominated in [bits](price.md#terms-used). Please refer to the [price explanation](price.md) for more details.
- `priceMin`: minimum price accepted from a dynamic pricing oracle (unused if no oracle is set)
- `priceMax`: maximum price accepted from a dynamic pricing oracle (unused if no oracle is set)
- `maxAmountOfTokenToBeSold`: the maximum amount of tokens to be sold in this round, denominated in [bits](price.md#terms-used)
- `currency`: ERC20 token used for the payment
- `token`: address of the token deployed when creating the new company
- `lastBuyDate`: Unix timestamp at which the fundraising will stop selling tokens automatically. Set to 0 to disable. Ensures the fundraising cannot be forgotten to be stopped when regulations require it.
- `priceOracle`: address of the price oracle contract for dynamic pricing. Set to zero address to disable.
- `tokenHolder`: if set, tokens are transferred from this address instead of being minted; if zero address, tokens are minted from the token contract

If `tokenHolder` is zero (minting), the contract needs to be given a minting allowance in the company token contract by calling `increaseMintingAllowance` from an address with the MintAllower role. The allowance should be set to `maxAmountOfTokenToBeSold` tokens.

An investor can buy tokens by calling the `buy(uint256 _tokenAmount, uint256 _maxCurrencyAmount, address _tokenReceiver)` function. `_tokenAmount` is the amount of tokens they are buying, in [bits](price.md#terms-used).

The investor needs to give a sufficient allowance in the currency contract to the Crowdinvesting contract for the deal to be successful.

The owner of the Crowdinvesting contract can pause the contract by calling `pause()`, which stops further buys. When paused, parameters of the fundraising can be changed. Each parameter change (re-)starts a cool down period of 1 hour. Only after this cool down period has passed can the fundraising be unpaused by calling `unpause()`. This is to ensure an investor can know the conditions that currently apply before investing (e.g. frontrunning a buy with a price increase is not possible).

## Secondary Market Trading

### TokenSwap

The [TokenSwap contract](../contracts/TokenSwap.sol) enables peer-to-peer trading of existing tokens on the secondary market. Unlike PrivateOffer and Crowdinvesting which mint new tokens from the company, TokenSwap facilitates the transfer of already-issued tokens between investors.

Deploy the contract using the factory:

```solidity
factory.createTokenSwapClone(
    bytes32 _rawSalt,
    address _trustedForwarder,
    TokenSwapInitializerArguments memory _arguments
)
```

Where `TokenSwapInitializerArguments` contains:

- `owner`: Address that can pause/unpause and update contract parameters
- `receiver`: Address that receives currency (sell orders) or tokens (buy orders)
- `holder`: Address holding tokens (sell orders) or currency (buy orders)
- `tokenPrice`: Price per token in currency, denominated in [bits](price.md#terms-used). See [price explanation](price.md)
- `currency`: ERC20 token used for payment (must be on allowlist with TRUSTED_CURRENCY attribute)
- `token`: The company token being traded

**Using TokenSwap as a sell order:**

1. Token holder deploys the contract with themselves as `holder` and their desired `receiver` for payments
2. Token holder grants the contract an allowance to transfer their tokens: `token.approve(tokenSwapAddress, amount)`
3. Any eligible buyer can purchase tokens by calling `buy(tokenAmount, maxCurrencyAmount, tokenReceiver)`
4. The buyer must first grant sufficient allowance in the payment currency
5. The contract can be used repeatedly until the holder revokes their token allowance

**Using TokenSwap as a buy order:**

1. Prospective buyer deploys the contract with themselves as `holder` and their desired `receiver` for tokens
2. Buyer grants the contract an allowance in payment currency: `currency.approve(tokenSwapAddress, amount)`
3. Any token holder can sell tokens by calling `sell(tokenAmount, minCurrencyAmount, currencyReceiver)`
4. The seller must first grant sufficient token allowance to the contract
5. The contract can be used repeatedly until the buyer revokes their currency allowance

**Updating parameters:**

The owner can update:

- Price: `setTokenPrice(newPrice)`
- Receiver: `setReceiver(newReceiver)`
- Outside the TokenContract:
  - token allowance
  - currency allowance

The owner can pause the contract using `pause()` to disable swaps, and unpause it using `unpause()` to re-enable swaps.

**Fees:**

TokenSwap charges secondary market fees according to the FeeSettings contract. Fees are only deducted from the currency transferred, not the token.

**Expiration:**

No dedicated order expiration is built into the TokenSwap contract. Incomplete orders can be disabled by pausing the contract or removing the allowance. The platform can help the user automate such expiration by storing a signed ERC2612 permit meta-transaction setting the token or currency allowance to 0 and executing it once an expiration date has passed (or similar prerequisites are met).

This offchain-approach keeps the contract slim and allows for high flexibility.

# Employee participation with or without vesting

In case there is no vesting, tokens can directly be issued by calling the `mint()` function on the token contract.

For vesting the [Vesting.sol](../contracts/Vesting.sol) contract is used.

The contract needs to be given a sufficient minting allowance in the company token contract by calling `increaseMintingAllowance` from an address which has the role of MintAllower.
