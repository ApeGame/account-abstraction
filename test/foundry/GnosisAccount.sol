// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "forge-std/Test.sol";
import "forge-std/console2.sol";

import "contracts/mock/erc20.sol";
import "@gnosis.pm/safe-contracts/contracts/common/Enum.sol";

import "contracts/samples/gnosis/EIP4337Fallback.sol";
import "contracts/samples/gnosis/EIP4337Manager.sol";
import "contracts/samples/gnosis/GnosisAccountFactory.sol";
import "@gnosis.pm/safe-contracts/contracts/GnosisSafe.sol";
import "@gnosis.pm/safe-contracts/contracts/GnosisSafeL2.sol";

contract GnosisAccount is Test {
    MyToken mt;
    GnosisSafeAccountFactory gnosisSafeAccountFactory;
    uint256 ownerPrivate = 0xB0B;
    address owner = vm.addr(ownerPrivate);

    function setUp() public {
        mt = new MyToken("aaa", "a");

        GnosisSafeProxyFactory gnosisSafeProxyFactory = new GnosisSafeProxyFactory();
        GnosisSafeL2 gnosisSafeL2 = new GnosisSafeL2();
        EIP4337Manager eIP4337Manager = new EIP4337Manager(owner);
        gnosisSafeAccountFactory = new GnosisSafeAccountFactory();
        gnosisSafeAccountFactory.initialize(
            gnosisSafeProxyFactory,
            address(gnosisSafeL2),
            eIP4337Manager
        );
    }

    function testCreateAddress() public returns (address) {
        address[] memory owners = new address[](1);
        owners[0] = owner;
        uint256 threshold = 1;
        uint256 salt = 1;

        address proxy = gnosisSafeAccountFactory.getAddress(
            owners,
            threshold,
            salt
        );

        address gnosisAccount = gnosisSafeAccountFactory.createAccount(
            owners,
            threshold,
            salt
        );

        require(proxy == gnosisAccount);

        uint8 accountType = EIP4337Fallback(gnosisAccount).getAccountType();
        require(accountType == 2);
        return proxy;
    }

    function testExecTransaction() public {
        address gnosisAccount = testCreateAddress();
        mt.mintTo(gnosisAccount, 100 ether);

        bytes memory data = abi.encodeWithSelector(
            mt.transfer.selector,
            address(1),
            2 ether
        );
        console.log(block.chainid);
        console.logAddress(address(mt));
        console.logBytes(data);
        console.logAddress(gnosisAccount);

        bytes32 hash_ = GnosisSafe(payable(gnosisAccount)).getTransactionHash(
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
        console.logBytes32(hash_);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivate, hash_);
        bytes memory signData_ = abi.encodePacked(r, s, v);

        vm.prank(owner);
        GnosisSafe(payable(gnosisAccount)).execTransaction(
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

        uint256 balance = mt.balanceOf(gnosisAccount);
        require(100 ether - balance == 2 ether);
    }
}
