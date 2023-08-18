//SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/draft-ERC20Permit.sol";

contract MyToken is ERC20, Ownable, ERC20Permit, ERC20Burnable {
    mapping(address => uint256) public frozenAmount;

    event Froze(address indexed user, uint256 indexed amount);
    event Unfroze(address indexed user, uint256 indexed amount);

    constructor(string memory _name, string memory _symbol)
        ERC20(_name, _symbol)
        ERC20Permit(_name)
    {}

    function mintTo(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function mintTos(address[] calldata _tos, uint256[] calldata _amounts)
        external
    {
        require(_tos.length == _amounts.length, "length mismatch");
        for (uint256 i = 0; i < _tos.length; ) {
            _mint(_tos[i], _amounts[i]);
            unchecked {
                i++;
            }
        }
    }

    function freeze(address _user, uint256 _amount) public onlyOwner {
        require(
            balanceOf(_user) >= _amount + frozenAmount[_user],
            "Insufficient amount that can be frozen"
        );
        frozenAmount[_user] += _amount;
        emit Froze(_user, _amount);
    }

    function unfreeze(address _user, uint256 _amount) public onlyOwner {
        require(frozenAmount[_user] >= _amount, "Excessive unfrozen amount");
        frozenAmount[_user] -= _amount;
        emit Unfroze(_user, _amount);
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual override {
        super._beforeTokenTransfer(from, to, amount);
        require(
            from == address(0) ||
                frozenAmount[from] == 0 ||
                balanceOf(from) >= frozenAmount[from] + amount,
            "Some funds have been frozen and cannot be transfer"
        );
    }
}
