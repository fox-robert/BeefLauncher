// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import "./IUniswapV4.sol";
import "./ERC20.sol";
import "./ERC721.sol";

contract Constants {
    uint8 internal constant _decimals_          = 18;
    uint internal constant _totalSupply_        = 1_000_000_000e18;
    uint24 internal constant _fee_              = 10000;     // 1.00%
    int24 internal constant _tickSpacing_       = 200;
    bytes32 internal constant _ecologyFeeTo_    = "ecologyFeeTo";
    bytes32 internal constant _ecologyFeeRatio_ = "ecologyFeeRatio";
    bytes32 internal constant _deplyerFeeRatio_ = "deplyerFeeRatio";
}
contract ConstEthereum {
    uint internal constant _virtualReserve_     = 20 ether;
    address internal constant _hookContract_    = address(0);
    address internal constant _PoolManager_     = 0x000000000004444c5dc75cB358380D2e3dE08A90;
    address internal constant _PositionManager_ = 0xbD216513d74C8cf14cf4747E6AaA6420FF64ee9e;
    address internal constant _Permit2_         = 0x000000000022D473030F116dDEE9F6B43aC78BA3;
    address internal constant _Locker_          = 0x0Ed77ba3bB0904A4a7bF24Dfa0f380dDc7bdE41A;
}
contract ConstSepolia {
    uint internal constant _virtualReserve_     = 69 ether;  // BNB
    address internal constant _hookContract_    = 0x53FeBbE669Ac387b41928Cac7D9CfB9d7c4F40CC;
    address internal constant _PoolManager_     = 0xE03A1074c86CFeDd5C142C4F04F1a1536e203543;
    address internal constant _PositionManager_ = 0x429ba70129df741B2Ca2a85BC3A2a3328e5c09b4;
    address internal constant _Permit2_         = 0x000000000022D473030F116dDEE9F6B43aC78BA3;
    address internal constant _Locker_          = 0x0Ed77ba3bB0904A4a7bF24Dfa0f380dDc7bdE41A;
}


contract LaunchMeme is Sets, SwapBase, Constants, ConstSepolia {
    using SafeCast for int128;
    using SafeCast for uint256;
	using SafeERC20 for IERC20;

    mapping (IERC20 => address) public deployers;
    mapping (IERC20 => IERC20) public currencies;
    mapping (IERC20 => uint) public tokenIds;

    function launchMeme(string memory symbol) external payable returns (IERC20 token, uint tokenId, uint amountOut) {
        token = IERC20(address(new ERC20(symbol, symbol, _decimals_, _totalSupply_)));
        tokenId = _createLiqudity(Currency.wrap(address(token)), _totalSupply_, CurrencyLibrary.ADDRESS_ZERO, _virtualReserve_);
        IERC721(_PositionManager_).approve(_Locker_, tokenId);
        ILocker(_Locker_).lockERC721(IERC721(_PositionManager_), tokenId, type(uint).max);
        if(msg.value > 0)
            amountOut = swapExactInputSingle(address(0), address(token), msg.value, 0);
        deployers[token] = msg.sender;
        currencies[token] = IERC20(address(0));
        tokenIds[token] = tokenId;
        emit MemeLaunched(msg.sender, token, tokenId, msg.value, amountOut);
    }
    event MemeLaunched(address indexed deployer, IERC20 indexed token, uint indexed tokenId, uint value, uint amount);
    
    function _createLiqudity(Currency token, uint totalSupply, Currency currency, uint virtualReserve) internal returns (uint tokenId) {
        uint160 sqrtPriceX96;
        bytes[] memory actParams = new bytes[](2);
        PoolKey memory poolKey;
        if(token < currency) {
            poolKey = PoolKey({
                currency0:      token,
                currency1:      currency,
                fee:            LPFeeLibrary.DYNAMIC_FEE_FLAG,
                tickSpacing:    _tickSpacing_,
                hooks:          IHooks(_hookContract_)
            });
            uint price = virtualReserve * 2**96 / totalSupply;
            sqrtPriceX96 = SafeCast.toUint160(Math.sqrt(price * (2**96)));
            int24 tick = TickMath.getTickAtSqrtPrice(sqrtPriceX96) / _tickSpacing_ * _tickSpacing_;
            actParams[0] = abi.encode(
                poolKey, 
                tick + _tickSpacing_, 
                887200, 
                LiquidityAmounts.getLiquidityForAmounts(
                    sqrtPriceX96, 
                    TickMath.getSqrtPriceAtTick(tick + _tickSpacing_), 
                    TickMath.getSqrtPriceAtTick(887200),
                    totalSupply,
                    0
                ), 
                totalSupply, 
                0, 
                address(this), 
                ""
            );
        } else {
            poolKey = PoolKey({
                currency0:      currency,
                currency1:      token,
                fee:            LPFeeLibrary.DYNAMIC_FEE_FLAG,
                tickSpacing:    _tickSpacing_,
                hooks:          IHooks(_hookContract_)
            });
            {
            uint price = totalSupply * 2**96 / virtualReserve;
            sqrtPriceX96 = SafeCast.toUint160(Math.sqrt(price * (2**96)));
            }
            int24 tick = TickMath.getTickAtSqrtPrice(sqrtPriceX96) / _tickSpacing_ * _tickSpacing_;
            actParams[0] = abi.encode(
                poolKey, 
                -887200, 
                tick, 
                LiquidityAmounts.getLiquidityForAmounts(
                    sqrtPriceX96, 
                    TickMath.getSqrtPriceAtTick(-887200), 
                    TickMath.getSqrtPriceAtTick(tick),
                    0,
                    totalSupply
                ), 
                0, 
                totalSupply, 
                address(this), 
                "");
        }
        bytes memory actions = abi.encodePacked(uint8(Actions.MINT_POSITION), uint8(Actions.SETTLE_PAIR));
        actParams[1] = abi.encode(poolKey.currency0, poolKey.currency1);

        IPositionManager posm = IPositionManager(_PositionManager_);
        bytes[] memory params = new bytes[](2);
        params[0] = abi.encodeWithSelector(posm.initializePool.selector, poolKey, sqrtPriceX96, "");
        params[1] = abi.encodeWithSelector(posm.modifyLiquidities.selector, abi.encode(actions, actParams), block.timestamp + 60);

        IERC20(Currency.unwrap(token)).approve(_Permit2_, type(uint256).max);
        IAllowanceTransfer(_Permit2_).approve(Currency.unwrap(token), address(posm), type(uint160).max, type(uint48).max);

        tokenId = posm.nextTokenId();
        posm.multicall{value: 0}(params);    // multicall to create pool & add liquidity

        token.transfer(_PoolManager_, totalSupply - token.balanceOf(_PoolManager_));    // clear dust
    }

    function swapExactInputSingle(address tokenIn, address tokenOut, uint amountIn, uint amountOutMin) public payable returns (uint amountOut) {
        if(tokenIn < tokenOut) {
            amountOut = swap(
                IPoolManager(_PoolManager_), 
                PoolKey({
                    currency0:      Currency.wrap(address(tokenIn)),
                    currency1:      Currency.wrap(address(tokenOut)),
                    fee:            LPFeeLibrary.DYNAMIC_FEE_FLAG,
                    tickSpacing:    _tickSpacing_,
                    hooks:          IHooks(_hookContract_)
                }),
                IPoolManager.SwapParams({
                    zeroForOne:         true,
                    amountSpecified:    -amountIn.toInt128(),
                    sqrtPriceLimitX96:  TickMath.MIN_SQRT_PRICE + 1
                }),
                "",                     //bytes memory hookData,
                false,                  //bool takeClaims,
                false                   //bool settleUsingBurn
            ).amount1().toUint128();
        } else {
            amountOut = swap(
                IPoolManager(_PoolManager_), 
                PoolKey({
                    currency0:      Currency.wrap(address(tokenOut)),
                    currency1:      Currency.wrap(address(tokenIn)),
                    fee:            LPFeeLibrary.DYNAMIC_FEE_FLAG,
                    tickSpacing:    _tickSpacing_,
                    hooks:          IHooks(_hookContract_)
                }),
                IPoolManager.SwapParams({
                    zeroForOne:         false,
                    amountSpecified:    -amountIn.toInt128(),
                    sqrtPriceLimitX96:  TickMath.MAX_SQRT_PRICE - 1
                }),
                "",                     //bytes memory hookData,
                false,                  //bool takeClaims,
                false                   //bool settleUsingBurn
            ).amount0().toUint128();
        }
        require(amountOut >= amountOutMin, "Too little received");
    }

    function swapExactOutputSingle(address tokenIn, address tokenOut, uint amountOut, uint amountInMax) external payable returns (uint amountIn) {
        if(tokenIn < tokenOut) {
            amountIn = (-swap(
                IPoolManager(_PoolManager_), 
                PoolKey({
                    currency0:      Currency.wrap(address(tokenIn)),
                    currency1:      Currency.wrap(address(tokenOut)),
                    fee:            LPFeeLibrary.DYNAMIC_FEE_FLAG,
                    tickSpacing:    _tickSpacing_,
                    hooks:          IHooks(_hookContract_)
                }),
                IPoolManager.SwapParams({
                    zeroForOne:         true,
                    amountSpecified:    amountOut.toInt128(),
                    sqrtPriceLimitX96:  TickMath.MIN_SQRT_PRICE + 1
                }),
                "",                     //bytes memory hookData,
                false,                  //bool takeClaims,
                false                   //bool settleUsingBurn
            ).amount0()).toUint128();
        } else {
            amountIn = (-swap(
                IPoolManager(_PoolManager_), 
                PoolKey({
                    currency0:      Currency.wrap(address(tokenOut)),
                    currency1:      Currency.wrap(address(tokenIn)),
                    fee:            LPFeeLibrary.DYNAMIC_FEE_FLAG,
                    tickSpacing:    _tickSpacing_,
                    hooks:          IHooks(_hookContract_)
                }),
                IPoolManager.SwapParams({
                    zeroForOne:         false,
                    amountSpecified:    amountOut.toInt128(),
                    sqrtPriceLimitX96:  TickMath.MAX_SQRT_PRICE - 1
                }),
                "",                     //bytes memory hookData,
                false,                  //bool takeClaims,
                false                   //bool settleUsingBurn
            ).amount1()).toUint128();
        }
        require(amountIn <= amountInMax, "Too much requested");
    }

    function collect(IERC20 token) external {
        ILocker(_Locker_).collectV4(_PositionManager_, tokenIds[token]);
        Currency currency = Currency.wrap(address(currencies[token]));
        uint value = currency.balanceOf(address(this));
        uint amount = token.balanceOf(address(this));
        _distributeFee(token, amount, currency, value);
        emit Collect(tokenIds[token], token, amount, currency, value);
    }
    event Collect(uint indexed tokenId, IERC20 indexed token, uint amount, Currency indexed currency, uint value);

    function _distributeFee(IERC20 token, uint amount, Currency currency, uint value) internal {
        address deplyerFeeTo = deployers[token];
        address protocolFeeto = Config.admin();
        if(protocolFeeto == address(0))
            protocolFeeto = Config.getA(_governor_);
        address ecologyFeeTo = Config.getA(_ecologyFeeTo_);
        if(ecologyFeeTo == address(0))
            ecologyFeeTo = protocolFeeto;
        
        uint deplyerFeeRatio = Config.get(_deplyerFeeRatio_);
        if(deplyerFeeRatio == 0)
            deplyerFeeRatio = 400000;               // 40%
        uint ecologyFeeRatio = Config.get(_ecologyFeeRatio_);
        if(ecologyFeeRatio == 0)
            ecologyFeeRatio = 300000;               // 30%

        uint deplyerFee  = value * deplyerFeeRatio / LPFeeLibrary.MAX_LP_FEE;
        uint ecologyFee  = value * ecologyFeeRatio / LPFeeLibrary.MAX_LP_FEE;
        uint protocolFee = value - deplyerFee -ecologyFee;

        currency.transfer(deplyerFeeTo,  deplyerFee);
        currency.transfer(ecologyFeeTo,  ecologyFee);
        currency.transfer(protocolFeeto, protocolFee);

        if(amount > 0)
            token.safeTransfer(deplyerFeeTo, amount);
    }

    receive() external payable { }
}

interface ILocker {
    function lockERC721(IERC721 nft, uint tokenId, uint expiry) external;
    function collectV4(address posm, uint tokenId) external returns(uint256 amount0, uint256 amount1);
}
