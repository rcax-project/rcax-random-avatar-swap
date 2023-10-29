require("@nomicfoundation/hardhat-toolbox");
require("@openzeppelin/hardhat-upgrades");
require('dotenv').config();

module.exports = {
  solidity: {
    compilers: [
      {
        version: '0.8.21',
        settings: {
          optimizer: {
            enabled: false,
            runs: 200
          },
          evmVersion: 'paris'
        }
      },
    ],
  },
  networks: {
    polygon: {
      url: process.env.POLYGON_RPC,
      // @ts-ignore
      accounts: [process.env.POLYGON_PRIVATE_KEY],
    },
    mumbai: {
      url: process.env.MUMBAI_RPC,
      // @ts-ignore
      accounts: [process.env.MUMBAI_PRIVATE_KEY],
    },
  },
  etherscan: {
    apiKey: process.env.ETHERSCAN_API_KEY,
  },
}
