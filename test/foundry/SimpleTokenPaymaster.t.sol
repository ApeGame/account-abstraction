// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "forge-std/Test.sol";
import "forge-std/console2.sol";

import "contracts/mock/erc20.sol";
import "contracts/samples/paymaster/SimpleTokenPaymaster.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "contracts/interfaces/IEntryPoint.sol";

contract SimpleTokenPaymasterTest is Test {
    MyToken mt;
    EntryPoint entrypoint;
    SimpleTokenPaymaster simpleTokenPaymaster;

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

        simpleTokenPaymaster = new SimpleTokenPaymaster();
        simpleTokenPaymaster.initialize(
            IEntryPoint(address(entrypoint)),
            IERC20(mt),
            owner,
            publicKey,
            0.01 ether
        );
        vm.warp(1670496243);

        mt.mintTo(owner, 100 ether);
        mt.mintTo(address(simpleTokenPaymaster), 100 ether);
    }

    function testValidatePaymasterUserOp() public {
        vm.prank(owner);
        mt.approve(address(simpleTokenPaymaster), 100 ether);

        address sender_ = owner;
        bool prepay_ = false;
        uint256 nonce_ = 1;
        uint256 price_ = 0.01 ether;
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
            paymasterAndData: abi.encodePacked(address(simpleTokenPaymaster)),
            signature: abi.encode("")
        });

        vm.startPrank(address(entrypoint));
        vm.expectRevert("TPM: invalid data length");
        simpleTokenPaymaster.validatePaymasterUserOp(
            op,
            bytes32(uint256(0)),
            1200000 * 1 gwei
        );

        vm.expectRevert("TPM: Invlida Signature");
        op.paymasterAndData = abi.encodePacked(
            address(simpleTokenPaymaster),
            abi.encode(
                prepay_,
                price_,
                deadline_ + 1,
                generateSig(sender_, nonce_, prepay_, price_, deadline_)
            )
        );
        simpleTokenPaymaster.validatePaymasterUserOp(
            op,
            bytes32(uint256(0)),
            1200000 * 1 gwei
        );
        vm.stopPrank();

        vm.prank(publicKey);
        vm.expectRevert("Sender not EntryPoint");
        simpleTokenPaymaster.validatePaymasterUserOp(
            op,
            bytes32(uint256(0)),
            1200000 * 1 gwei
        );

        vm.startPrank(address(entrypoint));
        op.paymasterAndData = abi.encodePacked(
            address(simpleTokenPaymaster),
            abi.encode(
                prepay_,
                price_,
                deadline_,
                generateSig(sender_, nonce_, prepay_, price_, deadline_)
            )
        );
        simpleTokenPaymaster.validatePaymasterUserOp(
            op,
            bytes32(uint256(0)),
            1200000 * 1 gwei
        );

        console.log(mt.balanceOf(op.sender));

        op.nonce = 2;
        op.paymasterAndData = abi.encodePacked(
            address(simpleTokenPaymaster),
            abi.encode(
                true,
                price_,
                deadline_,
                generateSig(op.sender, op.nonce, true, price_, deadline_)
            )
        );
        simpleTokenPaymaster.validatePaymasterUserOp(
            op,
            bytes32(uint256(0)),
            1200000 * 1 gwei
        );
        console.log(mt.balanceOf(op.sender));
        vm.stopPrank();
    }

    function testPostOp() public {
        uint256 price_ = 0.01 ether;

        vm.prank(address(entrypoint));
        simpleTokenPaymaster.postOp(
            IPaymaster.PostOpMode.opSucceeded,
            abi.encode(1 ether, false, price_, owner),
            0.1 ether
        );

        console.log(mt.balanceOf(owner));
        console.log(mt.balanceOf(address(simpleTokenPaymaster)));

        vm.prank(owner);
        mt.approve(address(simpleTokenPaymaster), 100 ether);

        vm.prank(address(entrypoint));
        simpleTokenPaymaster.postOp(
            IPaymaster.PostOpMode.opSucceeded,
            abi.encode(1 ether, true, price_, owner),
            0.1 ether
        );
    }

    function testTransfer() public {
        (bool success_, ) = address(simpleTokenPaymaster).call{value: 1 ether}(
            ""
        );
        require(success_);
        require(address(simpleTokenPaymaster).balance == 0 ether);
        require(address(entrypoint).balance == 1 ether);
        (uint112 balance, , , , ) = entrypoint.deposits(
            address(simpleTokenPaymaster)
        );
        require(balance == 1 ether);
    }

    function testCheckAdmin() public {
        vm.expectRevert("Admin: caller is not the admin");
        simpleTokenPaymaster.setPublicKey(publicKey);
        vm.prank(owner);
        simpleTokenPaymaster.setPublicKey(publicKey);

        vm.prank(admin);
        vm.expectRevert("Admin: caller is not the admin");
        simpleTokenPaymaster.setPublicKey(publicKey);

        vm.expectRevert("Ownable: caller is not the owner");
        simpleTokenPaymaster.setAdmin(admin, true);

        vm.prank(owner);
        simpleTokenPaymaster.setAdmin(admin, true);

        vm.prank(admin);
        simpleTokenPaymaster.setPublicKey(publicKey);

        vm.expectRevert("Admin: caller is not the admin");
        simpleTokenPaymaster.setFixedFee(1 ether);

        vm.expectRevert("Admin: caller is not the admin");
        simpleTokenPaymaster.setToken(IERC20(publicKey));

        vm.expectRevert("Admin: caller is not the admin");
        simpleTokenPaymaster.withdrawToken(publicKey, 1 ether);

        vm.startPrank(admin);
        simpleTokenPaymaster.setFixedFee(1 ether);
        simpleTokenPaymaster.withdrawToken(publicKey, 1 ether);
        simpleTokenPaymaster.setToken(IERC20(publicKey));
        require(simpleTokenPaymaster.fixedFee() == 1 ether);
        require(simpleTokenPaymaster.token() == IERC20(publicKey));
        require(mt.balanceOf(publicKey) == 1 ether);
        vm.stopPrank();
    }

    // function testVerify() public view {
    //     bytes32 hash_ = keccak256(
    //         abi.encode(
    //             0x460CD40b74a8d434EcA036742C3540C5FEd86e0A,
    //             3,
    //             10000000000000000,
    //             1691653020,
    //             31337
    //         )
    //     );

    //     console.log(
    //         ecrecover(
    //             hash_,
    //             uint8(28),
    //             bytes32(
    //                 0xd553749ccd2aa2b835f427a8652435c01254152d49130024110c2eee8a2467fe
    //             ),
    //             bytes32(
    //                 0x220785931684c75620314a174005ebe973871098a2370d6074781f001ef27760
    //             )
    //         )
    //     );
    // }

    function generateSig(
        address sender,
        uint256 nonce,
        bool prepay,
        uint256 price,
        uint256 deadline
    ) internal returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            publicKeyPrivateKey,
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
