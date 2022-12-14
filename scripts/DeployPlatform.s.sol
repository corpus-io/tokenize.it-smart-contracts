// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

// taken from https://moveseventyeight.com/deploy-your-first-nft-contract-with-foundry#heading-prepare-a-basic-deployment-script

import "../lib/forge-std/src/Script.sol";
import "../contracts/FeeSettings.sol";
import "../contracts/AllowList.sol";

contract DeployPlatform is Script {
    function setUp() public {}

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployerAddress = vm.addr(deployerPrivateKey);

        console.log("Deployer address: ", deployerAddress);

        vm.broadcast(deployerPrivateKey);

        console.log("Deploying FeeSettings contract...");
        Fees memory fees = Fees(20, 20, 20, 0);
        FeeSettings feeSettings = new FeeSettings(fees, deployerAddress);
        console.log("FeeSettings deployed at: ", address(feeSettings));

        console.log("Deploying AllowList contract...");
        AllowList allowList = new AllowList();
        console.log("Allowlist deployed at: ", address(allowList));

        vm.stopBroadcast();

        console.log(
            "Don't forget to transfer ownership to another address! Currently, the deployer is the owner."
        );
    }
}
