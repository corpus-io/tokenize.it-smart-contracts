# Deployment

## Platform

The platform-related contracts are:

- AllowList.sol
- FeeSettings.sol
- PersonalInviteFactory.sol

Currently, there is no need for them to be deployed automatically. Instead, deployment can be done with foundry. For some background, review the [foundry book's chapter on deployments](https://book.getfoundry.sh/forge/deploying).

Deploy these contracts like this:

```bash
source .env
forge script scripts/DeployPlatform.s.sol:DeployPlatform --rpc-url $GOERLI_RPC_URL --broadcast --verify --etherscan-api-key=$ETHERSCAN_API_KEY --private-key $PRIVATE_KEY
```

Note:

- for this to work, prepare an [environment file](https://book.getfoundry.sh/tutorials/solidity-scripting#environment-configuration) first
- drop the --broadcast in order to simulate the transaction, but not publish it
- edit the script (commenting out parts) to deploy less contracts
- generally, contracts with simple constructor arguments can also be deployed without script:
  ```bash
  forge create --rpc-url $GOERLI_RPC_URL --private-key $PRIVATE_KEY --verify --etherscan-api-key=$ETHERSCAN_API_KEY contracts/AllowList.sol:AllowList
  forge create --rpc-url $GOERLI_RPC_URL --private-key $PRIVATE_KEY --verify --etherscan-api-key=$ETHERSCAN_API_KEY contracts/PersonalInviteFactory.sol:PersonalInviteFactory
  ```

**After the contracts have been deployed like this, they are still owned by the wallet used for deployment. Don't forget to transfer ownership to a safer address, like a multisig.**

## Companies

The company-related contracts are:

- Token.sol
- ContinuousInvestment.sol
- PersonalInvite.sol

They are deployed through the web app.

As long as automatic verification is not implemented, the contracts need to be verified manually. Doing this with foundry was not successful, possibly because they are compiled using hardhat. The ContinuousFundraising contract can be verified like this:

```
yarn hardhat verify --network goerli 0x29b659E948616815FADCD013f6BfC767da1BDe83 0x0445d09A1917196E1DC12EdB7334C70c1FfB1623 0xA1e28D1f17b7Da62d10fbFaFCA98Fa406D759ce2 10000000000000000000 50000000000000000000 1000000 100000000000000000000 0x07865c6E87B9F70255377e024ace6630C1Eaa37F 0xc1C74cbD565D16E0cCe9C5DCf7683368DE4E35e2
```

The everything behind the first address is a constructor argument.
