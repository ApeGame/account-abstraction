// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "forge-std/Test.sol";
import "forge-std/console2.sol";

import "contracts/mock/erc20.sol";
import "contracts/samples/paymaster/SubsidyPaymaster.sol";
import "contracts/interfaces/IEntryPoint.sol";

contract SubsidyPaymasterTest is Test {
    MyToken mt;
    EntryPoint entrypoint;
    SubsidyPaymaster subsidyPaymaster;

    uint256 publicKeyPrivateKey = 0xA0A;
    uint256 ownerPrivate = 0xB0B;
    uint256 adminPrivate = 0xC0C;

    address publicKey = vm.addr(publicKeyPrivateKey);
    address owner = vm.addr(ownerPrivate);
    address admin = vm.addr(adminPrivate);

    function setUp() public {
        mt = new MyToken("aaa", "a");

        // deploy sender creator
        SenderCreator senderCreator = new SenderCreator();

        // deploy entrypoint
        entrypoint = new EntryPoint();
        entrypoint.initialize(senderCreator);

        subsidyPaymaster = new SubsidyPaymaster();
        subsidyPaymaster.initialize(IEntryPoint(entrypoint), owner, publicKey);
        vm.warp(1670496243);
        vm.deal(address(subsidyPaymaster), 10 ether);
        vm.deal(address(entrypoint), 10 ether);
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

        vm.startPrank(address(entrypoint));

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
        vm.stopPrank();

        vm.prank(publicKey);
        vm.expectRevert("Sender not EntryPoint");
        subsidyPaymaster.validatePaymasterUserOp(
            op,
            bytes32(uint256(0)),
            1200000 * 1 gwei
        );

        vm.startPrank(address(entrypoint));
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
        vm.stopPrank();
    }

    function testPostOp() public {
        vm.startPrank(address(entrypoint));
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
        vm.stopPrank();
    }

    function testWithdrawFromDeposit() public {
        (bool success_, ) = address(subsidyPaymaster).call{value: 1 ether}("");
        require(success_);
        require(address(subsidyPaymaster).balance == 10 ether);
        require(address(entrypoint).balance == 11 ether);
        console.log(address(subsidyPaymaster).balance);
        console.log(address(entrypoint).balance);
        require(subsidyPaymaster.balanceOf(address(this)) == 1 ether);

        subsidyPaymaster.withdrawFromDeposit(owner, 1 ether);
        require(address(entrypoint).balance == 10 ether);
        require(subsidyPaymaster.balanceOf(address(this)) == 0 ether);
    }

    function testCheckAdmin() public {
        vm.expectRevert("Admin: caller is not the admin");
        subsidyPaymaster.setPublicKey(publicKey);
        vm.prank(owner);
        subsidyPaymaster.setPublicKey(publicKey);

        vm.prank(admin);
        vm.expectRevert("Admin: caller is not the admin");
        subsidyPaymaster.setPublicKey(publicKey);

        vm.expectRevert("Ownable: caller is not the owner");
        subsidyPaymaster.setAdmin(admin, true);

        vm.prank(owner);
        subsidyPaymaster.setAdmin(admin, true);

        vm.prank(admin);
        subsidyPaymaster.setPublicKey(publicKey);
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
