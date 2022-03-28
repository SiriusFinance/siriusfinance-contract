const {ethers} = require("hardhat");

async function main() {
  
    const [deployer] = await ethers.getSigners();
    const admin = deployer;
    console.log("deployer:", admin.address);
    let poolAddr = "0xb26Ca3a7858dBfeCe00D42d8d8ddA3307707e3b1";
    let swapUtilsAddr = "0x9628B9E1a48Dc573e857D6c8b0aFB0c4965B29aA";
    let amplificationUtilsAddr = "0x41F9D7f04598a3C8858A5e0B530733E7465A62B4";

    const Swap = await ethers.getContractFactory("Swap", {
        libraries: {
            AmplificationUtils: amplificationUtilsAddr,
            SwapUtils: swapUtilsAddr
        }
    });
    const swap = await Swap.attach(poolAddr);
    console.log("Swap deployed to:", swap.address);

    // let getARes = await swap.getA();
    // console.log("GetA Res:", getARes.toString());
    // return;

    
    let daiAddr = "0xC4195CE9383eA77aED21bd662ecad10a935Ed459";
    let usdcAddr = "0x37B76d58FAFc3Bc32E12E2e720F7a57Fc94bE871";
    let usdtAddr = "0xa4C17AD6bEC86e1233499A9B174D1E2D466c7198";

    const ERC20 = await ethers.getContractFactory("GenericERC20");
    const token = await ERC20.attach(usdcAddr);
    console.log("token deployed to:", token.address);

    // let approveRes = await token.approve(swap.address, ethers.utils.parseEther("99999999999999999999"));
    // console.log("Approve Res :", approveRes.hash);
    // return;

    // let allowRes = await token.allowance(admin.address, swap.address);
    // console.log("Allow Res :", allowRes.toString());
    // return;
    
    // let addAmount = [
    //     ethers.utils.parseEther("1000000000"),
    //     ethers.utils.parseUnits("1000000000", 6),
    //     ethers.utils.parseUnits("1000000000", 6)
    // ];

    // let tokenAmountRes = await swap.calculateTokenAmount(addAmount, true);
    // console.log("Token Amount :", tokenAmountRes.toString());
    // return;
    let swapRes = await swap.swap(0, 1, ethers.utils.parseEther("10"), 0, 4801993200);
    console.log("Swap res :", swapRes.hash);
    return;

    // let depositRes = await swap.addLiquidity(addAmount, 0, 4801993200);

    // console.log("Deposit Res :" + depositRes.hash);


}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
