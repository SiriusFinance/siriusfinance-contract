
const {ethers} = require("hardhat");

async function main() {
  
    const [deployer] = await ethers.getSigners();
    const admin = deployer;
    console.log("deployer:", admin.address);

    let gaugeAddr = "0x6abeb5388550D23FE4C0DC3ACf7aed473e40895A";
    let gaugeControllerAddr = "0x643FEE5946eC636f9036D7857BaBC370B20fF2b7";
    const GaugeController = await ethers.getContractFactory("GaugeController");
    const gaugeController = await GaugeController.attach(gaugeControllerAddr);
    console.log("gaugeController deployed to:", gaugeController.address);

    // let addRes = await gaugeController.addType("LiquidityGaugeV4", ethers.utils.parseEther("1"));
    // console.log("Add Type Res:", addRes.hash);

    let gaugeRes = await gaugeController.gaugeTypes(gaugeAddr);
    console.log("Gauge Res:", gaugeRes.toString());

    // let getTotalWeightRes = await gaugeController.pointsTypeWeight(0,1647543832);
    // console.log("TotalWeight Res :", getTotalWeightRes.toString());
    // // return;

    // let weightRes = await gaugeController.gaugeRelativeWeight(gaugeAddr, 1648080000);
    // console.log("Wieght Res :", weightRes.toString());

    let listRes = await gaugeController.getGaugeList(0,100);
    console.log("List Res :", listRes);
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
