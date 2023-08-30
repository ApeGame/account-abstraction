import { types, task } from 'hardhat/config'
import TransparentUpgradeableProxy from '@openzeppelin/upgrades-core/artifacts/@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol/TransparentUpgradeableProxy.json'
import ProxyAdmin from '@openzeppelin/upgrades-core/artifacts/@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol/ProxyAdmin.json'
// hardhat deploy-all --network dev --token 0x13D91374CcB046ca0B66688AdCe4B2B62837A86a --pubkey 0xe184aF3b0b9CeFf9C2d11B1D33FF31Cc483C13F2 --fee 0.01

// hardhat deploy-all --network coqdeployer --token 0x13D91374CcB046ca0B66688AdCe4B2B62837A86a --pubkey 0xe184aF3b0b9CeFf9C2d11B1D33FF31Cc483C13F2 --fee 0.01
// hardhat deploy-all --network basegoerlideployer --token 0x77E825be7701Fe49D4b825304C77B3754f80D54d --pubkey 0xe184aF3b0b9CeFf9C2d11B1D33FF31Cc483C13F2 --fee 0.1
// hardhat deploy-all --network lineagoerlideployer --token 0xE45469233597318F51656B401DD561D9306ED2Fd --pubkey 0xe184aF3b0b9CeFf9C2d11B1D33FF31Cc483C13F2 --fee 0.1

task('deploy-all', 'deploy all contract')
  .addParam('token', 'erc20 contract (dev network will create it when it is undefined)', '', types.string)
  .addParam('pubkey', 'public key (tokenpaymster & subsidypaymaster need it)', '', types.string)
  .addParam('fee', 'fee of tokenpaymster (only tokenpaymster)', '', types.string)
  .setAction(async (taskArgs, hre) => {
    const TransparentUpgradeableProxyFactory = await hre.ethers.getContractFactory(TransparentUpgradeableProxy.abi, TransparentUpgradeableProxy.bytecode)
    let token = taskArgs.token
    const pubkey = taskArgs.pubkey
    let fee: bigint
    if (taskArgs.fee === '') {
      fee = BigInt(0)
    } else {
      fee = hre.ethers.parseEther(taskArgs.fee)
    }

    if (!hre.ethers.isAddress(token)) {
      console.log('invalid token')
      return ''
    }

    if (!hre.ethers.isAddress(pubkey)) {
      console.log('invalid pubkey')
      return ''
    }

    if (fee < 0) {
      console.log('invalid fee')
      return ''
    }

    console.log('')
    console.log('------------------- deployed contract -------------------')
    console.log('')
    const owner = (await hre.ethers.getSigners())[0].address
    let nonce: number = await hre.ethers.provider.getTransactionCount(owner)

    // hre.ethers.provider.es
    // mock erc20 in localhost network
    if (hre.network.name === 'dev') {
      const ownerErc20 = new hre.ethers.Wallet('0x92db14e403b83dfe3df233f83dfa3a0d7096f21ca9b0d6d6b8d88b2b4ec1564e', hre.ethers.provider)
      const ERC20 = await hre.ethers.getContractFactory('MyToken')
      const erc20 = await ERC20.connect(ownerErc20).deploy('mytoken', 'mt')
      await erc20.connect(ownerErc20).transferOwnership(owner)
      token = await erc20.getAddress()
    }

    const proxyAdmin: string = hre.ethers.getCreateAddress({ from: owner, nonce: 0 })
    // deploy proxy admin contract
    if (nonce === 0) {
      console.log(nonce)
      const proxyFactory = await hre.ethers.getContractFactory(ProxyAdmin.abi, ProxyAdmin.bytecode)
      const gasLimit: bigint = await hre.ethers.provider.estimateGas(await proxyFactory.getDeployTransaction())
      if (gasLimit === BigInt(0)) {
        return
      }
      await proxyFactory.deploy({ nonce: 0, gasLimit: gasLimit + BigInt(100000) })
      nonce += 1
    }

    // deploy entrypoiny
    if (nonce === 1) {
      console.log(nonce)
      const SenderCreator = await hre.ethers.getContractFactory('SenderCreator')
      const gasLimit: bigint = await hre.ethers.provider.estimateGas(await SenderCreator.getDeployTransaction())
      if (gasLimit === BigInt(0)) {
        return
      }
      await SenderCreator.deploy({ nonce: 1, gasLimit: gasLimit + BigInt(100000) })
      nonce += 1
    }

    const EntryPointFactory = await hre.ethers.getContractFactory('EntryPoint')
    if (nonce === 2) {
      console.log(nonce)
      const gasLimit: bigint = await hre.ethers.provider.estimateGas(await EntryPointFactory.getDeployTransaction())
      if (gasLimit === BigInt(0)) {
        return
      }
      await EntryPointFactory.deploy({ nonce: 2, gasLimit: gasLimit + BigInt(100000) })
      nonce += 1
    }

    if (nonce === 3) {
      console.log(nonce)
      const senderCreatorAddress: string = hre.ethers.getCreateAddress({ from: owner, nonce: 1 })
      const entryPointFactoryAddress: string = hre.ethers.getCreateAddress({ from: owner, nonce: 2 })
      const data = EntryPointFactory.interface.encodeFunctionData('initialize', [senderCreatorAddress])
      const gasLimit: bigint = await hre.ethers.provider.estimateGas(await TransparentUpgradeableProxyFactory.getDeployTransaction(entryPointFactoryAddress, proxyAdmin, data))
      if (gasLimit === BigInt(0)) {
        return
      }
      await TransparentUpgradeableProxyFactory.deploy(entryPointFactoryAddress, proxyAdmin, data, { nonce: 3, gasLimit: gasLimit + BigInt(100000) })
      nonce += 1
    }

    const entrypoint: string = hre.ethers.getCreateAddress({ from: owner, nonce: 3 })

    // deploy account factory
    if (nonce === 4) {
      console.log(nonce)
      const SimpleAccount = await hre.ethers.getContractFactory('SimpleAccount')
      const gasLimit: bigint = await hre.ethers.provider.estimateGas(await SimpleAccount.getDeployTransaction(entrypoint))
      if (gasLimit === BigInt(0)) {
        return
      }
      await SimpleAccount.deploy(entrypoint, { nonce: 4, gasLimit: gasLimit + BigInt(100000) })
      nonce += 1
    }

    const SimpleAccountFactoryFactory = await hre.ethers.getContractFactory('SimpleAccountFactory')
    if (nonce === 5) {
      console.log(nonce)
      const gasLimit: bigint = await hre.ethers.provider.estimateGas(await SimpleAccountFactoryFactory.getDeployTransaction())
      if (gasLimit === BigInt(0)) {
        return
      }
      await SimpleAccountFactoryFactory.deploy({ nonce: 5, gasLimit: gasLimit + BigInt(100000) })
      nonce += 1
    }

    if (nonce === 6) {
      console.log(nonce)
      const simpleAccountAddress = hre.ethers.getCreateAddress({ from: owner, nonce: 4 })
      const simpleAccountFactoryAddress = hre.ethers.getCreateAddress({ from: owner, nonce: 5 })
      const data = SimpleAccountFactoryFactory.interface.encodeFunctionData('initialize', [simpleAccountAddress])
      const gasLimit: bigint = await hre.ethers.provider.estimateGas(await TransparentUpgradeableProxyFactory.getDeployTransaction(simpleAccountFactoryAddress, proxyAdmin, data))
      if (gasLimit === BigInt(0)) {
        return
      }
      await TransparentUpgradeableProxyFactory.deploy(simpleAccountFactoryAddress, proxyAdmin, data, { nonce: 6, gasLimit: gasLimit + BigInt(100000) })
      nonce += 1
    }

    // deploy token paymaster
    const SimpleTokenPaymaster = await hre.ethers.getContractFactory('SimpleTokenPaymaster')
    if (nonce === 7) {
      console.log(nonce)
      const gasLimit: bigint = await hre.ethers.provider.estimateGas(await SimpleTokenPaymaster.getDeployTransaction())
      if (gasLimit === BigInt(0)) {
        return
      }
      await SimpleTokenPaymaster.deploy({ nonce: 7, gasLimit: gasLimit + BigInt(100000) })
      nonce += 1
    }

    if (nonce === 8) {
      console.log(nonce)
      const simpleTokenPaymasterFactoryAddress = hre.ethers.getCreateAddress({ from: owner, nonce: 7 })
      const data = SimpleTokenPaymaster.interface.encodeFunctionData('initialize', [entrypoint, token, owner, pubkey, fee])
      const gasLimit: bigint = await hre.ethers.provider.estimateGas(await TransparentUpgradeableProxyFactory.getDeployTransaction(simpleTokenPaymasterFactoryAddress, proxyAdmin, data))
      if (gasLimit === BigInt(0)) {
        return
      }
      await TransparentUpgradeableProxyFactory.deploy(simpleTokenPaymasterFactoryAddress, proxyAdmin, data, { nonce: 8, gasLimit: gasLimit + BigInt(100000) })
      nonce += 1
    }

    // deploy gnosis safe factory
    if (nonce === 9) {
      console.log(nonce)
      const GnosisSafeProxyFactory = await hre.ethers.getContractFactory('GnosisSafeProxyFactory')
      const gasLimit: bigint = await hre.ethers.provider.estimateGas(await GnosisSafeProxyFactory.getDeployTransaction())
      if (gasLimit === BigInt(0)) {
        return
      }
      await GnosisSafeProxyFactory.deploy({ nonce: 9, gasLimit: gasLimit + BigInt(100000) })
      nonce += 1
    }

    if (nonce === 10) {
      console.log(nonce)
      const GnosisSafeFactory = await hre.ethers.getContractFactory('GnosisSafeL2')
      const gasLimit: bigint = await hre.ethers.provider.estimateGas(await GnosisSafeFactory.getDeployTransaction())
      if (gasLimit === BigInt(0)) {
        return
      }
      await GnosisSafeFactory.deploy({ nonce: 10, gasLimit: gasLimit + BigInt(100000) })
      nonce += 1
    }

    if (nonce === 11) {
      console.log(nonce)
      const EIP4337ManagerFactory = await hre.ethers.getContractFactory('EIP4337Manager')
      const gasLimit: bigint = await hre.ethers.provider.estimateGas(await EIP4337ManagerFactory.getDeployTransaction(entrypoint))
      if (gasLimit === BigInt(0)) {
        return
      }
      await EIP4337ManagerFactory.deploy(entrypoint, { nonce: 11, gasLimit: gasLimit + BigInt(100000) })
      nonce += 1
    }

    const GnosisSafeAccountFactory = await hre.ethers.getContractFactory('GnosisSafeAccountFactory')

    if (nonce === 12) {
      console.log(nonce)
      const gasLimit: bigint = await hre.ethers.provider.estimateGas(await GnosisSafeAccountFactory.getDeployTransaction())
      if (gasLimit === BigInt(0)) {
        return
      }
      await GnosisSafeAccountFactory.deploy({ nonce: 12, gasLimit: gasLimit + BigInt(100000) })
      nonce += 1
    }

    if (nonce === 13) {
      console.log(nonce)
      const gnosisSafeProxyAddress = hre.ethers.getCreateAddress({ from: owner, nonce: 9 })
      const gnosisSafeAddress = hre.ethers.getCreateAddress({ from: owner, nonce: 10 })
      const eip4337MgrAddress = hre.ethers.getCreateAddress({ from: owner, nonce: 11 })
      const gnosisSafeAccountFactoryAddress = hre.ethers.getCreateAddress({ from: owner, nonce: 12 })
      const data = GnosisSafeAccountFactory.interface.encodeFunctionData('initialize', [gnosisSafeProxyAddress, gnosisSafeAddress, eip4337MgrAddress])
      const gasLimit: bigint = await hre.ethers.provider.estimateGas(await TransparentUpgradeableProxyFactory.getDeployTransaction(gnosisSafeAccountFactoryAddress, proxyAdmin, data))
      if (gasLimit === BigInt(0)) {
        return
      }
      await TransparentUpgradeableProxyFactory.deploy(gnosisSafeAccountFactoryAddress, proxyAdmin, data, { nonce: 13, gasLimit: gasLimit + BigInt(100000) })
      nonce += 1
    }

    // deploy subsidy paymaster
    const SubsidyPaymaster = await hre.ethers.getContractFactory('SubsidyPaymaster')
    if (nonce === 14) {
      console.log(nonce)
      const gasLimit: bigint = await hre.ethers.provider.estimateGas(await SubsidyPaymaster.getDeployTransaction())
      if (gasLimit === BigInt(0)) {
        return
      }
      await SubsidyPaymaster.deploy({ nonce: 14, gasLimit: gasLimit + BigInt(100000) })
      nonce += 1
    }

    if (nonce === 15) {
      console.log(nonce)
      const subsidyPaymasterFactroyAddress = hre.ethers.getCreateAddress({ from: owner, nonce: 14 })
      const data = SubsidyPaymaster.interface.encodeFunctionData('initialize', [entrypoint, owner, pubkey])
      const gasLimit: bigint = await hre.ethers.provider.estimateGas(await TransparentUpgradeableProxyFactory.getDeployTransaction(subsidyPaymasterFactroyAddress, proxyAdmin, data))
      if (gasLimit === BigInt(0)) {
        return
      }
      await TransparentUpgradeableProxyFactory.deploy(subsidyPaymasterFactroyAddress, proxyAdmin, data, { nonce: 15, gasLimit: gasLimit + BigInt(100000) })
      nonce += 1
    }

    if (nonce === 16) {
      console.log(nonce)
      const MultiSendCallOnly = await hre.ethers.getContractFactory('MultiSendCallOnly')
      const gasLimit: bigint = await hre.ethers.provider.estimateGas(await MultiSendCallOnly.getDeployTransaction())
      if (gasLimit === BigInt(0)) {
        return
      }
      await MultiSendCallOnly.deploy({ nonce: 16, gasLimit: gasLimit + BigInt(100000) })
    }

    console.log(`proxy admin            : ${proxyAdmin}`)
    console.log('---------------------------------------------------------')
    console.log(`entrypoint address     : ${hre.ethers.getCreateAddress({ from: owner, nonce: 3 })}`)
    console.log(`simple account factory : ${hre.ethers.getCreateAddress({ from: owner, nonce: 6 })}`)
    console.log('erc20 token            :', token)
    console.log(`simple token paymaster : ${hre.ethers.getCreateAddress({ from: owner, nonce: 8 })}`)
    console.log(`gnosis factory         : ${hre.ethers.getCreateAddress({ from: owner, nonce: 13 })}`)
    console.log(`subsidy paymaster      : ${hre.ethers.getCreateAddress({ from: owner, nonce: 15 })}`)
    console.log(`multisend call only    : ${hre.ethers.getCreateAddress({ from: owner, nonce: 16 })}`)
  })
