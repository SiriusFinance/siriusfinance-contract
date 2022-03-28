
const {ethers} = require("hardhat");

async function main() {
  
    const [deployer] = await ethers.getSigners();
    const admin = deployer;
    console.log("deployer:", admin.address);

    let liquidityGaugeAddr = "0xdc83771f234A7F15376943c30Cdb53e028D87746";
    let minterAddr = "0xA7BBEF5480C85D313DB1f1a3F7ef3ffE363dD70F";
    const Minter = await ethers.getContractFactory("Minter");
    const minter = await Minter.attach(minterAddr);
    console.log("Minter deployed to:", minter.address);

    let mintRes = await minter.mint(liquidityGaugeAddr);
    console.log("Mint Res :", mintRes.hash);

}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
