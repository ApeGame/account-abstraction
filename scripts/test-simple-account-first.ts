import { UserOperationStruct } from '../typechain/contracts/core/BaseAccount'
import { UserOperation } from '../test/UserOperation'
import { ethers, network, upgrades } from 'hardhat'

import { EntryPoint } from '../typechain'
import { init } from '@thehubbleproject/bls/dist/mcl'
import { parseEther, Wallet, keccak256, concat, toUtf8Bytes } from 'ethers'

const entrypoint = '0xd876ed6aAf728C927770E02672738364d759331f'
const accountFactory = '0x4435aFc3474e62aB81811d5c19300788a969928b'
const token = '0xa6eb75b11b36fb9175fb94c5b96959879a26c2a8'
const tokenPaymaster = '0x6Bc8c816a2f85Ab9478Cb50e28756CCc1F20169a'
const salt = '0x1fc44be88bb5b18430b5cafae006984102b4a3ac9887b7db77c54503a5fcd23d'
const ownerPrivateKey = '0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80' // 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266

async function main () {
// owner wallet
  const wallet = new Wallet(ownerPrivateKey, ethers.provider)

  // const mytoken = await ethers.getContractAt('MyToken', token)

  const mytokenFactory = await ethers.getContractFactory('MyToken')
  const mytoken = await mytokenFactory.deploy('aa', 'bb')

  // get entrypoint and account factory
  const EntryPoint = await ethers.getContractAt('EntryPoint', entrypoint)
  const AccountFactory = await ethers.getContractAt('SimpleAccountFactory', accountFactory)
  const Account = await ethers.getContractFactory('SimpleAccount')

  // Prepare useroperation

  const beneficiary = (await ethers.getSigners())[0].address

  const res = await ethers.provider.send(
    'eth_call',
    [{ to: accountFactory, data: AccountFactory.interface.encodeFunctionData('getAddress', [wallet.address, salt]) }, 'latest']
  )
  const sender = '0x'.concat(res.slice(26))

  const initCode = accountFactory.concat(
    AccountFactory.interface.encodeFunctionData('createAccount', [wallet.address, salt]).slice(2)
  )
  const feeData = await ethers.provider.getFeeData()
  const op: UserOperationStruct = {
    sender: sender,
    nonce: await EntryPoint.getNonce(sender, 0),
    initCode: initCode,
    callData: Account.interface.encodeFunctionData('execute', [await mytoken.getAddress(), 0, mytoken.interface.encodeFunctionData('transfer', ['0x24f59a23d97C166A78E2483CE81CBC0C24839623', parseEther('2')])]),
    callGasLimit: 1000000,
    verificationGasLimit: 1000000,
    preVerificationGas: 500000,
    maxFeePerGas: feeData.maxFeePerGas === null ? 0 : feeData.maxFeePerGas,
    maxPriorityFeePerGas: feeData.maxPriorityFeePerGas === null ? 0 : feeData.maxPriorityFeePerGas,
    paymasterAndData: '0x',
    signature: '0x'
  }

  console.log('useroperation:', op)

  // signature
  const userOpHash = await EntryPoint.getUserOpHash(op)
  console.log('userOpHash:', userOpHash)
  // op.signature = await wallet.signMessage(userOpHash)

  op.signature = wallet.signingKey.sign(hashMessage(userOpHash)).serialized
  console.log('userOperation sign: ', op.signature)

  // deposit token to aa
  await EntryPoint.depositTo(sender, { value: parseEther('0.05') })

  // send 100 mt to aa
  await mytoken.mintTo(sender, parseEther('100'))

  // deposit token to aa
  await EntryPoint.depositTo(tokenPaymaster, { value: parseEther('0.05') })

  // send 100 mt to aa
  await mytoken.mintTo(tokenPaymaster, parseEther('100'))

  // handleOPs
  console.log(op)
  const tx = await EntryPoint.handleOps([op], beneficiary)
  console.log(tx.hash)

//   const handleOpsData = EntryPoint.interface.encodeFunctionData('handleOps', [[op], beneficiary])
//   console.log(handleOpsData)
}

const MessagePrefix: string = '\x19Ethereum Signed Message:\n32'
export function hashMessage (message: string): string {
  return keccak256(concat([
    toUtf8Bytes(MessagePrefix),
    message
  ]))
}
// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error)
  process.exitCode = 1
})
