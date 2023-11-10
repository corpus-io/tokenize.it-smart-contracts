// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

// taken from https://moveseventyeight.com/deploy-your-first-nft-contract-with-foundry#heading-prepare-a-basic-deployment-script

import "../lib/forge-std/src/Script.sol";
import "../contracts/FeeSettings.sol";
import "../contracts/AllowList.sol";
import "../contracts/PrivateOfferFactory.sol";
import "../contracts/VestingWalletFactory.sol";
import "../contracts/TokenCloneFactory.sol";

contract DeployPlatform is Script {
    function setUp() public {}

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        // Goerli
        //address platformColdWallet = 0x1695F52e342f3554eC8BC06621B7f5d1644cCE39;
        //address platformAdminWallet = 0x1695F52e342f3554eC8BC06621B7f5d1644cCE39;

        // Mainnet
        //address platformColdWallet = 0x9E23f8AA17B2721cf69D157b8a15bd7b64ac881C;
        //address platformAdminWallet = platformColdWallet;

        // Anvil
        uint256 adminPrivateKey = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
        deployerPrivateKey = adminPrivateKey;

        address deployerAddress = vm.addr(deployerPrivateKey);
        console.log("Deployer address: ", deployerAddress);

        address platformColdWallet = deployerAddress;
        address platformAdminWallet = deployerAddress;

        vm.startBroadcast(deployerPrivateKey);

        console.log("Deploying FeeSettings contract...");
        Fees memory fees = Fees(1, 100, 1, 100, 1, 100, 0);
        FeeSettings feeSettings = new FeeSettings(fees, platformColdWallet, platformColdWallet, platformColdWallet);
        console.log("FeeSettings deployed at: ", address(feeSettings));
        feeSettings.transferOwnership(platformColdWallet);
        console.log("Started ownership transfer to: ", platformColdWallet);

        console.log("Deploying AllowList contract...");
        AllowList allowList = new AllowList();
        console.log("Allowlist deployed at: ", address(allowList));
        allowList.transferOwnership(platformAdminWallet);
        console.log("Started ownership transfer to: ", platformAdminWallet);

        console.log("Deploying PersonalInviteFactory contract...");
        PrivateOfferFactory privateOfferFactory = new PrivateOfferFactory();
        console.log("PersonalInviteFactory deployed at: ", address(privateOfferFactory));

        console.log("Deploying VestingWalletFactory contract...");
        VestingWalletFactory vestingWalletFactory = new VestingWalletFactory();
        console.log("VestingWalletFactory deployed at: ", address(vestingWalletFactory));

        console.log("Deploying TokenCloneFactory contract...");
        Token tokenLogicContract = new Token(address(1)); // use bullshit forwarder
        TokenCloneFactory tokenCloneFactory = new TokenCloneFactory(address(tokenLogicContract));
        console.log("TokenCloneFactory deployed at: ", address(tokenCloneFactory));

        console.log("Deploying Token contract...");
        Token token = Token(
            tokenCloneFactory.createTokenClone(
                0,
                address(1), // use bullshit forwarder
                feeSettings,
                platformAdminWallet,
                allowList,
                0,
                "Anvil Token",
                "ANVIL"
            )
        );
        console.log("Token deployed at: ", address(token));

        console.log("Minting tokens...");
        token.grantRole(token.MINTALLOWER_ROLE(), platformAdminWallet);
        token.mint(platformAdminWallet, 1000000000000000000000000000);
        console.log("Tokens minted.");

        vm.stopBroadcast();

        console.log("Don't forget to check and finalize ownership transfers for all contracts!");
    }
}
