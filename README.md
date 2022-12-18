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

It is possible to directly use all smart contracts in this project, without going through the platform's frontend at all.
In order to improve UX, though, a frontend will be offered. In order to improve UX even more, the user will not have to pay gas when using this frontend. This is achieved through two approaches:

1. the platform executes transactions like contract deployments
2. actions concerning our own contracts that require the user's approval are executed as meta-transactions, using EIP-2711
3. granting allowances on external currencies is possible through EIP-2612 (ERC20Permit), which is widely adopted. This is not in the scope of this documentation though.

Two contracts implement [EIP-2771](https://eips.ethereum.org/EIPS/eip-2771), and therefore use a trusted forwarder. The forwarder will be set in the constructor and there is no way to change it after deployment. The forwarder used will be the openGSN v2 forwarder deployed on mainnet. Some information about this contract:

- [Documentation and addresses](https://docs-v2.opengsn.org/networks/ethereum/mainnet.html)
- [Audit reports](https://docs-v2.opengsn.org/audits.html)
- Was deployed 2022-04-21
- It's address is **0xAa3E82b4c4093b4bA13Cb5714382C99ADBf750cA**
- Visit on [etherscan](https://etherscan.io/address/0xaa3e82b4c4093b4ba13cb5714382c99adbf750ca) ([see transactions here](https://etherscan.io/txsInternal?a=0xAa3E82b4c4093b4bA13Cb5714382C99ADBf750cA&&m=advanced&p=1))
- This [dashboard](https://dune.com/oren/meta-transactions-on-ethereum-over-time) lists the forwarder as second most active forwarder contract with over 2000 transactions executed
- it is also used in our [tests](./test/ContinuousFundraisingERC2771.t.sol).

The platform will maintain a hot wallet (EOA) in order to send transactions to the forwarder contract. This results in the following flow:

- contract A supports EIP-2771 and uses `forwarder` as its (one and only immutable) trusted forwarder
- user (investor or founder) wants to use function `a(...)` of contract `A` and uses the platform for this
- platform (tokenize.it) prepares meta transaction payload and asks user for signature
- user signs the payload with their own key (using metamask or similar)
- platform now has payload and signature and uses its hot wallet to call `forwarder.execute(payload, signature, ...)`
- forwarder verifies signature and payload on-chain
- forwarder executes `A.a(...)` with parameters according to payload
- contract `A` only verifies it is being called by the ONE forwarder it trusts. It does not verify any signatures. This is why the forwarder is called trusted forwarder: it is trusted to do the verification.
- contract `A` executes function `a(...)` in the name of user

This is a trustless process, because:

1. the forwarder contract can not be updated
2. the trusted forwarder setting in contract A is immutable
3. signature verification is executed on-chain

Open gas station network provides tools to execute meta transactions without involving a third party hot wallet. Tokenize.it does not plan on using these tools though. Exclusively using a hot wallet for transaction execution does not harm security at all.

The hot wallet approach might reduce availability, which is not a major concern for this use case (the hot wallet being available whenever the frontend is available is good enough). Keep in mind that EIP-2771 is purely offered for UX reasons. All smart contracts can be used directly, too, further reducing concerns about hot wallet availability.

An [Openzeppelin Defender Relay](https://docs.openzeppelin.com/defender/relay) may be used as hot wallet.

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
- [Deployment](./docs/deployment.md)
- Remaining questions: please get in touch at [hi@tokenize.it](mailto:hi@tokenize.it)
