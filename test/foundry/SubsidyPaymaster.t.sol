// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "forge-std/Test.sol";
import "forge-std/console2.sol";

import "contracts/mock/erc20.sol";
import "contracts/samples/paymaster/SubsidyPaymaster.sol";
import "contracts/interfaces/IEntryPoint.sol";

contract SubsidyPaymasterTest is Test {
    MyToken mt;
    SubsidyPaymaster subsidyPaymaster;

    uint256 publicKeyPrivateKey = 0xA0A;
    uint256 ownerPrivate = 0xB0B;

    address publicKey = vm.addr(publicKeyPrivateKey);
    address owner = vm.addr(ownerPrivate);

    function setUp() public {
        mt = new MyToken("aaa", "a");

        subsidyPaymaster = new SubsidyPaymaster();
        subsidyPaymaster.initialize(
            IEntryPoint(address(this)),
            owner,
            publicKey
        );
        vm.warp(1670496243);
        vm.deal(address(subsidyPaymaster), 10 ether);
    }

    function testValidatePaymasterUserOp() public {
        uint256 subsidyPct_ = 5000;
        uint256 deadline_ = block.timestamp + 1;
        UserOperation memory op = UserOperation({
            sender: owner,
            nonce: 1,
            initCode: abi.encode(""),
            callData: abi.encode(""),
            callGasLimit: 100,
            verificationGasLimit: 100,
            preVerificationGas: 100,
            maxFeePerGas: 100,
            maxPriorityFeePerGas: 100,
            paymasterAndData: abi.encodePacked(address(subsidyPaymaster)),
            signature: abi.encode("")
        });

        vm.expectRevert("TPM: invalid data length");
        subsidyPaymaster.validatePaymasterUserOp(
            op,
            bytes32(uint256(0)),
            1200000 * 1 gwei
        );

        vm.expectRevert("TPM: Invlida Signature");
        op.paymasterAndData = abi.encodePacked(
            address(subsidyPaymaster),
            abi.encode(
                subsidyPct_,
                deadline_ + 1,
                generateSig(op, subsidyPct_, deadline_)
            )
        );
        subsidyPaymaster.validatePaymasterUserOp(
            op,
            bytes32(uint256(0)),
            1200000 * 1 gwei
        );

        vm.prank(publicKey);
        vm.expectRevert("Sender not EntryPoint");
        subsidyPaymaster.validatePaymasterUserOp(
            op,
            bytes32(uint256(0)),
            1200000 * 1 gwei
        );

        op.paymasterAndData = abi.encodePacked(
            address(subsidyPaymaster),
            abi.encode(
                subsidyPct_,
                deadline_,
                generateSig(op, subsidyPct_, deadline_)
            )
        );

        vm.expectRevert("TPM: Insufficient prepaid funds for sender");
        subsidyPaymaster.validatePaymasterUserOp(
            op,
            bytes32(uint256(0)),
            1200000 * 1 gwei
        );

        subsidyPaymaster.depositTo{value: 1 ether}(op.sender);
        subsidyPaymaster.validatePaymasterUserOp(
            op,
            bytes32(uint256(0)),
            1200000 * 1 gwei
        );

        require(
            subsidyPaymaster.balanceOf(op.sender) ==
                1 ether - (1200000 * 1 gwei)
        );
        op.paymasterAndData = abi.encodePacked(
            address(subsidyPaymaster),
            abi.encode(20000, deadline_, generateSig(op, 20000, deadline_))
        );
        vm.expectRevert("TPM: Invalid subsidyPCT");
        subsidyPaymaster.validatePaymasterUserOp(
            op,
            bytes32(uint256(0)),
            1200000 * 1 gwei
        );

        op.nonce = 2;
        op.paymasterAndData = abi.encodePacked(
            address(subsidyPaymaster),
            abi.encode(0, deadline_, generateSig(op, 0, deadline_))
        );
        subsidyPaymaster.validatePaymasterUserOp(
            op,
            bytes32(uint256(0)),
            1200000 * 1 gwei
        );
        require(
            subsidyPaymaster.balanceOf(op.sender) ==
                1 ether - (1200000 * 1 gwei * 2)
        );
    }

    function testPostOp() public {
        subsidyPaymaster.postOp(
            IPaymaster.PostOpMode.opSucceeded,
            abi.encode(10000, 1200000 * 1 gwei, owner),
            1200000 * 1 gwei
        );
        require(subsidyPaymaster.balanceOf(owner) == 1200000 * 1 gwei);

        subsidyPaymaster.postOp(
            IPaymaster.PostOpMode.opSucceeded,
            abi.encode(5000, 0, owner),
            2400000 * 1 gwei
        );
        require(subsidyPaymaster.balanceOf(owner) == 0);

        subsidyPaymaster.postOp(
            IPaymaster.PostOpMode.postOpReverted,
            abi.encode(5000, 0, owner),
            1200000 * 1 gwei
        );

        vm.expectRevert("TPM: Insufficient payment amount");
        subsidyPaymaster.postOp(
            IPaymaster.PostOpMode.opSucceeded,
            abi.encode(5000, 0, owner),
            1300000 * 1 gwei
        );
    }

    function generateSig(
        UserOperation memory op,
        uint256 subsidy,
        uint256 deadline
    ) internal returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            publicKeyPrivateKey,
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
}
