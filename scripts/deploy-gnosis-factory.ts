// import { EntryPoint } from './../typechain/contracts/core/EntryPoint'
// import { GnosisSafe } from './../typechain/@gnosis.pm/safe-contracts/contracts/GnosisSafe'
import { task } from 'hardhat/config'

// hardhat deploy_gnosis_factory --network dev
task('deploy_gnosis_factory', 'deploy factory contract for gnosis')
  .addParam('entrypoint', "the entrypoint's address")
  .setAction(async (taskArgs, hre) => {
    const ethers = hre.ethers
    const upgrades = hre.upgrades
    // deploy GnosisSafeProxyFactory
    const GnosisSafeProxyFactory = await ethers.getContractFactory('GnosisSafeProxyFactory')
    const GnosisSafeProxyFactoryProxy = await GnosisSafeProxyFactory.deploy()
    const GnosisSafeFactoryProxyAddress = await GnosisSafeProxyFactoryProxy.getAddress()

    // deploy GnosisSafe
    const GnosisSafeFactory = await ethers.getContractFactory('GnosisSafeL2')
    const GnosisSafeFactoryProxy = await GnosisSafeFactory.deploy()
    const gnosisSafeAddress = await GnosisSafeFactoryProxy.getAddress()

    //
    // deploy sender creator
    const EIP4337ManagerFactory = await ethers.getContractFactory('EIP4337Manager')
    const EIP4337ManagerFactoryProxy = await EIP4337ManagerFactory.deploy(taskArgs.entrypoint)
    const eip4337MgrAddress = await EIP4337ManagerFactoryProxy.getAddress()

    // deploy GnosisSafeAccountFactory
    const GnosisSafeAccountFactory = await ethers.getContractFactory('GnosisSafeAccountFactory')
    const GnosisSafeAccountFactoryProxy = await upgrades.deployProxy(
      GnosisSafeAccountFactory,
      [GnosisSafeFactoryProxyAddress, gnosisSafeAddress, eip4337MgrAddress],
      {
        initializer: 'initialize'
      }
    )

    console.log(`gnosis factory: ${await GnosisSafeAccountFactoryProxy.getAddress()}`)
  })
