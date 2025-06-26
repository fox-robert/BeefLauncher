// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

contract ERC20 {
    string public name;
    string public symbol;
    uint8 public decimals;
    uint public totalSupply;
    mapping (address => uint) public balanceOf;
    mapping (address => mapping (address => uint)) public allowance;

    event Transfer(address indexed src, address indexed dst, uint amount);
    event Approval(address indexed owner, address indexed spender, uint amount);

    constructor(string memory name_, string memory symbol_, uint8 decimals_, uint totalSupply_) {
        totalSupply = totalSupply_;
        balanceOf[msg.sender] = totalSupply_;
        name = name_;
        symbol = symbol_;
        decimals = decimals_;
        emit Transfer(address(0), msg.sender, totalSupply_);
    }

    function transfer(address dst, uint amount) public returns (bool) {
        balanceOf[msg.sender] -= amount;
        balanceOf[dst] += amount;
        emit Transfer(msg.sender, dst, amount);
        return true;
    }

    function transferFrom(address src, address dst, uint amount) external returns (bool) {
        if(allowance[src][msg.sender] != type(uint).max)
            allowance[src][msg.sender] -= amount;
        balanceOf[src] -= amount;
        balanceOf[dst] += amount;
        emit Transfer(src, dst, amount);
        return true;
    }

    function approve(address spender, uint amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }
}
