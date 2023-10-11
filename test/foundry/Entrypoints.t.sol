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

contract Entrypoint is Test {
    using ECDSAUpgradeable for bytes32;

    MyToken mt;
    EntryPoint entrypoint;
    SimpleAccountFactory simpleAccountFactory;
    SimpleTokenPaymaster simpleTokenPaymaster;

    uint256 publicKeyPrivateKey = 0xA0A;
    uint256 ownerPrivate = 0xB0B;
    uint256 adminPrivate = 0xC0C;
    uint256 bundlerPrivate = 0xD0D;
    uint256 userPrivate = 0xE0E;
    uint256 user1Private = 0xF0F;

    address publicKey = vm.addr(publicKeyPrivateKey);
    address owner = vm.addr(ownerPrivate);
    address admin = vm.addr(adminPrivate);
    address bundler = vm.addr(bundlerPrivate);
    address user = vm.addr(userPrivate);
    address user1 = vm.addr(user1Private);

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

        mt.mintTo(sender, 2 ether);
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
}
