
const {ethers} = require("hardhat");

async function main() {
  
    const [deployer] = await ethers.getSigners();
    const admin = deployer;
    console.log("deployer:", admin.address);

    let lpToken = "0x6Cdd1Fc0cc15Dd5538DF649cC4c6e9E5C914c8c1";
    let liquidityGaugeAddr = "0x586A57579CcFa0De42Ac3Eb41bcE08f1aC0811B1";
    const LiquidityGauge = await ethers.getContractFactory("LiquidityGauge");
    const liquidityGauge = await LiquidityGauge.attach(liquidityGaugeAddr);
    console.log("liquidityGauge deployed to:", liquidityGauge.address);

    // let symbolRes = await liquidityGauge.symbol();
    // console.log("Gauge symbol Res :", symbolRes.toString());

    const ERC20 = await ethers.getContractFactory("GenericERC20");
    const token = await ERC20.attach(lpToken);
    console.log("token deployed to:", token.address);

    // let approveRes = await token.approve(liquidityGauge.address, ethers.utils.parseEther("99999999999999999999"));
    // console.log("Approve Res :", approveRes.hash);
    // return;

    // let depositAmount = ethers.utils.parseEther("1900000");
    // let depositRes = await liquidityGauge.deposit(depositAmount, admin.address, false);
    // console.log("Deposit Res :", depositRes.hash);
    // return;

    let claimableTokensRes = await liquidityGauge.claimableTokens(admin.address);
    console.log("ClaimableTokens Res:", claimableTokensRes.toString());

}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
