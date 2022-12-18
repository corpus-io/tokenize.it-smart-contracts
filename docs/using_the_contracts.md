# Create new company

## Prerequisites

Tokenize.it has already deployed:

1. [allowList](../contracts/AllowList.sol)
2. [feeSettings](../contracts/FeeSettings.sol)
3. [PersonalInviteFactory](../contracts/PersonalInviteFactory.sol)

These will be used for the next steps.

## Setting up the token contract

1. Deploy Token Contract “Token”:

   ```solidity
   constructor(
        address _trustedForwarder,
        FeeSettings _feeSettings,
        address _admin,
        AllowList _allowList,
        uint256 _requirements,
        string memory _name,
        string memory _symbol
    )
   ```

   - `trustedForwarder`: used for meta transactions following [EIP-2771](https://eips.ethereum.org/EIPS/eip-2771)
   - `feeSettings`: defines which fees have to be paid for minting and investing
   - `admin` : address of the administrator. Be careful, they have all the power in the beginning. They can do everything, and can give permissions (aka roles as defined in the OpenZeppelin AccessControl module).
   - `_allowList` : Allow list from tokenize.it.
   - `_requirements`: requirements addresses need to fulfill in order to send and receive tokens
   - `_name` : Name of the Token (e.g. PiedPiperToken)
   - `_symbol` : Ticker of the Token (e.g. PPT)

2. Create initial cap table by minting tokens for various addresses.

For this, the admin needs to give an account (can be himself) minting rights by calling `setMintingAllowance(address minter, uint _allowance)` :

- `minter` : account that will be granted the minting allowance
- `_allowance`: amount of tokens they can mint, denominated in [bits](https://docs.openzeppelin.com/contracts/2.x/crowdsales#crowdsale-rate).

To create the initial cap table, `_allowance` should be the total amount of shares in existence so far.

The minter can then create new shares for each shareholder, by calling `mint(address _to, uint256 _amount)`, where:

- `_to` is the shareholder's address
- `_amount` is the amount of shares the shareholder holds, denominated in [bits](https://docs.openzeppelin.com/contracts/2.x/crowdsales#crowdsale-rate)

## Enabling addresses to receive tokens

**All addresses which will receive tokens, through direct minting, investing or vesting, must be given the right to do so**, by either:

1. The `TransfererRoleAdmin` can give the `Transferer` -role to individual addresses
2. Tokenize.it will maintain an [allowList](../contracts/AllowList.sol), a list of addresses with fine-grained properties. The `Requirement`-role can then choose which requirements are necessary to transfer the tokens. In case they set requirements to 0, everyone can freely use the token.

# Investments

## Personal Invites

In order to create a personal investment invite this [contract](../contracts/PersonalInvite.sol) needs to be used.

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

The investment is executed during deployment of the contract. Therefore, two steps are necessary BEFORE deployment, or the deployment transaction will revert:

- The future contract address needs to be given minting right in the company token contract by calling `setMintingAllowance` from an address which has the role of the Minter Admin. In that call, an allowance needs to be given which matches or exceeds the `_amount` of tokens. This step signals the offering company's invitation.
- The investor needs to give a a sufficient allowance in the currency contract to the future address of the contract. This step signals the investors commitment to the offer.

Once both steps have been completed, the Personal Invite contract can be deployed by anyone (either of the two parties or a third party) with [CREATE2](https://docs.openzeppelin.com/cli/2.8/deploying-with-create2), through the Personal Invite Factory's deploy() function.
Limitations apply for `_amount`, see [above](###-Limitations-for-acceptable-amounts)

## Personal Invite Factory

This [contract](../contracts/PersonalInviteFactory.sol) can be used to:

1. Calculate the future address of a PersonalInvite
2. Deploy the PersonalInvite to this address

## Continuous Fundraising / Starting on open round

Deploy the [contract](../contracts/ContinuousFundraising.sol)

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

The parameter are similar to the PersonalInvite constructor, except for:

- `_currencyReceiver`: address of the recipient of the payment
- `_minAmountPerBuyer`: Minimal amount of tokens an investor needs to buy, in [bits](https://docs.openzeppelin.com/contracts/2.x/crowdsales#crowdsale-rate)

- `_maxAmountPerBuyer`: Maximal amount of tokens an investor can buy (can be the same as `_minAmount`), in bits
  `_tokenPrice`: price per token denoted in the currency defined in the next field, and denominated in [bits](https://docs.openzeppelin.com/contracts/2.x/crowdsales#crowdsale-rate) (smallest subunit, e.g. WEI for Ether). Please refer to the [price explanation](price.md) for more details.

- `_maxAmountOfTokenToBeSold` : the maximum amount of token to be sold in this round, denominated in [bits](https://docs.openzeppelin.com/contracts/2.x/crowdsales#crowdsale-rate)

- `_currency` : ERC20 token used for the payment. The `_buyer` must first give this contract the allowance to spend the amount he wants to invest.

- `_token` : address of the token deployed when creating the new company

The contract needs to be given minting right in the company token contract by calling `setMintingAllowance` from an address which has the role of the Minter Admin. In that call, an allowance needs to be given which matches the `_maxAmountOfTokenToBeSold` of tokens.

An investor can buy tokens by calling the `buy(uint _amount)` function.
`_amount` ist the amount of tokens he/she is buying.

Limitations apply for `_amount`, see [above](###-Limitations-for-acceptable-amounts)

The investor needs to give a a sufficient allowance in the currency contract to the continuousFundraising contract for the deal to be successful

The account who has created the continuous round can pause the contract by calling `pause()`, which stops further buys. When paused, all parameters of the fundraising can be changed through setter functions in the contract. Pausing the contract as well as each setting update starts a cool down period (defaulting to 24h hours). Only after this cool down period has passed can the fundraising be unpaused by calling `unpause()`. This is to ensure an investor can know the conditions that currently apply before investing.

# Employee participation with or without vesting

In case there is no vesting, shares can directly be issued through minting as described when setting up a new company.

For vesting the contract [DssVestMintable by makerdao](https://github.com/makerdao/dss-vest/blob/master/src/DssVest.sol) is used. See [documentation](https://github.com/makerdao/dss-vest) for general usage information.

The contract needs to be given minting right in the company token contract by calling `setMintingAllowance` from an address which has the role of the Minter Admin. In that call, an allowance needs to be given which matches the maximal amount of tokens to be vested.
