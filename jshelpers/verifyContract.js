const hre = require("hardhat");

const verify = async (contractAddress, args) => {
    console.log("Verifying contract:", contractAddress);

    try {
        await hre.run("verify:verify", {
            address: contractAddress,
            constructorArguments: args,
        });
        console.log("Contract verified!");
    } catch (e) {
        if (e.message.toLowerCase().includes("already verified")) {
            console.log("Already verified!");
        } else {
            throw e;
        }
    }
}

module.exports = { verify }
