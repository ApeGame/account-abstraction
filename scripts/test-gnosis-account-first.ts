import { UserOperationStruct } from '../typechain/contracts/core/BaseAccount'
import { UserOperation } from '../test/UserOperation'
import { ethers, network, upgrades } from 'hardhat'

import { EntryPoint } from '../typechain'
import { init } from '@thehubbleproject/bls/dist/mcl'
import { parseEther, Wallet, keccak256, concat, toUtf8Bytes } from 'ethers'

const entrypoint = '0xD5ac451B0c50B9476107823Af206eD814a2e2580'
const accountFactory = '0x22753E4264FDDc6181dc7cce468904A80a363E44'
const token = '0x4b6aB5F819A515382B0dEB6935D793817bB4af28'
const salt = '0x1fc44be88bb5b18430b5cafae006984102b4a3ac9887b7db77c54503b5fcd11f'
const ownerPrivateKey = '0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80' // 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266

async function main () {
// owner wallet
  const wallet = new Wallet(ownerPrivateKey, ethers.provider)

  const mytoken = await ethers.getContractAt('MyToken', token)

  // get entrypoint and account factory
  const EntryPoint = await ethers.getContractAt('EntryPoint', entrypoint)
  const AccountFactory = await ethers.getContractAt('GnosisSafeAccountFactory', accountFactory)
  const Account = await ethers.getContractFactory('GnosisSafeL2')

  // Prepare useroperation
  // 0x1c4fada7374c0a9ee8841fc38afe82932dc0f8e69012e927f061a8bae611a201

  const beneficiary = (await ethers.getSigners())[0].address

  const res = await ethers.provider.send(
    'eth_call',
    [{ to: accountFactory, data: AccountFactory.interface.encodeFunctionData('getAddress', [[wallet.address], 1, salt]) }, 'latest']
  )
  const sender = '0x'.concat(res.slice(26))

  const initCode = accountFactory.concat(
    AccountFactory.interface.encodeFunctionData('createAccount', [[wallet.address], 1, salt]).slice(2)
  )
  const feeData = await ethers.provider.getFeeData()

  // send 100 mt to aa
  await mytoken.mintTo(sender, parseEther('100'))

  const transferData = mytoken.interface.encodeFunctionData('transfer', ['0x24f59a23d97C166A78E2483CE81CBC0C24839623', parseEther('20')])

  const hash_ = gnosisHash(sender, token, 0, transferData, 0, 0, 0, 0, ethers.ZeroAddress, ethers.ZeroAddress, 0)

  const signature = wallet.signingKey.sign(hash_).serialized

  const calldata = Account.interface.encodeFunctionData('execTransaction', [
    token,
    0,
    transferData,
    0,
    0,
    0,
    0,
    ethers.ZeroAddress,
    ethers.ZeroAddress,
    signature
  ])

  const op: UserOperationStruct = {
    sender: sender,
    nonce: await EntryPoint.getNonce(sender, 0),
    initCode: initCode,
    callData: calldata,
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
  console.log('userOpHash:', userOpHash)
  // op.signature = await wallet.signMessage(userOpHash)

  op.signature = wallet.signingKey.sign(hashMessage(userOpHash)).serialized
  console.log('userOperation sign: ', op.signature)

  // deposit token to aa
  await EntryPoint.depositTo(sender, { value: parseEther('0.05') })

  // handleOPs
  console.log(op)
  const tx = await EntryPoint.handleOps([op], beneficiary)
  console.log(tx.hash)

  const balance = await mytoken.balanceOf(sender)
  console.log(balance)
}

const MessagePrefix: string = '\x19Ethereum Signed Message:\n32'
export function hashMessage (message: string): string {
  return keccak256(concat([
    toUtf8Bytes(MessagePrefix),
    message
  ]))
}

function gnosisHash (
  gnosis: string,
  to: string,
  value: number,
  data: string,
  operation: number,
  safeTxGas: number,
  baseGas: number,
  gasPrice: number,
  gasToken: string,
  refundReceiver: string,
  nonce: number
): string {
  const txHash = keccak256(
    ethers.AbiCoder.defaultAbiCoder().encode(
      ['bytes32', 'address', 'uint256', 'bytes32', 'uint8', 'uint256', 'uint256', 'uint256', 'address', 'address', 'uint256'],
      ['0xbb8310d486368db6bd6f849402fdd73ad53d316b5a4b2644ad6efe0f941286d8', to, value, keccak256(data), operation, safeTxGas, baseGas, gasPrice, gasToken, refundReceiver, nonce]
    )
  )
  const domainSeparator = keccak256(
    ethers.AbiCoder.defaultAbiCoder().encode(
      ['bytes32', 'uint256', 'address'],
      ['0x47e79534a245952e8b16893a336b85a3d9ea9fa8c573f3d803afb92a79469218', network.config.chainId, gnosis]
    )
  )

  return keccak256(
    concat([
      '0x19',
      '0x01',
      domainSeparator,
      txHash
    ])
  )
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error)
  process.exitCode = 1
})
