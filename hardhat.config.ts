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
    },
    {
      version: '0.8.9',
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
    dev: { url: 'http://127.0.0.1:8545', chainId: 31337 },
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
    },
    lineagoerli: {
      url: 'https://rpc.goerli.linea.build/',
      chainId: 59140,
      gasPrice: 1500000001,
      accounts:
        process.env.PRIVATE_KEY_TEST !== undefined
          ? [process.env.PRIVATE_KEY_TEST]
          : []
    },
    coqdeploy: {
      url: 'https://shanghai-inner-rpc.ankr.com/all/coq_testnet/rpc',
      chainId: 12077,
      gasPrice: 1000000000,
      accounts:
        process.env.PRIVATE_KEY_TEST_DEPLOYER !== undefined
          ? [process.env.PRIVATE_KEY_TEST_DEPLOYER]
          : []
    },
    basegoerlideploy: {
      url: 'https://goerli.base.org',
      chainId: 84531,
      gasPrice: 150000001,
      accounts:
        process.env.PRIVATE_KEY_TEST_DEPLOYER !== undefined
          ? [process.env.PRIVATE_KEY_TEST_DEPLOYER]
          : []
    },
    lineagoerlideploy: {
      url: 'https://rpc.goerli.linea.build/',
      chainId: 59140,
      gasPrice: 1500000001,
      accounts:
        process.env.PRIVATE_KEY_TEST_DEPLOYER !== undefined
          ? [process.env.PRIVATE_KEY_TEST_DEPLOYER]
          : []
    },
    basemaindeploy: {
      // url: 'https://developer-access-mainnet.base.org',
      url: 'http://127.0.0.1:8545',
      chainId: 8453,
      gasPrice: 130000001,
      accounts:
        process.env.PRIVATE_KEY_DEPLOYER !== undefined
          ? [process.env.PRIVATE_KEY_DEPLOYER]
          : []
    },
    lineamaindeploy: {
      // url: 'https://shanghai-inner-rpc.ankr.com/all/linea_mainnet/rpc',
      url: 'http://127.0.0.1:8545',
      chainId: 59144,
      gasPrice: 815000000,
      accounts:
        process.env.PRIVATE_KEY_DEPLOYER !== undefined
          ? [process.env.PRIVATE_KEY_DEPLOYER]
          : []
    }
  },
  mocha: {
    timeout: 10000
  },
  etherscan: {
    apiKey: {
      coq: 'QADPA8U7I9EU4K1I672Y9QHRAY7PFJ5WAX',
      basegoerli: '3WGNMRP6F45GDZVQDGEI3DWQDSP4YDJ9JU',
      lineagoerli: 'HCHMNPUTKD1AJYSNJXKRPADCN6B9E7BSWE',
      basemaindeploy: '3WGNMRP6F45GDZVQDGEI3DWQDSP4YDJ9JU',
      lineamaindeploy: 'HCHMNPUTKD1AJYSNJXKRPADCN6B9E7BSWE'
    },
    customChains: [
      {
        network: 'coq',
        chainId: 12077,
        urls: {
          apiURL: 'https://testnetscan.ankr.com/api',
          browserURL: 'https://testnetscan.ankr.com/'
        }
      },
      {
        network: 'basegoerli',
        chainId: 84531,
        urls: {
          apiURL: 'https://api-goerli.basescan.org/api',
          browserURL: 'https://goerli.basescan.org/'
        }
      },
      {
        network: 'lineagoerli',
        chainId: 59140,
        urls: {
          apiURL: 'https://api-testnet.lineascan.build/api',
          browserURL: 'https://goerli.lineascan.build/'
        }
      },
      {
        network: 'basemaindeploy',
        chainId: 8453,
        urls: {
          apiURL: 'https://api.basescan.org/api',
          browserURL: 'https://basescan.org/'
        }
      },
      {
        network: 'lineamaindeploy',
        chainId: 59144,
        urls: {
          apiURL: 'https://api.lineascan.build/api',
          browserURL: 'https://lineascan.build/'
        }
      }
    ]
  }
}

export default config
