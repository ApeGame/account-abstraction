// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

abstract contract Verify {
    address private publicKey;

    event SetPublicKey(address indexed pubkey);

    function _verify(bytes32 hashMessage, bytes memory _data)
        internal
        view
        returns (bool auth)
    {
        bytes32 r;
        bytes32 s;
        uint8 v;
        assembly {
            r := mload(add(_data, 0x20))
            s := mload(add(_data, 0x40))
            v := add(and(mload(add(_data, 0x41)), 0xff), 27)
        }

        address addr = ecrecover(hashMessage, v, r, s);
        if (publicKey == addr) {
            auth = true;
        }
        return auth;
    }

    function _setPublicKey(address _key) internal {
        publicKey = _key;
        emit SetPublicKey(_key);
    }

    function getPublicKey() public view returns (address) {
        return publicKey;
    }
}
