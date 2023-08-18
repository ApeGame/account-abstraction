import { UserOperationStruct } from '../typechain/contracts/core/BaseAccount'
import { ethers} from 'hardhat'

import { parseEther, Wallet, keccak256, concat, toUtf8Bytes } from 'ethers'

const entrypoint = '0xCf7Ed3AccA5a467e9e704C703E8D87F634fB0Fc9'
const accountFactory = '0x0165878A594ca255338adfa4d48449f69242Eb8F'
const token = '0xa513E6E4b8f2a923D98304ec87F64353C4D5C853'
const tokenPaymaster = '0x8A791620dd6260079BF849Dc5567aDC3F2FdC318'
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
    // callData: Account.interface.encodeFunctionData('execute', [await mytoken.getAddress(), 0, mytoken.interface.encodeFunctionData('approve', [tokenPaymaster, parseEther('2000')])]),
    callData: Account.interface.encodeFunctionData('execute', [await mytoken.getAddress(), 0, mytoken.interface.encodeFunctionData('transfer', [tokenPaymaster, parseEther('2000')])]),
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
