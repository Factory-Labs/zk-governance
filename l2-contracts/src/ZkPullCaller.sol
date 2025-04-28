// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "src/interfaces/IERC20.sol";
import "src/interfaces/IZkCappedMinter.sol";

contract ZkPullCaller {
    IERC20 public token;              // The ERC20 token contract
    IZkCappedMinter public minter;    // The ZkCappedMinter for which this project
    address public target;            // The target contract to call
    address public admin;
    bytes public functionSignature;   // The function signature to execute (e.g., function selector)
    bytes public callData;            // The call data for the function

    // Constructor to set the token, target contract, and function signature
    constructor(address _admin, address _tokenAddress, address _targetAddress, bytes memory _functionSignature, bytes memory _callData) {
        token = IERC20(_tokenAddress);
        target = _targetAddress;
        admin = _admin;
        functionSignature = _functionSignature;
        callData = _callData;
    }

    function setMinter(address _minter) external {
        require(msg.sender == admin, "Only admin can call set the minter");
        minter = IZkCappedMinter(_minter);
    }

    // Function to approve and call with arbitrary calldata
    function initiateCall() external {
        // Get this contract's entire token balance
        uint256 available = minter.CAP() - minter.minted();
        require(available > 0, "No tokens available");

        minter.mint(address(this), available);

        // Approve the target contract to spend the entire balance
        require(token.approve(target, available), "Approval failed");

        // Combine function signature with provided callData
        bytes memory fullCallData = abi.encodePacked(functionSignature, callData);
        (bool success, ) = target.call(fullCallData);
        require(success, "Function call failed");
    }
}