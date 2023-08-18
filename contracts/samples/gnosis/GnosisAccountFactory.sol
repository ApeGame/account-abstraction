// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.12;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/utils/Create2.sol";
import "@gnosis.pm/safe-contracts/contracts/proxies/GnosisSafeProxyFactory.sol";
import "./EIP4337Manager.sol";

/**
 * A wrapper factory contract to deploy GnosisSafe as an ERC-4337 account contract.
 */
contract GnosisSafeAccountFactory is Initializable {
    GnosisSafeProxyFactory public proxyFactory;
    address public safeSingleton;
    EIP4337Manager public eip4337Manager;

    function initialize(
        GnosisSafeProxyFactory _proxyFactory,
        address _safeSingleton,
        EIP4337Manager _eip4337Manager
    ) public initializer {
        proxyFactory = _proxyFactory;
        safeSingleton = _safeSingleton;
        eip4337Manager = _eip4337Manager;
    }

    function createAccount(
        address[] memory _owners,
        uint256 _threshold,
        uint256 _salt
    ) public returns (address) {
        address addr = getAddress(_owners, _threshold, _salt);
        uint codeSize = addr.code.length;
        if (codeSize > 0) {
            return addr;
        }
        return
            address(
                proxyFactory.createProxyWithNonce(
                    safeSingleton,
                    getInitializer(_owners, _threshold),
                    _salt
                )
            );
    }

    function getInitializer(address[] memory _owners, uint256 _threshold)
        internal
        view
        returns (bytes memory)
    {
        address eip4337fallback = eip4337Manager.eip4337Fallback();

        bytes memory setup4337Modules = abi.encodeCall(
            EIP4337Manager.setup4337Modules,
            (eip4337Manager)
        );

        return
            abi.encodeCall(
                GnosisSafe.setup,
                (
                    _owners,
                    _threshold,
                    address(eip4337Manager),
                    setup4337Modules,
                    eip4337fallback,
                    address(0),
                    0,
                    payable(0) //no payment receiver
                )
            );
    }

    /**
     * calculate the counterfactual address of this account as it would be returned by createAccount()
     * (uses the same "create2 signature" used by GnosisSafeProxyFactory.createProxyWithNonce)
     */
    function getAddress(
        address[] memory _owners,
        uint256 _threshold,
        uint256 _salt
    ) public view returns (address) {
        bytes memory initializer = getInitializer(_owners, _threshold);
        //copied from deployProxyWithNonce
        bytes32 salt2 = keccak256(
            abi.encodePacked(keccak256(initializer), _salt)
        );
        bytes memory deploymentData = abi.encodePacked(
            proxyFactory.proxyCreationCode(),
            uint256(uint160(safeSingleton))
        );
        return
            Create2.computeAddress(
                bytes32(salt2),
                keccak256(deploymentData),
                address(proxyFactory)
            );
    }
}
