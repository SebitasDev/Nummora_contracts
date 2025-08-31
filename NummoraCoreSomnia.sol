// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

interface INUMUSToken {
    function mint(address to, uint256 amount) external;
    function burn(address from, uint256 amount) external;
    function balanceOf(address account) external view returns (uint256);
}

interface ILoanNFT {
    function mint(address to, uint256 tokenId, string memory uri) external;
}

contract NummoraCore is ReentrancyGuard, Ownable {
    //Estructuras
    struct Loan {
        address lender;
        address borrower;
        uint256 amount;
        uint256 totalToPay;
        uint256 totalPaid;
        uint256 startTime;
        uint256 installments;
        uint256 installmentAmount;
        uint256 installmentsPaid;
        bool active;
    }

    INUMUSToken public numusToken;
    ILoanNFT public loanNFT;

    mapping(uint256 => Loan) public loans;
    mapping(address => bool) public lenders;
    mapping(address => bool) public borrowers;

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

    // Modificado para usar STT nativo
    function deposit(uint256 amount) external payable nonReentrant {
        require(lenders[msg.sender], "Not registered");
        require(msg.value == amount, "Amount mismatch");
        
        numusToken.mint(msg.sender, amount);
    }

    // Modificado para usar STT nativo
    function withdraw(uint256 amount) external nonReentrant {
        require(numusToken.balanceOf(msg.sender) >= amount, "Insufficient balance");
        
        numusToken.burn(msg.sender, amount);
        
        // Transfer STT nativo
        (bool success, ) = msg.sender.call{value: amount}("");
        require(success, "Transfer failed");
    }

    // ============ PRÉSTAMOS ============
    
    function createLoan(
        address lender,
        address borrower,
        uint256 amount,
        uint256 interest,
        uint256 installments
    ) external onlyOwner nonReentrant returns (uint256) {
        require(lenders[lender], "Lender not registered");
        require(borrowers[borrower], "Borrower not registered");
        require(numusToken.balanceOf(lender) >= amount, "Insufficient balance");
        
        uint256 loanId = nextLoanId++;
        uint256 totalToPay = amount + interest;
        uint256 installmentAmount = totalToPay / installments;
        
        loans[loanId] = Loan({
            lender: lender,
            borrower: borrower,
            amount: amount,
            totalToPay: totalToPay,
            totalPaid: 0,
            startTime: block.timestamp,
            installments: installments,
            installmentAmount: installmentAmount,
            installmentsPaid: 0,
            active: true
        });
        
        // Transfer funds en STT nativo
        numusToken.burn(lender, amount);
        (bool success, ) = borrower.call{value: amount}("");
        require(success, "Transfer failed");
        
        loanNFT.mint(lender, loanId, "");
        
        emit LoanCreated(loanId, lender, borrower, amount);
        return loanId;
    }

    // Modificado para aceptar STT nativo
    function payInstallment(uint256 loanId) external payable nonReentrant {
        Loan storage loan = loans[loanId];
        require(loan.active, "Loan not active");
        require(loan.borrower == msg.sender, "Not your loan");
        require(loan.installmentsPaid < loan.installments, "All paid");
        require(msg.value == loan.installmentAmount, "Incorrect payment");
        
        loan.totalPaid += loan.installmentAmount;
        loan.installmentsPaid++;
        
        emit PaymentMade(loanId, loan.installmentAmount);
        
        if (loan.installmentsPaid >= loan.installments) {
            _completeLoan(loanId);
        }
    }
    
    // Modificado para aceptar STT nativo
    function payEarly(uint256 loanId) external payable nonReentrant {
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
        require(msg.value == finalPayment, "Incorrect payment");
        
        loan.totalPaid = realTotal;
        loan.installmentsPaid = loan.installments;
        
        _completeLoan(loanId);
        
        emit EarlyPaymentMade(loanId, finalPayment, daysUsed);
    }

    function _completeLoan(uint256 loanId) internal {
        Loan storage loan = loans[loanId];
        loan.active = false;
        
        uint256 interest = loan.totalPaid - loan.amount;
        uint256 platformFee = (interest * fee) / 10000;
        uint256 lenderAmount = loan.totalPaid - platformFee;
        
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
    
    function updateFee(uint256 newFee) external onlyOwner {
        require(newFee <= 1000, "Fee too high");
        fee = newFee;
    }
    
    // Modificado para STT nativo
    function emergencyWithdraw(uint256 amount) external onlyOwner {
        (bool success, ) = owner().call{value: amount}("");
        require(success, "Transfer failed");
    }
    
    // Para recibir STT
    receive() external payable {}
}