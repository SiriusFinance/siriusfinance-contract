
const {ethers} = require("hardhat");

async function main() {
  
    const [deployer] = await ethers.getSigners();
    const admin = deployer;
    console.log("deployer:", admin.address);

    let liquidityGaugeAddr = "0xb8Da53be02E6E79273687771C11C071b6E470A4b";
    let minterAddr = "0x91DDE0801Fde0Bf2D5Cb74EEdcBAe8555762b3AA";
    const Minter = await ethers.getContractFactory("Minter");
    const minter = await Minter.attach(minterAddr);
    console.log("Minter deployed to:", minter.address);

    let srsAddrRes = await minter.token();
    console.log("SRS Res :", srsAddrRes.toString());
    // return;
    let mintRes = await minter.mint(liquidityGaugeAddr);
    console.log("Mint Res :", mintRes.hash);

}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
