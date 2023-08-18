// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "forge-std/Test.sol";
import "forge-std/console2.sol";

import "contracts/mock/erc20.sol";
import "contracts/core/EntryPoint.sol";
import "contracts/core/SenderCreator.sol";
import "contracts/samples/SimpleAccountFactory.sol";
import "contracts/samples/paymaster/SimpleTokenPaymaster.sol";

contract SimpleTokenPaymasterEntrypointTest is Test {
    MyToken mt;
    EntryPoint entrypoint;
    SimpleAccountFactory accountFactory;
    SimpleTokenPaymaster simpleTokenPaymaster;

    uint256 publicKeyPrivateKey = 0xA0A;
    uint256 ownerPrivate = 0xB0B;
    uint256 otherPrivate = 0xC0C;
    uint256 beneficiaryPrivate = 0xD0D;
    uint256 salt = 1;

    address publicKey = vm.addr(publicKeyPrivateKey);
    address owner = vm.addr(ownerPrivate);
    address other = vm.addr(otherPrivate);
    address beneficiary = vm.addr(beneficiaryPrivate);

    function setUp() public {
        // deploy erc20
        mt = new MyToken("aaa", "a");

        // deploy sender creator
        SenderCreator senderCreator = new SenderCreator();

        // deploy entrypoint
        entrypoint = new EntryPoint();
        entrypoint.initialize(senderCreator);

        // deploy simple account
        SimpleAccount account = new SimpleAccount(entrypoint);

        // deploy simple account factory
        accountFactory = new SimpleAccountFactory();
        accountFactory.initialize(account);

        // deploy SimpleTokenPaymaster;
        simpleTokenPaymaster = new SimpleTokenPaymaster();
        simpleTokenPaymaster.initialize(
            entrypoint,
            IERC20(address(mt)),
            owner,
            publicKey,
            0.01 ether
        );

        mt.mintTo(address(simpleTokenPaymaster), 100 ether);

        entrypoint.depositTo{value: 10 ether}(address(simpleTokenPaymaster));
        vm.warp(1670496243);
    }

    function testHandleOpFirst() public {
        UserOperation memory op = createUserOp();

        bytes32 userOpHash = entrypoint.getUserOpHash(op);
        op.signature = signature(userOpHash);

        entrypoint.depositTo{value: 1 ether}(op.sender);
        UserOperation[] memory ops = new UserOperation[](1);
        ops[0] = op;

        mt.mintTo(op.sender, 100 ether);

        entrypoint.handleOps(ops, payable(beneficiary));

        console.log(mt.balanceOf(op.sender));
    }

    function testHandleOpSecond() public {
        testHandleOpFirst();

        UserOperation memory op = createUserOp();
        op.initCode = abi.encodePacked("");
        op.callData = abi.encodeWithSignature(
            "execute(address,uint256,bytes)",
            address(mt),
            0,
            abi.encodeWithSignature(
                "approve(address,uint256)",
                address(simpleTokenPaymaster),
                10000 ether
            )
        );

        bytes32 userOpHash = entrypoint.getUserOpHash(op);
        op.signature = signature(userOpHash);

        UserOperation[] memory ops = new UserOperation[](1);
        ops[0] = op;

        entrypoint.handleOps(ops, payable(beneficiary));
    }

    function testHandleOpthird() public {
        testHandleOpSecond();
        UserOperation memory op = createUserOp();

        uint256 price_ = 0.01 ether;
        uint256 deadline_ = block.timestamp + 1;
        op.initCode = abi.encodePacked("");
        op.paymasterAndData = abi.encodePacked(
            address(simpleTokenPaymaster),
            abi.encode(
                price_,
                deadline_,
                generateSig(op.sender, op.nonce, price_, deadline_)
            )
        );

        bytes32 userOpHash = entrypoint.getUserOpHash(op);
        op.signature = signature(userOpHash);

        UserOperation[] memory ops = new UserOperation[](1);
        ops[0] = op;

        entrypoint.handleOps(ops, payable(beneficiary));
    }

    function createUserOp() internal view returns (UserOperation memory) {
        bytes memory initCode_ = abi.encodePacked(
            address(accountFactory),
            abi.encodeWithSelector(
                SimpleAccountFactory.createAccount.selector,
                owner,
                salt
            )
        );
        address sender_ = accountFactory.getAddress(owner, salt);
        uint256 nonce_ = entrypoint.getNonce(sender_, 0);
        bytes memory callData_ = abi.encodeWithSelector(
            SimpleAccount.execute.selector,
            address(mt),
            0,
            abi.encodeWithSignature("transfer(address,uint256)", other, 1 ether)
        );

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

    function signature(bytes32 hash_) internal returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            ownerPrivate,
            ECDSAUpgradeable.toEthSignedMessageHash(hash_)
        );
        return abi.encodePacked(r, s, v);
    }

    function generateSig(
        address sender,
        uint256 nonce,
        uint256 price,
        uint256 deadline
    ) internal returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            publicKeyPrivateKey,
            keccak256(abi.encode(sender, nonce, price, deadline, block.chainid))
        );
        return abi.encodePacked(r, s, bytes1(v - 27));
    }
}
