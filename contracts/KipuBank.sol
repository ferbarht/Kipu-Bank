// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @title KipuBank - Bóveda personal con límite de retiro y depósito global
/// @author Fernando
/// @notice Deposita y retira ETH en bóvedas personales, límites configurados en despliegue
/// @dev Errores personalizados, checks-effects-interactions, transferencia nativa segura, protección básica contra reentrancy

contract KipuBank {
    /*//////////////////////////////////////////////////////////////
                                 ESTADO
    //////////////////////////////////////////////////////////////*/

    /// @notice Límite máximo por retiro por transacción (wei)
    /// @dev Inmutable, fijado en el constructor
    uint256 public immutable withdrawalLimit;
    /// @notice Límite global acumulado de depósitos permitidos en el contrato (wei)
    /// @dev Inmutable, fijado en el constructor
    uint256 public immutable bankCap;
    /// @notice Total acumulado depositado actualmente en el contrato (wei)
    uint256 public totalDeposited;
    /// @notice Saldo de la bóveda por usuario (wei)
    mapping(address => uint256) private vaults;
    /// @notice Contador de depósitos por usuario
    mapping(address => uint256) public depositCount;
    /// @notice Contador de retiros por usuario
    mapping(address => uint256) public withdrawalCount;
    /// @dev Mutex simple para protección contra reentrancy
    uint256 private _locked;

    /*//////////////////////////////////////////////////////////////
                                 EVENTOS
    //////////////////////////////////////////////////////////////*/

    /// @notice Evento emitido cuando un usuario deposita ETH
    /// @param user Dirección del depositante
    /// @param amount Cantidad depositada en wei
    event Deposited(address indexed user, uint256 amount);
    /// @notice Evento emitido cuando un usuario retira ETH
    /// @param user Dirección del que retira
    /// @param amount Cantidad retirada en wei
    event Withdrawn(address indexed user, uint256 amount);

    /*//////////////////////////////////////////////////////////////
                                 ERRORES
    //////////////////////////////////////////////////////////////*/

    /// @notice Se lanza cuando un depósito hace que totalDeposited supere bankCap
    error BankCapExceeded(uint256 attemptedTotal, uint256 bankCap);
    /// @notice Se lanza cuando el monto de retiro excede withdrawalLimit
    error WithdrawalLimitExceeded(uint256 requested, uint256 limit);
    /// @notice Se lanza cuando el usuario no tiene suficiente saldo en su bóveda
    error InsufficientVaultBalance(uint256 requested, uint256 available);
    /// @notice Se lanza cuando la transferencia nativa falla
    error NativeTransferFailed(address to, uint256 amount);
    /// @notice Se lanza cuando se intenta depositar 0 wei
    error ZeroDeposit();
    /// @notice Se lanza cuando se detecta reentrancy
    error Reentrancy();

    /*//////////////////////////////////////////////////////////////
                                MODIFICADORES
    //////////////////////////////////////////////////////////////*/

    /// @notice Valida que el depósito no sea de 0 wei
    /// @dev Previene depósitos nulos que no afectan el estado
    modifier nonZeroDeposit() {
        if (msg.value == 0) revert ZeroDeposit();
        _;
    }

    /// @notice Previene reentrancy en funciones sensibles
    /// @dev Implementa un mutex simple para proteger contra reentrancy
    modifier nonReentrant() {
        if (_locked == 1) revert Reentrancy();
        _locked = 1;
        _;
        _locked = 0;
    }

    /// @notice Valida que el monto solicitado no exceda el límite de retiro
    /// @dev Compara el monto con withdrawalLimit
    /// @param amount Monto solicitado para retiro
    modifier validWithdrawal(uint256 amount) {
        if (amount > withdrawalLimit) revert WithdrawalLimitExceeded(amount, withdrawalLimit);
        _;
    }

    /// @notice Verifica que el usuario tenga saldo suficiente en su bóveda
    /// @dev Compara el monto solicitado con el saldo actual
    /// @param amount Monto solicitado para retiro
    modifier hasSufficientBalance(uint256 amount) {
        uint256 balance = vaults[msg.sender];
        if (amount > balance) revert InsufficientVaultBalance(amount, balance);
        _;
    }

    /// @notice Verifica que el depósito no exceda el límite global del banco
    /// @dev Compara el nuevo total con bankCap
    /// @param amount Monto a depositar
    modifier validDepositCap(uint256 amount) {
        uint256 newTotal = totalDeposited + amount;
        if (newTotal > bankCap) revert BankCapExceeded(newTotal, bankCap);
        _;
    }

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @notice Inicializa los límites del contrato y permite depósito inicial
    /// @param _withdrawalLimit Límite por retiro por transacción en wei
    /// @param _bankCap Límite global total de depósitos en wei
    constructor(uint256 _withdrawalLimit, uint256 _bankCap) payable {
        withdrawalLimit = _withdrawalLimit;
        bankCap = _bankCap;
        _locked = 0;

        if (msg.value > 0) {
            _handleDeposit(msg.sender, msg.value);
        }
    }

    /*//////////////////////////////////////////////////////////////
                             FUNCIONES EXTERNAS
    //////////////////////////////////////////////////////////////*/

    /// @notice Deposita ETH en la bóveda personal del remitente
    /// @dev Checks-Effects-Interactions, emite evento y actualiza contadores
    function deposit()
        external
        payable
        nonZeroDeposit
        nonReentrant
        validDepositCap(msg.value)
    {
        _handleDeposit(msg.sender, msg.value);
    }

    /// @notice Retira ETH de la bóveda del remitente hasta withdrawalLimit
    /// @param amount Monto a retirar en wei
    /// @dev Checks-Effects-Interactions, usa _safeTransfer para la interacción externa
    function withdraw(uint256 amount)
        external
        nonReentrant
        validWithdrawal(amount)
        hasSufficientBalance(amount)
    {
        unchecked {
            vaults[msg.sender] -= amount;
            totalDeposited -= amount;
        }
        withdrawalCount[msg.sender] += 1;
        _safeTransfer(msg.sender, amount);
        emit Withdrawn(msg.sender, amount);
    }

    /*//////////////////////////////////////////////////////////////
                             FUNCIONES DE VISTA
    //////////////////////////////////////////////////////////////*/

    /// @notice Devuelve el saldo de la bóveda del remitente en wei
    /// @return balance Saldo disponible
    function getMyVaultBalance() external view returns (uint256 balance) {
        return vaults[msg.sender];
    }

    /// @notice Devuelve el saldo de la bóveda de una dirección dada en wei
    /// @param user Dirección a consultar
    /// @return balance Saldo disponible
    function getVaultBalanceOf(address user) external view returns (uint256 balance) {
        return vaults[user];
    }

    /*//////////////////////////////////////////////////////////////
                            FUNCIONES INTERNAS
    //////////////////////////////////////////////////////////////*/

    /// @notice Maneja la lógica de depósito en bóveda personal
    /// @dev Actualiza vaults, totalDeposited y contadores, emite evento
    /// @param sender Dirección que realiza el depósito
    /// @param amount Monto depositado en wei
    function _handleDeposit(address sender, uint256 amount) internal {
        unchecked {
            vaults[sender] += amount;
            totalDeposited += amount;
        }
        depositCount[sender] += 1;
        emit Deposited(sender, amount);
    }

    /// @notice Realiza transferencia nativa segura de ETH
    /// @dev Usa call y revierte si falla; evita send/transfer
    /// @param to Dirección receptora
    /// @param amount Monto en wei a transferir
    function _safeTransfer(address to, uint256 amount) private {
        (bool ok, ) = to.call{value: amount}("");
        if (!ok) revert NativeTransferFailed(to, amount);
    }

    /*//////////////////////////////////////////////////////////////
                          RECEIVE / FALLBACK
    //////////////////////////////////////////////////////////////*/

    /// @notice Recibe ETH directo y lo trata como deposit()
    receive()
        external
        payable
        nonZeroDeposit
        nonReentrant
        validDepositCap(msg.value)
    {
        _handleDeposit(msg.sender, msg.value);
    }

    /// @notice Fallback: acepta datos y ETH, si llega ETH se comporta como deposit()
    fallback()
        external
        payable
        nonZeroDeposit
        nonReentrant
        validDepositCap(msg.value)
    {
        _handleDeposit(msg.sender, msg.value);
    }
}
