// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract NCOP is ERC20, ERC20Burnable, ERC20Pausable, Ownable {
    constructor(uint256 initialSupply) 
        ERC20("NCOP", "NCOP") 
        Ownable(msg.sender) 
    {
        _mint(msg.sender, initialSupply * 10 ** decimals());
    }

    // Función para crear nuevos tokens (solo el owner)
    function mint(address to, uint256 amount) public onlyOwner {
        _mint(to, amount);
    }

    // Función para pausar todas las transferencias (solo el owner)
    function pause() public onlyOwner {
        _pause();
    }

    // Función para reanudar las transferencias (solo el owner)
    function unpause() public onlyOwner {
        _unpause();
    }

    // Override requerido por Solidity cuando se usan múltiples herencias
    function _update(address from, address to, uint256 value)
        internal
        override(ERC20, ERC20Pausable)
    {
        super._update(from, to, value);
    }
}