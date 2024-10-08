import { HardhatUserConfig, task } from 'hardhat/config';

import 'dotenv/config';
import 'hardhat-gas-reporter';
import '@nomicfoundation/hardhat-verify';
import '@nomicfoundation/hardhat-ethers';
import '@nomicfoundation/hardhat-chai-matchers';
import '@typechain/hardhat';

// This is a sample Hardhat task. To learn how to create your own go to
// https://hardhat.org/guides/create-task.html
task('accounts', 'Prints the list of accounts', async (taskArgs, hre) => {
  const accounts = await hre.ethers.getSigners();

  for (const account of accounts) {
    console.log(account.address);
  }
});

// You need to export an object to set up your config
// Go to https://hardhat.org/config/ to learn more

/**
 * @type import('hardhat/config').HardhatUserConfig
 */
const config: HardhatUserConfig = {
  solidity: {
    version: '0.8.23',
    settings: {
      // optimizer: {
      //   enabled: true,
      //   runs: 10000,
      // },
      metadata: {
        bytecodeHash: 'none',
      },
      viaIR: true,
      optimizer: {
        enabled: true,
        details: {
          yulDetails: {
            //optimizerSteps: 'u', // recommended by hh, but yields longer bytecode
          },
        },
      },
      // outputSelection: { "*": { "*": ["storageLayout"] } },
    },
  },
  networks: {
    localhost: {
      url: 'http://localhost:8545',
    },
    chiado: {
      url: process.env.CHIADO_RPC_URL || '',
      accounts:
        process.env.PRIVATE_KEY !== undefined ? [process.env.PRIVATE_KEY] : [],
    },
    gnosis: {
      url: process.env.GNOSIS_RPC_URL || '',
      accounts:
        process.env.PRIVATE_KEY !== undefined ? [process.env.PRIVATE_KEY] : [],
    },
    goerli: {
      url: process.env.GOERLI_RPC_URL || '',
      accounts:
        process.env.PRIVATE_KEY !== undefined ? [process.env.PRIVATE_KEY] : [],
    },
    mainnet: {
      url: process.env.MAINNET_RPC_URL || '',
      accounts:
        process.env.PRIVATE_KEY !== undefined ? [process.env.PRIVATE_KEY] : [],
    },
  },
  gasReporter: {
    enabled: process.env.REPORT_GAS !== undefined,
    currency: 'USD',
  },
  sourcify: {
    enabled: true,
  },
  etherscan: {
    apiKey: {
      mainnet: process.env.ETHERSCAN_API_KEY || '',
      sepolia: process.env.ETHERSCAN_API_KEY || '',
      chiado: process.env.GNOSISSCAN_API_KEY || '',
      gnosis: process.env.GNOSISSCAN_API_KEY || '',
    },
    customChains: [
      {
        network: `chiado`,
        chainId: 10200,
        urls: {
          apiURL: `https://gnosis-chiado.blockscout.com/api`,
          browserURL: `https://blockscout.chiadochain.net`,
        },
      },
      {
        network: 'gnosis',
        chainId: 100,
        urls: {
          // 3) Select to what explorer verify the contracts
          // Gnosisscan https://gnosis.blockscout.com/api?
          apiURL: 'https://api.gnosisscan.io/api',
          browserURL: 'https://gnosisscan.io/',
          // Blockscout
          // apiURL: 'https://blockscout.com/xdai/mainnet/api',
          // browserURL: 'https://blockscout.com/xdai/mainnet',
        },
      },
    ],
  },
  typechain: {
    outDir: 'types',
    target: 'ethers-v6',
    alwaysGenerateOverloads: false, // should overloads with full signatures like deposit(uint256) be generated always, even if there are no overloads?
    externalArtifacts: ['externalArtifacts/*.json'], // optional array of glob patterns with external artifacts to process (for example external libs from node_modules)
    dontOverrideCompile: false, // defaults to false
  },
};

export default config;
