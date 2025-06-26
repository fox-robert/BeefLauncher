// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

//import "forge-std/Script.sol";
//import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
//import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {Hooks, IPoolManager} from "./IUniswapV4.sol";

/// @title HookMiner
/// @notice a minimal library for mining hook addresses
library HookMiner {
    // mask to slice out the bottom 14 bit of the address
    uint160 constant FLAG_MASK = Hooks.ALL_HOOK_MASK; // 0000 ... 0000 0011 1111 1111 1111

    // Maximum number of iterations to find a salt, avoid infinite loops or MemoryOOG
    // (arbitrarily set)
    uint256 constant MAX_LOOP = 160_444;

    /// @notice Find a salt that produces a hook address with the desired `flags`
    /// @param deployer The address that will deploy the hook. In `forge test`, this will be the test contract `address(this)` or the pranking address
    /// In `forge script`, this should be `0x4e59b44847b379578588920cA78FbF26c0B4956C` (CREATE2 Deployer Proxy)
    /// @param flags The desired flags for the hook address. Example `uint160(Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG | ...)`
    /// @param creationCode The creation code of a hook contract. Example: `type(Counter).creationCode`
    /// @param constructorArgs The encoded constructor arguments of a hook contract. Example: `abi.encode(address(manager))`
    /// @return (hookAddress, salt) The hook deploys to `hookAddress` when using `salt` with the syntax: `new Hook{salt: salt}(<constructor arguments>)`
    function find(address deployer, uint160 flags, bytes memory creationCode, bytes memory constructorArgs)
        internal
        view
        returns (address, bytes32)
    {
        flags = flags & FLAG_MASK; // mask for only the bottom 14 bits
        bytes memory creationCodeWithArgs = abi.encodePacked(creationCode, constructorArgs);

        address hookAddress;
        for (uint256 salt; salt < MAX_LOOP; salt++) {
            hookAddress = computeAddress(deployer, salt, creationCodeWithArgs);

            // if the hook's bottom 14 bits match the desired flags AND the address does not have bytecode, we found a match
            if (uint160(hookAddress) & FLAG_MASK == flags && hookAddress.code.length == 0) {
                return (hookAddress, bytes32(salt));
            }
        }
        revert("HookMiner: could not find salt");
    }

    /// @notice Precompute a contract address deployed via CREATE2
    /// @param deployer The address that will deploy the hook. In `forge test`, this will be the test contract `address(this)` or the pranking address
    /// In `forge script`, this should be `0x4e59b44847b379578588920cA78FbF26c0B4956C` (CREATE2 Deployer Proxy)
    /// @param salt The salt used to deploy the hook
    /// @param creationCodeWithArgs The creation code of a hook contract, with encoded constructor arguments appended. Example: `abi.encodePacked(type(Counter).creationCode, abi.encode(constructorArg1, constructorArg2))`
    function computeAddress(address deployer, uint256 salt, bytes memory creationCodeWithArgs)
        internal
        pure
        returns (address hookAddress)
    {
        return address(
            uint160(uint256(keccak256(abi.encodePacked(bytes1(0xFF), deployer, salt, keccak256(creationCodeWithArgs)))))
        );
    }
}


contract DeployHook {
    function find(uint160 flags, bytes memory creationCode, bytes memory constructorArgs) external view returns(address hookAddress, bytes32 salt) {
        return HookMiner.find(address(this), flags, creationCode, constructorArgs);
    }

    function deploy(bytes memory creationCode, bytes memory constructorArgs, address hookAddress, bytes32 salt) external payable {
        bytes memory bytecode = abi.encodePacked(creationCode, constructorArgs);
        address hook;
        assembly {
            hook := create2(0, add(bytecode, 32), mload(bytecode), salt)
        }
       require(hook == hookAddress, "DeployHook: hook address mismatch");
       emit HookDeployed(msg.sender, hookAddress, salt);
    }
    event HookDeployed(address sender, address hookAddress, bytes32 salt);
}


/*
/// @dev Replace import with your own hook
//import {MockCounterHook} from "../test/mocks/MockCounterHook.sol";

/// @notice Mines the address and deploys the Counter.sol Hook contract
contract DeployHookScript is Script {
    address constant CREATE2_DEPLOYER = address(0x4e59b44847b379578588920cA78FbF26c0B4956C);

    /// @dev Replace with the desired PoolManager on its corresponding chain
    IPoolManager constant POOLMANAGER = IPoolManager(address(0xE03A1074c86CFeDd5C142C4F04F1a1536e203543));

    function setUp() public {}

    function run() public {
        // hook contracts must have specific flags encoded in the address
        uint160 flags = uint160(
            Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG | Hooks.BEFORE_ADD_LIQUIDITY_FLAG
                | Hooks.BEFORE_REMOVE_LIQUIDITY_FLAG
        );

        bytes memory constructorArgs = abi.encode(POOLMANAGER);

        // Mine a salt that will produce a hook address with the correct flags
        (address hookAddress, bytes32 salt) =
            HookMiner.find(CREATE2_DEPLOYER, flags, type(MockCounterHook).creationCode, constructorArgs);

        // Deploy the hook using CREATE2
        vm.broadcast();
        MockCounterHook counter = new MockCounterHook{salt: salt}(IPoolManager(POOLMANAGER));
        require(address(counter) == hookAddress, "CounterScript: hook address mismatch");
    }
}
*/