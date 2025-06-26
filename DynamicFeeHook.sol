// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {SafeCast, Hooks, IHooks, IPoolManager, PoolKey, Currency, CurrencyLibrary, BalanceDelta, BalanceDeltaLibrary, toBeforeSwapDelta, BeforeSwapDelta, BeforeSwapDeltaLibrary, LPFeeLibrary, StateLibrary, PoolIdLibrary} from "./IUniswapV4.sol";

contract DynamicFeeHook {
    using Hooks for IHooks;
    using LPFeeLibrary for uint24;

    uint160 internal constant _initialSqrtPriceX96  = 301616459959743488966662124432145;    // 59/1_000_000_000

    mapping(Currency => uint) public feePriority;

    constructor() {
        IHooks(address(this)).validateHookPermissions(
            Hooks.Permissions({         //0x00CC
                beforeInitialize:                   false,
                afterInitialize:                    false,
                beforeAddLiquidity:                 false,
                afterAddLiquidity:                  false,
                beforeRemoveLiquidity:              false,
                afterRemoveLiquidity:               false,
                beforeSwap:                 true,
                afterSwap:                  true,
                beforeDonate:                       false,
                afterDonate:                        false,
                beforeSwapReturnDelta:      true,
                afterSwapReturnDelta:       true,
                afterAddLiquidityReturnDelta:       false,
                afterRemoveLiquidityReturnDelta:    false
            })
        );
        feePriority[CurrencyLibrary.ADDRESS_ZERO] = 100;
    }

//    function setFeePriority(Currency currency, uint priority) external {
//        feePriority[currency] = priority;
//    }

    function beforeSwap(address, PoolKey calldata key, IPoolManager.SwapParams calldata params, bytes calldata) external
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        uint24 fee = lpFee(IPoolManager(msg.sender), key, params.zeroForOne);
        (Currency currencyInput, Currency currencyOutput) = params.zeroForOne ? (key.currency0, key.currency1) : (key.currency1, key.currency0);
        if(feePriority[currencyInput] >= feePriority[currencyOutput]) {
            emit BeforeSwap(fee, 0);
            // attach the fee flag to `fee` to enable overriding the pool's stored fee
            return (IHooks.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, fee | LPFeeLibrary.OVERRIDE_FEE_FLAG);
        } else if(params.amountSpecified > 0) {
            int128 deltaSpecified = SafeCast.toInt128(uint(params.amountSpecified) * fee / LPFeeLibrary.MAX_LP_FEE);
            (uint fee0, uint fee1) = params.zeroForOne ? (uint(0), uint(int(deltaSpecified))) : (uint(int(deltaSpecified)), 0);
            IPoolManager(msg.sender).donate(key, fee0, fee1, "");
            emit BeforeSwap(fee, deltaSpecified);
            return (IHooks.beforeSwap.selector, toBeforeSwapDelta(deltaSpecified, 0), 0 | LPFeeLibrary.OVERRIDE_FEE_FLAG);     // hookFee instead of lpFee
        } else {
            emit BeforeSwap(fee, 0);
            return (IHooks.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0 | LPFeeLibrary.OVERRIDE_FEE_FLAG);     // hookFee instead of lpFee
        }
    }
    event BeforeSwap(uint24 fee, int128 deltaSpecified);

    function afterSwap(address, PoolKey calldata key, IPoolManager.SwapParams calldata params, BalanceDelta delta, bytes calldata) external
        returns (bytes4, int128 deltaUnspecified)
    {
        uint24 fee = lpFee(IPoolManager(msg.sender), key, params.zeroForOne);
        (Currency currencyInput, Currency currencyOutput) = params.zeroForOne ? (key.currency0, key.currency1) : (key.currency1, key.currency0);
        if(feePriority[currencyInput] < feePriority[currencyOutput] && params.amountSpecified < 0) {
            int128 amountUnspecified = params.zeroForOne ? delta.amount1() : delta.amount0();
            deltaUnspecified = SafeCast.toInt128(uint(int(amountUnspecified)) * fee / LPFeeLibrary.MAX_LP_FEE);
            (uint fee0, uint fee1) = params.zeroForOne ? (uint(0), uint(int(deltaUnspecified))) : (uint(int(deltaUnspecified)), 0);
            IPoolManager(msg.sender).donate(key, fee0, fee1, "");
        } else
            deltaUnspecified = 0;
        emit AfterSwap(fee, deltaUnspecified);
        return (IHooks.afterSwap.selector, deltaUnspecified);
    }
    event AfterSwap(uint24 fee, int128 deltaUnspecified);

    function lpFee(IPoolManager poolManager, PoolKey calldata key, bool zeroForOne) public view returns (uint24 fee) {
        (uint160 sqrtPriceX96,,,) = StateLibrary.getSlot0(poolManager, PoolIdLibrary.toId(key));
        require(sqrtPriceX96 <= _initialSqrtPriceX96, "sqrtPriceX96 is too large");
        if(zeroForOne)
            return 10000;       // buy fee is allways 1%
        fee = uint24(uint(50000) * sqrtPriceX96 / _initialSqrtPriceX96);
        if(fee < 10000)
            fee = 10000;        // sell fee is proportional to the sqrtPriceX96 and ranges from 5% to 1%
    }
}

