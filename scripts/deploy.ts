import { task } from 'hardhat/config'

import { ethers, upgrades } from 'hardhat'
import { Wallet, parseEther } from 'ethers'
import { string } from 'hardhat/internal/core/params/argumentTypes'

// const ownerPrivateKey = '0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80' // 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266

// hardhat deploy --network coq --token 0x13D91374CcB046ca0B66688AdCe4B2B62837A86a --pubkey 0xe184aF3b0b9CeFf9C2d11B1D33FF31Cc483C13F2
// hardhat deploy --network dev
task('deploy', 'deploy contract')
  .addParam('pubkey', 'paymaster public key', '0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266', undefined)
  .addParam('token', 'token of other chain', '', undefined, true)
  .setAction(async (taskArgs, hre) => {
    const ethers = hre.ethers
    const upgrades = hre.upgrades
    const pubkey: string = taskArgs.pubkey
    let token: string = taskArgs.token
    if (hre.network.name === 'dev') {
      const MyToken = await ethers.getContractFactory('MyToken')
      const mytoken = await MyToken.deploy('my token', 'MT')
      token = await mytoken.getAddress()
    }

    if (!hre.ethers.isAddress(token)) {
      console.log('invalid token')
    } else {
      // deploy sender creator
      const SenderCreator = await ethers.getContractFactory('SenderCreator')
      const senderCreator = await SenderCreator.deploy()
      // console.log('sender creator: ', await senderCreator.getAddress())

      // deploy entrypoint
      const EntryPointFactory = await ethers.getContractFactory('EntryPoint')
      const EntryPointProxy = await upgrades.deployProxy(
        EntryPointFactory,
        [await senderCreator.getAddress()],
        {
          initializer: 'initialize'
        }
      )
      const EntryPointProxyAddr = await EntryPointProxy.getAddress()
      console.log(`entry point address    : ${EntryPointProxyAddr}`)

      // deploy simple account
      const SimpleAccount = await ethers.getContractFactory('SimpleAccount')
      const simpleAccount = await SimpleAccount.deploy(EntryPointProxyAddr)
      // console.log('simple account: ', await simpleAccount.getAddress())

      // deploy simple account factory
      const SimpleAccountFactoryFactory = await ethers.getContractFactory('SimpleAccountFactory')
      const SimpleAccountFactoryProxy = await upgrades.deployProxy(
        SimpleAccountFactoryFactory,
        [await simpleAccount.getAddress()],
        {
          initializer: 'initialize'
        }
      )
      const simpleAccountFactoryProxyAddr = await SimpleAccountFactoryProxy.getAddress()
      console.log(`simple account factory : ${simpleAccountFactoryProxyAddr}`)

      console.log('erc20 token            :', token)

      // deploy token paymster
      const owner = (await ethers.getSigners())[0].address
      const SimpleTokenPaymaster = await ethers.getContractFactory('SimpleTokenPaymaster')
      const simpleTokenPaymaster = await upgrades.deployProxy(
        SimpleTokenPaymaster,
        [EntryPointProxyAddr, token, owner, pubkey, parseEther('0.01')],
        {
          initializer: 'initialize'
        }
      )
      const simpleTokenPaymasterProxyAddr = await simpleTokenPaymaster.getAddress()
      console.log(`simple token paymaster : ${simpleTokenPaymasterProxyAddr}`)

      // -------------------- deploy GnosisSafeProxyFactory ---------------------
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
      const EIP4337ManagerFactoryProxy = await EIP4337ManagerFactory.deploy(EntryPointProxyAddr)
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

      console.log(`gnosis factory         : ${await GnosisSafeAccountFactoryProxy.getAddress()}`)
    }
  })
