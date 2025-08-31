// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract NummusToken is ERC20, Ownable {

    //Variables
    address public nummoraCore;

    //Modificador
    modifier onlyCore() {
        require(msg.sender == nummoraCore, "Only core contract");
        _;
    }

    //Constructor
    constructor(address _nummoraCore) ERC20("NUMMORA 1:1", "NUMMUS") 
        Ownable(msg.sender) 
    {
        nummoraCore = _nummoraCore;
    }

    //Eventos
    event NUMMUSMinted(address indexed to, uint256 amount);
    event NUMMUSBurned(address indexed from, uint256 amount);
    event CoreContractUpdated(address indexed newCore);

    //Funciones de escritura

    function mint(address to, uint256 amount) public onlyCore {
        _mint(to, amount);
        emit NUMMUSMinted(to, amount);
    }

    function burn(address from, uint256 amount) public onlyCore {
        _burn(from, amount);
        emit NUMMUSBurned(from, amount);
    }

    function updateCoreContract(address newCore) external onlyOwner {
        require(newCore != address(0), "Invalid address");
        nummoraCore = newCore;
        emit CoreContractUpdated(newCore);
    }

    //Funciones de lectura

    function decimals() public pure override returns (uint8) {
        return 6;
    }

    function isCoreContract(address account) external view returns (bool) {
        return account == nummoraCore;
    }
}