// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

// @title KipuBank - Bóveda personal con límite de retiro y depósito global
// @author Fernando
// @notice Deposita y retira ETH en bóvedas personales; límites configurados en despliegue
// @dev Errores personalizados, checks-effects-interactions, transferencia nativa segura, protección básica contra reentrancy
contract KipuBank {
    /*//////////////////////////////////////////////////////////////
                                 ESTADO
    //////////////////////////////////////////////////////////////*/

    // @notice Límite máximo por retiro por transacción (wei)
    // @dev Inmutable, fijado en el constructor
    uint256 public immutable withdrawalLimit; 
    // @notice Límite global acumulado de depósitos permitidos en el contrato (wei)
    // @dev Inmutable, fijado en el constructor
    uint256 public immutable bankCap; 
    // @notice Total acumulado depositado actualmente en el contrato (wei)
    uint256 public totalDeposited; 
    /// @notice Saldo de la bóveda por usuario (wei)
    mapping(address => uint256) private vaults; 
    // @notice Contador de depósitos por usuario
    mapping(address => uint256) public depositCount; 
    // @notice Contador de retiros por usuario
    mapping(address => uint256) public withdrawalCount; 
    // @dev Mutex simple para protección contra reentrancy
    uint256 private _locked; 

    /*//////////////////////////////////////////////////////////////
                                 EVENTOS
    //////////////////////////////////////////////////////////////*/

    // @notice Evento emitido cuando un usuario deposita ETH
    // @param user Dirección del depositante
    // @param amount Cantidad depositada en wei
    event Deposited(address indexed user, uint256 amount); 
    // @notice Evento emitido cuando un usuario retira ETH
    // @param user Dirección del que retira
    // @param amount Cantidad retirada en wei
    event Withdrawn(address indexed user, uint256 amount); 

    /*//////////////////////////////////////////////////////////////
                                 ERRORES
    //////////////////////////////////////////////////////////////*/

    // @notice Se lanza cuando un depósito hace que totalDeposited supere bankCap
    error BankCapExceeded(uint256 attemptedTotal, uint256 bankCap); 
    // @notice Se lanza cuando el monto de retiro excede withdrawalLimit
    error WithdrawalLimitExceeded(uint256 requested, uint256 limit); 
    // @notice Se lanza cuando el usuario no tiene suficiente saldo en su bóveda
    error InsufficientVaultBalance(uint256 requested, uint256 available); 
    // @notice Se lanza cuando la transferencia nativa falla
    error NativeTransferFailed(address to, uint256 amount); 
    // @notice Se lanza cuando se intenta depositar 0 wei
    error ZeroDeposit(); 
    // @notice Se lanza cuando se detecta reentrancy
    error Reentrancy(); 

    /*//////////////////////////////////////////////////////////////
                                MODIFICADORES
    //////////////////////////////////////////////////////////////*/

    // @dev Valida que msg.value > 0 para funciones de depósito
    modifier nonZeroDeposit() {
        if (msg.value == 0) revert ZeroDeposit();
        _;
    }

    // @dev Mutex para prevenir reentrancy
    modifier nonReentrant() {
        if (_locked == 1) revert Reentrancy();
        _locked = 1;
        _;
        _locked = 0;
    }

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    // @param _withdrawalLimit Límite por retiro por transacción en wei
    // @param _bankCap Límite global total de depósitos en wei
    // ¡CORRECCIÓN APLICADA AQUÍ! Se añade 'payable'.
    constructor(uint256 _withdrawalLimit, uint256 _bankCap) payable {
        withdrawalLimit = _withdrawalLimit;
        bankCap = _bankCap;
        _locked = 0;

        // Si se envió ETH al constructor, se trata como un depósito inicial del desplegador
        if (msg.value > 0) {
            uint256 newTotal = totalDeposited + msg.value;
            if (newTotal > bankCap) revert BankCapExceeded(newTotal, bankCap);

            // Se suma al saldo personal del desplegador
            vaults[msg.sender] += msg.value;
            totalDeposited = newTotal;
            depositCount[msg.sender] += 1;
            
            // Opcional: emitir un evento por el depósito inicial
            emit Deposited(msg.sender, msg.value);
        }
    }

    /*//////////////////////////////////////////////////////////////
                             FUNCIONES EXTERNAS
    //////////////////////////////////////////////////////////////*/

    // @notice Deposita ETH en la bóveda personal del remitente
    // @dev Checks-Effects-Interactions; emite evento y actualiza contadores
    function deposit() external payable nonZeroDeposit nonReentrant {
        uint256 newTotal = totalDeposited + msg.value;
        if (newTotal > bankCap) revert BankCapExceeded(newTotal, bankCap);

        vaults[msg.sender] += msg.value;
        totalDeposited = newTotal;
        depositCount[msg.sender] += 1;

        emit Deposited(msg.sender, msg.value);
    }

    // @notice Retira ETH de la bóveda del remitente hasta withdrawalLimit
    // @param amount Monto a retirar en wei
    // @dev Checks-Effects-Interactions; usa _safeTransfer para la interacción externa
    function withdraw(uint256 amount) external nonReentrant {
        if (amount > withdrawalLimit) revert WithdrawalLimitExceeded(amount, withdrawalLimit);
        uint256 userBalance = vaults[msg.sender];
        if (amount > userBalance) revert InsufficientVaultBalance(amount, userBalance);

        vaults[msg.sender] = userBalance - amount;
        withdrawalCount[msg.sender] += 1;
        totalDeposited -= amount;

        _safeTransfer(msg.sender, amount);

        emit Withdrawn(msg.sender, amount);
    }

    /*//////////////////////////////////////////////////////////////
                             FUNCIONES DE VISTA
    //////////////////////////////////////////////////////////////*/

    // @notice Devuelve el saldo de la bóveda del remitente en wei
    // @return balance Saldo disponible
    function getMyVaultBalance() external view returns (uint256 balance) {
        return vaults[msg.sender]; 
    }

    // @notice Devuelve el saldo de la bóveda de una dirección dada en wei
    // @param user Dirección a consultar
    // @return balance Saldo disponible
    function getVaultBalanceOf(address user) external view returns (uint256 balance) {
        return vaults[user]; 
    }

    /*//////////////////////////////////////////////////////////////
                            FUNCIONES PRIVADAS
    //////////////////////////////////////////////////////////////*/

    // @dev Transferencia nativa segura usando call; revierte con error personalizado si falla
    // @param to Dirección receptora
    // @param amount Monto en wei a transferir
    function _safeTransfer(address to, uint256 amount) private {
        (bool ok, ) = to.call{value: amount}(""); 
        if (!ok) revert NativeTransferFailed(to, amount);
    }

    /*//////////////////////////////////////////////////////////////
                          RECEIVE / FALLBACK
    //////////////////////////////////////////////////////////////*/

    // @notice Recibe ETH directo y lo trata como deposit()
    receive() external payable nonZeroDeposit nonReentrant {
        uint256 newTotal = totalDeposited + msg.value; 
        if (newTotal > bankCap) revert BankCapExceeded(newTotal, bankCap);

        vaults[msg.sender] += msg.value;
        totalDeposited = newTotal;
        depositCount[msg.sender] += 1;

        emit Deposited(msg.sender, msg.value); 
    }

    // @notice Fallback: acepta datos y ETH; si llega ETH se comporta como deposit()
    fallback() external payable nonZeroDeposit nonReentrant {
        uint256 newTotal = totalDeposited + msg.value; 
        if (newTotal > bankCap) revert BankCapExceeded(newTotal, bankCap);

        vaults[msg.sender] += msg.value;
        totalDeposited = newTotal;
        depositCount[msg.sender] += 1;

        emit Deposited(msg.sender, msg.value);
    }
}
