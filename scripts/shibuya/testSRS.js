
const {ethers} = require("hardhat");

async function main() {
  
    const [deployer] = await ethers.getSigners();
    const admin = deployer;
    console.log("deployer:", admin.address);

    let srsAddr = "0x41F9D7f04598a3C8858A5e0B530733E7465A62B4";
    const SRS = await ethers.getContractFactory("SRS");
    const srs = await SRS.attach(srsAddr);
    console.log("SRS deployed to:", srs.address);

    let rate = await srs.startEpochTime();
    console.log("Rate Res :", rate.toString());
    let futureRes = await srs.futureEpochTimeWrite();
    console.log("Future Res :", futureRes.hash);

}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
