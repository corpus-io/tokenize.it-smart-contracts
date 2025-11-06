// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// taken from https://moveseventyeight.com/deploy-your-first-nft-contract-with-foundry#heading-prepare-a-basic-deployment-script

import "../lib/forge-std/src/Script.sol";
import "../contracts/factories/FeeSettingsCloneFactory.sol";
import "../contracts/factories/AllowListCloneFactory.sol";
import "../contracts/factories/PrivateOfferFactory.sol";
import "../contracts/factories/VestingCloneFactory.sol";
import "../contracts/factories/TokenProxyFactory.sol";
import "../contracts/factories/CrowdinvestingCloneFactory.sol";
import "../contracts/factories/TokenSwapCloneFactory.sol";
import "@opengsn/contracts/src/forwarder/Forwarder.sol";

contract DeployPlatform is Script {
    function setUp() public {}

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployerAddress = vm.addr(deployerPrivateKey);

        /*
         * config
         */

        // Goerli
        // address platformColdWallet = 0x1695F52e342f3554eC8BC06621B7f5d1644cCE39;
        // address trustedForwarder = 0x0445d09A1917196E1DC12EdB7334C70c1FfB1623;
        // address[] memory trustedCurrencies = new address[](6);
        // trustedCurrencies[0] = address(0x07865c6E87B9F70255377e024ace6630C1Eaa37F); // USDC
        // trustedCurrencies[1] = address(0xB4FBF271143F4FBf7B91A5ded31805e42b2208d6); // WETH
        // trustedCurrencies[2] = address(0xC04B0d3107736C32e19F1c62b2aF67BE61d63a05); // WBTC
        // trustedCurrencies[3] = address(0x73967c6a0904aA032C103b4104747E88c566B1A2); // DAI
        // trustedCurrencies[4] = address(0xA683d909e996052955500DDc45CA13E25c76e286); // EUROC
        // trustedCurrencies[5] = address(0xcB444e90D8198415266c6a2724b7900fb12FC56E); // EURe

        // Mainnet
        // address platformColdWallet = 0x9E23f8AA17B2721cf69D157b8a15bd7b64ac881C;
        // address trustedForwarder = 0xAa3E82b4c4093b4bA13Cb5714382C99ADBf750cA;
        // address[] memory trustedCurrencies = new address[](6);
        // trustedCurrencies[0] = address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2); // WEth
        // trustedCurrencies[1] = address(0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599); // WBTC
        // trustedCurrencies[2] = address(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48); // USDC
        // trustedCurrencies[3] = address(0x1aBaEA1f7C830bD89Acc67eC4af516284b1bC33c); // EUROC
        // trustedCurrencies[4] = address(0x6B175474E89094C44Da98b954EedeAC495271d0F); // DAI
        // trustedCurrencies[5] = address(0x3231Cb76718CDeF2155FC47b5286d82e6eDA273f); // EURe

        // Sepolia
        // address platformColdWallet = 0x9E23f8AA17B2721cf69D157b8a15bd7b64ac881C;
        // address trustedForwarder = 0x274ca5f21Cdde06B6E4Fe063f5087EB6Cf3eAe55;
        // address[] memory trustedCurrencies = new address[](2);
        // trustedCurrencies[0] = address(0x30627856Ef668F0A6a1ca9145C9538f7d5b42BDE); // tEUROC
        // trustedCurrencies[1] = address(0x86f488C7CC923d987b246994a0E5e20B3364fd92); // tUSDC

        // Gnosis Chiado
        // address platformColdWallet = 0x99b686F27413fd41F338aDD3Bce2eb60bBa7885E;
        // address trustedForwarder = 0x2659B6c5121049626363dBc1d22f267e79a0BFDE;
        // address[] memory trustedCurrencies = new address[](6);
        // trustedCurrencies[0] = address(0xb106ed7587365a16b6691a3D4B2A734f4E8268a2); // Monerium

        // Gnosis Mainnet
        address platformColdWallet = 0x9E23f8AA17B2721cf69D157b8a15bd7b64ac881C;
        address trustedForwarder = 0x7eEae829DF28F9Ce522274D5771A6Be91d00E5ED;
        address[] memory trustedCurrencies = new address[](6);
        trustedCurrencies[0] = address(0xcB444e90D8198415266c6a2724b7900fb12FC56E); // Monerium

        /*
         * execution
         */
        console.log("Deployer address: ", deployerAddress);
        vm.startBroadcast(deployerPrivateKey);

        console.log("Deploying FeeSettingsCloneFactory contract...");
        FeeSettings feeSettingsLogicContract = new FeeSettings(trustedForwarder);
        FeeSettingsCloneFactory feeSettingsCloneFactory = new FeeSettingsCloneFactory(
            address(feeSettingsLogicContract)
        );
        console.log("FeeSettingsCloneFactory deployed at: ", address(feeSettingsCloneFactory));

        console.log("Deploying FeeSettings contract...");
        Fees memory fees = Fees(200, 600, 200, 0);
        FeeSettings feeSettings = FeeSettings(
            feeSettingsCloneFactory.createFeeSettingsClone(
                bytes32(0),
                trustedForwarder,
                platformColdWallet,
                fees,
                platformColdWallet,
                platformColdWallet,
                platformColdWallet
            )
        );
        console.log("FeeSettings deployed at: ", address(feeSettings));

        console.log("Deploying AllowListCloneFactory contract...");
        AllowList allowListLogicContract = new AllowList(trustedForwarder);
        AllowListCloneFactory allowListCloneFactory = new AllowListCloneFactory(address(allowListLogicContract));
        console.log("AllowListCloneFactory deployed at: ", address(allowListCloneFactory));

        console.log("Deploying AllowList contract...");

        uint256[] memory attributes = new uint256[](trustedCurrencies.length);
        for (uint256 i = 0; i < trustedCurrencies.length; i++) {
            attributes[i] = TRUSTED_CURRENCY;
        }
        AllowList allowList = AllowList(
            allowListCloneFactory.createAllowListClone(
                bytes32(0),
                trustedForwarder,
                platformColdWallet,
                trustedCurrencies,
                attributes
            )
        );
        console.log("Allowlist deployed at: ", address(allowList));

        console.log("Deploying VestingCloneFactory contract...");
        Vesting vestingImplementation = Vesting(0xa740Dd991655b2887321C71D8Ac0c171a0C9E969);
        VestingCloneFactory vestingCloneFactory = new VestingCloneFactory(address(vestingImplementation));
        console.log("VestingCloneFactory deployed at: ", address(vestingCloneFactory));

        console.log("Deploying PrivateOfferFactory contract...");
        PrivateOfferFactory privateOfferFactory = new PrivateOfferFactory(vestingCloneFactory);
        console.log("PrivateOfferFactory deployed at: ", address(privateOfferFactory));

        console.log("Deploying TokenProxyFactory contract...");
        Token tokenImplementation = new Token(trustedForwarder);
        TokenProxyFactory tokenProxyFactory = new TokenProxyFactory(address(tokenImplementation));
        console.log("TokenProxyFactory deployed at: ", address(tokenProxyFactory));

        // console.log("Deploying Tokens to use as currrency on testnet...");
        // Token tUSDC = Token(
        //     tokenProxyFactory.createTokenProxy(
        //         bytes32(0),
        //         trustedForwarder,
        //         feeSettings,
        //         platformColdWallet,
        //         allowList,
        //         0,
        //         "tokenize.it_USDC",
        //         "tUSDC"
        //     )
        // );
        // console.log("tUSDC deployed at: ", address(tUSDC));
        // Token tEUROC = Token(
        //     tokenProxyFactory.createTokenProxy(
        //         bytes32(0),
        //         trustedForwarder,
        //         feeSettings,
        //         platformColdWallet,
        //         allowList,
        //         0,
        //         "tokenize.it_EUROC",
        //         "tEUROC"
        //     )
        // );
        // console.log("tEUROC deployed at: ", address(tEUROC));
        // console.log("Remember to add the tokens to the AllowList with attribute TRUSTED_CURRENCY: ", TRUSTED_CURRENCY);

        // deploy crowdinvesting factory
        console.log("Deploying CrowdinvestingFactory contract...");
        Crowdinvesting crowdinvestingImplementation = new Crowdinvesting(trustedForwarder);
        CrowdinvestingCloneFactory crowdinvestingCloneFactory = new CrowdinvestingCloneFactory(
            address(crowdinvestingImplementation)
        );
        console.log("CrowdinvestingFactory deployed at: ", address(crowdinvestingCloneFactory));

        deploy TokenSwap logic
        console.log("Deploying TokenSwap contracts...");
        TokenSwap tokenSwapLogicImplementation = new TokenSwap(trustedForwarder);
        console.log("TokenSwap logic deployed at: ", address(tokenSwapLogicImplementation));

        deploy TokenSwapFactory based on logic
        TokenSwapCloneFactory tokenSwapCloneFactory =  TokenSwapCloneFactory(address(0x314d4AD6a2C3310d45cE432f5119AF2e4f274852));
        console.log("TokenSwap factory deployed at: ", address(tokenSwapCloneFactory));

        deploy TokenSwap (use correct StableCoin address and Token address based on chain), just to verify the contract
        TokenSwapInitializerArguments memory arguments = TokenSwapInitializerArguments(
            vm.addr(3),
            vm.addr(2),
            vm.addr(1),
            1,
            IERC20(0x08210F9170F89Ab7658F0B5E3fF39b0E03C594D4), // StableCoin in Allowlist
            Token(0xaCB976B126d3bD67454b7418E0EF24099D2EBAa0) // A Token
        );

        address tokenSwap = tokenSwapCloneFactory.createTokenSwapClone(bytes32("0x1"), trustedForwarder, arguments);
        console.log("TokenSwap deployed at: ", tokenSwap);

        vm.stopBroadcast();
    }
}
