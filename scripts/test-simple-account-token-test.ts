import { UserOperationStruct } from '../typechain/contracts/core/BaseAccount'
import { ethers} from 'hardhat'

import { parseEther, Wallet, keccak256, concat, toUtf8Bytes } from 'ethers'

const entrypoint = '0xCf7Ed3AccA5a467e9e704C703E8D87F634fB0Fc9'
const accountFactory = '0x0165878A594ca255338adfa4d48449f69242Eb8F'
const token = '0x05Ecb110a232161fbF719E5889A95e42ca0be154'
const tokenPaymaster = '0x2279B7A0a67DB372996a5FaB50D91eAA73d2eBe6'
const salt = '0x1fc44be88bb5b18430b5cafae006984102b4a3ac9887b7db77c54503a5fcd23d'
const ownerPrivateKey = '0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80' // 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266

async function main () {
// owner wallet
  const wallet = new Wallet(ownerPrivateKey, ethers.provider)

  const mytoken = await ethers.getContractAt('MyToken', token)

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

  const initCode = '0x'
  const feeData = await ethers.provider.getFeeData()
  const op: UserOperationStruct = {
    sender: sender,
    nonce: await EntryPoint.getNonce(sender, 0),
    initCode: initCode,
    callData: Account.interface.encodeFunctionData('execute', ['0x25B94a38374c4Cbf547a61476a12470650EaFA0C', 0, '0x6548b7ae0000000000000000000000000000000000000000000000000000000000000007000000000000000000000000000000000000000000000000000000000000013700000000000000000000000000000000000000000000000000000000000000030000000000000000000000000000000000000000000000000000000000000080000000000000000000000000000000000000000000000000000000000000004140311a803e9f8bc513262e67ee82924dbe041ad466742cf64b31355f9be2ac173fd4adbafc6754f316b8396551a58d1744ad330d663f61986b8dde238eb59a450000000000000000000000000000000000000000000000000000000000000000']),
    callGasLimit: 1000000,
    verificationGasLimit: 1000000,
    preVerificationGas: 500000,
    maxFeePerGas: 1,
    maxPriorityFeePerGas: 1,
    paymasterAndData: '0x',
    signature: '0x'
  }

  // signature
  const userOpHash = await EntryPoint.getUserOpHash(op)
  console.log('userOpHash:', userOpHash)
  // op.signature = await wallet.signMessage(userOpHash)

  op.signature = wallet.signingKey.sign(hashMessage(userOpHash)).serialized
  console.log('userOperation sign: ', op.signature)

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
