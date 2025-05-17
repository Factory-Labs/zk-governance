// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "src/ZkMinterModTriggerV1.sol";
import "src/ZkMinterModTargetExampleV1.sol";
import "src/MerkleDropFactory.sol";
import "src/ZkCappedMinterV2.sol";

contract MockERC20 is Test {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        require(allowance[from][msg.sender] >= amount, "Insufficient allowance");
        require(balanceOf[from] >= amount, "Insufficient balance");
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        require(balanceOf[msg.sender] >= amount, "Insufficient balance");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }
}

contract ZkMinterModTriggerV1Test is Test {
    ZkMinterModTriggerV1 public trigger;
    ZkMinterModTargetExampleV1 public target;
    MockERC20 public token;
    address public user = address(0x123);

    ZkCappedMinterV2 public cappedMinter;
    address cappedMinterAdmin = makeAddr("cappedMinterAdmin");
    bytes32 constant MINTER_ROLE = keccak256("MINTER_ROLE");


    event TransferProcessed(address indexed sender, uint256 amount);

    function setUp() public virtual {
        token = new MockERC20();
        target = new ZkMinterModTargetExampleV1(address(token));

        // Deploy GenericCaller with the function signature for executeTransferAndLogic
        bytes memory sig = abi.encodeWithSignature("executeTransferAndLogic(uint256)");
        bytes memory callData = abi.encode(uint256(500 ether)); // Fixed amount baked in
        trigger = new ZkMinterModTriggerV1(cappedMinterAdmin, address(token), address(target), sig, callData);

        // Setup ZkCappedMinterV2
        uint48 startTime = uint48(block.timestamp);
        uint48 expirationTime = uint48(startTime + 3 days);
        uint256 cap = 500e18;

        cappedMinter = new ZkCappedMinterV2(
            IMintable(address(token)), // Assuming MockERC20 is compatible with IMintable
            cappedMinterAdmin,
            cap,
            startTime,
            expirationTime
        );
        vm.prank(cappedMinterAdmin);
        trigger.setMinter(address(cappedMinter));
        vm.prank(cappedMinterAdmin);
        cappedMinter.grantRole(MINTER_ROLE, address(trigger));
    }

    function testInitiateCallFullBalance() public {
        uint256 initialBalance = token.balanceOf(address(trigger));
        assertEq(initialBalance, 0);

        // Expect the event from TransferAndLogic
        vm.expectEmit(true, false, false, true, address(target));
        emit TransferProcessed(address(trigger), 500 ether);

        // Call initiateCall as the user (though caller uses its own balance)
        vm.prank(user);
        trigger.initiateCall();

        // Verify tokens were transferred to the target
        assertEq(token.balanceOf(address(trigger)), 0);
        assertEq(token.balanceOf(address(target)), 500 ether);

        // Verify allowance was set and consumed
        assertEq(token.allowance(address(trigger), address(target)), 0);
    }

    function testFailInsufficientBalance() public {
        // Mint tokens to the caller contract
        token.mint(address(trigger), 500 ether);

        // Deploy a new caller with insufficient tokens
        bytes memory sig = abi.encodeWithSignature("executeTransferAndLogic(uint256)");
        bytes memory callData = abi.encode(uint256(200 ether));
        ZkMinterModTriggerV1 lowBalanceCaller = new ZkMinterModTriggerV1(cappedMinterAdmin, address(token), address(target), sig, callData);

        // Mint less than the required amount
        token.mint(address(lowBalanceCaller), 100 ether);

        // Should revert due to insufficient balance
        vm.prank(user);
        vm.expectRevert("Insufficient balance");
        lowBalanceCaller.initiateCall();
    }

    function testCallWithCustomCallData() public {
        // Expect the event with the fixed amount from callData
        vm.expectEmit(true, false, false, true, address(target));
        emit TransferProcessed(address(trigger), 500 ether);

        // Call initiateCall
        vm.prank(user);
        trigger.initiateCall();

        // Verify token transfer
        assertEq(token.balanceOf(address(trigger)), 0);
        assertEq(token.balanceOf(address(target)), 500 ether);
    }
}

contract MintFromZkCappedMinter is ZkMinterModTriggerV1Test {

    function setUp() public virtual override {
        // Call parent setUp first
        super.setUp();

    }

    function testMintFromCappedMinterAndInitiateCall() public {
        // Verify initial state
        assertEq(token.balanceOf(address(trigger)), 0);
        assertEq(token.balanceOf(address(target)), 0);

        // Expect the TransferProcessed event with the fixed amount
        vm.expectEmit(true, false, false, true, address(target));
        emit TransferProcessed(address(trigger), 500 ether);

        // Execute the initiateCall flow
        vm.prank(user);
        trigger.initiateCall();

        // Verify final state
        assertEq(token.balanceOf(address(trigger)), 0);
        assertEq(token.balanceOf(address(target)), 500 ether);
        assertEq(token.allowance(address(trigger), address(target)), 0);
    }
}

contract MerkleTargetTest is Test {
    ZkMinterModTriggerV1 public caller;
    MerkleDropFactory public target;
    MockERC20 public token;
    address public user = address(0x123);
    ZkCappedMinterV2 public cappedMinter;
    address cappedMinterAdmin = makeAddr("cappedMinterAdmin");
    bytes32 constant MINTER_ROLE = keccak256("MINTER_ROLE");

    event WithdrawalOccurred(uint indexed treeIndex, address indexed destination, uint value);

    function setUp() public virtual {
        token = new MockERC20();
        target = new MerkleDropFactory();

        // Setup Merkle tree
        uint256 withdrawAmount = 500 ether;
        address destination = address(0x456); // Where tokens will go
        bytes32 leaf = keccak256(abi.encode(destination, withdrawAmount));
        bytes32 merkleRoot = leaf; // Simplest tree: root = leaf (single entry)
        bytes32 ipfsHash = keccak256("ipfs data");

        // Deploy ZkMinterModTriggerV1 with the function signature for addMerkleTree
        bytes memory sig = abi.encodeWithSignature("addMerkleTree(bytes32,bytes32,address,uint256)");
        bytes memory callData = abi.encode(merkleRoot, ipfsHash, address(token), uint256(500 ether));
        caller = new ZkMinterModTriggerV1(cappedMinterAdmin, address(token), address(target), sig, callData);

        // Setup ZkCappedMinterV2
        uint48 startTime = uint48(block.timestamp);
        uint48 expirationTime = uint48(startTime + 3 days);
        uint256 cap = 500e18;

        cappedMinter = new ZkCappedMinterV2(
            IMintable(address(token)), // Assuming MockERC20 is compatible with IMintable
            cappedMinterAdmin,
            cap,
            startTime,
            expirationTime
        );

        vm.prank(cappedMinterAdmin);
        caller.setMinter(address(cappedMinter));
        vm.prank(cappedMinterAdmin);
        cappedMinter.grantRole(MINTER_ROLE, address(caller));
    }

    function testMintFromCappedMinterAndWithdrawFromMerkleDrop() public {
        // Setup Merkle tree
        uint256 withdrawAmount = 500 ether;
        address destination = address(0x456); // Where tokens will go
        bytes32 leaf = keccak256(abi.encode(destination, withdrawAmount));
        bytes32 merkleRoot = leaf; // Simplest tree: root = leaf (single entry)
        bytes32 ipfsHash = keccak256("ipfs data");

        // Verify initial state
        assertEq(token.balanceOf(address(caller)), 0 ether);
        assertEq(token.balanceOf(address(target)), 0);
        assertEq(token.balanceOf(destination), 0);

        vm.prank(user);
        caller.initiateCall();

        assertEq(token.balanceOf(address(caller)), 0 ether);
        assertEq(token.balanceOf(address(target)), 500 ether);
        assertEq(token.balanceOf(destination), 0 ether);

        // Verify tree setup
        (bytes32 merkleRoot1, bytes32 ipfsHash1, address tokenAddress1, uint tokenBalance1, uint spentTokens1) = target.merkleTrees(1);

        assertEq(merkleRoot1, merkleRoot);
        assertEq(ipfsHash1, ipfsHash);
        assertEq(tokenAddress1, address(token));
        assertEq(tokenBalance1, 500 ether);
        assertEq(spentTokens1, 0);

        // Expect the WithdrawalOccurred event
        vm.expectEmit(true, true, false, true, address(target));
        emit WithdrawalOccurred(1, destination, withdrawAmount);

        bytes32[] memory proof = new bytes32[](0);
        target.withdraw(1, destination, 500 ether, proof);


        assertEq(token.balanceOf(address(caller)), 0 ether);
        assertEq(token.balanceOf(address(target)), 0 ether);
        assertEq(token.balanceOf(destination), 500 ether);

        {
            (bytes32 merkleRoot2, bytes32 ipfsHash2, address tokenAddress2, uint tokenBalance2, uint spentTokens2) = target.merkleTrees(1);
            assertEq(merkleRoot2, merkleRoot);
            assertEq(ipfsHash2, ipfsHash);
            assertEq(tokenAddress2, address(token));
            assertEq(tokenBalance2, 0);
            assertEq(spentTokens2, 500 ether);
        }
        assertTrue(target.getWithdrawn(1, leaf));
    }
}