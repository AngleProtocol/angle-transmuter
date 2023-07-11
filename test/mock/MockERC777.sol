// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.19;

import "oz/token/ERC777/ERC777.sol";

contract MockERC777 is ERC777 {
    event Minting(address indexed _to, address indexed _minter, uint256 _amount);

    event Burning(address indexed _from, address indexed _burner, uint256 _amount);

    constructor(string memory name_, string memory symbol_, uint8 decimal_) ERC777(name_, symbol_, new address[](0)) {}

    function mint(address account, uint256 amount) external {
        _mint(account, amount, "", "");
        emit Minting(account, msg.sender, amount);
    }

    function burn(address account, uint256 amount) public {
        _burn(account, amount, "", "");
        emit Burning(account, msg.sender, amount);
    }

    function setAllowance(address from, address to) public {
        _approve(from, to, type(uint256).max);
    }
}
