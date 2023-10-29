const { ethers, upgrades } = require("hardhat");
const { isAddress } = require("web3-validator");
const {verify} = require("../jshelpers/verifyContract");

const PROXY_ADDRESS = process.argv[2];

async function main() {
  if (!isAddress(PROXY_ADDRESS)) {
    throw new Error("Please pass a valid proxy address. Eg: npm run <SCRIPT> <ADDRESS>");
  }

  // Deploy AvatarContracts first
  const AvatarContracts = await ethers.getContractFactory('AvatarContracts');

  const avatarContracts = await AvatarContracts.deploy();

  await avatarContracts.waitForDeployment();

  await avatarContracts.deploymentTransaction().wait(6);

  const avatarContractsAddress = await avatarContracts.getAddress();

  const NewImplementation = await ethers.getContractFactory('RCAXAvatarSwap', {
    libraries: {
      'AvatarContracts': avatarContractsAddress
    }
  });

  console.log("Upgrading proxy...");

  const upgrade = await upgrades.upgradeProxy(PROXY_ADDRESS, NewImplementation, {});

  await upgrade.waitForDeployment();

  const proxyAddress = await upgrade.getAddress();

  console.log("Proxy updated!");

  // Verify here instead of earlier to give impl contract time to confirm before verifying
  await verify(avatarContractsAddress, []);

  await verify(proxyAddress, []);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
