import { UserOperationStruct } from '../typechain/contracts/core/BaseAccount'
import { ethers } from 'hardhat'

import { parseEther, Wallet, keccak256, concat, toUtf8Bytes } from 'ethers'

const entrypoint = '0x1f4457F251D5D2Bbd69d2cA40CaDda1cBB63209d'
const accountFactory = '0x3a66271f6997e7279e78dA27B47718ff823B874B'
const salt = '0x1fc44be88bb5b18430b5cafae006984102b4a3ac9887b7db77c54503a5fcd23d'
const ownerPrivateKey = '0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80' // 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266

async function main () {
// owner wallet
  const wallet = new Wallet(ownerPrivateKey, ethers.provider)

  // deploy erc20 token
  const MyToken = await ethers.getContractFactory('MyToken')
  const mytoken = await MyToken.deploy('my token', 'MT')
  // const mytoken = await ethers.getContractAt('MyToken', '0xB4b6D806479FC5CF30baa36538Cc225247e50394')

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
    callData: Account.interface.encodeFunctionData('execute', [await mytoken.getAddress(), 0, mytoken.interface.encodeFunctionData('transfer', ['0x24f59a23d97C166A78E2483CE81CBC0C24839623', parseEther('2')])]),
    callGasLimit: 1000000,
    verificationGasLimit: 1000000,
    preVerificationGas: 500000,
    maxFeePerGas: feeData.maxFeePerGas === null ? 0 : feeData.maxFeePerGas,
    maxPriorityFeePerGas: feeData.maxPriorityFeePerGas === null ? 0 : feeData.maxPriorityFeePerGas,
    paymasterAndData: '0x',
    signature: '0x'
  }

  // signature
  const userOpHash = await EntryPoint.getUserOpHash(op)
  op.signature = wallet.signingKey.sign(hashMessage(userOpHash)).serialized

  // handleOPs
  console.log(op)
  const tx = await await EntryPoint.simulateValidation(op)
  console.log(tx)
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
