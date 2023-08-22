// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.12;

// Import the required libraries and contracts
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/cryptography/EIP712.sol";

import "contracts/core/EntryPoint.sol";
import "contracts/samples/paymaster/BasePaymaster.sol";
import "../utils/Verify.sol";

contract SubsidyPaymaster is BasePaymaster, Verify {
    /// maps paymaster to their deposits and stakes
    mapping(address => uint256) public deposits;

    event PostOpReverted(address indexed user, uint256 preCharge);

    event UserOperationPayInfo(
        address indexed user,
        PostOpMode indexed mode,
        uint256 actualGasCost,
        uint256 subsidy
    );

    event Deposited(address indexed account, uint256 totalDeposit);

    event Withdrawn(
        address indexed account,
        address withdrawAddress,
        uint256 amount
    );

    function initialize(
        IEntryPoint _entryPoint,
        address _owner,
        address _pubkey
    ) external initializer {
        __paymaster_init(_entryPoint);
        _transferOwnership(_owner);
        _setPublicKey(_pubkey);
    }

    function setPublicKey(address _pubkey) external onlyOwner {
        _setPublicKey(_pubkey);
    }

    /// @notice Validates a paymaster user operation and calculates the required token amount for the transaction.
    /// @param _userOp The user operation data.
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
            (uint256 subsidy_, uint256 deadline_, bytes memory data_) = abi
                .decode(
                    _userOp.paymasterAndData[20:_userOp
                        .paymasterAndData
                        .length],
                    (uint256, uint256, bytes)
                );
            require(
                verifySig(_userOp, subsidy_, deadline_, data_),
                "TPM: Invlida Signature"
            );
            uint256 prefund_;
            if (_requiredPreFund > subsidy_) {
                prefund_ = _requiredPreFund - subsidy_;
                require(
                    deposits[_userOp.sender] >= prefund_,
                    "TPM: Insufficient prepaid funds for sender"
                );
                deposits[_userOp.sender] -= prefund_;
            }

            context = abi.encode(subsidy_, prefund_, _userOp.sender);

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
        unchecked {
            (uint256 subsidy_, uint256 prefund_, address userOpSender_) = abi
                .decode(_context, (uint256, uint256, address));

            if (_mode == PostOpMode.postOpReverted) {
                emit PostOpReverted(userOpSender_, prefund_);
                return;
            }

            uint256 need_;
            if (_actualGasCost > subsidy_) {
                need_ = _actualGasCost - subsidy_;
            }

            uint256 balance_ = deposits[userOpSender_];
            if (prefund_ >= need_) {
                // refund
                deposits[userOpSender_] = balance_ + (prefund_ - need_);
            } else {
                if (balance_ >= (need_ - prefund_)) {
                    // supplement
                    deposits[userOpSender_] = balance_ - (need_ - prefund_);
                } else {
                    require(false, "TPM: Insufficient payment amount");
                }
            }

            emit UserOperationPayInfo(
                userOpSender_,
                _mode,
                _actualGasCost,
                subsidy_
            );
        }
    }

    function verifySig(
        UserOperation calldata userOp,
        uint256 _subsidy,
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
                        userOp.callData,
                        _subsidy,
                        _deadline,
                        block.chainid
                    )
                ),
                _data
            );
    }

    /**
     * add to the deposit of the given account
     */
    function depositTo(address _account) public payable {
        deposits[_account] += msg.value;
        emit Deposited(_account, msg.value);
    }

    function balanceOf(address _account) external view returns (uint256) {
        return deposits[_account];
    }

    /**
     * withdraw from the deposit.
     * @param _withdrawAddress the address to send withdrawn value.
     * @param _withdrawAmount the amount to withdraw.
     */
    function withdrawFromDeposit(
        address _withdrawAddress,
        uint256 _withdrawAmount
    ) external {
        uint256 balance_ = deposits[msg.sender];
        require(balance_ >= _withdrawAmount, "Withdraw amount too large");
        deposits[msg.sender] = balance_ - _withdrawAmount;
        emit Withdrawn(msg.sender, _withdrawAddress, _withdrawAmount);
        (bool success, ) = _withdrawAddress.call{value: _withdrawAmount}("");
        require(success, "Failed to withdraw");
    }

    receive() external payable {
        depositTo(msg.sender);
    }
}
