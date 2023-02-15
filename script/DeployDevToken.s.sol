// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

// taken from https://moveseventyeight.com/deploy-your-first-nft-contract-with-foundry#heading-prepare-a-basic-deployment-script

import "../lib/forge-std/src/Script.sol";
import "../contracts/FeeSettings.sol";
import "../contracts/AllowList.sol";
import "../contracts/PersonalInviteFactory.sol";

contract DeployToken is Script {
    function setUp() public {}

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployerAddress = vm.addr(deployerPrivateKey);
        vm.startBroadcast(deployerPrivateKey);

        console.log("Deployer address: ", deployerAddress);
        Fees memory fees = Fees(20, 20, 20, 0);
        FeeSettings feeSettings = new FeeSettings(fees, deployerAddress);
        //FeeSettings(    0x147addF9C8E4030F8104c713Dad2A1d76E6c85a1);
        console.log("FeeSettings at: ", address(feeSettings));

        AllowList allowList = new AllowList();
        //AllowList(            0x274ca5f21Cdde06B6E4Fe063f5087EB6Cf3eAe55);
        console.log("Allowlist at: ", address(allowList));
        address admin = 0x6CcD9E07b035f9E6e7f086f3EaCf940187d03A29;
        string memory name = "MyTasticToken";
        string memory symbol = "MTT";
        address forwarder = 0x0445d09A1917196E1DC12EdB7334C70c1FfB1623;
        uint256 requirements = 0x0;

        console.log("Deploying Token contract...");

        Token token = new Token(
            forwarder,
            feeSettings,
            admin,
            allowList,
            requirements,
            name,
            symbol
        );

        vm.stopBroadcast();

        console.log("Token deployed at: ", address(token));
    }
}
