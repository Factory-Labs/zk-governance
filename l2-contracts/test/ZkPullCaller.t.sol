// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "src/ZkPullCaller.sol";
import "src/ZkPullTarget.sol";
import "src/ZkCappedMinterV2.sol";
import {ZkPullTargetTest} from "./ZkPullTarget.t.sol";

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
}

contract ZkPullCallerTest is Test {
    ZkPullCaller public caller;
    ZkPullTarget public target;
    MockERC20 public token;
    address public user = address(0x123);

    event TransferProcessed(address indexed sender, uint256 amount);

    function setUp() public virtual {
        token = new MockERC20();
        target = new ZkPullTarget(address(token));

        // Deploy GenericCaller with the function signature for executeTransferAndLogic
        bytes memory sig = abi.encodeWithSignature("executeTransferAndLogic(uint256)");
        bytes memory callData = abi.encode(uint256(500 ether)); // Fixed amount baked in
        caller = new ZkPullCaller(address(token), address(target), sig, callData);

    }

    function testInitiateCallFullBalance() public {
        // Mint tokens to the caller contract
        token.mint(address(caller), 500 ether);

        uint256 initialBalance = token.balanceOf(address(caller));
        assertEq(initialBalance, 500 ether);

        // Expect the event from TransferAndLogic
        vm.expectEmit(true, false, false, true, address(target));
        emit TransferProcessed(address(caller), 500 ether);

        // Call initiateCall as the user (though caller uses its own balance)
        vm.prank(user);
        caller.initiateCall();

        // Verify tokens were transferred to the target
        assertEq(token.balanceOf(address(caller)), 0);
        assertEq(token.balanceOf(address(target)), 500 ether);

        // Verify allowance was set and consumed
        assertEq(token.allowance(address(caller), address(target)), 0);
    }

    function testFailInsufficientBalance() public {
        // Mint tokens to the caller contract
        token.mint(address(caller), 500 ether);

        // Deploy a new caller with insufficient tokens
        bytes memory sig = abi.encodeWithSignature("executeTransferAndLogic(uint256)");
        bytes memory callData = abi.encode(uint256(200 ether));
        ZkPullCaller lowBalanceCaller = new ZkPullCaller(address(token), address(target), sig, callData);

        // Mint less than the required amount
        token.mint(address(lowBalanceCaller), 100 ether);

        // Should revert due to insufficient balance
        vm.prank(user);
        vm.expectRevert("Insufficient balance");
        lowBalanceCaller.initiateCall();
    }

    function testCallWithCustomCallData() public {
        // Mint tokens to the caller contract
        token.mint(address(caller), 500 ether);

        // Deploy a new caller with custom callData including a different amount
        bytes memory sig = abi.encodeWithSignature("executeTransferAndLogic(uint256)");
        bytes memory customCallData = abi.encode(uint256(300 ether));
        ZkPullCaller customCaller = new ZkPullCaller(address(token), address(target), sig, customCallData);

        // Mint tokens to the new caller
        token.mint(address(customCaller), 300 ether);

        // Expect the event with the fixed amount from callData
        vm.expectEmit(true, false, false, true, address(target));
        emit TransferProcessed(address(customCaller), 300 ether);

        // Call initiateCall
        vm.prank(user);
        customCaller.initiateCall();

        // Verify token transfer
        assertEq(token.balanceOf(address(customCaller)), 0);
        assertEq(token.balanceOf(address(target)), 300 ether);
    }
}

contract MintFromZkCappedMinter is ZkPullCallerTest {
    ZkCappedMinterV2 public cappedMinter;
    address cappedMinterAdmin = makeAddr("cappedMinterAdmin");
    bytes32 constant MINTER_ROLE = keccak256("MINTER_ROLE");

    function setUp() public virtual override {
        // Call parent setUp first
        super.setUp();

        // Setup ZkCappedMinterV2
        uint48 startTime = uint48(block.timestamp);
        uint48 expirationTime = uint48(startTime + 3 days);
        uint256 cap = 100_000_000e18;

        cappedMinter = new ZkCappedMinterV2(
            IMintable(address(token)), // Assuming MockERC20 is compatible with IMintable
            cappedMinterAdmin,
            cap,
            startTime,
            expirationTime
        );
    }

    function testMintFromCappedMinterAndInitiateCall() public {
        // Mint tokens to ZkPullCaller via ZkCappedMinterV2
        uint256 mintAmount = 500 ether; // Enough to cover the 100 ether in callData
        address minter = makeAddr("minter");

        // Grant MINTER_ROLE to minter on cappedMinter
        vm.prank(cappedMinterAdmin);
        cappedMinter.grantRole(MINTER_ROLE, minter);

        // Mint tokens to caller
        vm.prank(minter);
        cappedMinter.mint(address(caller), mintAmount);

        // Verify initial state
        assertEq(token.balanceOf(address(caller)), mintAmount);
        assertEq(token.balanceOf(address(target)), 0);

        // Expect the TransferProcessed event with the fixed amount
        vm.expectEmit(true, false, false, true, address(target));
        emit TransferProcessed(address(caller), 500 ether);

        // Execute the initiateCall flow
        vm.prank(user);
        caller.initiateCall();

        // Verify final state
        assertEq(token.balanceOf(address(caller)), 0); // 200 - 100 = 100 ether
        assertEq(token.balanceOf(address(target)), 500 ether);
        assertEq(token.allowance(address(caller), address(target)), 0);
    }
}