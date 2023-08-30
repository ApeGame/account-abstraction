// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.12;

// Import the required libraries and contracts
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/cryptography/EIP712.sol";

import "contracts/core/EntryPoint.sol";
import "contracts/samples/paymaster/BasePaymaster.sol";
import "../utils/Verify.sol";

contract SimpleTokenPaymaster is BasePaymaster, Verify {
    event SetFee(uint256 indexed fee);
    event SetToken(address indexed token);
    event Received(address indexed sender, uint256 value);

    event PostOpReverted(address indexed user, uint256 preCharge);

    event UserOperationPayInfo(
        address indexed user,
        PostOpMode indexed mode,
        uint256 actualToken,
        uint256 price,
        uint256 actualGasCost
    );

    IERC20 public token;

    uint256 public fixedFee;

    function initialize(
        IEntryPoint _entryPoint,
        IERC20 _token,
        address _owner,
        address _pubkey,
        uint256 _fee
    ) external initializer {
        __paymaster_init(_entryPoint);
        token = _token;
        _setToken(_token);
        _transferOwnership(_owner);
        _setPublicKey(_pubkey);
        _setFixedFee(_fee);
    }

    function setPublicKey(address _pubkey) external onlyOwner {
        _setPublicKey(_pubkey);
    }

    function setFixedFee(uint256 _fee) external onlyOwner {
        _setFixedFee(_fee);
    }

    function _setFixedFee(uint256 _fee) internal {
        fixedFee = _fee;
        emit SetFee(_fee);
    }

    function setToken(IERC20 _token) external onlyOwner {
        _setToken(_token);
    }

    function _setToken(IERC20 _token) internal {
        token = _token;
        emit SetToken(address(_token));
    }

    /// @notice Allows the contract owner to withdraw a specified amount of tokens from the contract.
    /// @param _to The address to transfer the tokens to.
    /// @param _amount The amount of tokens to transfer.
    function withdrawToken(address _to, uint256 _amount) external onlyOwner {
        SafeERC20.safeTransfer(token, _to, _amount);
    }

    /// @notice Validates a paymaster user operation and calculates the required token amount for the transaction.
    /// @param _userOp The user operation data.
    /// @param _requiredPreFund The amount of tokens required for pre-funding.
    /// @return context The context containing the token amount and user sender address (if applicable).
    /// @return validationResult A uint256 value indicating the result of the validation (always 0 in this implementation).
    function _validatePaymasterUserOp(
        UserOperation calldata _userOp,
        bytes32,
        uint256 _requiredPreFund
    )
        internal
        override
        returns (bytes memory context, uint256 validationResult)
    {
        unchecked {
            uint256 paymasterAndDataLength_ = _userOp.paymasterAndData.length -
                20;
            require(paymasterAndDataLength_ != 0, "TPM: invalid data length");

            (
                bool prepay_,
                uint256 price_,
                uint256 deadline_,
                bytes memory data_
            ) = abi.decode(
                    _userOp.paymasterAndData[20:_userOp
                        .paymasterAndData
                        .length],
                    (bool, uint256, uint256, bytes)
                );

            require(
                verifySig(_userOp, prepay_, price_, deadline_, data_),
                "TPM: Invlida Signature"
            );

            uint256 tokenAmount = weiToToken(_requiredPreFund, price_) +
                fixedFee;
            if (prepay_) {
                require(
                    token.balanceOf(_userOp.sender) >= tokenAmount,
                    "TPM: Insufficient payable token for sender"
                );
            } else {
                SafeERC20.safeTransferFrom(
                    token,
                    _userOp.sender,
                    address(this),
                    tokenAmount
                );
            }

            context = abi.encode(tokenAmount, prepay_, price_, _userOp.sender);
            validationResult = _packValidationData(
                false,
                uint48(block.timestamp + 60),
                uint48(block.timestamp - 1)
            );
        }
    }

    /// @notice Performs post-operation tasks, such as updating the token price and refunding excess tokens.
    /// @dev This function is called after a user operation has been executed or reverted.
    /// @param _mode The post-operation mode (either successful or reverted).
    /// @param _context The context containing the token amount and user sender address.
    /// @param _actualGasCost The actual gas cost of the transaction.
    function _postOp(
        PostOpMode _mode,
        bytes calldata _context,
        uint256 _actualGasCost
    ) internal override {
        (
            uint256 preCharge_,
            bool prepay_,
            uint256 price_,
            address userOpSender_
        ) = abi.decode(_context, (uint256, bool, uint256, address));

        if (_mode == PostOpMode.postOpReverted) {
            emit PostOpReverted(userOpSender_, preCharge_);
            return;
        }
        uint256 actualTokenNeeded_ = weiToToken(_actualGasCost, price_) +
            fixedFee;

        unchecked {
            if (prepay_) {
                SafeERC20.safeTransferFrom(
                    token,
                    userOpSender_,
                    address(this),
                    actualTokenNeeded_
                );
            } else {
                if (actualTokenNeeded_ > preCharge_) {
                    SafeERC20.safeTransferFrom(
                        token,
                        userOpSender_,
                        address(this),
                        actualTokenNeeded_ - preCharge_
                    );
                } else {
                    SafeERC20.safeTransfer(
                        token,
                        userOpSender_,
                        preCharge_ - actualTokenNeeded_
                    );
                }
            }

            emit UserOperationPayInfo(
                userOpSender_,
                _mode,
                actualTokenNeeded_,
                price_,
                _actualGasCost
            );
        }
    }

    function verifySig(
        UserOperation calldata userOp,
        bool _prepay,
        uint256 _price,
        uint256 _deadline,
        bytes memory _data
    ) public view returns (bool) {
        require(block.timestamp <= _deadline, "TPM: Signature Expiration");

        return
            _verify(
                keccak256(
                    abi.encode(
                        userOp.sender,
                        userOp.nonce,
                        _prepay,
                        _price,
                        _deadline,
                        block.chainid
                    )
                ),
                _data
            );
    }

    /// @param _amount required prefund gas fee
    /// @param _price  _price = erc20 token(wei) / 1eth(wei)
    function weiToToken(uint256 _amount, uint256 _price)
        public
        pure
        returns (uint256)
    {
        return (_amount * _price) / 1 ether;
    }

    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    receive() external payable {
        emit Received(msg.sender, msg.value);
    }
}
