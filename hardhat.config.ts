import * as dotenv from 'dotenv'

import { HardhatUserConfig, task } from 'hardhat/config'
import '@nomiclabs/hardhat-etherscan'
import '@nomiclabs/hardhat-waffle'
import '@openzeppelin/hardhat-upgrades'
import '@typechain/hardhat'
import 'solidity-coverage'
import './scripts/index'

dotenv.config()

// You need to export an object to set up your config
// Go to https://hardhat.org/config/ to learn more

task('set_balance', 'set balance for account').addParam('account', "the account's address").setAction(async (taskArgs, hre) => {
  await hre.network.provider.send(
    'anvil_setBalance',
    [taskArgs.account, '0x021e19e0c9bab2400000']
  )
})

const config: HardhatUserConfig = {
  solidity: {
    compilers: [{
      version: '0.8.17',
      settings: {
        optimizer: { enabled: true, runs: 1000000 }
      }
    }]
    // overrides: {
    //   'contracts/core/EntryPoint.sol': optimizedComilerSettings,
    //   'contracts/samples/SimpleAccount.sol': optimizedComilerSettings
    // }
  },
  networks: {
    dev: { url: 'http://localhost:8545', chainId: 31337 },
    // github action starts localgeth service, for gas calculations
    // localgeth: { url: 'http://localgeth:8545' },
    coq: {
      url: 'https://shanghai-inner-rpc.ankr.com/all/coq_testnet/rpc',
      chainId: 12077,
      accounts:
        process.env.PRIVATE_KEY_TEST !== undefined
          ? [process.env.PRIVATE_KEY_TEST]
          : []
    },
    aaed: {
      url: 'https://shanghai-inner-rpc.ankr.com/all/aed_devnet/rpc',
      chainId: 5201,
      gasPrice: 3500000000,
      accounts:
        process.env.PRIVATE_KEY_TEST !== undefined
          ? [process.env.PRIVATE_KEY_TEST]
          : []
    },
    goerli: {
      url: 'https://shanghai-inner-rpc.ankr.com/eth_goerli_1/rpc',
      chainId: 5,
      accounts:
        process.env.PRIVATE_KEY_TEST !== undefined
          ? [process.env.PRIVATE_KEY_TEST]
          : []
    },
    basegoerli: {
      url: 'https://rpc.ankr.com/base_goerli',
      chainId: 84531,
      gasPrice: 150000001,
      accounts:
        process.env.PRIVATE_KEY_TEST !== undefined
          ? [process.env.PRIVATE_KEY_TEST]
          : []
    }
  },
  mocha: {
    timeout: 10000
  },
  etherscan: {
    apiKey: {
      coq: 'QADPA8U7I9EU4K1I672Y9QHRAY7PFJ5WAX'
    },
    customChains: [
      {
        network: 'coq',
        chainId: 12077,
        urls: {
          apiURL: 'https://testnetscan.ankr.com/api',
          browserURL: 'https://testnetscan.ankr.com/'
        }
      }
    ]
  }
}

export default config
