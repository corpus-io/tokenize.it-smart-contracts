// To run the example:
// yarn build
// yarn hardhat node
// yarn hardhat run --network localhost scripts/deploy.ts
// copy and paste contract address
// yarn ts-node example.ts

import {CorpusToken__factory} from './dist/types'
import {ethers} from 'ethers'

const TOKEN_CONTRACT_ADDRESS = '0x5FbDB2315678afecb367f032d93F642f64180aa3'

async function main() {

    // can be an RPC URL or injected e.g. by MetaMask
    const provider = new ethers.providers.JsonRpcProvider('http://127.0.0.1:8545') 

    const signer = new ethers.Wallet(
        '0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80', // private key
        provider
    )

    const corpusTokenContracInstance = CorpusToken__factory.connect(TOKEN_CONTRACT_ADDRESS, signer);
    
    // call contract (read)
    const symbol = await corpusTokenContracInstance.symbol() 
    console.log('Token Symbol: ' + symbol)

    // send transaction (write, change contract state)
    await corpusTokenContracInstance.pause() 
    // call contract (read)
    console.log('Paused: ' + await corpusTokenContracInstance.paused()) 

    // send transaction (write, change contract state)
    await corpusTokenContracInstance.unpause() 
    // call contract (read)
    console.log('Paused: ' + await corpusTokenContracInstance.paused()) 


}

main()