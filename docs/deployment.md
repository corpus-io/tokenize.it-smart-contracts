# Deployment

## Platform

The platform-related contracts are:

- AllowList.sol
- FeeSettings.sol
- PersonalInviteFactory.sol

Currently, there is no need for them to be deployed automatically. Instead, deployment can be done with foundry. For some background, review the [foundry book's chapter on deployments](https://book.getfoundry.sh/forge/deploying).

Deploy both contract like this:

```bash
source .env
forge script scripts/DeployPlatform.s.sol:DeployPlatform --rpc-url $GOERLI_RPC_URL --broadcast
```

Note:

- for this to work, prepare an [environment file](https://book.getfoundry.sh/tutorials/solidity-scripting#environment-configuration) first
- drop the --broadcast in order to simulate the transaction, but not publish it
- edit the script (commenting out parts) to deploy just one of the contracts instead of both
- generally, contracts with simple constructor arguments can also be deployed without script:
  ```bash
  forge create --rpc-url $GOERLI_RPC_URL --private-key $PRIVATE_KEY contracts/AllowList.sol:AllowList
  ```

**After the contracts have been deployed like this, they are still owned by the wallet used for deployment. Don't forget to transfer ownership to a safer address, like a multisig.**

## Companies

The company-related contracts are:

- Token.sol
- ContinuousInvestment.sol
- PersonalInvite.sol

It will be possible to deploy those through the web app.
