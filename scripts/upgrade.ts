
import { types, task } from 'hardhat/config'
import { HardhatRuntimeEnvironment } from 'hardhat/types'
import { Sleep } from './common'

const sleepTime = 6000 // 6s
// hardhat deploy --network coq --contract entrypoint
// hardhat deploy --network coq --contract all --token 0x13D91374CcB046ca0B66688AdCe4B2B62837A86a --pubkey 0xe184aF3b0b9CeFf9C2d11B1D33FF31Cc483C13F2 --fee 0.01
// hardhat deploy --network coq --contract accountfactory --entrypoint 0x83DA221A7D6D96357794eC749a658811997Ee039
// hardhat deploy --network coq --contract tokenpaymster --entrypoint 0x83DA221A7D6D96357794eC749a658811997Ee039 --token 0x13D91374CcB046ca0B66688AdCe4B2B62837A86a --pubkey 0xe184aF3b0b9CeFf9C2d11B1D33FF31Cc483C13F2 --fee 0.01
// hardhat deploy --network coq --contract gnosisfactory --entrypoint 0x83DA221A7D6D96357794eC749a658811997Ee039
// hardhat deploy --network coq --contract subsidypaymaster --entrypoint 0x83DA221A7D6D96357794eC749a658811997Ee039 --token 0x13D91374CcB046ca0B66688AdCe4B2B62837A86a --pubkey 0xe184aF3b0b9CeFf9C2d11B1D33FF31Cc483C13F2
// hardhat deploy --network coq --contract multisendcallonly

task('upgrade', 'upgrade contract')
  .addParam('contract', 'Which contract is deployed? (subsidypaymaster)')
  .addParam('address', 'contract address', '', types.string)
  .setAction(async (taskArgs, hre) => {
    const address = taskArgs.address
    const contract = taskArgs.contract

    if (!hre.ethers.isAddress(address)) {
      console.log('invalid address')
      return ''
    }

    if (contract === 'subsidypaymaster') {
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

  const SubsidyPaymaster = await ethers.getContractFactory('contracts/samples/paymaster/SubsidyPaymaster.sol:SubsidyPaymaster')
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
