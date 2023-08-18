/**
 ** Account-Abstraction (EIP-4337) singleton EntryPoint implementation.
 ** Only one instance required on each chain.
 **/
// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.12;

/* solhint-disable avoid-low-level-calls */
/* solhint-disable no-inline-assembly */

import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

import "../interfaces/IAccount.sol";
import "../interfaces/IPaymaster.sol";
import "../interfaces/IEntryPoint.sol";

import "../utils/Exec.sol";
import "./StakeManager.sol";
import "./SenderCreator.sol";
import "./Helpers.sol";
import "./NonceManager.sol";

contract EntryPoint is
    IEntryPoint,
    StakeManager,
    NonceManager,
    ReentrancyGuardUpgradeable
{
    using UserOperationLib for UserOperation;

    SenderCreator private senderCreator;

    // internal value used during simulation: need to query aggregator.
    address private constant SIMULATE_FIND_AGGREGATOR = address(1);

    // marker for inner call revert on out of gas
    bytes32 private constant INNER_OUT_OF_GAS = hex"deaddead";

    uint256 private constant REVERT_REASON_MAX_LEN = 2048;

    /**
     * for simulation purposes, validateUserOp (and validatePaymasterUserOp) must return this value
     * in case of signature failure, instead of revert.
     */
    uint256 public constant SIG_VALIDATION_FAILED = 1;

    function initialize(SenderCreator _senderCreator) external initializer {
        __ReentrancyGuard_init();
        senderCreator = _senderCreator;
    }

    /**
     * compensate the caller's beneficiary address with the collected fees of all UserOperations.
     * 执行 userOperations 时 收取的手续费
     * @param beneficiary the address to receive the fees
     * @param amount amount to transfer.
     */
    function _compensate(address payable beneficiary, uint256 amount) internal {
        require(beneficiary != address(0), "AA90 invalid beneficiary");
        (bool success, ) = beneficiary.call{value: amount}("");
        require(success, "AA91 failed send to beneficiary");
    }

    /**
     * execute a user op
     * 执行一个 userOp, 验证完 userOperation 之后 会执行. 返回
     * @param opIndex index into the opInfo array
     * @param userOp the userOp to execute
     * @param opInfo the opInfo filled by validatePrepayment for this userOp.
     * @return collected the total amount this userOp paid.
     */
    function _executeUserOp(
        uint256 opIndex,
        UserOperation calldata userOp,
        UserOpInfo memory opInfo
    ) private returns (uint256 collected) {
        uint256 preGas = gasleft();
        // offset(uint256) => bytes
        bytes memory context = getMemoryBytesFromOffset(opInfo.contextOffset);

        try this.innerHandleOp(userOp.callData, opInfo, context) returns (
            uint256 _actualGasCost
        ) {
            collected = _actualGasCost;
        } catch {
            bytes32 innerRevertCode;
            assembly {
                returndatacopy(0, 0, 32)
                innerRevertCode := mload(0)
            }
            // handleOps was called with gas limit too low. abort entire bundle.
            if (innerRevertCode == INNER_OUT_OF_GAS) {
                //report paymaster, since if it is not deliberately caused by the bundler,
                // it must be a revert caused by paymaster.
                revert FailedOp(opIndex, "AA95 out of gas");
            }
            // 如果innerHandleOp (calldata)调用失败了, 还是要 调用的postOP, 和退钱操作
            uint256 actualGas = preGas - gasleft() + opInfo.preOpGas;
            // collected 是 执行 useroperation 中 (validata  & calldata ) 的gas * gasprice 的花费
            collected = _handlePostOp(
                opIndex,
                IPaymaster.PostOpMode.postOpReverted,
                opInfo,
                context,
                actualGas
            );
        }
    }

    /**
     * Execute a batch of UserOperations.
     * no signature aggregator is used.
     * if any account requires an aggregator (that is, it returned an aggregator when
     * performing simulateValidation), then handleAggregatedOps() must be used instead.
     * 执行一批 userOperation
     * @param ops the operations to execute
     * @param beneficiary the address to receive the fees; 手续手续费的地址
     */
    function handleOps(
        UserOperation[] calldata ops,
        address payable beneficiary
    ) public nonReentrant {
        uint256 opslen = ops.length;
        UserOpInfo[] memory opInfos = new UserOpInfo[](opslen);

        unchecked {
            for (uint256 i = 0; i < opslen; i++) {
                UserOpInfo memory opInfo = opInfos[i];
                // userOperation 中有一个 paymasterAndData 字段, 前 20 byte 为paymaster 地址
                // 验证  userOperation & paymaster; 同时已经扣除了 手续费 (account & paymaster 似乎都要扣除 执行的手续费)
                (
                    uint256 validationData,
                    uint256 pmValidationData
                ) = _validatePrepayment(i, ops[i], opInfo);
                // 解析并验证 account 和paymaster 的validataData(这部分是不收取任何手续费的)
                _validateAccountAndPaymasterValidationData(
                    i,
                    validationData,
                    pmValidationData,
                    address(0)
                );
            }

            uint256 collected = 0;
            emit BeforeExecution();

            for (uint256 i = 0; i < opslen; i++) {
                // 执行 userOperation calldata.
                collected += _executeUserOp(i, ops[i], opInfos[i]);
            }

            // 转给 beneficiary 的collected
            _compensate(beneficiary, collected);
        } //unchecked
    }

    /**
     * Execute a batch of UserOperation with Aggregators
     * @param opsPerAggregator the operations to execute, grouped by aggregator (or address(0) for no-aggregator accounts)
     * @param beneficiary the address to receive the fees
     */
    function handleAggregatedOps(
        UserOpsPerAggregator[] calldata opsPerAggregator,
        address payable beneficiary
    ) public nonReentrant {
        uint256 opasLen = opsPerAggregator.length;
        uint256 totalOps = 0;
        // 先进行 聚合签名 验证
        for (uint256 i = 0; i < opasLen; i++) {
            UserOpsPerAggregator calldata opa = opsPerAggregator[i];
            UserOperation[] calldata ops = opa.userOps;
            IAggregator aggregator = opa.aggregator;

            //address(1) is special marker of "signature error"
            require(
                address(aggregator) != address(1),
                "AA96 invalid aggregator"
            );

            if (address(aggregator) != address(0)) {
                // solhint-disable-next-line no-empty-blocks
                // 使用聚合签名器 验证 UserOpsPerAggregator.userOps & signature
                try aggregator.validateSignatures(ops, opa.signature) {} catch {
                    revert SignatureValidationFailed(address(aggregator));
                }
            }

            totalOps += ops.length;
        }

        UserOpInfo[] memory opInfos = new UserOpInfo[](totalOps);

        emit BeforeExecution();

        // userOperation 验证
        uint256 opIndex = 0;
        for (uint256 a = 0; a < opasLen; a++) {
            UserOpsPerAggregator calldata opa = opsPerAggregator[a];
            UserOperation[] calldata ops = opa.userOps;
            IAggregator aggregator = opa.aggregator;

            uint256 opslen = ops.length;
            for (uint256 i = 0; i < opslen; i++) {
                UserOpInfo memory opInfo = opInfos[opIndex];
                (
                    uint256 validationData,
                    uint256 paymasterValidationData
                ) = _validatePrepayment(opIndex, ops[i], opInfo);
                _validateAccountAndPaymasterValidationData(
                    i,
                    validationData,
                    paymasterValidationData,
                    address(aggregator)
                );
                opIndex++;
            }
        }

        // 执行 calldata ,退款流程
        uint256 collected = 0;
        opIndex = 0;
        for (uint256 a = 0; a < opasLen; a++) {
            UserOpsPerAggregator calldata opa = opsPerAggregator[a];
            emit SignatureAggregatorChanged(address(opa.aggregator));
            UserOperation[] calldata ops = opa.userOps;
            uint256 opslen = ops.length;

            for (uint256 i = 0; i < opslen; i++) {
                collected += _executeUserOp(opIndex, ops[i], opInfos[opIndex]);
                opIndex++;
            }
        }
        emit SignatureAggregatorChanged(address(0));

        // 提取收益
        _compensate(beneficiary, collected);
    }

    /// @inheritdoc IEntryPoint
    function simulateHandleOp(
        UserOperation calldata op,
        address target,
        bytes calldata targetCallData
    ) external override {
        UserOpInfo memory opInfo;
        // 检查 initcode 和 paymaster
        _simulationOnlyValidations(op);
        (
            uint256 validationData,
            uint256 paymasterValidationData
        ) = _validatePrepayment(0, op, opInfo);
        ValidationData memory data = _intersectTimeRange(
            validationData,
            paymasterValidationData
        );

        numberMarker();
        uint256 paid = _executeUserOp(0, op, opInfo);
        numberMarker();
        bool targetSuccess;
        bytes memory targetResult;
        if (target != address(0)) {
            (targetSuccess, targetResult) = target.call(targetCallData);
        }
        revert ExecutionResult(
            opInfo.preOpGas,
            paid,
            data.validAfter,
            data.validUntil,
            targetSuccess,
            targetResult
        );
    }

    // A memory copy of UserOp static fields only.
    // Excluding: callData, initCode and signature. Replacing paymasterAndData with paymaster.
    struct MemoryUserOp {
        address sender;
        uint256 nonce;
        uint256 callGasLimit;
        uint256 verificationGasLimit;
        uint256 preVerificationGas;
        address paymaster;
        uint256 maxFeePerGas;
        uint256 maxPriorityFeePerGas;
    }

    struct UserOpInfo {
        MemoryUserOp mUserOp;
        bytes32 userOpHash;
        uint256 prefund;
        uint256 contextOffset;
        uint256 preOpGas;
    }

    /**
     * inner function to handle a UserOperation.
     * Must be declared "external" to open a call context, but it can only be called by handleOps.
     * 执行 用户的callData,
     */
    function innerHandleOp(
        bytes memory callData,
        UserOpInfo memory opInfo,
        bytes calldata context
    ) external returns (uint256 actualGasCost) {
        uint256 preGas = gasleft();
        require(msg.sender == address(this), "AA92 internal call only");
        MemoryUserOp memory mUserOp = opInfo.mUserOp;

        uint callGasLimit = mUserOp.callGasLimit;
        unchecked {
            // handleOps was called with gas limit too low. abort entire bundle.
            if (
                gasleft() < callGasLimit + mUserOp.verificationGasLimit + 5000
            ) {
                assembly {
                    mstore(0, INNER_OUT_OF_GAS)
                    revert(0, 32)
                }
            }
        }

        IPaymaster.PostOpMode mode = IPaymaster.PostOpMode.opSucceeded;
        if (callData.length > 0) {
            // 调用 账户合约
            bool success = Exec.call(mUserOp.sender, 0, callData, callGasLimit);
            if (!success) {
                // 获取失败的return data.
                bytes memory result = Exec.getReturnData(REVERT_REASON_MAX_LEN);
                if (result.length > 0) {
                    emit UserOperationRevertReason(
                        opInfo.userOpHash,
                        mUserOp.sender,
                        mUserOp.nonce,
                        result
                    );
                }
                mode = IPaymaster.PostOpMode.opReverted;
            }
        }

        unchecked {
            uint256 actualGas = preGas - gasleft() + opInfo.preOpGas;
            //note: opIndex is ignored (relevant only if mode==postOpReverted, which is only possible outside of innerHandleOp)
            // 不论 调用成功失败, paymaster(有的情况下) 都要调用 postOp,
            return _handlePostOp(0, mode, opInfo, context, actualGas);
        }
    }

    /**
     * generate a request Id - unique identifier for this request.
     * the request ID is a hash over the content of the userOp (except the signature), the entrypoint and the chainid.
     */
    function getUserOpHash(UserOperation calldata userOp)
        public
        view
        returns (bytes32)
    {
        // userOpHash : hash(userOp) + addresss(this) + chainid
        return
            keccak256(abi.encode(userOp.hash(), address(this), block.chainid));
    }

    /**
     * copy general fields from userOp into the memory opInfo structure.
     */
    function _copyUserOpToMemory(
        UserOperation calldata userOp,
        MemoryUserOp memory mUserOp
    ) internal pure {
        mUserOp.sender = userOp.sender;
        mUserOp.nonce = userOp.nonce;
        mUserOp.callGasLimit = userOp.callGasLimit;
        mUserOp.verificationGasLimit = userOp.verificationGasLimit;
        mUserOp.preVerificationGas = userOp.preVerificationGas;
        mUserOp.maxFeePerGas = userOp.maxFeePerGas;
        mUserOp.maxPriorityFeePerGas = userOp.maxPriorityFeePerGas;
        bytes calldata paymasterAndData = userOp.paymasterAndData;
        if (paymasterAndData.length > 0) {
            require(
                paymasterAndData.length >= 20,
                "AA93 invalid paymasterAndData"
            );
            mUserOp.paymaster = address(bytes20(paymasterAndData[:20]));
        } else {
            mUserOp.paymaster = address(0);
        }
    }

    /**
     * Simulate a call to account.validateUserOp and paymaster.validatePaymasterUserOp.
     * @dev this method always revert. Successful result is ValidationResult error. other errors are failures.
     * @dev The node must also verify it doesn't use banned opcodes, and that it doesn't reference storage outside the account's data.
     * @param userOp the user operation to validate.
     */
    function simulateValidation(UserOperation calldata userOp) external {
        UserOpInfo memory outOpInfo;

        _simulationOnlyValidations(userOp);
        (
            uint256 validationData,
            uint256 paymasterValidationData
        ) = _validatePrepayment(0, userOp, outOpInfo);
        StakeInfo memory paymasterInfo = _getStakeInfo(
            outOpInfo.mUserOp.paymaster
        );
        StakeInfo memory senderInfo = _getStakeInfo(outOpInfo.mUserOp.sender);
        StakeInfo memory factoryInfo;
        {
            bytes calldata initCode = userOp.initCode;
            address factory = initCode.length >= 20
                ? address(bytes20(initCode[0:20]))
                : address(0);
            factoryInfo = _getStakeInfo(factory);
        }

        ValidationData memory data = _intersectTimeRange(
            validationData,
            paymasterValidationData
        );
        address aggregator = data.aggregator;
        bool sigFailed = aggregator == address(1);
        ReturnInfo memory returnInfo = ReturnInfo(
            outOpInfo.preOpGas,
            outOpInfo.prefund,
            sigFailed,
            data.validAfter,
            data.validUntil,
            getMemoryBytesFromOffset(outOpInfo.contextOffset)
        );

        if (aggregator != address(0) && aggregator != address(1)) {
            AggregatorStakeInfo memory aggregatorInfo = AggregatorStakeInfo(
                aggregator,
                _getStakeInfo(aggregator)
            );
            revert ValidationResultWithAggregation(
                returnInfo,
                senderInfo,
                factoryInfo,
                paymasterInfo,
                aggregatorInfo
            );
        }
        revert ValidationResult(
            returnInfo,
            senderInfo,
            factoryInfo,
            paymasterInfo
        );
    }

    // ( call gaslimit + verifucation gas limit * mul + preVerificationGas ) * maxFeePerGas
    //
    function _getRequiredPrefund(MemoryUserOp memory mUserOp)
        internal
        pure
        returns (uint256 requiredPrefund)
    {
        unchecked {
            //when using a Paymaster, the verificationGasLimit is used also to as a limit for the postOp call.
            // our security model might call postOp eventually twice
            uint256 mul = mUserOp.paymaster != address(0) ? 3 : 1;
            uint256 requiredGas = mUserOp.callGasLimit +
                mUserOp.verificationGasLimit *
                mul +
                mUserOp.preVerificationGas;

            requiredPrefund = requiredGas * mUserOp.maxFeePerGas;
        }
    }

    // create the sender's contract if needed.
    // 创建 合约, erc4337 账号,
    function _createSenderIfNeeded(
        uint256 opIndex,
        UserOpInfo memory opInfo,
        bytes calldata initCode
    ) internal {
        if (initCode.length != 0) {
            address sender = opInfo.mUserOp.sender;
            if (sender.code.length != 0)
                revert FailedOp(opIndex, "AA10 sender already constructed");
            // 创建 用户合约.
            address sender1 = senderCreator.createSender{
                gas: opInfo.mUserOp.verificationGasLimit
            }(initCode);
            if (sender1 == address(0))
                revert FailedOp(opIndex, "AA13 initCode failed or OOG");
            if (sender1 != sender)
                revert FailedOp(opIndex, "AA14 initCode must return sender");
            if (sender1.code.length == 0)
                revert FailedOp(opIndex, "AA15 initCode must create sender");
            address factory = address(bytes20(initCode[0:20]));
            emit AccountDeployed(
                opInfo.userOpHash,
                sender,
                factory,
                opInfo.mUserOp.paymaster
            );
        }
    }

    /**
     * Get counterfactual sender address.
     *  Calculate the sender contract address that will be generated by the initCode and salt in the UserOperation.
     * this method always revert, and returns the address in SenderAddressResult error
     * @param initCode the constructor code to be passed into the UserOperation.
     */
    function getSenderAddress(bytes calldata initCode) public {
        address sender = senderCreator.createSender(initCode);
        revert SenderAddressResult(sender);
    }

    function _simulationOnlyValidations(UserOperation calldata userOp)
        internal
        view
    {
        // solhint-disable-next-line no-empty-blocks
        try
            this._validateSenderAndPaymaster(
                userOp.initCode,
                userOp.sender,
                userOp.paymasterAndData
            )
        {} catch Error(string memory revertReason) {
            // 当 err 的结不为空时 revert
            if (bytes(revertReason).length != 0) {
                revert FailedOp(0, revertReason);
            }
        }
    }

    /**
     * Called only during simulation.
     * This function always reverts to prevent warm/cold storage differentiation in simulation vs execution.
     */
    function _validateSenderAndPaymaster(
        bytes calldata initCode,
        address sender,
        bytes calldata paymasterAndData
    ) external view {
        if (initCode.length == 0 && sender.code.length == 0) {
            // iniCode 为0 , 还不创建 aa 账号的下场
            // it would revert anyway. but give a meaningful message
            revert("AA20 account not deployed");
        }
        if (paymasterAndData.length >= 20) {
            address paymaster = address(bytes20(paymasterAndData[0:20]));
            if (paymaster.code.length == 0) {
                // 只取到了 paymaster 了, 但没有calldata 的数据,就会报错
                // it would revert anyway. but give a meaningful message
                revert("AA30 paymaster not deployed");
            }
        }
        // always revert
        revert("");
    }

    /**
     * call account.validateUserOp.
     * revert (with FailedOp) in case validateUserOp reverts, or account didn't send required prefund.
     * decrement account's deposit if needed
     * 验证用户交易(userOperation), 并扣除 必要的手续费后, 返回 花费的验证过程花费的gas 和 验证的 结果
     */
    function _validateAccountPrepayment(
        uint256 opIndex,
        UserOperation calldata op,
        UserOpInfo memory opInfo,
        uint256 requiredPrefund
    )
        internal
        returns (
            uint256 gasUsedByValidateAccountPrepayment,
            uint256 validationData
        )
    {
        unchecked {
            uint256 preGas = gasleft();
            MemoryUserOp memory mUserOp = opInfo.mUserOp;
            address sender = mUserOp.sender;
            // 创建 合约
            _createSenderIfNeeded(opIndex, opInfo, op.initCode);
            address paymaster = mUserOp.paymaster;
            // 创建合约 后, 0~32 地址会被使用, 重新建 内存0地址 设置为 block number
            numberMarker();
            uint256 missingAccountFunds = 0;
            if (paymaster == address(0)) {
                // 如果 payMaster 没有时, 则需要自己的账户 付款. 需要先扣除 手续费
                uint256 bal = balanceOf(sender); // stake manager 自己的账户中查找

                // missingAccountFunds. 存在entrypoint 中的钱 足够支付时, 则missingAccountFunds 为0, 则不需在用 account 来支付, 不足时,需要account 支付 剩余款
                missingAccountFunds = bal > requiredPrefund
                    ? 0
                    : requiredPrefund - bal;
            }
            // 验证userOperation交易
            try
                IAccount(sender).validateUserOp{
                    gas: mUserOp.verificationGasLimit
                }(op, opInfo.userOpHash, missingAccountFunds)
            returns (uint256 _validationData) {
                validationData = _validationData;
            } catch Error(string memory revertReason) {
                revert FailedOp(
                    opIndex,
                    string.concat("AA23 reverted: ", revertReason)
                );
            } catch {
                revert FailedOp(opIndex, "AA23 reverted (or OOG)");
            }
            if (paymaster == address(0)) {
                // 扣除 手续费用
                DepositInfo storage senderInfo = deposits[sender];
                uint256 deposit = senderInfo.deposit;
                if (requiredPrefund > deposit) {
                    revert FailedOp(opIndex, "AA21 didn't pay prefund");
                }
                senderInfo.deposit = uint112(deposit - requiredPrefund);
            }
            // 验证用户交易(useroperation) 花费的gas
            gasUsedByValidateAccountPrepayment = preGas - gasleft();
        }
    }

    /**
     * In case the request has a paymaster:
     * Validate paymaster has enough deposit.
     * Call paymaster.validatePaymasterUserOp.
     * Revert with proper FailedOp in case paymaster reverts.
     * Decrement paymaster's deposit
     *
     * 使用剩余的 gas 验证 paymaster, 返回  context, 和 validation data
     */
    function _validatePaymasterPrepayment(
        uint256 opIndex,
        UserOperation calldata op,
        UserOpInfo memory opInfo,
        uint256 requiredPreFund,
        uint256 gasUsedByValidateAccountPrepayment
    ) internal returns (bytes memory context, uint256 validationData) {
        unchecked {
            MemoryUserOp memory mUserOp = opInfo.mUserOp;
            uint256 verificationGasLimit = mUserOp.verificationGasLimit;
            require(
                verificationGasLimit > gasUsedByValidateAccountPrepayment,
                "AA41 too little verificationGas"
            );
            uint256 gas = verificationGasLimit -
                gasUsedByValidateAccountPrepayment;

            address paymaster = mUserOp.paymaster;
            DepositInfo storage paymasterInfo = deposits[paymaster];
            uint256 deposit = paymasterInfo.deposit;
            if (deposit < requiredPreFund) {
                revert FailedOp(opIndex, "AA31 paymaster deposit too low");
            }
            // paymaster deposi 也要扣除 手续费
            paymasterInfo.deposit = uint112(deposit - requiredPreFund);
            // 使用 剩余 的 gas(verificationGasLimit- gasUsedByValidateAccountPrepayment) validata paymaster
            try
                IPaymaster(paymaster).validatePaymasterUserOp{gas: gas}(
                    op,
                    opInfo.userOpHash,
                    requiredPreFund
                )
            returns (bytes memory _context, uint256 _validationData) {
                context = _context;
                validationData = _validationData;
            } catch Error(string memory revertReason) {
                revert FailedOp(
                    opIndex,
                    string.concat("AA33 reverted: ", revertReason)
                );
            } catch {
                revert FailedOp(opIndex, "AA33 reverted (or OOG)");
            }
        }
    }

    /**
     * revert if either account validationData or paymaster validationData is expired
     */
    function _validateAccountAndPaymasterValidationData(
        uint256 opIndex,
        uint256 validationData,
        uint256 paymasterValidationData,
        address expectedAggregator
    ) internal view {
        // 解析并验证 account 的userOperation
        (address aggregator, bool outOfTimeRange) = _getValidationData(
            validationData
        );
        if (expectedAggregator != aggregator) {
            revert FailedOp(opIndex, "AA24 signature error");
        }
        if (outOfTimeRange) {
            revert FailedOp(opIndex, "AA22 expired or not due");
        }
        //pmAggregator is not a real signature aggregator: we don't have logic to handle it as address.
        // non-zero address means that the paymaster fails due to some signature check (which is ok only during estimation)

        // 解析并验证 paymaster 的userOperation
        address pmAggregator;
        (pmAggregator, outOfTimeRange) = _getValidationData(
            paymasterValidationData
        );
        if (pmAggregator != address(0)) {
            revert FailedOp(opIndex, "AA34 signature error");
        }
        if (outOfTimeRange) {
            revert FailedOp(opIndex, "AA32 paymaster expired or not due");
        }
    }

    // 解析 validata data
    function _getValidationData(uint256 validationData)
        internal
        view
        returns (address aggregator, bool outOfTimeRange)
    {
        if (validationData == 0) {
            return (address(0), false);
        }
        // validationData: data.validAfter . data.validUntil. aggregator
        // data.validUntil 如果为0, 则为 type(uint48).max;
        ValidationData memory data = _parseValidationData(validationData);
        // solhint-disable-next-line not-rely-on-time
        outOfTimeRange =
            block.timestamp > data.validUntil ||
            block.timestamp < data.validAfter;
        aggregator = data.aggregator;
    }

    /**
     * validate account and paymaster (if defined).
     * also make sure total validation doesn't exceed verificationGasLimit
     * this method is called off-chain (simulateValidation()) and on-chain (from handleOps)
     * @param opIndex the index of this userOp into the "opInfos" array
     * @param userOp the userOp to validate
     */
    function _validatePrepayment(
        uint256 opIndex,
        UserOperation calldata userOp,
        UserOpInfo memory outOpInfo
    )
        private
        returns (uint256 validationData, uint256 paymasterValidationData)
    {
        uint256 preGas = gasleft();
        MemoryUserOp memory mUserOp = outOpInfo.mUserOp;
        // 将  UserOperation copy 至 UserOpInfo 中.
        _copyUserOpToMemory(userOp, mUserOp);
        // 获取 userOperation 的 hash
        outOpInfo.userOpHash = getUserOpHash(userOp);
        // validate all numeric values in userOp are well below 128 bit, so they can safely be added
        // and multiplied without causing overflow
        uint256 maxGasValues = mUserOp.preVerificationGas |
            mUserOp.verificationGasLimit |
            mUserOp.callGasLimit |
            userOp.maxFeePerGas |
            userOp.maxPriorityFeePerGas;
        require(maxGasValues <= type(uint120).max, "AA94 gas values overflow");

        uint256 gasUsedByValidateAccountPrepayment;
        // 似乎是 为了获取必要的 手续费 (最大值), 去验证, 防止失败
        uint256 requiredPreFund = _getRequiredPrefund(mUserOp);
        // 验证所花费的gas 和 验证结果
        (
            gasUsedByValidateAccountPrepayment, // 验证所花费的gas
            validationData // 验证结果
        ) = _validateAccountPrepayment( // 如果 paymaster == 0, 则直接扣除这币userOperation 的gas fee
            opIndex,
            userOp,
            outOpInfo,
            requiredPreFund
        );

        // sender nonce +1
        if (!_validateAndUpdateNonce(mUserOp.sender, mUserOp.nonce)) {
            revert FailedOp(opIndex, "AA25 invalid account nonce");
        }

        //a "marker" where account opcode validation is done and paymaster opcode validation is about to start
        // (used only by off-chain simulateValidation)
        numberMarker();

        bytes memory context;
        if (mUserOp.paymaster != address(0)) {
            // 也是 验证paymaster
            (context, paymasterValidationData) = _validatePaymasterPrepayment(
                opIndex,
                userOp,
                outOpInfo,
                requiredPreFund,
                gasUsedByValidateAccountPrepayment
            );
        }
        unchecked {
            uint256 gasUsed = preGas - gasleft();

            if (userOp.verificationGasLimit < gasUsed) {
                revert FailedOp(opIndex, "AA40 over verificationGasLimit");
            }
            outOpInfo.prefund = requiredPreFund; // 提前收取的 手续费
            outOpInfo.contextOffset = getOffsetOfMemoryBytes(context);
            outOpInfo.preOpGas = preGas - gasleft() + userOp.preVerificationGas; // validata 阶段使用的gas
        }
    }

    /**
     * process post-operation.
     * called just after the callData is executed.
     * if a paymaster is defined and its validation returned a non-empty context, its postOp is called.
     * the excess amount is refunded to the account (or paymaster - if it was used in the request)
     * 调用 paymaster 的postOP(暂时不知是做什么的). 然后退钱
     * @param opIndex index in the batch
     * @param mode - whether is called from innerHandleOp, or outside (postOpReverted)
     * @param opInfo userOp fields and info collected during validation
     * @param context the context returned in validatePaymasterUserOp
     * @param actualGas the gas used so far by this user operation;  user operation 执行 validata & calldata 花费的 gas fee
     */
    function _handlePostOp(
        uint256 opIndex,
        IPaymaster.PostOpMode mode,
        UserOpInfo memory opInfo,
        bytes memory context,
        uint256 actualGas
    ) private returns (uint256 actualGasCost) {
        uint256 preGas = gasleft();
        unchecked {
            address refundAddress;
            MemoryUserOp memory mUserOp = opInfo.mUserOp;
            uint256 gasPrice = getUserOpGasPrice(mUserOp);

            address paymaster = mUserOp.paymaster;
            if (paymaster == address(0)) {
                refundAddress = mUserOp.sender;
            } else {
                refundAddress = paymaster;
                if (context.length > 0) {
                    actualGasCost = actualGas * gasPrice;
                    if (mode != IPaymaster.PostOpMode.postOpReverted) {
                        IPaymaster(paymaster).postOp{
                            gas: mUserOp.verificationGasLimit
                        }(mode, context, actualGasCost);
                    } else {
                        // solhint-disable-next-line no-empty-blocks
                        try
                            IPaymaster(paymaster).postOp{
                                gas: mUserOp.verificationGasLimit
                            }(mode, context, actualGasCost)
                        {} catch Error(string memory reason) {
                            revert FailedOp(
                                opIndex,
                                string.concat("AA50 postOp reverted: ", reason)
                            );
                        } catch {
                            revert FailedOp(opIndex, "AA50 postOp revert");
                        }
                    }
                }
            }
            actualGas += preGas - gasleft();
            actualGasCost = actualGas * gasPrice;
            if (opInfo.prefund < actualGasCost) {
                revert FailedOp(opIndex, "AA51 prefund below actualGasCost");
            }
            uint256 refund = opInfo.prefund - actualGasCost;
            // 把 多扣的钱 退给 refundAddress(用户 or paymaster)
            _incrementDeposit(refundAddress, refund);
            bool success = mode == IPaymaster.PostOpMode.opSucceeded;
            emit UserOperationEvent(
                opInfo.userOpHash,
                mUserOp.sender,
                mUserOp.paymaster,
                mUserOp.nonce,
                success,
                actualGasCost,
                actualGas
            );
        } // unchecked
    }

    /**
     * the gas price this UserOp agrees to pay.
     * relayer/block builder might submit the TX with higher priorityFee, but the user should not
     */
    function getUserOpGasPrice(MemoryUserOp memory mUserOp)
        internal
        view
        returns (uint256)
    {
        unchecked {
            uint256 maxFeePerGas = mUserOp.maxFeePerGas;
            uint256 maxPriorityFeePerGas = mUserOp.maxPriorityFeePerGas;
            if (maxFeePerGas == maxPriorityFeePerGas) {
                //legacy mode (for networks that don't support basefee opcode)
                return maxFeePerGas;
            }
            return min(maxFeePerGas, maxPriorityFeePerGas + block.basefee);
        }
    }

    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    function getOffsetOfMemoryBytes(bytes memory data)
        internal
        pure
        returns (uint256 offset)
    {
        assembly {
            offset := data
        }
    }

    function getMemoryBytesFromOffset(uint256 offset)
        internal
        pure
        returns (bytes memory data)
    {
        assembly {
            data := offset
        }
    }

    //place the NUMBER opcode in the code.
    // this is used as a marker during simulation, as this OP is completely banned from the simulated code of the
    // account and paymaster.
    function numberMarker() internal view {
        assembly {
            mstore(0, number())
        }
    }
}
