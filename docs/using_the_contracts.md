# Create new company

## Prerequisites

Tokenize.it has already deployed these contracts:

1. [allowList](../contracts/AllowList.sol)
2. [feeSettings](../contracts/FeeSettings.sol)
3. [TokenFactory](../contracts/TokenProxyFactory.sol)
4. [PrivateOfferFactory](../contracts/PrivateOfferFactory.sol)
5. [PublicFundraisingFactory](../contracts/PublicFundraisingCloneFactory.sol)
6. [VestingFactory](../contracts/VestingCloneFactory.sol)
7. [PriceLinearFactory](../contracts/PriceLinearCloneFactory.sol) or other dynamic pricing factories

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

Constructor:

```solidity
factory.deploy(
        bytes32 _salt,
        address _currencyPayer,
        address _tokenReceiver,
        address _currencyReceiver,
        uint256 _tokenAmount,
        uint256 _tokenPrice,
        uint256 _expiration,
        IERC20 _currency,
        IERC20 _token
    )
```

- `_salt`: a random number that influences the future contract address
- `_currencyPayer`: address of the investor that has granted the allowance in the currency contract
- `_tokenReceiver`: address of the investor that shall receive the tokens
- `_currencyReceiver`: address of the recipient of the payment
- `_tokenAmount`: amount of tokens the investor can to buy, in [bits](https://docs.openzeppelin.com/contracts/2.x/crowdsales#crowdsale-rate) (smallest subunit of the token, e.g. the equivalent of WEI for Ether)
- `_tokenPrice`: price per token denoted in the currency defined in the next field, and denominated in [bits](https://docs.openzeppelin.com/contracts/2.x/crowdsales#crowdsale-rate). Please refer to the [price explanation](price.md) for more details.
- `_expiration`: Unix timestamp at which the offer expires
- `_currency` : ERC20 token used for the payment. The `_buyer` must first give this contract the allowance to spend the amount he wants to invest.
- `_token` : address of the token deployed when creating the new company

The investment is executed during deployment of the contract. Therefore, three steps are necessary BEFORE deployment, or the deployment transaction will revert:

- All constructor arguments must be agreed upon to calculate the future address of the contract.
- The future contract address needs to be given a minting right in the company token contract by calling `increaseMintingAllowance` from an address which has the role of the Minter Admin. In that call, an allowance needs to be given which matches or exceeds the `_tokenAmount`. This step signals the offering company's invitation.
- The investor needs to give a a sufficient allowance in the currency contract to the future address of the contract. This step signals the investors commitment to the offer.

Once these steps have been completed, the Private Offer contract can be deployed by anyone (either of the two parties or a third party) with [CREATE2](https://docs.openzeppelin.com/cli/2.8/deploying-with-create2), through the Private Offer Factory's deploy() function.

## Public Fundraising / Starting on open round

Deploy the [contract](../contracts/PublicFundraising.sol) using the factory.

```solidity
factory.createPublicFundraisingClone(
        bytes32 _rawSalt,
        address _trustedForwarder,
        address _owner,
        address _currencyReceiver,
        uint256 _minAmountPerBuyer,
        uint256 _maxAmountPerBuyer,
        uint256 _tokenPrice,
        uint256 _maxAmountOfTokenToBeSold,
        IERC20 _currency,
        Token _token,
        uint256 _autoPauseDate
    )
```

- `_rawSalt`: a random number that influences the future contract address
- `_trustedForwarder`: contract that performs on-chain signature verification for [EIP-2771 meta transactions](../README.md#eip-2771)
- `_owner`: address of the owner of the fundraising contract. This address can change the parameters of the fundraising contract, and can pause it.
- `_currencyReceiver`: address of the recipient of the payment
- `_minAmountPerBuyer`: Minimum amount of tokens an investor needs to buy, in [bits](https://docs.openzeppelin.com/contracts/2.x/crowdsales#crowdsale-rate)

- `_maxAmountPerBuyer`: Maximum amount of tokens an investor can buy (can be the same as `_minAmountPerBuyer`), in [bits](https://docs.openzeppelin.com/contracts/2.x/crowdsales#crowdsale-rate)
- `_tokenPrice`: price per token denoted in `_currency`, and denominated in [bits](https://docs.openzeppelin.com/contracts/2.x/crowdsales#crowdsale-rate). Please refer to the [price explanation](price.md) for more details.

- `_maxAmountOfTokenToBeSold` : the maximum amount of token to be sold in this round, denominated in [bits](https://docs.openzeppelin.com/contracts/2.x/crowdsales#crowdsale-rate)

- `_currency` : ERC20 token used for the payment.

- `_token` : address of the token deployed when creating the new company
- `_autoPauseDate` : Unix timestamp at which the fundraising will be paused automatically. This is to ensure the fundraising can not be forgotten to be paused when regulations require it to be paused.

The contract needs to be given a minting allowance in the company token contract by calling `increaseMintingAllowance` from an address which has the role of the MintAllower. The allowance should be set to `_maxAmountOfTokenToBeSold` tokens.

An investor can buy tokens by calling the `buy(uint _amount)` function.
`_amount` ist the amount of tokens they are buying, in [bits](https://docs.openzeppelin.com/contracts/2.x/crowdsales#crowdsale-rate).

The investor needs to give a sufficient allowance in the currency contract to the PublicFundraising contract for the deal to be successful.

The owner of the PublicFundraising contract can pause the contract by calling `pause()`, which stops further buys. When paused, parameters of the fundraising can be changed. Each parameter change (re-)starts a cool down period of 24 hours. Only after this cool down period has passed can the fundraising be unpaused by calling `unpause()`. This is to ensure an investor can know the conditions that currently apply before investing (e.g. frontrunning a buy with a price increase is not possible).

# Employee participation with or without vesting

In case there is no vesting, tokens can directly be issued by calling the `mint()` function on the token contract.

For vesting the [Vesting.sol](../contracts/Vesting.sol) contract is used.

The contract needs to be given a sufficient minting allowance in the company token contract by calling `increaseMintingAllowance` from an address which has the role of MintAllower.
