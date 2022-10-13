# Create new company

## Setting up the contract

1. Deploy Token Contract “CorpusToken”: [https://github.com/corpus-ventures/corpus/blob/main/contracts/corpusToken.sol](https://github.com/corpus-ventures/corpus/blob/main/contracts/corpusToken.sol)
    Constructor: 
    ```solidity 
    constructor(address _admin, AllowList _allowList, uint256 _requirements, string memory*name, string memory symbol)
    ```

    - `admin` : address of the adminstrator. Be careful, he has all the power. He can do everything, and he can give permissions (aka roles as defined in the OpenZeppelin AccessControl modul). In the beginning, it is the ethereum address of the account connected through MetaMask*
    - `_allowList` : Allow list from corpus. Not deployed yet.
    - `_requirements`: requirements addresses need to fulfill in order to send and receive tokens
    - `_name` : Name of the Token (e.g. PiedPiperToken)
    - `_symbol` : Ticker of the Token (e.g. PPT)
2. Create initial cap table by minting tokens for various addresses. For this, the admin needs to give an account (can be himself) minting right by calling `setUpMinter(address *minter, uint _allowance)` : [https://github.com/corpus-ventures/corpus/blob/main/contracts/corpusToken.sol#L37](https://github.com/corpus-ventures/corpus/blob/main/contracts/corpusToken.sol#L37)
    
    - `minter` : account with minting rights*
    - `_allowance`: amount of tokens he can mint, denominated in its smallest subunit (e.g. WEI for Ether)

    To create the initial cap table, `_amount` should be the total amount of shares in existence.
    The minter, can then create new shares for each shareholder, by calling `mint(address *to, uint256 amount)` , where*
    `_to` is the shareholder
    `_amount` is the amount of shares, denominated in its smallest subunit (e.g. WEI for Ether)

## Enabling addresses to receive tokens
**All addresses which will receive tokens, through direct minting, investing or vesting, must be given the right to do so**, by either:

1. The `TransfererRoleAdmin` can give the `Transferer` -role to individual addresses
2. We as corpus will maintain a list of addresses with fine-grained properties. The `Requirement`-role can then choose which requirements are necessary to transfer the tokens. In case they set requirements to 0, everyone can freely use the token.

# Investments
### Limitations for acceptable amounts

Both types of investment contracts (Personal Invites and Continuous Fundraising) enforce `_amount *tokenPrice` to be a multiple of `10**token.decimals()`. This avoids rounding errors, making sure the price to be paid can precisely be expressed as integer. The requirement enforced is:

` (_amount * tokenPrice) % 10**token.decimals() == 0` 

See [price](price.md) for more background on this.

## Personal Invites

In order to create a personal investment invite this [contract](https://github.com/corpus-ventures/corpus/blob/main/contracts/PersonalInvite.sol) needs to be deployed.

Constructor: 
```solidity 
constructor(address payable _buyer, address payable _receiver, uint _minAmount, uint _maxAmount, uint _tokenPrice, uint _expiration, IERC20 _currency, MintableERC20 _token)
```

- `_buyer`: address of the investor

- `_receiver`: address of the recipient of the payment
- `_minAmount`: Minimal amount of tokens the investor needs to buy, in [bits](https://docs.openzeppelin.com/contracts/2.x/crowdsales#crowdsale-rate) (smallest subunit of the token, e.g. the equivalent of WEI for Ether)

- `_maxAmount`: Maximal amount of tokens the investor can buy (can be the same as `_minAmount`), in [bits](https://docs.openzeppelin.com/contracts/2.x/crowdsales#crowdsale-rate)
`_tokenPrice`: price per token denoted in the currency defined in the next field, and denominated in [bits](https://docs.openzeppelin.com/contracts/2.x/crowdsales#crowdsale-rate). Please refer to the [price explanation](price.md) for more details.

- `_expiration`: Unix timestamp  at which the offer expires

- `_currency` : ERC20 token used for the payment. The `_buyer` must first give this contract the allowance to spend the amount he wants to invest.

- `_token` : address of the corpus token deployed when creating the new company

The contract needs to be given minting right in the company token contract by calling `setUpMinter` from an address which has the role of the Minter Admin. In that call, an allowance needs to be given which matches the `_maxAmount` of tokens.

For the investor to accept the personal invite, the function `deal(uint *amount)` needs to be called, where `*amount`  is the amount of tokens the investor is buying.

Limitations apply for `_amount`, see [above](###-Limitations-for-acceptable-amounts)

The investor needs to give a a sufficient allowance in the currency contract to the personalInvite contract for the deal to be successful

The personal investment invite can be withdrawn by the same address who deployed the contract by calling `revoke()` 

## Continuous Fundraising / Starting on open round

Deploy the  [contract](https://github.com/corpus-ventures/corpus/blob/main/contracts/ContinuousFundraising.sol)

Constructor: `constructor(address payable _currencyReceiver, uint _minAmountPerBuyer, uint _maxAmountPerBuyer, uint _tokenPrice, uint _maxAmountOfTokenToBeSold, IERC20 _currency, EIERC20 _token)`

The parameter are similar to the PersonalInvite constructor, except for:

- `_currencyReceiver`: address of the recipient of the payment
- `_minAmountPerBuyer`: Minimal amount of tokens an investor needs to buy, in [bits](https://docs.openzeppelin.com/contracts/2.x/crowdsales#crowdsale-rate)

- `_maxAmountPerBuyer`: Maximal amount of tokens an investor can buy (can be the same as `_minAmount`), in bits
`_tokenPrice`: price per token denoted in the currency defined in the next field, and denominated in [bits](https://docs.openzeppelin.com/contracts/2.x/crowdsales#crowdsale-rate) (smallest subunit, e.g. WEI for Ether). Please refer to the [price explanation](price.md) for more details.

- `_maxAmountOfTokenToBeSold` : the maximum amount of token to be sold in this round, denominated in [bits](https://docs.openzeppelin.com/contracts/2.x/crowdsales#crowdsale-rate)

- `_currency` : ERC20 token used for the payment. The `_buyer` must first give this contract the allowance to spend the amount he wants to invest.

- `_token` : address of the token deployed when creating the new company



The contract needs to be given minting right in the company token contract by calling `setUpMinter` from an address which has the role of the Minter Admin. In that call, an allowance needs to be given which matches the `_maxAmountOfTokenToBeSold` of tokens.

An investor can buy tokens by calling the `buy(uint _amount)` function.
`_amount` ist the amount of tokens he/she is buying. 

Limitations apply for `_amount`, see [above](###-Limitations-for-acceptable-amounts)

The investor needs to give a a sufficient allowance in the currency contract to the continuousFundraising contract for the deal to be successful

The account who has created the continuous round can pause the contract by calling `pause()`, which stopps further buys. When paused, all parameters of the fundraising can be changed through setter functions in the contract. Pausing the contract as well as each setting update starts a cooldown period (defaulting to 24h hours). Only after this cooldown period has passed can the fundraising be unpaused by calling `unpause()`. This is to ensure an investor can know the conditions that currently apply before investing.

# Employee participation with or without vesting

In case there is no vesting, shares can directly be issued through minting as described when setting up a new company.

For vesting the contract [DssVestMintable by makerdao](https://github.com/makerdao/dss-vest/blob/master/src/DssVest.sol)  is used. See [documentation](https://github.com/makerdao/dss-vest) for general usage information.

The contract needs to be given minting right in the company token contract by calling `setUpMinter` from an address which has the role of the Minter Admin. In that call, an allowance needs to be given which matches the maximal amount of tokens to be vested.
 



