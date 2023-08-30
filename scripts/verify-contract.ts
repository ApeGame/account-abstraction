
import { types, task } from 'hardhat/config'
import { HardhatRuntimeEnvironment } from 'hardhat/types'

// hardhat verify-contract --network basegoerli --entrypoint 0x7815A7628691419f6e706253411A7887bEECff4c --simpleaccountfactory 0xa3b3b990b3215DB2Ece49BB089c579DA4ada5392 --tokenpaymaster 0x53e4681cBbC2DF09bFc4c2016819be626C639a5a --gnosisfactory 0x0B732e4Ad461e587595aa555D608e93097862284 --subsidypaymaster 0x73100D1C8c4F8EB18b4663d058Bffb6DcA024E65 --multisendcallonly 0xB14ec8929E4EE157eec8137964E61a1E9a8C940c
// hardhat verify-contract --network lineagoerli --entrypoint 0x51b49D7351187c2B6b49AaD80301bF2E7e1A9889 --simpleaccountfactory 0x083DDdD02835385A239b710648f33781B15Cc3C0 --tokenpaymaster 0x43b1eb399A3841B122FaBFdcd3B8f52E546bd4d2 --gnosisfactory 0xE4bC4bb0aCFDb0C754d1F652599b98d9Cdf2afE9 --subsidypaymaster 0xE739F1b6cCA0CfA613Dd6A947d92510D2a7E91dE --multisendcallonly 0xBE7A42513F093F7663841E44a45C2852Cf2c07c2

task('verify-contract', 'verify contract')
  .addParam('sendercreator', 'sender creator', '', types.string)
  .addParam('token', 'erc20 token', '', types.string)
  .addParam('entrypoint', "the entrypoint's address", '', types.string)
  .addParam('simpleaccountfactory', 'simple account factory', '', types.string)
  .addParam('tokenpaymaster', 'simple token paymster', '', types.string)
  .addParam('gnosisfactory', 'gnosis factory', '', types.string)
  .addParam('subsidypaymaster', 'subsidy paymaster', '', types.string)
  .addParam('multisendcallonly', 'multisend call only', '', types.string)
  .setAction(async (taskArgs, hre) => {
    const entrypoint: string = taskArgs.entrypoint
    const token: string = taskArgs.token
    const sendercreator: string = taskArgs.sendercreator
    const simpleAccountFactory: string = taskArgs.simpleaccountfactory
    const tokenPaymaster: string = taskArgs.tokenpaymaster
    const gnosisFactory: string = taskArgs.gnosisfactory
    const subsidyPaymaster: string = taskArgs.subsidypaymaster
    const multisendCallOnly: string = taskArgs.multisendcallonly

    await verifyToken(hre, token)
    if (!hre.ethers.isAddress(entrypoint)) {
      console.log('invalid entrypoint')
      return ''
    }

    await verifyEntrypoint(hre, sendercreator, entrypoint)
    await verifyAccountFactory(hre, entrypoint, simpleAccountFactory)
    await verifyTokenPaymaster(hre, tokenPaymaster)
    await verifyGnosisSafeProxyFactory(hre, entrypoint, gnosisFactory)
    await verifySubsidyPaymaster(hre, subsidyPaymaster)
    await verifyMultiSendCallOnly(hre, multisendCallOnly)
  })

async function verifyToken (hre: HardhatRuntimeEnvironment, token: string): Promise<boolean> {
  if (hre.config.etherscan.apiKey[hre.network.name] !== undefined) {
    if (hre.ethers.isAddress(token)) {
      await hre.run('verify:verify', {
        address: token,
        constructorArguments: [
          'my token', 'MT'
        ],
        contract: 'contracts/mock/erc20.sol:MyToken'
      })
    }
  }
  return true
}

async function verifyEntrypoint (hre: HardhatRuntimeEnvironment, senderCreatorAddr: string, entrypointAddr: string): Promise<boolean> {
  if (hre.config.etherscan.apiKey[hre.network.name] !== undefined) {
    if (hre.ethers.isAddress(senderCreatorAddr)) {
      await hre.run('verify:verify', {
        address: senderCreatorAddr,
        constructorArguments: [],
        contract: 'contracts/core/SenderCreator.sol:SenderCreator'
      })
      console.log('sender creator verifyed')
    }
    if (hre.ethers.isAddress(entrypointAddr)) {
      const entrypoinyImpl = await hre.upgrades.erc1967.getImplementationAddress(entrypointAddr)
      await hre.run('verify:verify', {
        address: entrypoinyImpl,
        constructorArguments: [],
        contract: 'contracts/core/EntryPoint.sol:EntryPoint'
      })
      console.log('entrypoint verifyed')
    }
  }
  return true
}

async function verifyAccountFactory (hre: HardhatRuntimeEnvironment, entrypointAddr: string, simpleAccountFactoryProxyAddr: string): Promise<boolean> {
  if (hre.ethers.isAddress(simpleAccountFactoryProxyAddr)) {
    const simpleAccountFactory = await hre.ethers.getContractAt('SimpleAccountFactory', simpleAccountFactoryProxyAddr)
    const simpleAccountAddress = await simpleAccountFactory.accountImplementation()
    if (hre.config.etherscan.apiKey[hre.network.name] !== undefined) {
      await hre.run('verify:verify', {
        address: simpleAccountAddress,
        constructorArguments: [
          entrypointAddr
        ],
        contract: 'contracts/samples/SimpleAccount.sol:SimpleAccount'
      })
      console.log('simple account verifyed')

      const simpleAccountFactoryImpl = await hre.upgrades.erc1967.getImplementationAddress(simpleAccountFactoryProxyAddr)
      await hre.run('verify:verify', {
        address: simpleAccountFactoryImpl,
        constructorArguments: [],
        contract: 'contracts/samples/SimpleAccountFactory.sol:SimpleAccountFactory'
      })
      console.log('simple account factory verifyed')
    }
  }
  return true
}

async function verifyTokenPaymaster (hre: HardhatRuntimeEnvironment, tokenPaymasterAddr: string): Promise<boolean> {
  if (hre.ethers.isAddress(tokenPaymasterAddr) && hre.config.etherscan.apiKey[hre.network.name] !== undefined) {
    const simpleTokenPaymasterImpl = await hre.upgrades.erc1967.getImplementationAddress(tokenPaymasterAddr)
    await hre.run('verify:verify', {
      address: simpleTokenPaymasterImpl,
      constructorArguments: [],
      contract: 'contracts/samples/paymaster/SimpleTokenPaymaster.sol:SimpleTokenPaymaster'
    })
    console.log('token paymaster verifyed')
  }
  return true
}

async function verifyGnosisSafeProxyFactory (hre: HardhatRuntimeEnvironment, entrypointAddr: string, gnosisFactoryAddr: string): Promise<boolean> {
  if (hre.ethers.isAddress(gnosisFactoryAddr)) {
    const gnosisFactory = await hre.ethers.getContractAt('GnosisSafeAccountFactory', gnosisFactoryAddr)
    const gnosisSafeProxyAddress = await gnosisFactory.proxyFactory()
    const gnosisSafeAddress = await gnosisFactory.safeSingleton()
    const eip4337MgrAddress = await gnosisFactory.eip4337Manager()

    if (hre.config.etherscan.apiKey[hre.network.name] !== undefined) {
      await hre.run('verify:verify', {
        address: gnosisSafeProxyAddress,
        constructorArguments: [],
        contract: 'lib/@gnosis.pm/safe-contracts/contracts/proxies/GnosisSafeProxyFactory.sol:GnosisSafeProxyFactory'
      })
      console.log('GnosisSafeProxyFactory verifyed')

      await hre.run('verify:verify', {
        address: gnosisSafeAddress,
        constructorArguments: [],
        contract: 'lib/@gnosis.pm/safe-contracts/contracts/GnosisSafeL2.sol:GnosisSafeL2'
      })
      console.log('GnosisSafeL2 verifyed')

      await hre.run('verify:verify', {
        address: eip4337MgrAddress,
        constructorArguments: [
          entrypointAddr
        ],
        contract: 'contracts/samples/gnosis/EIP4337Manager.sol:EIP4337Manager'
      })
      console.log('EIP4337Manager verifyed')

      const impl = await hre.upgrades.erc1967.getImplementationAddress(gnosisFactoryAddr)
      await hre.run('verify:verify', {
        address: impl,
        constructorArguments: [],
        contract: 'contracts/samples/gnosis/GnosisAccountFactory.sol:GnosisSafeAccountFactory'
      })
      console.log('gnosis factory verifyed')
    }
  }
  return true
}

async function verifySubsidyPaymaster (hre: HardhatRuntimeEnvironment, subsidyPaymasterAddr: string): Promise<boolean> {
  if (hre.ethers.isAddress(subsidyPaymasterAddr) && hre.config.etherscan.apiKey[hre.network.name] !== undefined) {
    const subsidyPaymasterImpl = await hre.upgrades.erc1967.getImplementationAddress(subsidyPaymasterAddr)
    await hre.run('verify:verify', {
      address: subsidyPaymasterImpl,
      constructorArguments: [],
      contract: 'contracts/samples/paymaster/SubsidyPaymaster.sol:SubsidyPaymaster'
    })
    console.log('subsidy paymaster verifyed')
  }
  return true
}

async function verifyMultiSendCallOnly (hre: HardhatRuntimeEnvironment, multiSendCallOnlyAddr: string): Promise<boolean> {
  if (hre.ethers.isAddress(multiSendCallOnlyAddr) && hre.config.etherscan.apiKey[hre.network.name] !== undefined) {
    await hre.run('verify:verify', {
      address: multiSendCallOnlyAddr,
      constructorArguments: [],
      contract: 'contracts/samples/gnosis/MultiSendCallOnly.sol:MultiSendCallOnly'
    })
    console.log('multiSendCallOnly verifyed')
  }
  return true
}
