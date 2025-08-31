// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

contract LoanNFT is ERC721, ERC721URIStorage, Ownable {
    using Strings for uint256;

    //Estructuras
    struct LoanMetadata {
        uint256 loanId;
        address borrower;
        uint256 amount;
        uint256 totalToPay;
        uint256 installments;
        uint256 startTime;
        uint256 finishTime;
        string documentHash;
        bool active;
    }

    //Variables
    address public nummoraCore;
    string public baseTokenURI;

    // Mapping de tokenId a metadata del préstamo
    mapping(uint256 => LoanMetadata) public loanMetadata;
    
    // Mapping para tracking de préstamos por lender
    mapping(address => uint256[]) public lenderLoans;

    //Eventos

    event LoanNFTMinted(address indexed to, uint256 indexed tokenId);
    event LoanNFTBurned(uint256 indexed tokenId);
    event LoanMetadataUpdated(uint256 indexed tokenId);
    event BaseURIUpdated(string newBaseURI);

    //Modificadores

    modifier onlyCore() {
        require(msg.sender == nummoraCore, "Only core contract");
        _;
    }

    //Constructor

    constructor(address _nummoraCore, string memory name_, string memory symbol_) 
        ERC721(name_, symbol_) 
        Ownable(msg.sender) 
    {
        nummoraCore = _nummoraCore;
        baseTokenURI = "https://api.nummora.io/loan/";
    }

    function mint(
        address to, 
        uint256 tokenId, 
        string memory documentHash
    ) external onlyCore {
        _mint(to, tokenId);
        
        // Inicializar metadata básico
        loanMetadata[tokenId] = LoanMetadata({
            loanId: tokenId,
            borrower: address(0), // Se actualiza después
            amount: 0,
            totalToPay: 0,
            installments: 0,
            startTime: block.timestamp,
            finishTime: block.timestamp,
            documentHash: documentHash,
            active: true
        });
        
        lenderLoans[to].push(tokenId);
        
        emit LoanNFTMinted(to, tokenId);
    }

    function updateLoanMetadata(
        uint256 tokenId,
        address borrower,
        uint256 amount,
        uint256 totalToPay,
        uint256 installments
    ) external onlyCore {
        require(_ownerOf(tokenId) != address(0), "Token does not exist");
        
        LoanMetadata storage metadata = loanMetadata[tokenId];
        metadata.borrower = borrower;
        metadata.amount = amount;
        metadata.totalToPay = totalToPay;
        metadata.installments = installments;
        
        emit LoanMetadataUpdated(tokenId);
    }

    function burn(uint256 tokenId) external onlyCore {
        require(_ownerOf(tokenId) != address(0), "Token does not exist");
        
        // Remover de la lista del lender
        address owner = ownerOf(tokenId);
        _removeLoanFromLender(owner, tokenId);
        
        // Limpiar metadata antes de quemar
        delete loanMetadata[tokenId];
        
        // Usar la función burn interna correcta
        _burn(tokenId);
        
        emit LoanNFTBurned(tokenId);
    }

    // ============ URI FUNCTIONS ============
    
    /**
     * @dev Retorna URI del token con metadata dinámico
     */
    function tokenURI(uint256 tokenId) 
        public 
        view 
        override(ERC721, ERC721URIStorage) 
        returns (string memory) 
    {
        require(_ownerOf(tokenId) != address(0), "URI query for nonexistent token");
        
        string memory baseURI = _baseURI();
        return bytes(baseURI).length > 0 
            ? string(abi.encodePacked(baseURI, tokenId.toString(), ".json"))
            : "";
    }
    
    function _baseURI() internal view override returns (string memory) {
        return baseTokenURI;
    }
    
    /**
     * @dev Actualiza base URI (solo owner)
     */
    function setBaseURI(string memory newBaseURI) external onlyOwner {
        baseTokenURI = newBaseURI;
        emit BaseURIUpdated(newBaseURI);
    }
    
    // ============ VIEW FUNCTIONS ============
    
    /**
     * @dev Retorna metadata completo de un préstamo
     */
    function getLoanMetadata(uint256 tokenId) 
        external 
        view 
        returns (LoanMetadata memory) 
    {
        require(_ownerOf(tokenId) != address(0), "Token does not exist");
        return loanMetadata[tokenId];
    }
    
    /**
     * @dev Retorna todos los préstamos de un lender
     */
    function getLenderLoans(address lender) 
        external 
        view 
        returns (uint256[] memory) 
    {
        return lenderLoans[lender];
    }

    // ============ TRANSFER HOOKS ============
    
    /**
     * @dev Hook que actualiza tracking cuando se transfiere NFT
     * Compatible con OpenZeppelin v5.x
     */
    function _update(
        address to,
        uint256 tokenId,
        address auth
    ) internal override returns (address) {
        address from = _ownerOf(tokenId);
        
        // Actualizar listas de préstamos en transfers
        if (from != address(0) && to != address(0) && from != to) {
            _removeLoanFromLender(from, tokenId);
            lenderLoans[to].push(tokenId);
        }
        
        return super._update(to, tokenId, auth);
    }
    
    function _removeLoanFromLender(address lender, uint256 tokenId) internal {
        uint256[] storage loans = lenderLoans[lender];
        for (uint256 i = 0; i < loans.length; i++) {
            if (loans[i] == tokenId) {
                loans[i] = loans[loans.length - 1];
                loans.pop();
                break;
            }
        }
    }

    // ============ ADMIN FUNCTIONS ============
    
    /**
     * @dev Actualiza dirección del contrato core
     */
    function updateCoreContract(address newCore) external onlyOwner {
        require(newCore != address(0), "Invalid address");
        nummoraCore = newCore;
    }
    
    /**
     * @dev Verifica si token existe
     */
    function exists(uint256 tokenId) external view returns (bool) {
        return _ownerOf(tokenId) != address(0);
    }
    
    // ============ OVERRIDES REQUERIDOS ============
    
    /**
     * @dev Override requerido por herencia múltiple
     */
    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721, ERC721URIStorage)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}