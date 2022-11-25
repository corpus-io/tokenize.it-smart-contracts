# tokenize.it

These smart contracts implement [tokenize.it](https://tokenize.it/)'s tokenized cap table management.

# Getting Started

1. clone repository: `git clone --recurse-submodules git@github.com:corpus-ventures/tokenize.it-smart-contracts.git`
2. enter project root folder: `cd tokenize.it-smart-contracts`
3. if repository was cloned without submodules, init submodules now (not necessary if cloning command above was used): `git submodule update --init --recursive`
4. init project: `yarn install`
5. run tests: `forge test --no-match-test Mainnet`

For information regarding testing, please go to [testing](docs/testing.md). There is no deploy script yet.

# Main Concept

1. All shares of a company are tokenized using the [Token.sol](contracts/Token.sol) contract
2. Funds are raised through selling of these tokens:
   - a customized deal to a specific investor can be realized through the [PersonalInvite.sol](contracts/archive/PersonalInvite.sol) contract
   - continuous fundraising, which is open to everyone meeting the requirements, is done through the [ContinuousFundraising.sol](contracts/ContinuousFundraising.sol) contract
3. Employee participation is easy:
   - direct distribution of tokens (does not need another smart contract)
   - vesting can be realized using the [DssVest.sol](https://github.com/makerdao/dss-vest/blob/master/src/DssVest.sol) contract by MakerDao

The requirements for participation in fundraising are checked against the [AllowList.sol](contracts/AllowList.sol) contract. Fees are collected according to the settings in [FeeSettings.sol](./contracts/FeeSettings.sol). Tokenize.it will deploy and manage at least one AllowList and one FeeSettings contract.

# Contracts

The smart contracts can be found in the contracts/ folder.

All contracts are based on the well documented and tested [OpenZeppelin smart contract suite](https://docs.openzeppelin.com/contracts/4.x/).

# Resources

The following resources are available regarding the contracts:

- [Basic high level overview](docs/user_overview.md)
- [Basic dev overview](docs/dev_overview.md)
- [More detailed walkthrough](docs/using_the_contracts.md)
- In-depth explanation: please read the [contracts](contracts/)
- [Specification](docs/specification.md)
- [Price format explainer](docs/price.md)
- [Fee Collection](./docs/fees.md)
- Remaining questions: please get in touch at [hi@tokenize.it](mailto:hi@tokenize.it)
