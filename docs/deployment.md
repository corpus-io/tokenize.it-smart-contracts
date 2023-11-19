# Deployment

## Platform

The platform-related contracts are:

1. [allowList](../contracts/AllowList.sol)
2. [feeSettings](../contracts/FeeSettings.sol)
3. [TokenFactory](../contracts/TokenProxyFactory.sol)
4. [PrivateOfferCloneFactory](../contracts/PrivateOfferCloneFactory.sol)
5. [CrowdinvestingFactory](../contracts/CrowdinvestingCloneFactory.sol)
6. [VestingFactory](../contracts/VestingCloneFactory.sol)
7. [PriceLinearFactory](../contracts/PriceLinearCloneFactory.sol) or other dynamic pricing factories

Some of them can be deployed manually. A script is provided to automate some of the deployment steps though. It can quickly be adapted to deploy more or less of these contracts.

The script is called like this:

```bash
source .env
forge script script/DeployPlatform.s.sol:DeployPlatform --rpc-url $GOERLI_RPC_URL --broadcast --verify --private-key $PRIVATE_KEY
```

Note:

- for this to work, prepare an [environment file](https://book.getfoundry.sh/tutorials/solidity-scripting#environment-configuration) first
- drop the --broadcast in order to simulate the transaction, but not publish it
- edit the script (commenting out parts) to deploy less contracts
- generally, contracts with simple constructor arguments can also be deployed without script:
  ```bash
  forge create --rpc-url $GOERLI_RPC_URL --private-key $PRIVATE_KEY --verify --etherscan-api-key=$ETHERSCAN_API_KEY contracts/AllowList.sol:AllowList
  forge create --rpc-url $GOERLI_RPC_URL --private-key $PRIVATE_KEY --verify --etherscan-api-key=$ETHERSCAN_API_KEY contracts/PrivateOfferCloneFactory.sol:PrivateOfferCloneFactory
  forge create --rpc-url $GOERLI_RPC_URL --private-key $PRIVATE_KEY --verify --etherscan-api-key=$ETHERSCAN_API_KEY contracts/VestingWalletFactory.sol:VestingWalletFactory
  ```

**After the contracts have been deployed like this, they are still owned by the wallet used for deployment. Don't forget to transfer ownership to a safer address, like a multisig.**

## Companies

The company-related contracts are:

- Token.sol
- Crowdinvesting.sol
- PrivateOffer.sol

They are deployed through the web app.

For development purposes, the contracts can be deployed by adapting this script and executing it:

```bash
forge script script/DeployToken.s.sol --rpc-url $GOERLI_RPC_URL  --verify --broadcast
```

## Forwarder

If the forwarder has not been deployed yet, e.g. when working in a testing environment, it can be deployed like this:
`forge create node_modules/@opengsn/contracts/src/forwarder/Forwarder.sol:Forwarder --private-key $PRIVATE_KEY --rpc-url $GOERLI_RPC_URL --verify --etherscan-api-key $ETHERSCAN_API_KEY`

## Contract Verification

As the web app does not automatically verify the contracts (with etherscan or other services), this needs to be done manually. Use hardhat or foundry for this purpose. Sometimes one or the other works better.

### hardhat

The Crowdinvesting contract can be verified like this:

```
yarn hardhat verify --network goerli 0x29b659E948616815FADCD013f6BfC767da1BDe83 0x0445d09A1917196E1DC12EdB7334C70c1FfB1623 0xA1e28D1f17b7Da62d10fbFaFCA98Fa406D759ce2 10000000000000000000 50000000000000000000 1000000 100000000000000000000 0x07865c6E87B9F70255377e024ace6630C1Eaa37F 0xc1C74cbD565D16E0cCe9C5DCf7683368DE4E35e2
```

Everything behind the first address is a constructor argument.

Even better is to use a file for the constructor arguments. Create a file `constructorArguments.js` with the following content:

```
module.exports = [
    "0x0445d09A1917196E1DC12EdB7334C70c1FfB1623",
    "0xA1e28D1f17b7Da62d10fbFaFCA98Fa406D759ce2",
    "10000000000000000000",
    "50000000000000000000",
    "1000000",
    "100000000000000000000",
    "0x07865c6E87B9F70255377e024ace6630C1Eaa37F",
    "0x1672E16ac9CeF8f9Fc31daFB21d637a23415DEf6"
];
```

And then verify like this:

```
npx hardhat verify --network goerli 0xC64519eC6Bd54F14323a34E122c4c798cF5AeD53 --constructor-args constructorArguments.js
```

Be careful to use the proper configuration in hardhat.config.js. Even if the optimizer is disabled, the number of runs configured has some influence on the resulting bytecode:

```
optimizer: {
        enabled: false,
        runs: 200,
      },
```

### foundry

Example for token verification:

```
forge verify-contract 0x458A75E83c50080279e8d8e870cF0d0F4B48C01b --constructor-args-path verificationArguments/foundry/Token --chain goerli Token
```

Provide the constructor arguments separated by whitespace in a file like this:

```
0x0445d09A1917196E1DC12EdB7334C70c1FfB1623 0x387aD1Aa745C70829b651B3F2D3E7852Df961C93 0x2Db0DD9394f851baefD1FA3334c6B188A0C0548D 0x274ca5f21Cdde06B6E4Fe063f5087EB6Cf3eAe55 0 'Max Mustermann Token' 'MAXMT'
```

More info can be found [here](https://book.getfoundry.sh/reference/forge/forge-verify-contract).
