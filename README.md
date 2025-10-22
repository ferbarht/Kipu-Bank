# KipuBank

## Descripción

**KipuBank** es un contrato inteligente en Solidity que permite a cada usuario tener una bóveda personal de ETH con las siguientes características:

- Cada retiro está limitado por un monto máximo (`withdrawalLimit`) definido al momento del despliegue.
- Existe un tope global de depósitos (`bankCap`) que no puede ser superado.
- Cada usuario puede depositar y retirar ETH, y su saldo se guarda en un `mapping` privado.
- El contrato emite eventos por cada depósito y retiro, y lleva contadores individuales (`depositCount`, `withdrawalCount`).
- Se implementan errores personalizados para revertir con información clara.
- Se protege contra reentrancy con un mutex simple (`nonReentrant`).
- Se permite recibir ETH directamente vía `receive()` y `fallback()` reutilizando la lógica de depósito.
- La lógica de depósito está modularizada en `_handleDeposit`, y las transferencias nativas se realizan con `call()` y chequeo de error.
- Se utiliza `unchecked` donde no hay riesgo de overflow/underflow para optimizar gas.
- Las validaciones están encapsuladas en modificadores (`nonZeroDeposit`, `validDepositCap`, etc.) para mayor claridad y reutilización.

---

## Instrucciones de despliegue

### Remix

1. Abrir [Remix](https://remix.ethereum.org) y pegar el contenido de `contracts/KipuBank.sol`.
2. Compilar el contrato con la versión **0.8.30**.
3. En la pestaña **Deploy & Run Transactions**:
   - Seleccionar **Injected Provider - MetaMask**.
   - Estar conectado a la red **Sepolia**.
   - Ingresar los parámetros del constructor:
     - `withdrawalLimit`: por ejemplo `500000000000000000` (0.5 ETH en wei)
     - `bankCap`: por ejemplo `2000000000000000000` (2 ETH en wei)
   - Se pueden enviar ETH en el campo **Value**.
4. Hacer click en **Deploy** y confirmar la transacción en MetaMask.

---

## Cómo interactuar con el contrato

### Funciones principales

- `deposit()`  
  - Función `external payable`.  
  - Enviá ETH en el campo **Value** para depositar en tu bóveda.  
  - Requiere que `msg.value > 0` y que el nuevo total no supere `bankCap`.

- `withdraw(uint256 amount)`  
  - Retira hasta `withdrawalLimit` por transacción.  
  - Requiere que tengas suficiente saldo en tu bóveda.  
  - El monto debe estar en **wei**.

- `getMyVaultBalance()`  
  - Devuelve tu saldo actual en la bóveda.

- `getVaultBalanceOf(address user)`  
  - Devuelve el saldo de otra dirección.

### Interacción directa

- También se puede enviar ETH directamente al contrato (sin llamar a `deposit()`) y se ejecutará la lógica de depósito automáticamente gracias a `receive()` y `fallback()`.

---

## Dirección del contrato desplegado

- Dirección: `0xF47BBB36A1E55517a299D2Aac49dBB4674679114`
- Verificación en Etherscan: [Ver contrato](https://sepolia.etherscan.io/address/0xF47BBB36A1E55517a299D2Aac49dBB4674679114#code)


