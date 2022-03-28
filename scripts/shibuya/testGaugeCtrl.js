
const {ethers} = require("hardhat");

async function main() {
  
    const [deployer] = await ethers.getSigners();
    const admin = deployer;
    console.log("deployer:", admin.address);

    let gaugeAddr = "0xE1aE9279D289cFA7eEffdB7cC4a9B8e4Cae83731";
    let gaugeControllerAddr = "0x929ec53d40c21F85bdaCc40B7da509af314C2747";
    const GaugeController = await ethers.getContractFactory("GaugeController");
    const gaugeController = await GaugeController.attach(gaugeControllerAddr);
    console.log("gaugeController deployed to:", gaugeController.address);

    // let addRes = await gaugeController.addType("LiquidityGaugeV4", ethers.utils.parseEther("1"));
    // console.log("Add Type Res:", addRes.hash);

    // let addGaugeRes = await gaugeController.addGauge(gaugeAddr, 0, ethers.utils.parseEther("1"));
    // console.log("Add Gauge Res:", addGaugeRes.hash);

    let getTotalWeightRes = await gaugeController.pointsTypeWeight(0,1647543832);
    console.log("TotalWeight Res :", getTotalWeightRes.toString());
    // return;

    let weightRes = await gaugeController.gaugeRelativeWeight(gaugeAddr, 1648080000);
    console.log("Wieght Res :", weightRes.toString());
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
