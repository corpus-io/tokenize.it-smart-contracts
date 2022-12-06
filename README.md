# tokenize.it

These smart contracts implement [tokenize.it](https://tokenize.it/)'s tokenized cap table management.

# Getting Started

1. clone repository: `git clone --recurse-submodules git@github.com:corpus-ventures/tokenize.it-smart-contracts.git`
2. enter project root folder: `cd tokenize.it-smart-contracts`
3. if repository was cloned without submodules, init submodules now (not necessary if cloning command above was used): `git submodule update --init --recursive`
4. init project: `yarn install`
5. run tests: `forge test --no-match-test Mainnet`

If you are missing dependencies:

- node/npm:
  - install [nvm](https://github.com/nvm-sh/nvm)
  - `nvm install 18`
  - `nvm use 18`
- yarn: `npm install yarn`
- foundry: [install guide](https://book.getfoundry.sh/getting-started/installation)

For information regarding testing, please go to [testing](docs/testing.md).
There is no deploy script yet.

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

## EIP-2771

Two contracts use a trusted forwarder to implement EIP-2771. The forwarder used will be the openGSN v2 forwarder deployed on mainnet: https://docs-v2.opengsn.org/networks/ethereum/mainnet.html
It has been audited and working well for over a year. It's address is 0xAa3E82b4c4093b4bA13Cb5714382C99ADBf750cA, and it is also used in our [tests](./test/ContinuousFundraisingERC2771.t.sol).
Instead of leveraging the full potential of the gas station network, tokenize.it will have it's own service for sending eligible transactions to the forwarder.

## Supported Currencies

The currencies used for payments must conform to the ERC20 standard. This standard is not very strict though. It can be implemented in many ways, including **incompatible and even malicious contracts**. Therefore, tokenize.it will limit the currencies supported in the web frontend to this list:

- WETH: [0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2](https://etherscan.io/address/0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2)
- WBTC: [0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599](https://etherscan.io/address/0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599)
- USDC: [0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48](https://etherscan.io/address/0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48)
- EUROC: [0x1aBaEA1f7C830bD89Acc67eC4af516284b1bC33c](https://etherscan.io/address/0x1aBaEA1f7C830bD89Acc67eC4af516284b1bC33c)

These four implementations have been checked and tested to work well with the tokenize.it smart contracts. The use of any other currencies is HIGHLY DISCOURAGED and might lead to:

- loss of funds due to various attacks
- partial payments due to the currency deducting a transfer fee
- other issues

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
