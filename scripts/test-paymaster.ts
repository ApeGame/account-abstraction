import { UserOperationStruct } from '../typechain/contracts/core/BaseAccount'
import { ethers } from 'hardhat'

import { parseEther, Wallet, keccak256, concat, toUtf8Bytes, AbiCoder, BigNumberish } from 'ethers'

const entrypoint = '0xDc64a140Aa3E981100a9becA4E685f962f0cF6C9'
const accountFactory = '0xa513E6E4b8f2a923D98304ec87F64353C4D5C853'
const token = '0x5FbDB2315678afecb367f032d93F642f64180aa3'
const tokenPaymaster = '0x8A791620dd6260079BF849Dc5567aDC3F2FdC318'
const salt = '0x1fc44be88bb5b18430b5cafae006984102b4a3ac9887b7db77c54503a5fcd23d'
const ownerPrivateKey = '0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80' // 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266

async function main () {
// owner wallet
  const wallet = new Wallet(ownerPrivateKey, ethers.provider)

  const mytoken = await ethers.getContractAt('MyToken', token)

  const simpleTokenPaymaster = await ethers.getContractAt('SimpleTokenPaymaster', tokenPaymaster)

  // get entrypoint and account factory
  const EntryPoint = await ethers.getContractAt('EntryPoint', entrypoint)
  const AccountFactory = await ethers.getContractFactory('SimpleAccountFactory')
  const Account = await ethers.getContractFactory('SimpleAccount')

  // Prepare useroperation
  const res = await ethers.provider.send(
    'eth_call',
    [{ to: accountFactory, data: AccountFactory.interface.encodeFunctionData('getAddress', [wallet.address, salt]) }, 'latest']
  )
  const sender = '0x'.concat(res.slice(26))

  const nonce = await EntryPoint.getNonce(sender, 0)
  const price = parseEther('0.01')
  const dealine = Math.floor(Date.now() / 1000)
  const chainId = (await ethers.provider.getNetwork()).chainId

  const beneficiary = (await ethers.getSigners())[0].address

  // ethers.AbiCoder.defaultAbiCoder().encode()
  const sig = wallet.signingKey.sign(keccak256(
    AbiCoder.defaultAbiCoder().encode(['address', 'uint256', 'uint256', 'uint256', 'uint256'], [sender, nonce, price, dealine, chainId])
  ))

  const paymasterAndData = concat([
    tokenPaymaster,
    AbiCoder.defaultAbiCoder().encode(['uint256', 'uint256', 'bytes'],
      [price, dealine, concat([sig.r, sig.s, sig.v === 27 ? '0x00' : '0x01'])])])

  const initCode = '0x'
  const op: UserOperationStruct = {
    sender: sender,
    nonce: await EntryPoint.getNonce(sender, 0),
    initCode: initCode,
    callData: Account.interface.encodeFunctionData('execute', [await mytoken.getAddress(), 0, mytoken.interface.encodeFunctionData('transfer', ['0x24f59a23d97C166A78E2483CE81CBC0C24839623', parseEther('1')])]),
    callGasLimit: 1000000,
    verificationGasLimit: 1000000,
    preVerificationGas: 500000,
    maxFeePerGas: 1,
    maxPriorityFeePerGas: 1,
    paymasterAndData: paymasterAndData,
    signature: '0x'
  }

  const userOpHash = await EntryPoint.getUserOpHash(op)
  // console.log('userOpHash:', userOpHash)

  op.signature = wallet.signingKey.sign(hashMessage(userOpHash)).serialized
  // console.log('userOperation sign: ', op.signature)

  console.log(op)
  const tx = await EntryPoint.handleOps([op], beneficiary)
  console.log(tx.hash)
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
