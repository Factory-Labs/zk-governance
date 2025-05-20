# ZkMinterModTriggerV1 Test Suite (`ZkMinterModTriggerV1.t.sol`)

## Overview
This test suite, written using Foundry, verifies the functionality of the `ZkMinterModTriggerV1` contract. It covers its core logic, administrative functions, and interactions with mock and example contracts, including `ZkMinterModTargetExampleV1`, `MockERC20`, `ZkCappedMinterV2`, and `MerkleDropFactory`.

## Test Contracts and Setup

### `MockERC20`
A simple ERC20 token implementation for testing purposes, allowing minting, approving, and transferring tokens.

### `ZkMinterModTriggerV1Test` (Base Contract)
This contract sets up the common testing environment:
- Deploys `MockERC20`.
- Deploys `ZkMinterModTargetExampleV1` (as the `target`).
- Deploys `ZkMinterModTriggerV1` (as `trigger`) configured to call `executeTransferAndLogic(uint256)` on the `target` with a fixed amount (500 ether).
- Deploys `ZkCappedMinterV2` (as `cappedMinter`) and configures it:
    - Sets the `trigger` contract as a minter on `cappedMinter` by granting `MINTER_ROLE`.
    - Sets `cappedMinter` as the minter for the `trigger` contract.
- Defines a `user` address for emulating external calls.

### `MintFromZkCappedMinter` (Inherits `ZkMinterModTriggerV1Test`)
This contract focuses on tests specifically involving the minting process from `ZkCappedMinterV2` via `ZkMinterModTriggerV1`.

### `MerkleTargetTest`
This contract tests the scenario where `ZkMinterModTriggerV1` is configured to interact with a `MerkleDropFactory` contract. It sets up:
- `MockERC20`
- `MerkleDropFactory` (as the `target`).
- `ZkMinterModTriggerV1` (as `caller`) configured to call `addMerkleTree(...)` on the `MerkleDropFactory`.
- `ZkCappedMinterV2` (as `cappedMinter`), with the `caller` granted `MINTER_ROLE`.

## Key Test Scenarios

### In `ZkMinterModTriggerV1Test` & `MintFromZkCappedMinter`:
- **`testInitiateCallFullBalance()` / `testMintFromCappedMinterAndInitiateCall()`**: 
    - Verifies that `initiateCall()` successfully mints tokens from `cappedMinter`, approves the `target` (`ZkMinterModTargetExampleV1`), and calls `executeTransferAndLogic` on it.
    - Checks that tokens are transferred correctly to the `target`.
    - Confirms event emission (`TransferProcessed`).
- **`testFailInsufficientBalance()` (Illustrative, may need context adjustment)**:
    - This test, as originally written, seems to test a scenario where the *trigger contract itself* has a balance, which is not the primary flow when using `ZkCappedMinterV2`. The primary flow is that `ZkMinterModTriggerV1` mints *new* tokens from `ZkCappedMinterV2`. A more relevant test for insufficient balance would be if `ZkCappedMinterV2` cannot mint the requested amount (e.g., cap reached).
- **`testCallWithCustomCallData()`**: 
    - Reinforces that `initiateCall` uses the `callData` configured in the `trigger`'s constructor or set by an admin.

### In `MerkleTargetTest`:
- **`testAddMerkleTreeViaCaller()`**: 
    - Verifies that `initiateCall()` on the `caller` (a `ZkMinterModTriggerV1` instance) successfully mints tokens, approves the `MerkleDropFactory` (`target`), and calls `addMerkleTree` on it.
    - Checks that the `MerkleDropFactory` has the tokens and the Merkle tree is added.
    - Confirms event emission (`MerkleTreeAdded`).

## Running the Tests
To execute these tests, use the Foundry command line tool:
```bash
forge test --match-path test/ZkMinterModTriggerV1.t.sol -vvv
```

## Test Coverage Highlights
- Core `initiateCall()` logic: minting, approval, and target call.
- Integration with `ZkCappedMinterV2` for minting.
- Interaction with different target contracts (`ZkMinterModTargetExampleV1`, `MerkleDropFactory`).
- Correct handling of call data and function signatures.
- Event emissions.

## Dependencies
- [Forge Standard Library (forge-std)](https://github.com/foundry-rs/forge-std)
- Project's own contracts (`ZkMinterModTriggerV1`, `ZkMinterModTargetExampleV1`, `MerkleDropFactory`, `ZkCappedMinterV2`).
