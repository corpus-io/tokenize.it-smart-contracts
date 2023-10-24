// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

// taken from https://moveseventyeight.com/deploy-your-first-nft-contract-with-foundry#heading-prepare-a-basic-deployment-script

import "../lib/forge-std/src/Script.sol";
import "../contracts/FeeSettings.sol";
import "../contracts/AllowList.sol";
import "../contracts/PrivateOfferFactory.sol";
import "../contracts/VestingWalletFactory.sol";

contract DeployPlatform is Script {
    function setUp() public {}

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployerAddress = vm.addr(deployerPrivateKey);

        // Goerli
        //address platformColdWallet = 0x1695F52e342f3554eC8BC06621B7f5d1644cCE39;
        //address platformAdminWallet = 0x1695F52e342f3554eC8BC06621B7f5d1644cCE39;

        // Mainnet
        address platformColdWallet = 0x9E23f8AA17B2721cf69D157b8a15bd7b64ac881C;
        address platformAdminWallet = platformColdWallet;

        console.log("Deployer address: ", deployerAddress);

        vm.startBroadcast(deployerPrivateKey);

        console.log("Deploying FeeSettings contract...");
        Fees memory fees = Fees(100, 100, 100, 0);
        FeeSettings feeSettings = new FeeSettings(fees, platformColdWallet, platformColdWallet, platformColdWallet);
        console.log("FeeSettings deployed at: ", address(feeSettings));
        feeSettings.transferOwnership(platformColdWallet);
        console.log("Started ownership transfer to: ", platformColdWallet);

        console.log("Deploying AllowList contract...");
        AllowList allowList = new AllowList();
        console.log("Allowlist deployed at: ", address(allowList));
        allowList.transferOwnership(platformAdminWallet);
        console.log("Started ownership transfer to: ", platformAdminWallet);

        console.log("Deploying PrivateOfferFactory contract...");
        PrivateOfferFactory privateOfferFactory = new PrivateOfferFactory();
        console.log("PrivateOfferFactory deployed at: ", address(privateOfferFactory));

        console.log("Deploying VestingWalletFactory contract...");
        VestingWalletFactory vestingWalletFactory = new VestingWalletFactory();
        console.log("VestingWalletFactory deployed at: ", address(vestingWalletFactory));

        vm.stopBroadcast();

        console.log("Don't forget to check and finalize ownership transfers for all contracts!");
    }
}
