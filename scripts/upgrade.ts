
import { types, task } from 'hardhat/config'
import { HardhatRuntimeEnvironment } from 'hardhat/types'
import { Sleep } from './common'

const sleepTime = 6000 // 6s
// hardhat upgrade --network coq --contract entrypoint  --address 0x79a2557f8b6E1B8187eE9af155978686a7574144
// hardhat upgrade --network coq --contract subsidypaymaster  --address 0xe340DE9dec782cc432FBcc374302b5C68396DED8

task('upgrade', 'upgrade contract')
  .addParam('contract', 'Which contract is deployed? (entrypoint|subsidypaymaster)')
  .addParam('address', 'contract address', '', types.string)
  .setAction(async (taskArgs, hre) => {
    const address = taskArgs.address
    const contract = taskArgs.contract

    if (!hre.ethers.isAddress(address)) {
      console.log('invalid address')
      return ''
    }

    if (contract === 'entrypoint') {
      const upgraded = await upgradeEntrypoint(hre, address)
      if (upgraded) {
        console.log('')
        console.log('------------------- upgrade contract -------------------')
        console.log('')
        console.log('entrypoint upgrade completed')
      }
    } else if (contract === 'subsidypaymaster') {
      const upgraded = await upgradeSubsidyPaymaster(hre, address)
      if (upgraded) {
        console.log('')
        console.log('------------------- upgrade contract -------------------')
        console.log('')
        console.log('subsidy paymaster upgrade completed')
      }
    } else {
      console.log('invalid contract')
    }
  })

async function upgradeEntrypoint (hre: HardhatRuntimeEnvironment, address: string): Promise<boolean> {
  const ethers = hre.ethers
  const upgrades = hre.upgrades

  const proxyadmin = await upgrades.erc1967.getAdminAddress(address)
  const contractFactory = await upgrades.admin.getInstance()

  const owner = await contractFactory.attach(proxyadmin).owner()

  if (owner !== (await ethers.getSigners())[0].address) {
    console.log(`proxyadmin owner: ${owner}`)
    console.log(`your owner: ${(await ethers.getSigners())[0].address}`)
    console.log('No upgrade permission')
    return false
  }

  const EntryPoint = await ethers.getContractFactory('contracts/core/EntryPoint.sol:EntryPoint')
  const entryPoint = await EntryPoint.deploy()
  const entryPointAddr = await entryPoint.getAddress()

  await contractFactory.attach(proxyadmin).upgrade(address, entryPointAddr)

  // // console.log(`subsidy paymaster      : ${EntryPointAddr}`)
  if (hre.config.etherscan.apiKey[hre.network.name] !== undefined) {
    await Sleep(sleepTime)
    await hre.run('verify:verify', {
      address: entryPointAddr,
      constructorArguments: [],
      contract: 'contracts/core/EntryPoint.sol:EntryPoint'
    })
  }
  return true
}

async function upgradeSubsidyPaymaster (hre: HardhatRuntimeEnvironment, address: string): Promise<boolean> {
  const ethers = hre.ethers
  const upgrades = hre.upgrades

  const proxyadmin = await upgrades.erc1967.getAdminAddress(address)
  const contractFactory = await upgrades.admin.getInstance()

  const owner = await contractFactory.attach(proxyadmin).owner()

  if (owner !== (await ethers.getSigners())[0].address) {
    console.log(`proxyadmin owner: ${owner}`)
    console.log(`your owner: ${(await ethers.getSigners())[0].address}`)
    console.log('No upgrade permission')
    return false
  }

  const SubsidyPaymaster = await ethers.getContractFactory('SubsidyPaymaster')
  const subsidyPaymaster = await SubsidyPaymaster.deploy()
  const subsidyPaymasterAddr = await subsidyPaymaster.getAddress()

  await contractFactory.attach(proxyadmin).upgrade(address, subsidyPaymasterAddr)

  // // console.log(`subsidy paymaster      : ${subsidyPaymasterAddr}`)
  if (hre.config.etherscan.apiKey[hre.network.name] !== undefined) {
    await Sleep(sleepTime)
    await hre.run('verify:verify', {
      address: subsidyPaymasterAddr,
      constructorArguments: [],
      contract: 'contracts/samples/paymaster/SubsidyPaymaster.sol:SubsidyPaymaster'
    })
  }
  return true
}
