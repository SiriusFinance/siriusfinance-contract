export const CHAIN_ID = {
  MAINNET: "1",
  ROPSTEN: "3",
  KOVAN: "42",
  HARDHAT: "31337",
  BSC_TESTNET: "97",
  ASTAR_MAINNET: "592",
  SHIBUYA: "81"
}

export function isMainnet(networkId: string): boolean {
  return (
    networkId == CHAIN_ID.MAINNET ||
    networkId == CHAIN_ID.ASTAR_MAINNET 
    
  )
}

export function isTestNetwork(networkId: string): boolean {
  return (
    networkId == CHAIN_ID.HARDHAT ||
    networkId == CHAIN_ID.ROPSTEN ||
    networkId == CHAIN_ID.KOVAN ||
    networkId == CHAIN_ID.BSC_TESTNET ||
    networkId == CHAIN_ID.SHIBUYA 
  )
}

export const ALCHEMY_BASE_URL = {
  [CHAIN_ID.MAINNET]: "https://eth-mainnet.alchemyapi.io/v2/",
  [CHAIN_ID.ROPSTEN]: "https://ropsten.infura.io/v3/",
  [CHAIN_ID.KOVAN]: "https://kovan.infura.io/v3/",
  [CHAIN_ID.BSC_TESTNET]: "https://data-seed-prebsc-1-s1.binance.org:8545/",
  [CHAIN_ID.ASTAR_MAINNET]: "https://rpc.astar.network:8545/",
  [CHAIN_ID.SHIBUYA]: "https://rpc.shibuya.astar.network:8545/"

}
