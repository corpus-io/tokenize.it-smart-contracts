## Token.sol

The [token contract](./contracts/Token.sol) is based on the OpenZeppelin ERC20 contract using the AccessControl extension. It also implements meta transactions following [EIP-2771](https://eips.ethereum.org/EIPS/eip-2771) and [EIP-2612](https://eips.ethereum.org/EIPS/eip-2612).
Beyond being an ERC20 token, it has fine grained access control to:

- define who can set requirements which a user has to meet in order to transact
- define burning rights (only company admin)
- define who is allowed to transfer the token
- define who is allowed to pause the contract
- define minting rights (through increaseMintingAllowance and decreaseMintingAllowance functions)

### Minting

Minting is very central to the usage of this contract. The MintAllower role (see [access control](https://docs.openzeppelin.com/contracts/2.x/access-control)) can give an address a minting allowance. For example the admin (or CEO) of the company might need a minting allowance to create new shares. Each investment or vesting contract also needs a minting allowance in order to function.
The allowances are stored in the map `mintingAllowance`.

### Requirements

We expect that the companies issuing a token through tokenize.it need control about who can transact with the token for compliance reasons.
There are two ways to control who can transact with the token:

1. The `TransfererRoleAdmin` can give the `Transferer`-role to individual addresses
2. We as tokenize.it will maintain a list of addresses with fine-grained properties. The `Requirement`-role can then choose which requirements are necessary to transfer the tokens. In case they set requirements to 0, everyone can freely use the token.

## Investments

Please read the [supported currencies](../README.md#supported-currencies) section first.
Remember that extra tokens will be minted to cover [fees](fees.md), and fees will also be deducted from the payment, unless the fee is set to 0.

There are 2 investment contracts:

### 1. Personal invite (PrivateOffer.sol)

This is a personal investment invite allowing a particular investor (represented by their ethereum address) to buy newly issued tokens at a fixed price. The contract is deployed using CREATE2, and the investment is executed during deployment. [Read this](./using_the_contracts.md#personal-invites) for more information.

### 2. PublicFundraising (PublicFundraising.sol)

This contract allows everyone who has the `Transferer`-role on the `token` contract or who is certified by the allow-list to meet the requirements set in the `token` contract to buy newly issued tokens at a fixed price. The number of token that can be minted in this way can be limited to `maxAmountOfTokenToBeSold`, which is the maximal amount of token to be sold in this fundraising round.

Furthermore, this contract can be paused by the owner to change the parameters. The pause is always at least 1 day, and starts new after each parameter change.

## Employee participation

In case there is no vesting, shares can directly be issued through minting as described when setting up a new company.

For vesting the contract [DssVestMintable by makerdao](https://github.com/makerdao/dss-vest/blob/master/src/DssVest.sol) is used. See [documentation](https://github.com/makerdao/dss-vest) for general usage information.

The contract needs to be given a minting allowance of maximum amount of tokens to be vested in the company token contract by calling `increaseMintingAllowance(contractAddress, amount)` from an address which has the MintAllower role.
