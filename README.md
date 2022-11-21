# tokenize.it

These smart contracts implement [tokenize.it](https://tokenize.it/)'s tokenized cap table management.

# Developers

For information regarding testing, please go to [testing](docs/testing.md)

# Main Concept

1. All shares of a company are tokenized using the [Token.sol](contracts/Token.sol) contract
2. Funds are raised through selling of these tokens:
   - a customized deal to a specific investor can be realized through the [PersonalInvite.sol](contracts/archive/PersonalInvite.sol) contract
   - continuous fundraising, which is open to everyone meeting the requirements, is done through the [ContinuousFundraising.sol](contracts/ContinuousFundraising.sol) contract
3. Employee participation is easy:
   - direct distribution of tokens (does not need another smart contract)
   - vesting can be realized using the [DssVest.sol](https://github.com/makerdao/dss-vest/blob/master/src/DssVest.sol) contract by MakerDao

The requirements for participation in fundraising are checked against the [AllowList.sol](contracts/AllowList.sol) contract. Tokenize.it will deploy and manage one of these.

# Contracts

All contracts are based on the well documented and tested [OpenZeppelin smart contract suite](https://docs.openzeppelin.com/contracts/4.x/).

The following resources are available regarding the contracts:

- Basic overview: see below
- [Usage walkthrough](docs/using_the_contracts.md)
- [Price format explainer](docs/price.md)
- In-depth explanation: please read the [contracts](contracts/)
- [Specification](docs/specification.md)
- [Fee Collection](./docs/fees.md)
- Remaining questions: please get in touch at [hi@tokenize.it](mailto:hi@tokenize.it)

## Token.sol

The [token contract](./contracts/Token.sol) is based on the OpenZeppelin ERC20 contract using the AccessControl extension. Also implements meta transactions following [EIP-2771](https://eips.ethereum.org/EIPS/eip-2771) and [EIP-2612](https://eips.ethereum.org/EIPS/eip-2612).
Beyond being an ERC20 token, it has fine grained access control to:

- define minting rights
- setting requirements which a user has to meet in order to transact
- define burning rights (only company admin)
- define who is allowed to transfer the token
- define who is allowed to pause the contract

### Minting

According to the AccessControl module, there is an admin for each role, which controls who holds this role. Minting is very central to the usage of this contract. The Minteradmin can give an address minter rights. For example the admin (or CEO) of the company, to create new shares.
Each investment or vesting contract also needs minting rights in order to function.
In addition to the right to mint, there is also a minting allowance, which needs to be issued by the Minteradmin. This is stored in the map `mintingAllowance`

### Requirements

We expect that the companies issuing a token through tokenize.it need control about who can transact with the token for compliance reasons.
There are two ways to control who can transact with the token:

1. The `TransfererRoleAdmin` can give the `Transferer`-role to individual addresses
2. We as tokenize.it will maintain a list of addresses with fine-grained properties. The `Requirement`-role can then choose which requirements are necessary to transfer the tokens. In case they set requirements to 0, everyone can freely use the token.

## Investments

Currently, WETH, WBTC, USDC, EUROC are supported as investment currencies.

There are 2 types of investments:

### 1. Personal invite (PersonalInvite.sol)

This is a personal investment invite allowing a particular investor (represented by his/her ethereum address) to buy newly issued tokens at a fixed price. The contract is deployed using CREATE2, and the investment is executed during deployment. [Read this](./docs/using_the_contracts.md#personal-invites) for more information.

### 2. ContinuousFundraising (ContinuousFundraising.sol)

This contract allows everyone who has the `Transferer`-role on the `token` contract or who is certified by the allow-list to meet the requirements set in the `token` contract to buy newly issued tokens at a fixed price. Until a certain threshold of maximal tokens to be issued is met.
The arguments in the constructor are similar to PersonalInvite.sol, with the addition of `maxAmountOfTokenToBeSold` , which is the maximal amount of token to be sold in this fundraising round.

Furthermore, this contract can be paused by the owner to change the parameters. The pause is always at least 1 day.

## Employee participation

In case there is no vesting, shares can directly be issued through minting as described when setting up a new company.

For vesting the contract [DssVestMintable by makerdao](https://github.com/makerdao/dss-vest/blob/master/src/DssVest.sol) is used. See [documentation](https://github.com/makerdao/dss-vest) for general usage information.

The contract needs to be given minting right in the company token contract by calling `setUpMinter` from an address which has the role of the Minter Admin. In that call, an allowance needs to be given which matches the maximal amount of tokens to be vested.
