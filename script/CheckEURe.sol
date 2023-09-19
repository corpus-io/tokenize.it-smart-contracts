// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

// taken from https://moveseventyeight.com/deploy-your-first-nft-contract-with-foundry#heading-prepare-a-basic-deployment-script

import "../lib/forge-std/src/Script.sol";
import "../contracts/FeeSettings.sol";
import "../contracts/AllowList.sol";
import "../contracts/PersonalInviteFactory.sol";
import "../contracts/Token.sol";
import "../contracts/interfaces/IMintAndCallToken.sol";

/*
    This script is used to check the deployed token contract.
    It is not meant to be used in production, but rather as a reference for how to interact with the deployed contracts.

    To run this script, use the following command:
        forge script CheckToken.sol --rpc-url $GOERLI_RPC_URL

*/

address constant TOKEN_ADDRESS = 0x9693f471524Ba0629e540f368573711C76ACBABa;
address constant TRUSTED_FORWARDER = 0x994257AcCF99E5995F011AB2A3025063e5367629;
address constant FEE_SETTINGS = 0x147addF9C8E4030F8104c713Dad2A1d76E6c85a1;
address constant ALLOW_LIST = 0x274ca5f21Cdde06B6E4Fe063f5087EB6Cf3eAe55;
address constant ADMIN = 0x45a1cbD9788f5eA4061640ad7CB55031AE62b9dB;
bytes32 constant DEFAULT_ADMIN_ROLE = 0x00;

uint256 constant account0PrivateKey = 0x78fa52242e7ebe1fe263c51e1b4b6f8c12a85f5bef3638f4e8ea21274abe2939;
address constant account0Address = 0xF0317e0038AE9b934b7CC3c2836dBbE9C4DBEa90;

address constant eureAddress = 0x65b33E1F703B9255f4FcE7f931a06473298Db7f4;

contract CheckToken is Script {
    function run() public {
        // check some settings using our token interface
        Token token = Token(eureAddress);

        console.log("Remember to update addresses in this script in order to check other deployments.");

        console.log("Token name: ", token.name());
        console.log("Token symbol: ", token.symbol());

        console.log("Token admin matches: ", token.hasRole(DEFAULT_ADMIN_ROLE, account0Address));

        console.log("Token balance: ", token.balanceOf(account0Address));

        // create frontend
        IMintAndCallToken frontend = IMintAndCallToken(eureAddress);

        // grant necessary roles in the controller contract
        address controllerAddress = frontend.getController();
        IMintAndCallTokenController mintAndCallController = IMintAndCallTokenController(controllerAddress);

        vm.startBroadcast(account0PrivateKey);

        mintAndCallController.addSystemAccount(account0Address);
        mintAndCallController.addAdminAccount(account0Address);

        uint256 maxMintAllowance = 1000 * 10 ** 18;

        mintAndCallController.setMaxMintAllowance(maxMintAllowance);
        mintAndCallController.setMintAllowance(account0Address, maxMintAllowance);

        uint256 mintAllowance = mintAndCallController.getMintAllowance(account0Address);
        console.log("Max mint allowance: ", mintAndCallController.getMaxMintAllowance());

        console.log("Mint allowance: ", mintAllowance);

        // mint 1000 tokens to account0 through the frontend
        frontend.mintTo(account0Address, 100 * 10 ** 18);
        vm.stopBroadcast();
    }
}
