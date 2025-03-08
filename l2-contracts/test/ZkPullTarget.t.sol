// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/ZkPullTarget.sol";

// Mock ERC20 for testing
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

contract ZkPullTargetTest is Test {
    ZkPullTarget public transferContract;
    MockERC20 public token;
    address public user = address(0x123);

    event TransferProcessed(address indexed sender, uint256 amount);

    function setUp() public {
        token = new MockERC20();
        transferContract = new ZkPullTarget(address(token));

        // Mint some tokens to the user
        token.mint(user, 1000 ether);
    }

    function testExecuteTransferAndLogic() public {
        uint256 amount = 100 ether;

        // User approves the contract
        vm.prank(user);
        token.approve(address(transferContract), amount);

        // Expect the event
        vm.expectEmit(true, false, false, true);
        emit TransferProcessed(user, amount);

        // Call the function as the user
        vm.prank(user);
        transferContract.executeTransferAndLogic(amount);

        // Verify the contract received the tokens
        assertEq(token.balanceOf(address(transferContract)), amount);
        assertEq(token.balanceOf(user), 900 ether); // 1000 - 100
    }

    function testFailNoApproval() public {
        // Call without approval should fail
        vm.prank(user);
        transferContract.executeTransferAndLogic(100 ether);
    }
}