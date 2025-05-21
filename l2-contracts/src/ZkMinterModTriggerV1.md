# ZkMinterModTriggerV1

## Overview
`ZkMinterModTriggerV1.sol` is a trigger contract designed to work with `ZkCappedMinterV2` for executing arbitrary function calls with minted tokens. It enables gas-efficient batch operations by combining token minting and function execution in a single transaction.

It can be configured to call any target contract and function, making it a flexible tool for various on-chain operations that require prior token minting and approval.

## Key Features
- Integrates with `ZkCappedMinterV2` (or any contract implementing `IZkCappedMinter`) for controlled token minting.
- Executes arbitrary function calls on target contracts.
- Supports dynamic call data and function signatures, configurable at deployment and updatable by an admin.
- Admin-controlled configuration for critical parameters.

## Core Components

### State Variables
- `token`: The `IERC20` token contract that will be minted and used.
- `minter`: The `IZkCappedMinter` contract instance responsible for minting tokens.
- `target`: The address of the contract that `ZkMinterModTriggerV1` will call after minting and approving tokens.
- `admin`: The address with administrative privileges to change configurations.
- `functionSignature`: The 4-byte selector of the function to be called on the `target` contract.
- `callData`: The encoded arguments to be passed to the `target` function call.

## Functions

### `constructor(address _admin, address _tokenAddress, address _targetAddress, bytes memory _functionSignature, bytes memory _callData)`
Initialises the trigger contract with admin, token, target, and call configuration.

### `setMinter(address _minter) external adminOnly`
Updates the minter contract address. Only callable by the `admin`.

### `setTarget(address _target) external adminOnly`
Updates the target contract address. Only callable by the `admin`.

### `setAdmin(address _admin) external adminOnly`
Transfers admin privileges to a new address. Only callable by the current `admin`.

### `setFunctionSignature(bytes calldata _functionSignature) external adminOnly`
Updates the function signature for the target call. Only callable by the `admin`.

### `setCallData(bytes calldata _callData) external adminOnly`
Updates the call data for the target function. Only callable by the `admin`.

### `initiateCall() external`
This is the main function that orchestrates the operation:
1. Determines the amount of tokens available to mint (up to the `minter`'s cap) and mints these tokens from `minter` to itself.
2. Approves the `target` contract to spend the minted tokens.
3. Constructs the `fullCallData` by combining `functionSignature` and `callData`.
4. Executes the call to the `target` contract with `fullCallData`.

## Security Considerations
- **Admin Control**: The `admin` has significant control. Secure the admin key diligently.
- **Target Interaction**: The contract interacts with an external `target`. Ensure the `target` address, `functionSignature`, and `callData` are correctly set and the target contract is audited and secure. A malicious or buggy target could lead to loss of funds or unexpected behavior.
- **Minter Trust**: The `minter` contract must be trusted to mint tokens correctly and securely.
- **Token Contract**: The `token` contract itself should be a standard and secure ERC20 token.

## Integration Example
This contract is often deployed with a specific purpose, for example, to fund a `MerkleDropFactory`.

```solidity
// Example: Setting up to call addMerkleTree on a MerkleDropFactory
address adminAddress = msg.sender;
address tokenAddress = address(myErc20Token);
address merkleDropFactoryAddress = address(myMerkleDropFactory);

bytes4 funcSig = myMerkleDropFactory.addMerkleTree.selector;
bytes memory callArgs = abi.encode(
    bytes32_merkleRoot, 
    bytes32_ipfsHash, 
    tokenAddress, 
    uint256_amountToFund
);

ZkMinterModTriggerV1 trigger = new ZkMinterModTriggerV1(
    adminAddress,
    tokenAddress,
    merkleDropFactoryAddress,
    abi.encodePacked(funcSig), // Note: abi.encodePacked for bytes4 selector
    callArgs
);

// After deployment, set the minter
// Assume zkCappedMinter is already deployed
trigger.setMinter(address(zkCappedMinter));

// Grant MINTER_ROLE to the trigger contract on zkCappedMinter
// zkCappedMinter.grantRole(MINTER_ROLE, address(trigger));

// Now, anyone can call initiateCall on the trigger
// trigger.initiateCall(); 
// This will mint from zkCappedMinter, approve MerkleDropFactory, and call addMerkleTree
```

Refer to `DeployZkMinterModTriggerV1.ts` for a deployment script example.
