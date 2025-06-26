// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;
pragma experimental ABIEncoderV2;

import "./ERC721.sol";

contract Locker {
    using SafeMath for uint;
	using SafeERC20 for IERC20;

    mapping(IERC20 => mapping(address => uint)) public balanceOf;
    mapping(IERC20 => mapping(address => uint)) public tokenExpiryOf;
    mapping(IERC721 => mapping(uint => address)) public ownerOf;
    mapping(IERC721 => mapping(uint => uint)) public nftExpiryOf;
    
    function lockERC20(IERC20 token, uint amount, uint expiry) external {
        require(expiry > block.timestamp, "expiry should be in the future");
        require(expiry >= tokenExpiryOf[token][msg.sender], "the new expiry should be later than before");
        uint balance = token.balanceOf(address(this));
        token.safeTransferFrom(msg.sender, address(this), amount);
        amount = token.balanceOf(address(this)).sub(balance);
        balance = balanceOf[token][msg.sender] = balanceOf[token][msg.sender].add(amount);
        tokenExpiryOf[token][msg.sender] = expiry;
        emit LockERC20(msg.sender, token, amount, balance, expiry);
    }
    event LockERC20(address indexed owner, IERC20 indexed token, uint amount, uint balance, uint expiry);

    function unlockERC20(IERC20 token) external {
        require(tokenExpiryOf[token][msg.sender] <= block.timestamp, "It is not time to unlock");
        uint amount = balanceOf[token][msg.sender];
        token.safeTransfer(msg.sender, amount);
        balanceOf[token][msg.sender] = 0;
        tokenExpiryOf[token][msg.sender] = 0;
        emit UnlockERC20(msg.sender, token, amount);
    }
    event UnlockERC20(address indexed owner, IERC20 indexed token, uint amount);

    function lockERC721(IERC721 nft, uint tokenId, uint expiry) external {
        require(expiry > block.timestamp, "expiry should be in the future");
        require(expiry >= nftExpiryOf[nft][tokenId], "the new expiry should be later than before");
        if(nft.ownerOf(tokenId) == msg.sender) {
            nft.transferFrom(msg.sender, address(this), tokenId);
            ownerOf[nft][tokenId] = msg.sender;
        } else
            require(ownerOf[nft][tokenId] == msg.sender, "You are not the owner of the nft");
        nftExpiryOf[nft][tokenId] = expiry;
        emit LockERC721(msg.sender, nft, tokenId, expiry);
    }
    event LockERC721(address indexed owner, IERC721 indexed nft, uint indexed tokenId, uint expiry);

    function unlockERC721(IERC721 nft, uint tokenId) external {
        require(nftExpiryOf[nft][tokenId] <= block.timestamp, "It is not time to unlock");
        require(ownerOf[nft][tokenId] == msg.sender, "You are not the owner of the nft");
        nft.transferFrom(address(this), msg.sender, tokenId);
        ownerOf[nft][tokenId] = address(0);
        nftExpiryOf[nft][tokenId] = 0;
        emit UnlockERC721(msg.sender, nft, tokenId);
    }
    event UnlockERC721(address indexed owner, IERC721 indexed nft, uint indexed tokenId);

    function collectV3(INonfungiblePositionManager posm, uint tokenId) external returns(uint256 amount0, uint256 amount1) {
        require(ownerOf[posm][tokenId] == msg.sender, "You are not the owner of the nft");
        (amount0, amount1) = posm.collect(
            INonfungiblePositionManager.CollectParams({
                tokenId     : tokenId,
                recipient   : msg.sender,
                amount0Max  : type(uint128).max,
                amount1Max  : type(uint128).max
            })
        );
        emit Collect(msg.sender, posm, tokenId, amount0, amount1);
    }

    function collectV4(IPositionManager posm, uint tokenId) external returns(uint256 amount0, uint256 amount1) {
        require(ownerOf[posm][tokenId] == msg.sender, "You are not the owner of the nft");
        (PoolKey memory poolKey,) = posm.getPoolAndPositionInfo(tokenId);
        amount0 = address(poolKey.currency0) == address(0) ? msg.sender.balance : poolKey.currency0.balanceOf(msg.sender);
        amount1 = poolKey.currency1.balanceOf(msg.sender);

        bytes memory actions = abi.encodePacked(uint8(Actions.DECREASE_LIQUIDITY), uint8(Actions.TAKE_PAIR));
        bytes[] memory params = new bytes[](2);
        params[0] = abi.encode(tokenId, 0, 0, 0, "");
        params[1] = abi.encode(poolKey.currency0, poolKey.currency1, msg.sender);
        posm.modifyLiquidities{value: 0}(abi.encode(actions, params), block.timestamp + 60);

        amount0 = (poolKey.currency0 == IERC20(address(0)) ? msg.sender.balance : poolKey.currency0.balanceOf(msg.sender)) - amount0;
        amount1 = poolKey.currency1.balanceOf(msg.sender) - amount1;
        emit Collect(msg.sender, posm, tokenId, amount0, amount1);
    }
    event Collect(address indexed owner, IERC721 indexed posm, uint256 indexed tokenId, uint256 amount0, uint256 amount1);
}

interface INonfungiblePositionManager is IERC721 {
    struct CollectParams {
        uint256 tokenId;
        address recipient;
        uint128 amount0Max;
        uint128 amount1Max;
    }

    function collect(CollectParams calldata params) external payable returns (uint256 amount0, uint256 amount1);
}

interface IPositionManager is IERC721 {
    function getPoolAndPositionInfo(uint256 tokenId) external view returns (PoolKey memory, uint);
    function modifyLiquidities(bytes calldata unlockData, uint256 deadline) external payable;
}

struct PoolKey {
    IERC20 currency0;
    IERC20 currency1;
    uint24 fee;
    int24 tickSpacing;
    address hooks;
}

library Actions {
    uint256 internal constant DECREASE_LIQUIDITY = 0x01;
    uint256 internal constant TAKE_PAIR = 0x11;
}


