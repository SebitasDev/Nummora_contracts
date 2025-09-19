// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

interface INUMUSToken {
    function mint(address to, uint256 amount) external;
    function burn(address from, uint256 amount) external;
    function balanceOf(address account) external view returns (uint256);
    function approve(address spender, uint256 value) external returns (bool);
}

interface ILoanNFT {
    function mint(address to, uint256 tokenId, string memory uri) external;
}

contract NummoraCore is ReentrancyGuard, Ownable {
    using ECDSA for bytes32;
    using MessageHashUtils for bytes32;

    //Estructuras
    struct Loan {
        address lender;
        address borrower;
        address stablecoin;
        uint256 amount;
        uint256 totalToPay;
        uint256 totalPaid;
        uint256 startTime;
        uint256 installments;
        uint256 installmentAmount;
        uint256 installmentsPaid;
        bool active;
        uint256 platformFee;
    }

    INUMUSToken public numusToken;
    ILoanNFT public loanNFT;

    mapping(uint256 => Loan) public loans;
    mapping(address => bool) public lenders;
    mapping(address => bool) public borrowers;
    mapping(address => bool) public stablecoins;

    uint256 public nextLoanId = 1;
    uint256 public fee = 200; // 2%

    // ============ EVENTOS ============
    
    event LenderRegistered(address lender);
    event BorrowerRegistered(address borrower);
    event LoanCreated(uint256 loanId, address lender, address borrower, uint256 amount);
    event PaymentMade(uint256 loanId, uint256 amount);
    event LoanCompleted(uint256 loanId);
    event EarlyPaymentMade(uint256 indexed loanId, uint256 amount, uint256 daysUsed);

    constructor(address _numus, address _nft) Ownable(msg.sender) {
        numusToken = INUMUSToken(_numus);
        loanNFT = ILoanNFT(_nft);
        
        //Stablecoins Mento Alfajores
        stablecoins[0xe6A57340f0df6E020c1c0a80bC6E13048601f0d4] = true; //-> cCOP
        stablecoins[0x641b9a432fEccAA89123951339D1941D792bf65f] = false; //SOMNIA nCop
        stablecoins[0xB4630414268949dd89D335a66be40819D2db0C5c] = true; //Lisk nCop
        /*stablecoins[0x10c892A6EC43a53E45D0B916B4b7D383B1b78C0F] = true;
        stablecoins[0xE4D517785D091D3c54818832dB6094bcc2744545] = true;*/
    }

    // ============ REGISTRO ============
    
    function registerLender() external {
        lenders[msg.sender] = true;
        emit LenderRegistered(msg.sender);
    }
    
    function registerBorrower() external {
        borrowers[msg.sender] = true;
        emit BorrowerRegistered(msg.sender);
    }

    function deposit(address token, uint256 amount) external nonReentrant {
        require(stablecoins[token], "Token not supported");
        require(lenders[msg.sender], "Not registered");
        
        IERC20(token).transferFrom(msg.sender, address(this), amount);
        numusToken.mint(msg.sender, amount);
        numusToken.approve(address(this), amount);
    }

    function withdraw(address token, uint256 amount) external nonReentrant {
        require(stablecoins[token], "Token not supported");
        require(numusToken.balanceOf(msg.sender) >= amount, "Insufficient balance");
        
        numusToken.burn(msg.sender, amount);
        IERC20(token).transfer(msg.sender, amount);
    }

    // ============ PRÉSTAMOS ============ //-> poner owner dps
    
    function createLoan(
        address lender,
        address borrower,
        address token,
        uint256 amount,
        uint256 interest,
        uint256 installments,
        uint256 platformFee
    ) external nonReentrant returns (uint256) {
        require(lenders[lender], "Lender not registered");
        require(borrowers[borrower], "Borrower not registered");
        require(stablecoins[token], "Token not supported");
        require(numusToken.balanceOf(lender) >= amount, "Insufficient balance");
        
        uint256 loanId = nextLoanId++;
        uint256 totalToPay = amount + interest;
        uint256 installmentAmount = totalToPay / installments;
        
        loans[loanId] = Loan({
            lender: lender,
            borrower: borrower,
            stablecoin: token,
            amount: amount,
            totalToPay: totalToPay,
            totalPaid: 0,
            startTime: block.timestamp,
            installments: installments,
            installmentAmount: installmentAmount,
            installmentsPaid: 0,
            active: true,
            platformFee: platformFee
        });
        
        // Transfer funds
        numusToken.burn(lender, amount);
        IERC20(token).transfer(borrower, amount);
        loanNFT.mint(lender, loanId, "");
        
        emit LoanCreated(loanId, lender, borrower, amount);
        return loanId;
    }

    // ============ PAGOS ============ //
    
    function payEarly(uint256 loanId) external nonReentrant {
        Loan storage loan = loans[loanId];
        require(loan.active, "Loan not active");
        require(loan.borrower == msg.sender, "Not your loan");
        
        // Cálculo simple de pago anticipado
        uint256 daysUsed = (block.timestamp - loan.startTime) / 1 days;
        if (daysUsed == 0) daysUsed = 1;
        
        // Fórmula: solo pagar por días usados (máximo 30 días por defecto)
        uint256 maxDays = 30;
        if (daysUsed > maxDays) daysUsed = maxDays;
        
        uint256 dailyInterest = (loan.totalToPay - loan.amount) / maxDays;
        uint256 realTotal = loan.amount + (dailyInterest * daysUsed);
        uint256 finalPayment = realTotal - loan.totalPaid;
        
        require(finalPayment > 0, "Already paid");
        
        IERC20(loan.stablecoin).transferFrom(msg.sender, address(this), finalPayment);
        
        loan.totalPaid = realTotal;
        loan.installmentsPaid = loan.installments;
        
        _completeLoan(loanId);
        
        emit PaymentMade(loanId, finalPayment);
    }

    /// @notice El owner paga la cuota en nombre del borrower, pero el borrower firma la autorización
    function payInstallmentWithSignature(
        uint256 loanId,
        bytes calldata signature
    ) external onlyOwner nonReentrant {
        Loan storage loan = loans[loanId];
        require(loan.active, "Loan not active");
        require(loan.installmentsPaid < loan.installments, "All paid");

        // Crear hash con los datos relevantes para evitar replay attacks
        bytes32 messageHash = keccak256(
            abi.encodePacked(address(this), loanId, loan.installmentAmount)
        );

        // Recuperar el firmante de la firma
        address signer = recoverSigner(messageHash, signature);
        require(signer == loan.borrower, "Invalid borrower signature");

        // Transferir tokens desde el borrower al contrato (requiere approve previo)
        IERC20(loan.stablecoin).transferFrom(
            loan.borrower,
            address(this),
            loan.installmentAmount
        );

        // Actualizar estado del préstamo
        loan.totalPaid += loan.installmentAmount;
        loan.installmentsPaid++;

        emit PaymentMade(loanId, loan.installmentAmount);

        // Completar préstamo si ya pagó todas
        if (loan.installmentsPaid >= loan.installments) {
            _completeLoan(loanId);
        }
    }

    /// @notice Verifica y recupera la dirección que firmó un mensaje
    function recoverSigner(bytes32 messageHash, bytes memory signature) public pure returns (address) {
        bytes32 ethSignedMessageHash = messageHash.toEthSignedMessageHash();
        return ethSignedMessageHash.recover(signature);
    }

    //--//

    function _completeLoan(uint256 loanId) internal {
        Loan storage loan = loans[loanId];
        loan.active = false;
        
        uint256 lenderAmount = loan.totalPaid - loan.platformFee;
        
        numusToken.mint(loan.lender, lenderAmount);
        
        emit LoanCompleted(loanId);
    }

    // ============ CONSULTAS ============
    
    function getLoan(uint256 loanId) external view returns (Loan memory) {
        return loans[loanId];
    }
    
    function getBalance(address user) external view returns (uint256) {
        return numusToken.balanceOf(user);
    }
    
    function isLender(address user) external view returns (bool) {
        return lenders[user];
    }
    
    function isBorrower(address user) external view returns (bool) {
        return borrowers[user];
    }
    
    // ============ ADMIN ============
    
    function addStablecoin(address token) external onlyOwner {
        stablecoins[token] = true;
    }
    
    function updateFee(uint256 newFee) external onlyOwner {
        require(newFee <= 1000, "Fee too high");
        fee = newFee;
    }
    
    function emergencyWithdraw(address token, uint256 amount) external onlyOwner {
        IERC20(token).transfer(owner(), amount);
    }

}