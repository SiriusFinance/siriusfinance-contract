
const {ethers} = require("hardhat");

async function main() {
  
    const [deployer] = await ethers.getSigners();
    const admin = deployer;
    console.log("deployer:", admin.address);

    let srsAddr = "0x97037fc6086AE66d0AA2d445E03CA04A190B7c04";
    const SRS = await ethers.getContractFactory("SRS");
    const srs = await SRS.attach(srsAddr);
    console.log("SRS deployed to:", srs.address);
    
    let minterAddr = "0x1a6FB13B19a1E5c2a225033222269B97295A52cf";
    // let setMinterRes = await srs.setMinter(minterAddr);
    // console.log("Set Minter Res :", setMinterRes.toString());
    let futureRes = await srs.paused();
    console.log("Future Res :", futureRes.toString());

}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
