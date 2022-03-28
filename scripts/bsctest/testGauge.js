
const {ethers} = require("hardhat");

async function main() {
  
    const [deployer] = await ethers.getSigners();
    const admin = deployer;
    console.log("deployer:", admin.address);

    let lpToken = "0x37bE1DCdf70B836321d9268561B8A9735A69a9c9";
    let liquidityGaugeAddr = "0xb8Da53be02E6E79273687771C11C071b6E470A4b";
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

    // let depositAmount = ethers.utils.parseEther("1900");
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
