import { config as dotEnvConfig } from "dotenv";
import { Deployer } from "@matterlabs/hardhat-zksync-deploy";
import { Wallet } from "zksync-ethers";
import { ethers } from "ethers";
import * as hre from "hardhat";

// Before executing a real deployment, be sure to set these values as appropriate for the environment being deploying
// to. The values used in the script at the time of deployment can be checked in along with the deployment artifacts
// produced by running the scripts.
const ADMIN_ACCOUNT = "0xdEADBEeF00000000000000000000000000000000";
const TOKEN_ADDRESS = "0x99E12239CBf8112fBB3f7Fd473d0558031abcbb5";
const TARGET_ADDRESS = "0x99E12239CBf8112fBB3f7Fd473d0558031abcbb5";
const MERKLE_ROOT = "0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef";
const IPFS_HASH = "0xabcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890";
const MINT_AMOUNT = 1000;
const CONTRACT_ABI = [
  "function addMerkleTree(bytes32 merkleRoot, bytes32 ipfsHash, address token, uint256 amount)"
];
const iface = new ethers.Interface(CONTRACT_ABI);
const FUNCTION_SIGNATURE = iface.getSighash("addMerkleTree");
const CALL_DATA = ethers.AbiCoder.defaultAbiCoder().encode(
  ["bytes32", "bytes32", "address", "uint256"],
  [MERKLE_ROOT, IPFS_HASH, TOKEN_ADDRESS, MINT_AMOUNT]
);

async function main() {
  dotEnvConfig();

  const deployerPrivateKey = process.env.DEPLOYER_PRIVATE_KEY;
  if (!deployerPrivateKey) {
    throw "Please set DEPLOYER_PRIVATE_KEY in your .env file";
  }

  const contractName = "ZkMinterModTriggerV1";
  console.log("Deploying " + contractName + "...");

  const zkWallet = new Wallet(deployerPrivateKey);
  const deployer = new Deployer(hre, zkWallet);

  const contract = await deployer.loadArtifact(contractName);
  const constructorArgs = [ADMIN_ACCOUNT, TOKEN_ADDRESS, TARGET_ADDRESS, FUNCTION_SIGNATURE, CALL_DATA];
  const distributor = await deployer.deploy(contract, constructorArgs);

  console.log("constructor args:" + distributor.interface.encodeDeploy(constructorArgs));

  const contractAddress = await distributor.getAddress();
  console.log(`${contractName} was deployed to ${contractAddress}`);

}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
  });
