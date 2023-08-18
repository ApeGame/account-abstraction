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

    event Deposited(address indexed account, uint256 totalDeposit);

    event Withdrawn(
        address indexed account,
        address withdrawAddress,
        uint256 amount
    );

    event UserOperationPayInfo(
        address indexed user,
        PostOpMode indexed mode,
        uint256 actualToken,
        uint256 price,
        uint256 actualGasCost
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
    {}

    /// @notice Performs post-operation tasks, such as updating the token price and refunding excess tokens.
    /// @dev This function is called after a user operation has been executed or reverted.
    /// @param _mode The post-operation mode (either successful or reverted).
    /// @param _context The context containing the token amount and user sender address.
    /// @param _actualGasCost The actual gas cost of the transaction.
    function _postOp(
        PostOpMode _mode,
        bytes calldata _context,
        uint256 _actualGasCost
    ) internal override {}

    function verifySig(
        UserOperation calldata userOp,
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
                        _price,
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
    // function depositTo(address _account) public payable {
    //     deposits[_account] += msg.value;
    //     emit Deposited(_account, msg.value);
    // }

    // function balanceOf(address _account) external view returns (uint256) {
    //     return deposits[_account];
    // }

    // /**
    //  * withdraw from the deposit.
    //  * @param _withdrawAddress the address to send withdrawn value.
    //  * @param _withdrawAmount the amount to withdraw.
    //  */
    // function withdrawTo(
    //     address payable _withdrawAddress,
    //     uint256 _withdrawAmount
    // ) external {
    //     uint256 balance_ = deposits[msg.sender];
    //     require(balance_ >= _withdrawAmount, "Withdraw amount too large");
    //     deposits[msg.sender] = balance_ - _withdrawAmount;
    //     emit Withdrawn(msg.sender, _withdrawAddress, _withdrawAmount);
    //     (bool success, ) = _withdrawAddress.call{value: _withdrawAmount}("");
    //     require(success, "failed to withdraw");
    // }

    receive() external payable {
        // depositTo(msg.sender);
    }
}
