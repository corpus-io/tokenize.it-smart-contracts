# Create new company

## Prerequisites

Tokenize.it has already deployed:

1. [allowList](../contracts/AllowList.sol)
2. [feeSettings](../contracts/FeeSettings.sol)
3. [PrivateOfferFactory](../contracts/PrivateOfferFactory.sol)

These will be used for the next steps.

## Setting up the token contract

1. Deploy Token Contract “Token”:

   ```solidity
   constructor(
        address _trustedForwarder,
        IFeeSettingsV1 _feeSettings,
        address _admin,
        AllowList _allowList,
        uint256 _requirements,
        string memory _name,
        string memory _symbol
    )
   ```

   - `trustedForwarder`: used for meta transactions following [EIP-2771](../README.md#eip-2771)
   - `feeSettings`: defines which fees have to be paid to the platform
   - `admin` : address of the administrator. Be careful, they have all the power in the beginning. They can do everything, and can give permissions (aka roles as defined in the OpenZeppelin AccessControl module).
   - `_allowList` : Allow list from tokenize.it.
   - `_requirements`: requirements addresses need to fulfill in order to send and receive tokens
   - `_name` : Name of the Token (e.g. PiedPiperToken)
   - `_symbol` : Ticker of the Token (e.g. PPT)

2. Create initial cap table by minting tokens for various addresses.

   For this, the admin needs to give an account (can be himself) a minting allowance by calling `increaseMintingAllowance(address minter, uint _allowance)` :

   - `minter` : account that will be granted the minting allowance
   - `_allowance`: amount of tokens they can mint, denominated in [bits](https://docs.openzeppelin.com/contracts/2.x/crowdsales#crowdsale-rate) (assuming their minting allowance was 0 before).

   To create the initial cap table, `_allowance` should be the total amount of shares in existence so far, in bits (be sure to understand the concept of [decimals](https://docs.openzeppelin.com/contracts/3.x/api/token/erc20#ERC20-decimals--)).

   The minter can then create new shares for each shareholder, by calling `mint(address _to, uint256 _amount)`, where:

   - `_to` is the shareholder's address
   - `_amount` is the amount of shares the shareholder holds, denominated in [bits](https://docs.openzeppelin.com/contracts/2.x/crowdsales#crowdsale-rate)

   Note that extra tokens will be minted to feeCollector. See the section on [fees](fees.md) for more information.

## Enabling addresses to receive tokens

**All addresses which will receive tokens, through direct minting, investing or vesting, must be given the right to do so**, by either:

1. The `TransfererRoleAdmin` can give the `Transferer` -role to individual addresses
2. Tokenize.it will maintain an [allowList](../contracts/AllowList.sol), a list of addresses with fine-grained properties. The `Requirement`-role can then choose which requirements are necessary to transfer the tokens. In case they set requirements to 0, everyone can freely use the token.

# Investments

## Private Offers

In order to create a personal investment invite this [contract](../contracts/PrivateOffer.sol) needs to be used.

Constructor:

```solidity
constructor(
        address _buyer,
        address _receiver,
        uint256 _amount,
        uint256 _tokenPrice,
        uint256 _expiration,
        IERC20 _currency,
        Token _token
    )
```

- `_buyer`: address of the investor

- `_receiver`: address of the recipient of the payment
- `_amount`: amount of tokens the investor can to buy, in [bits](https://docs.openzeppelin.com/contracts/2.x/crowdsales#crowdsale-rate) (smallest subunit of the token, e.g. the equivalent of WEI for Ether)
- `_tokenPrice`: price per token denoted in the currency defined in the next field, and denominated in [bits](https://docs.openzeppelin.com/contracts/2.x/crowdsales#crowdsale-rate). Please refer to the [price explanation](price.md) for more details.

- `_expiration`: Unix timestamp at which the offer expires

- `_currency` : ERC20 token used for the payment. The `_buyer` must first give this contract the allowance to spend the amount he wants to invest.

- `_token` : address of the token deployed when creating the new company

The investment is executed during deployment of the contract. Therefore, three steps are necessary BEFORE deployment, or the deployment transaction will revert:

- All constructor arguments must be agreed upon to calculate the future address of the contract.
- The future contract address needs to be given minting right in the company token contract by calling `increaseMintingAllowance` from an address which has the role of the Minter Admin. In that call, an allowance needs to be given which matches or exceeds the `_amount` of tokens. This step signals the offering company's invitation.
- The investor needs to give a a sufficient allowance in the currency contract to the future address of the contract. This step signals the investors commitment to the offer.

Once these steps have been completed, the Private Offer contract can be deployed by anyone (either of the two parties or a third party) with [CREATE2](https://docs.openzeppelin.com/cli/2.8/deploying-with-create2), through the Private Offer Factory's deploy() function.

## Private Offer Factory

This [contract](../contracts/PrivateOfferFactory.sol) can be used to:

1. Calculate the future address of a PrivateOffer
2. Deploy the PrivateOffer to this address

## Public Fundraising / Starting on open round

Deploy the [contract](../contracts/PublicFundraising.sol)

Constructor:

```solidity
constructor(
        address _trustedForwarder,
        address _currencyReceiver,
        uint256 _minAmountPerBuyer,
        uint256 _maxAmountPerBuyer,
        uint256 _tokenPrice,
        uint256 _maxAmountOfTokenToBeSold,
        IERC20 _currency,
        Token _token
    )
```

- `_trustedForwarder`: contract that performs on-chain signature verification for [EIP-2771 meta transactions](../README.md#eip-2771)
- `_currencyReceiver`: address of the recipient of the payment
- `_minAmountPerBuyer`: Minimum amount of tokens an investor needs to buy, in [bits](https://docs.openzeppelin.com/contracts/2.x/crowdsales#crowdsale-rate)

- `_maxAmountPerBuyer`: Maximum amount of tokens an investor can buy (can be the same as `_minAmountPerBuyer`), in [bits](https://docs.openzeppelin.com/contracts/2.x/crowdsales#crowdsale-rate)
- `_tokenPrice`: price per token denoted in `_currency`, and denominated in [bits](https://docs.openzeppelin.com/contracts/2.x/crowdsales#crowdsale-rate). Please refer to the [price explanation](price.md) for more details.

- `_maxAmountOfTokenToBeSold` : the maximum amount of token to be sold in this round, denominated in [bits](https://docs.openzeppelin.com/contracts/2.x/crowdsales#crowdsale-rate)

- `_currency` : ERC20 token used for the payment.

- `_token` : address of the token deployed when creating the new company

The contract needs to be given a minting allowance in the company token contract by calling `increaseMintingAllowance` from an address which has the role of the MintAllower. The allowance should be set to `_maxAmountOfTokenToBeSold` tokens.

An investor can buy tokens by calling the `buy(uint _amount)` function.
`_amount` ist the amount of tokens they are buying, in [bits](https://docs.openzeppelin.com/contracts/2.x/crowdsales#crowdsale-rate).

The investor needs to give a a sufficient allowance in the currency contract to the publicFundraising contract for the deal to be successful

The owner of the PublicFundraising contract can pause the contract by calling `pause()`, which stops further buys. When paused, parameters of the fundraising can be changed. Pausing the contract as well as each setting update starts a cool down period of 24 hours. Only after this cool down period has passed can the fundraising be unpaused by calling `unpause()`. This is to ensure an investor can know the conditions that currently apply before investing (e.g. frontrunning in a buy with a price increase is not possible).

# Employee participation with or without vesting

In case there is no vesting, shares can directly be issued through minting as described when setting up a new company.

For vesting the [Vesting.sol](../contracts/Vesting.sol) contract is used.

The contract needs to be given a sufficient minting allowance in the company token contract by calling `increaseMintingAllowance` from an address which has the role of MintAllower.
