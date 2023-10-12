// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "forge-std/Test.sol";
import "forge-std/console2.sol";
import "@openzeppelin/contracts-upgradeable/utils/cryptography/ECDSAUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import "contracts/mock/erc20.sol";

import "contracts/interfaces/UserOperation.sol";

import "contracts/interfaces/IEntryPoint.sol";
import "contracts/core/SenderCreator.sol";
import "contracts/core/EntryPoint.sol";

import "contracts/samples/SimpleAccount.sol";
import "contracts/samples/SimpleAccountFactory.sol";

import "contracts/samples/paymaster/SimpleTokenPaymaster.sol";

import "contracts/samples/paymaster/SubsidyPaymaster.sol";

import "@gnosis.pm/safe-contracts/contracts/common/Enum.sol";
import "contracts/samples/gnosis/EIP4337Manager.sol";
import "contracts/samples/gnosis/GnosisAccountFactory.sol";
import "@gnosis.pm/safe-contracts/contracts/GnosisSafe.sol";
import "@gnosis.pm/safe-contracts/contracts/GnosisSafeL2.sol";

contract Entrypoint is Test {
    bytes32 private constant DOMAIN_SEPARATOR_TYPEHASH =
        0x47e79534a245952e8b16893a336b85a3d9ea9fa8c573f3d803afb92a79469218;
    bytes32 private constant SAFE_TX_TYPEHASH =
        0xbb8310d486368db6bd6f849402fdd73ad53d316b5a4b2644ad6efe0f941286d8;
    using ECDSAUpgradeable for bytes32;

    MyToken mt;
    EntryPoint entrypoint;
    SimpleAccountFactory simpleAccountFactory;
    SimpleTokenPaymaster simpleTokenPaymaster;
    SubsidyPaymaster subsidyPaymaster;
    GnosisSafeAccountFactory gnosisSafeAccountFactory;

    uint256 publicKeyPrivateKey = 0xA0A;
    uint256 ownerPrivate = 0xB0B;
    uint256 adminPrivate = 0xC0C;
    uint256 bundlerPrivate = 0xD0D;
    uint256 userPrivate = 0xE0E;
    uint256 user1Private = 0xF0F;
    uint256 user2Private = 0xF1F;

    address publicKey = vm.addr(publicKeyPrivateKey);
    address owner = vm.addr(ownerPrivate);
    address admin = vm.addr(adminPrivate);
    address bundler = vm.addr(bundlerPrivate);
    address user = vm.addr(userPrivate);
    address user1 = vm.addr(user1Private);
    address user2 = vm.addr(user2Private);

    function setUp() public {
        mt = new MyToken("aaa", "a");

        // entrypoint
        SenderCreator senderCreator = new SenderCreator();
        entrypoint = new EntryPoint();
        entrypoint.initialize(senderCreator);

        // simple account factory
        SimpleAccount simpleAccount = new SimpleAccount(
            IEntryPoint(address(entrypoint))
        );
        simpleAccountFactory = new SimpleAccountFactory();
        simpleAccountFactory.initialize(simpleAccount);

        simpleTokenPaymaster = new SimpleTokenPaymaster();
        simpleTokenPaymaster.initialize(
            IEntryPoint(entrypoint),
            IERC20(mt),
            address(this),
            publicKey,
            0.1 ether
        );

        subsidyPaymaster = new SubsidyPaymaster();
        subsidyPaymaster.initialize(
            IEntryPoint(entrypoint),
            address(this),
            publicKey
        );

        GnosisSafeProxyFactory gnosisSafeProxyFactory = new GnosisSafeProxyFactory();
        GnosisSafeL2 gnosisSafeL2 = new GnosisSafeL2();
        EIP4337Manager eIP4337Manager = new EIP4337Manager(address(entrypoint));
        gnosisSafeAccountFactory = new GnosisSafeAccountFactory();
        gnosisSafeAccountFactory.initialize(
            gnosisSafeProxyFactory,
            address(gnosisSafeL2),
            eIP4337Manager
        );
        swithChain();
    }

    function swithChain() internal {
        if (block.chainid == 59144 || block.chainid == 8453) {
            entrypoint = EntryPoint(
                payable(0xd876ed6aAf728C927770E02672738364d759331f)
            );

            simpleAccountFactory = SimpleAccountFactory(
                0x4435aFc3474e62aB81811d5c19300788a969928b
            );

            simpleTokenPaymaster = SimpleTokenPaymaster(
                payable(0x6Bc8c816a2f85Ab9478Cb50e28756CCc1F20169a)
            );

            subsidyPaymaster = SubsidyPaymaster(
                payable(0xf648d0F7D9Ef86F5f1445fcA7EF746A14C719A4e)
            );

            gnosisSafeAccountFactory = GnosisSafeAccountFactory(
                0xd39CF75392AE743e8661b80f4d8675Ed90943E3f
            );

            //set publickey for simple token paymster
            vm.store(
                address(simpleTokenPaymaster),
                bytes32(uint256(102)),
                bytes32(uint256(uint160(address(publicKey))))
            );

            // set erc20 for simple token paymster
            vm.store(
                address(simpleTokenPaymaster),
                bytes32(uint256(104)),
                bytes32(uint256(uint160(address(mt))))
            );

            //set publickey for subsidy paymaster
            vm.store(
                address(subsidyPaymaster),
                bytes32(uint256(102)),
                bytes32(uint256(uint160(address(publicKey))))
            );
        }
    }

    function testTransferETH() public {
        UserOperation[] memory ops = new UserOperation[](2);

        address sender = simpleAccountFactory.getAddress(publicKey, 0);
        vm.deal(sender, 3 ether);

        ops[0] = UserOperation({
            sender: sender,
            nonce: 0,
            initCode: abi.encodePacked(
                address(simpleAccountFactory),
                abi.encodeWithSelector(
                    SimpleAccountFactory.createAccount.selector,
                    publicKey,
                    0
                )
            ),
            callData: abi.encodeWithSelector(
                SimpleAccount.execute.selector,
                user,
                1 ether,
                abi.encode("")
            ),
            callGasLimit: 50000,
            verificationGasLimit: 500000,
            preVerificationGas: 50000,
            maxFeePerGas: 0,
            maxPriorityFeePerGas: 0,
            paymasterAndData: abi.encodePacked(""),
            signature: abi.encodePacked("")
        });
        ops[0].signature = simpleAccountSignature(
            entrypoint.getUserOpHash(ops[0]),
            publicKeyPrivateKey
        );

        ops[1] = UserOperation({
            sender: sender,
            nonce: 1,
            initCode: abi.encodePacked(""),
            callData: abi.encodeWithSelector(
                SimpleAccount.execute.selector,
                user,
                1 ether,
                abi.encode("")
            ),
            callGasLimit: 50000,
            verificationGasLimit: 500000,
            preVerificationGas: 50000,
            maxFeePerGas: 0,
            maxPriorityFeePerGas: 0,
            paymasterAndData: abi.encodePacked(""),
            signature: abi.encodePacked("")
        });
        ops[1].signature = simpleAccountSignature(
            entrypoint.getUserOpHash(ops[1]),
            publicKeyPrivateKey
        );

        vm.prank(bundler);
        entrypoint.handleOps(ops, payable(bundler));

        assertEq(user.balance, 2 ether);
    }

    function testTransferErc20() public {
        UserOperation[] memory ops = new UserOperation[](2);

        address sender = simpleAccountFactory.getAddress(owner, 0);
        vm.deal(sender, 1 ether);

        mt.mintTo(sender, 2 ether);

        ops[0] = UserOperation({
            sender: sender,
            nonce: 0,
            initCode: abi.encodePacked(
                address(simpleAccountFactory),
                abi.encodeWithSelector(
                    SimpleAccountFactory.createAccount.selector,
                    owner,
                    0
                )
            ),
            callData: abi.encodeWithSelector(
                SimpleAccount.execute.selector,
                address(mt),
                0,
                abi.encodeWithSignature(
                    "transfer(address,uint256)",
                    user,
                    1 ether
                )
            ),
            callGasLimit: 50000,
            verificationGasLimit: 500000,
            preVerificationGas: 50000,
            maxFeePerGas: 0,
            maxPriorityFeePerGas: 0,
            paymasterAndData: abi.encodePacked(""),
            signature: abi.encodePacked("")
        });
        ops[0].signature = simpleAccountSignature(
            entrypoint.getUserOpHash(ops[0]),
            ownerPrivate
        );

        ops[1] = UserOperation({
            sender: sender,
            nonce: 1,
            initCode: abi.encodePacked(""),
            callData: abi.encodeWithSelector(
                SimpleAccount.execute.selector,
                address(mt),
                0,
                abi.encodeWithSignature(
                    "transfer(address,uint256)",
                    user,
                    1 ether
                )
            ),
            callGasLimit: 50000,
            verificationGasLimit: 500000,
            preVerificationGas: 50000,
            maxFeePerGas: 0,
            maxPriorityFeePerGas: 0,
            paymasterAndData: abi.encodePacked(""),
            signature: abi.encodePacked("")
        });
        ops[1].signature = simpleAccountSignature(
            entrypoint.getUserOpHash(ops[1]),
            ownerPrivate
        );

        vm.prank(bundler);
        entrypoint.handleOps(ops, payable(bundler));

        assertEq(mt.balanceOf(user), 2 ether);
        assertEq(mt.balanceOf(sender), 0);
    }

    function testTransferErc20TokenPaymaster() public {
        UserOperation[] memory ops = new UserOperation[](1);

        address sender = simpleAccountFactory.getAddress(user, 0);

        mt.mintTo(sender, 3 ether);
        entrypoint.depositTo{value: 1 ether}(address(simpleTokenPaymaster));

        // 1、approval
        ops[0] = UserOperation({
            sender: sender,
            nonce: 0,
            initCode: abi.encodePacked(
                address(simpleAccountFactory),
                abi.encodeWithSelector(
                    SimpleAccountFactory.createAccount.selector,
                    user,
                    0
                )
            ),
            callData: abi.encodeWithSelector(
                SimpleAccount.execute.selector,
                address(mt),
                0,
                abi.encodeWithSelector(
                    IERC20.approve.selector,
                    address(simpleTokenPaymaster),
                    1 ether
                )
            ),
            callGasLimit: 50000,
            verificationGasLimit: 500000,
            preVerificationGas: 50000,
            maxFeePerGas: 1,
            maxPriorityFeePerGas: 1,
            paymasterAndData: abi.encodePacked(
                address(simpleTokenPaymaster),
                abi.encode(
                    true,
                    0.01 ether,
                    block.timestamp + 1,
                    generateSig(
                        publicKeyPrivateKey,
                        sender,
                        0,
                        true,
                        0.01 ether,
                        block.timestamp + 1
                    )
                )
            ),
            signature: abi.encodePacked("")
        });
        ops[0].signature = simpleAccountSignature(
            entrypoint.getUserOpHash(ops[0]),
            userPrivate
        );

        vm.prank(bundler);
        entrypoint.handleOps(ops, payable(bundler));

        // 2 transfer
        ops[0] = UserOperation({
            sender: sender,
            nonce: 1,
            initCode: abi.encodePacked(""),
            callData: abi.encodeWithSelector(
                SimpleAccount.execute.selector,
                address(mt),
                0,
                abi.encodeWithSelector(IERC20.transfer.selector, user, 1 ether)
            ),
            callGasLimit: 50000,
            verificationGasLimit: 500000,
            preVerificationGas: 50000,
            maxFeePerGas: 1,
            maxPriorityFeePerGas: 1,
            paymasterAndData: abi.encodePacked(
                address(simpleTokenPaymaster),
                abi.encode(
                    false,
                    0.01 ether,
                    block.timestamp + 1,
                    generateSig(
                        publicKeyPrivateKey,
                        sender,
                        1,
                        false,
                        0.01 ether,
                        block.timestamp + 1
                    )
                )
            ),
            signature: abi.encodePacked("")
        });
        ops[0].signature = simpleAccountSignature(
            entrypoint.getUserOpHash(ops[0]),
            userPrivate
        );

        vm.prank(bundler);
        entrypoint.handleOps(ops, payable(bundler));

        assertEq(mt.balanceOf(user), 1 ether);

        // 3 transfer for subsidy
        subsidyPaymaster.depositTo{value: 1 ether}(sender);
        ops[0] = UserOperation({
            sender: sender,
            nonce: 2,
            initCode: abi.encodePacked(""),
            callData: abi.encodeWithSelector(
                SimpleAccount.execute.selector,
                address(mt),
                0,
                abi.encodeWithSelector(IERC20.transfer.selector, user, 1 ether)
            ),
            callGasLimit: 50000,
            verificationGasLimit: 500000,
            preVerificationGas: 50000,
            maxFeePerGas: 1,
            maxPriorityFeePerGas: 1,
            paymasterAndData: abi.encodePacked(""),
            signature: abi.encodePacked("")
        });
        ops[0].paymasterAndData = abi.encodePacked(
            address(subsidyPaymaster),
            abi.encode(
                5000,
                block.timestamp + 1,
                generateSubsidySig(
                    publicKeyPrivateKey,
                    ops[0],
                    5000,
                    block.timestamp + 1
                )
            )
        );
        ops[0].signature = simpleAccountSignature(
            entrypoint.getUserOpHash(ops[0]),
            userPrivate
        );

        vm.prank(bundler);
        entrypoint.handleOps(ops, payable(bundler));

        assertEq(mt.balanceOf(user), 2 ether);
    }

    function testTransferForGnosis() public {
        address[] memory owners = new address[](1);
        owners[0] = user2;
        address sender = gnosisSafeAccountFactory.getAddress(owners, 1, 0);
        vm.deal(sender, 1 ether);

        UserOperation[] memory ops = new UserOperation[](2);
        mt.mintTo(sender, 2 ether);

        bytes memory data = abi.encodeWithSelector(
            mt.transfer.selector,
            address(user),
            1 ether
        );

        bytes32 hash_ = getTransactionHash(
            sender,
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

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(user2Private, hash_);
        bytes memory signData_ = abi.encodePacked(r, s, v);

        bytes memory callData = abi.encodeWithSelector(
            GnosisSafe.execTransaction.selector,
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

        ops[0] = UserOperation({
            sender: sender,
            nonce: 0,
            initCode: abi.encodePacked(
                address(gnosisSafeAccountFactory),
                abi.encodeWithSelector(
                    gnosisSafeAccountFactory.createAccount.selector,
                    owners,
                    1,
                    0
                )
            ),
            callData: callData,
            callGasLimit: 500000,
            verificationGasLimit: 500000,
            preVerificationGas: 50000,
            maxFeePerGas: 0,
            maxPriorityFeePerGas: 0,
            paymasterAndData: abi.encodePacked(""),
            signature: abi.encodePacked("")
        });
        ops[0].signature = simpleAccountSignature(
            entrypoint.getUserOpHash(ops[0]),
            user2Private
        );

        // ops 1
        hash_ = getTransactionHash(
            sender,
            address(mt),
            0,
            data,
            Enum.Operation.Call,
            0,
            0,
            0,
            address(0),
            address(0),
            1
        );

        (v, r, s) = vm.sign(user2Private, hash_);
        signData_ = abi.encodePacked(r, s, v);

        callData = abi.encodeWithSelector(
            GnosisSafe.execTransaction.selector,
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

        ops[1] = UserOperation({
            sender: sender,
            nonce: 1,
            initCode: abi.encodePacked(""),
            callData: callData,
            callGasLimit: 50000,
            verificationGasLimit: 500000,
            preVerificationGas: 50000,
            maxFeePerGas: 0,
            maxPriorityFeePerGas: 0,
            paymasterAndData: abi.encodePacked(""),
            signature: abi.encodePacked("")
        });
        ops[1].signature = simpleAccountSignature(
            entrypoint.getUserOpHash(ops[1]),
            user2Private
        );

        vm.prank(bundler);
        // entrypoint.simulateHandleOp(ops[0], address(0), abi.encodePacked(""));
        entrypoint.handleOps(ops, payable(bundler));

        assertEq(mt.balanceOf(user), 2 ether);
    }

    function simpleAccountSignature(bytes32 userOpHash, uint256 signer)
        internal
        returns (bytes memory)
    {
        bytes32 hash = userOpHash.toEthSignedMessageHash();
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signer, hash);
        return abi.encodePacked(r, s, v);
    }

    function generateSig(
        uint256 signer,
        address sender,
        uint256 nonce,
        bool prepay,
        uint256 price,
        uint256 deadline
    ) internal returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            signer,
            keccak256(
                abi.encode(
                    sender,
                    nonce,
                    prepay,
                    price,
                    deadline,
                    block.chainid
                )
            )
        );
        return abi.encodePacked(r, s, bytes1(v - 27));
    }

    function generateSubsidySig(
        uint256 singer,
        UserOperation memory op,
        uint256 subsidy,
        uint256 deadline
    ) internal returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            singer,
            keccak256(
                abi.encode(
                    op.sender,
                    op.nonce,
                    op.callData,
                    subsidy,
                    deadline,
                    block.chainid
                )
            )
        );
        return abi.encodePacked(r, s, bytes1(v - 27));
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
