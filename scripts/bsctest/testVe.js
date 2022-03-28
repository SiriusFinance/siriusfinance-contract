
const {ethers} = require("hardhat");

async function main() {
  
    const [deployer] = await ethers.getSigners();
    const admin = deployer;
    console.log("deployer:", admin.address);

    let srsAddr = "0xf6c1C296F972999ea6Efb08fb3d84337b137Cb40";
    const SRS = await ethers.getContractFactory("SRS");
    const srs = await SRS.attach(srsAddr);
    console.log("SRS deployed to:", srs.address);

    let veAddr = "0xDC45818DCE0fa6e506cfC4D41Bf0aBbBE63614C1";
    const VotingEscrow = await ethers.getContractFactory("VotingEscrow");
    const ve = await VotingEscrow.attach(veAddr);
    console.log("VotingEscrow deployed to:", ve.address);

    // let approveRes = await srs.approve(ve.address, ethers.utils.parseEther("99999999999999999999"));
    // console.log("Approve Res :", approveRes.hash);
    // return;

    // let userPointEpochRes = await ve.supply();
    // console.log("UserPointEpoch Res :", userPointEpochRes.toString());
    // return;

    // let amount = ethers.utils.parseEther("999");
    // let createLockRes = await ve.createLock(amount, 1679011200);
    // console.log("CreateLock Res:", createLockRes.hash);

    let tokenRes = await ve["balanceOf(address)"]("0x2c45869703bf137050637f1c48d1a0c71e151ac6");
    console.log("Token Res：", tokenRes.toString());
    return;

}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
