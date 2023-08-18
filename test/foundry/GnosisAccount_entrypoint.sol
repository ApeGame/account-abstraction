// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "forge-std/Test.sol";
import "forge-std/console2.sol";

import "contracts/mock/erc20.sol";
import "contracts/core/EntryPoint.sol";
import "contracts/core/SenderCreator.sol";

import "@openzeppelin/contracts-upgradeable/utils/cryptography/ECDSAUpgradeable.sol";

import "@gnosis.pm/safe-contracts/contracts/common/Enum.sol";
import "contracts/samples/gnosis/EIP4337Fallback.sol";
import "contracts/samples/gnosis/EIP4337Manager.sol";
import "contracts/samples/gnosis/GnosisAccountFactory.sol";
import "@gnosis.pm/safe-contracts/contracts/GnosisSafe.sol";
import "@gnosis.pm/safe-contracts/contracts/GnosisSafeL2.sol";

contract GnosisAccountEntrypoint is Test {
    bytes32 private constant DOMAIN_SEPARATOR_TYPEHASH =
        0x47e79534a245952e8b16893a336b85a3d9ea9fa8c573f3d803afb92a79469218;
    bytes32 private constant SAFE_TX_TYPEHASH =
        0xbb8310d486368db6bd6f849402fdd73ad53d316b5a4b2644ad6efe0f941286d8;

    MyToken mt;
    EntryPoint entrypoint;
    GnosisSafeAccountFactory gnosisSafeAccountFactory;

    uint256 ownerPrivate = 0xB0B;
    address owner = vm.addr(ownerPrivate);

    uint256 beneficiaryPrivate = 0xD0D;
    address beneficiary = vm.addr(beneficiaryPrivate);

    function setUp() public {
        mt = new MyToken("aaa", "a");

        // deploy sender creator
        SenderCreator senderCreator = new SenderCreator();

        // deploy entrypoint
        entrypoint = new EntryPoint();
        entrypoint.initialize(senderCreator);

        GnosisSafeProxyFactory gnosisSafeProxyFactory = new GnosisSafeProxyFactory();
        GnosisSafeL2 gnosisSafeL2 = new GnosisSafeL2();
        EIP4337Manager eIP4337Manager = new EIP4337Manager(address(entrypoint));
        gnosisSafeAccountFactory = new GnosisSafeAccountFactory();
        gnosisSafeAccountFactory.initialize(
            gnosisSafeProxyFactory,
            address(gnosisSafeL2),
            eIP4337Manager
        );
    }

    function testExecTransaction() public {
        UserOperation memory op = createUserOp();

        mt.mintTo(op.sender, 100 ether);
        entrypoint.depositTo{value: 1 ether}(op.sender);

        bytes memory data = abi.encodeWithSelector(
            mt.transfer.selector,
            address(1),
            2 ether
        );

        bytes32 hash_ = getTransactionHash(
            op.sender,
            address(mt),
            0,
            data,
            Enum.Operation.Call,
            0,
            0,
            0,
            address(0),
            address(0),
            0
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivate, hash_);
        bytes memory signData_ = abi.encodePacked(r, s, v);

        op.callData = abi.encodeWithSelector(
            GnosisSafe(payable(op.sender)).execTransaction.selector,
            address(mt),
            0,
            data,
            Enum.Operation.Call,
            0,
            0,
            0,
            address(0),
            payable(0),
            signData_
        );

        bytes32 ophash_ = entrypoint.getUserOpHash(op);
        op.signature = signature(ophash_);

        UserOperation[] memory ops = new UserOperation[](1);
        ops[0] = op;

        entrypoint.handleOps(ops, payable(beneficiary));
    }

    function signature(bytes32 hash_) internal returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            ownerPrivate,
            ECDSAUpgradeable.toEthSignedMessageHash(hash_)
        );
        return abi.encodePacked(r, s, v);
    }

    function createUserOp() internal view returns (UserOperation memory) {
        address[] memory owners = new address[](1);
        owners[0] = owner;
        uint256 threshold = 1;
        uint256 salt = 1;

        bytes memory initCode_ = abi.encodePacked(
            address(gnosisSafeAccountFactory),
            abi.encodeWithSelector(
                GnosisSafeAccountFactory.createAccount.selector,
                owners,
                threshold,
                salt
            )
        );

        address sender_ = gnosisSafeAccountFactory.getAddress(
            owners,
            threshold,
            salt
        );
        uint256 nonce_ = entrypoint.getNonce(sender_, 0);

        bytes memory callData_ = abi.encode("");

        UserOperation memory op = UserOperation({
            sender: sender_,
            nonce: nonce_,
            initCode: initCode_,
            callData: callData_,
            callGasLimit: 1000000,
            verificationGasLimit: 1000000,
            preVerificationGas: 50000,
            maxFeePerGas: 100,
            maxPriorityFeePerGas: 100,
            paymasterAndData: abi.encodePacked(""),
            signature: abi.encodePacked("")
        });
        return op;
    }

    function getTransactionHash(
        address gnosis,
        address to,
        uint256 value,
        bytes memory data,
        Enum.Operation operation,
        uint256 safeTxGas,
        uint256 baseGas,
        uint256 gasPrice,
        address gasToken,
        address refundReceiver,
        uint256 _nonce
    ) internal view returns (bytes32) {
        bytes32 safeTxHash = keccak256(
            abi.encode(
                SAFE_TX_TYPEHASH,
                to,
                value,
                keccak256(data),
                operation,
                safeTxGas,
                baseGas,
                gasPrice,
                gasToken,
                refundReceiver,
                _nonce
            )
        );
        return
            keccak256(
                abi.encodePacked(
                    bytes1(0x19),
                    bytes1(0x01),
                    domainSeparator(gnosis),
                    safeTxHash
                )
            );
    }

    function domainSeparator(address gnosis) internal view returns (bytes32) {
        return
            keccak256(
                abi.encode(DOMAIN_SEPARATOR_TYPEHASH, block.chainid, gnosis)
            );
    }
}
