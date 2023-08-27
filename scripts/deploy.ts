
import { types, task } from 'hardhat/config'
import { HardhatRuntimeEnvironment } from 'hardhat/types'
// import { EntryPoint } from './../typechain/contracts/core/EntryPoint'
// import { GnosisSafe } from './../typechain/@gnosis.pm/safe-contracts/contracts/GnosisSafe'
import { Sleep } from './common'

const sleepTime = 6000 // 6s
// hardhat deploy --network coq --contract entrypoint
// hardhat deploy --network coq --contract all --token 0x13D91374CcB046ca0B66688AdCe4B2B62837A86a --pubkey 0xe184aF3b0b9CeFf9C2d11B1D33FF31Cc483C13F2 --fee 0.01
// hardhat deploy --network coq --contract accountfactory --entrypoint 0x83DA221A7D6D96357794eC749a658811997Ee039
// hardhat deploy --network coq --contract tokenpaymster --entrypoint 0x83DA221A7D6D96357794eC749a658811997Ee039 --token 0x13D91374CcB046ca0B66688AdCe4B2B62837A86a --pubkey 0xe184aF3b0b9CeFf9C2d11B1D33FF31Cc483C13F2 --fee 0.01
// hardhat deploy --network coq --contract gnosisfactory --entrypoint 0x83DA221A7D6D96357794eC749a658811997Ee039
// hardhat deploy --network coq --contract subsidypaymaster --entrypoint 0x83DA221A7D6D96357794eC749a658811997Ee039 --token 0x13D91374CcB046ca0B66688AdCe4B2B62837A86a --pubkey 0xe184aF3b0b9CeFf9C2d11B1D33FF31Cc483C13F2
// hardhat deploy --network coq --contract multisendcallonly

task('deploy', 'deploy contract')
  .addParam('token', 'erc20 contract (dev network will create it when it is undefined)', '', types.string)
  .addParam('entrypoint', "the entrypoint's address", '', types.string)
  .addParam('pubkey', 'public key (tokenpaymster & subsidypaymaster need it)', '', types.string)
  .addParam('fee', 'fee of tokenpaymster (only tokenpaymster)', '', types.string)
  .addParam('contract', 'Which contract is deployed? (all|entrypoint|accountfactory|tokenpaymster|gnosisfactory|multisendcallonly|subsidypaymaster)')
  .setAction(async (taskArgs, hre) => {
    let token = taskArgs.token
    let entrypoint: string = taskArgs.entrypoint
    const pubkey = taskArgs.pubkey
    let fee: bigint
    if (taskArgs.fee === '') {
      fee = BigInt(0)
    } else {
      fee = hre.ethers.parseEther(taskArgs.fee)
    }
    const contract = taskArgs.contract
    if (contract === 'all') {
      if (token === '' && hre.network.name === 'dev') {
        token = await deployToken(hre)
      }
      if (!hre.ethers.isAddress(token)) {
        console.log('invalid token')
        return ''
      }

      if (!hre.ethers.isAddress(pubkey)) {
        console.log('invalid pubkey')
        return ''
      }

      if (fee <= 0) {
        console.log('invalid fee')
        return ''
      }

      entrypoint = await deployEntrypoint(hre)
      const accountFactory = await deployAccountFactory(hre, entrypoint)
      const tokenPaymaster = await deployTokenPaymaster(hre, entrypoint, token, pubkey, fee)
      const gnosisFactory = await deployGnosisSafeProxyFactory(hre, entrypoint)
      const subsidyPaymaster = await deploySubsidyPaymaster(hre, entrypoint, pubkey)
      const multiSendCallOnly = await deployMultiSendCallOnly(hre)
      console.log('')
      console.log('------------------- deployed contract -------------------')
      console.log('')
      console.log(`entrypoint address     : ${entrypoint}`)
      console.log(`simple account factory : ${accountFactory}`)
      console.log('erc20 token            :', token)
      console.log(`simple token paymaster : ${tokenPaymaster}`)
      console.log(`gnosis factory         : ${gnosisFactory}`)
      console.log(`subsidy paymaster      : ${subsidyPaymaster}`)
      console.log(`multisend call only    : ${multiSendCallOnly}`)
    } else if (contract === 'entrypoint') {
      entrypoint = await deployEntrypoint(hre)
      console.log('')
      console.log('------------------- deployed contract -------------------')
      console.log('')
      console.log(`entry point address    : ${entrypoint}`)
    } else if (contract === 'accountfactory') {
      if (!hre.ethers.isAddress(entrypoint)) {
        console.log('invalid entrypoint')
        return ''
      }
      const accountFactory = await deployAccountFactory(hre, entrypoint)
      console.log('')
      console.log('------------------- deployed contract -------------------')
      console.log('')
      console.log(`simple account factory : ${accountFactory}`)
    } else if (contract === 'tokenpaymster') {
      if (!hre.ethers.isAddress(entrypoint)) {
        console.log('invalid entrypoint')
        return ''
      }
      if (!hre.ethers.isAddress(token)) {
        console.log('invalid token')
        return ''
      }
      if (!hre.ethers.isAddress(pubkey)) {
        console.log('invalid pubkey')
        return ''
      }
      if (fee <= 0) {
        console.log('invalid fee')
        return ''
      }

      const tokenPaymaster = await deployTokenPaymaster(hre, entrypoint, token, pubkey, fee)
      console.log('')
      console.log('------------------- deployed contract -------------------')
      console.log('')
      console.log(`simple token paymaster : ${tokenPaymaster}`)
    } else if (contract === 'gnosisfactory') {
      if (!hre.ethers.isAddress(entrypoint)) {
        console.log('invalid entrypoint')
        return ''
      }
      const gnosisFactory = await deployGnosisSafeProxyFactory(hre, entrypoint)
      console.log('')
      console.log('------------------- deployed contract -------------------')
      console.log('')
      console.log(`gnosis factory         : ${gnosisFactory}`)
    } else if (contract === 'multisendcallonly') {
      const multiSendCallOnly = await deployMultiSendCallOnly(hre)
      console.log('')
      console.log('------------------- deployed contract -------------------')
      console.log('')
      console.log(`multisend call only    : ${multiSendCallOnly}`)
    } else if (contract === 'subsidypaymaster') {
      if (!hre.ethers.isAddress(entrypoint)) {
        console.log('invalid entrypoint')
        return ''
      }
      if (!hre.ethers.isAddress(token)) {
        console.log('invalid token')
        return ''
      }
      if (!hre.ethers.isAddress(pubkey)) {
        console.log('invalid pubkey')
        return ''
      }
      const subsidypaymaster = await deploySubsidyPaymaster(hre, entrypoint, pubkey)
      console.log('')
      console.log('------------------- deployed contract -------------------')
      console.log('')
      console.log(`subsidy paymaster      : ${subsidypaymaster}`)
    } else {
      console.log('invalid contract')
    }
  })

async function deployToken (hre: HardhatRuntimeEnvironment): Promise<string> {
  const ethers = hre.ethers
  const MyToken = await ethers.getContractFactory('MyToken')
  const mytoken = await MyToken.deploy('my token', 'MT')
  const token = await mytoken.getAddress()

  // if (hre.config.etherscan.apiKey[hre.network.name] !== undefined) {
  //   await Sleep(sleepTime)
  //   await hre.run('verify:verify', {
  //     address: token,
  //     constructorArguments: [
  //       'my token', 'MT'
  //     ],
  //     contract: 'contracts/mock/erc20.sol:MyToken'
  //   })
  // }
  return token
}

async function deployEntrypoint (hre: HardhatRuntimeEnvironment): Promise<string> {
  const ethers = hre.ethers
  const upgrades = hre.upgrades
  // deploy sender creator
  const SenderCreator = await ethers.getContractFactory('SenderCreator')
  const senderCreator = await SenderCreator.deploy()
  const senderCreatorAddress = await senderCreator.getAddress()

  // deploy entrypoint
  const EntryPointFactory = await ethers.getContractFactory('EntryPoint')
  const entryPointProxy = await upgrades.deployProxy(
    EntryPointFactory,
    [senderCreatorAddress],
    {
      initializer: 'initialize'
    }
  )
  const entryPointProxyAddr = await entryPointProxy.getAddress()

  // if (hre.config.etherscan.apiKey[hre.network.name] !== undefined) {
  //   await Sleep(sleepTime)

  //   await hre.run('verify:verify', {
  //     address: senderCreatorAddress,
  //     constructorArguments: [],
  //     contract: 'contracts/core/SenderCreator.sol:SenderCreator'
  //   })

  //   const entrypoinyImpl = await upgrades.erc1967.getImplementationAddress(entryPointProxyAddr)
  //   await hre.run('verify:verify', {
  //     address: entrypoinyImpl,
  //     constructorArguments: [],
  //     contract: 'contracts/core/EntryPoint.sol:EntryPoint'
  //   })
  // }
  return entryPointProxyAddr
}

async function deployAccountFactory (hre: HardhatRuntimeEnvironment, entrypoint: string): Promise<string> {
  const ethers = hre.ethers
  const upgrades = hre.upgrades
  const SimpleAccount = await ethers.getContractFactory('SimpleAccount')
  const simpleAccount = await SimpleAccount.deploy(entrypoint)
  const simpleAccountAddress = await simpleAccount.getAddress()

  // deploy simple account factory
  const SimpleAccountFactoryFactory = await ethers.getContractFactory('SimpleAccountFactory')
  const simpleAccountFactoryProxy = await upgrades.deployProxy(
    SimpleAccountFactoryFactory,
    [simpleAccountAddress],
    {
      initializer: 'initialize'
    }
  )
  const simpleAccountFactoryProxyAddr = await simpleAccountFactoryProxy.getAddress()
  // if (hre.config.etherscan.apiKey[hre.network.name] !== undefined) {
  //   await Sleep(sleepTime)
  //   await hre.run('verify:verify', {
  //     address: simpleAccountAddress,
  //     constructorArguments: [
  //       entrypoint
  //     ],
  //     contract: 'contracts/samples/SimpleAccount.sol:SimpleAccount'
  //   })

  //   const simpleAccountFactoryImpl = await upgrades.erc1967.getImplementationAddress(simpleAccountFactoryProxyAddr)
  //   await hre.run('verify:verify', {
  //     address: simpleAccountFactoryImpl,
  //     constructorArguments: [],
  //     contract: 'contracts/samples/SimpleAccountFactory.sol:SimpleAccountFactory'
  //   })
  // }

  return simpleAccountFactoryProxyAddr
}

async function deployTokenPaymaster (hre: HardhatRuntimeEnvironment, entrypoint: string, token: string, pubkey: string, fee: bigint): Promise<string> {
  const ethers = hre.ethers
  const upgrades = hre.upgrades
  const owner = (await ethers.getSigners())[0].address
  const SimpleTokenPaymaster = await ethers.getContractFactory('SimpleTokenPaymaster')
  const simpleTokenPaymaster = await upgrades.deployProxy(
    SimpleTokenPaymaster,
    [entrypoint, token, owner, pubkey, fee],
    {
      initializer: 'initialize'
    }
  )
  const simpleTokenPaymasterProxyAddr = await simpleTokenPaymaster.getAddress()
  // if (hre.config.etherscan.apiKey[hre.network.name] !== undefined) {
  //   await Sleep(sleepTime)
  //   const simpleTokenPaymasterImpl = await upgrades.erc1967.getImplementationAddress(simpleTokenPaymasterProxyAddr)
  //   await hre.run('verify:verify', {
  //     address: simpleTokenPaymasterImpl,
  //     constructorArguments: [],
  //     contract: 'contracts/samples/paymaster/SimpleTokenPaymaster.sol:SimpleTokenPaymaster'
  //   })
  // }
  return simpleTokenPaymasterProxyAddr
}

async function deployGnosisSafeProxyFactory (hre: HardhatRuntimeEnvironment, entrypoint: string): Promise<string> {
  const ethers = hre.ethers
  const upgrades = hre.upgrades
  const GnosisSafeProxyFactory = await ethers.getContractFactory('GnosisSafeProxyFactory')
  const gnosisSafeProxyFactoryProxy = await GnosisSafeProxyFactory.deploy()
  const gnosisSafeProxyAddress = await gnosisSafeProxyFactoryProxy.getAddress()

  // deploy GnosisSafe
  const GnosisSafeFactory = await ethers.getContractFactory('GnosisSafeL2')
  const gnosisSafeFactoryProxy = await GnosisSafeFactory.deploy()
  const gnosisSafeAddress = await gnosisSafeFactoryProxy.getAddress()

  //
  // deploy sender creator
  const EIP4337ManagerFactory = await ethers.getContractFactory('EIP4337Manager')
  const eIP4337ManagerFactoryProxy = await EIP4337ManagerFactory.deploy(entrypoint)
  const eip4337MgrAddress = await eIP4337ManagerFactoryProxy.getAddress()

  // deploy GnosisSafeAccountFactory
  const GnosisSafeAccountFactory = await ethers.getContractFactory('GnosisSafeAccountFactory')
  const gnosisSafeAccountFactoryProxy = await upgrades.deployProxy(
    GnosisSafeAccountFactory,
    [gnosisSafeProxyAddress, gnosisSafeAddress, eip4337MgrAddress],
    {
      initializer: 'initialize'
    }
  )
  const gnosisSafeAccountFactoryProxyAddress = await gnosisSafeAccountFactoryProxy.getAddress()

  // if (hre.config.etherscan.apiKey[hre.network.name] !== undefined) {
  //   await Sleep(sleepTime)
  //   await hre.run('verify:verify', {
  //     address: gnosisSafeProxyAddress,
  //     constructorArguments: [],
  //     contract: 'lib/@gnosis.pm/safe-contracts/contracts/proxies/GnosisSafeProxyFactory.sol:GnosisSafeProxyFactory'
  //   })

  //   await hre.run('verify:verify', {
  //     address: gnosisSafeAddress,
  //     constructorArguments: [],
  //     contract: 'lib/@gnosis.pm/safe-contracts/contracts/GnosisSafeL2.sol:GnosisSafeL2'
  //   })

  //   await hre.run('verify:verify', {
  //     address: eip4337MgrAddress,
  //     constructorArguments: [
  //       entrypoint
  //     ],
  //     contract: 'contracts/samples/gnosis/EIP4337Manager.sol:EIP4337Manager'
  //   })

  //   const impl = await upgrades.erc1967.getImplementationAddress(gnosisSafeAccountFactoryProxyAddress)
  //   await hre.run('verify:verify', {
  //     address: impl,
  //     constructorArguments: [],
  //     contract: 'contracts/samples/gnosis/GnosisAccountFactory.sol:GnosisSafeAccountFactory'
  //   })
  // }
  return gnosisSafeAccountFactoryProxyAddress
}

async function deploySubsidyPaymaster (hre: HardhatRuntimeEnvironment, entrypoint: string, pubkey: string): Promise<string> {
  const ethers = hre.ethers
  const upgrades = hre.upgrades
  const owner = (await ethers.getSigners())[0].address
  const SubsidyPaymaster = await ethers.getContractFactory('SubsidyPaymaster')
  const subsidyPaymaster = await upgrades.deployProxy(
    SubsidyPaymaster,
    [entrypoint, owner, pubkey],
    {
      initializer: 'initialize'
    }
  )
  const subsidyPaymasterAddr = await subsidyPaymaster.getAddress()
  // if (hre.config.etherscan.apiKey[hre.network.name] !== undefined) {
  //   await Sleep(sleepTime)
  //   const subsidyPaymasterImpl = await upgrades.erc1967.getImplementationAddress(subsidyPaymasterAddr)
  //   await hre.run('verify:verify', {
  //     address: subsidyPaymasterImpl,
  //     constructorArguments: [],
  //     contract: 'contracts/samples/paymaster/SubsidyPaymaster.sol:SubsidyPaymaster'
  //   })
  // }
  return subsidyPaymasterAddr
}

async function deployMultiSendCallOnly (hre: HardhatRuntimeEnvironment): Promise<string> {
  const ethers = hre.ethers
  const MultiSendCallOnly = await ethers.getContractFactory('MultiSendCallOnly')
  const multiSendCallOnly = await MultiSendCallOnly.deploy()
  const multiSendCallOnlyAddr = await multiSendCallOnly.getAddress()
  // console.log(`subsidy paymaster      : ${subsidyPaymasterAddr}`)
  // if (hre.config.etherscan.apiKey[hre.network.name] !== undefined) {
  //   await Sleep(sleepTime)

  //   await hre.run('verify:verify', {
  //     address: multiSendCallOnlyAddr,
  //     constructorArguments: [],
  //     contract: 'contracts/samples/gnosis/MultiSendCallOnly.sol:MultiSendCallOnly'
  //   })
  // }
  return multiSendCallOnlyAddr
}
