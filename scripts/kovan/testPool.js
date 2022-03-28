const {ethers} = require("hardhat");

async function main() {
  
    const [deployer] = await ethers.getSigners();
    const admin = deployer;
    console.log("deployer:", admin.address);
    let poolAddr = "0x9880647f5f0fd73b1E9CB9D24B23401d5264082d";
    let swapUtilsAddr = "0x4883ADe74901734a1a452E9D01Ba643fF2340e0c";
    let amplificationUtilsAddr = "0xd4d2eA65e0489904c718D1F73270D67dd676e0Fb";

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

    
    let daiAddr = "0x417E9d065ee22DFB7CC6C63C403600E27627F333";
    let usdcAddr = "0xd87a1DC37616392c57EcdB5131789d001c520D72";
    let usdtAddr = "0xA7287deD495DEb246C3A49916a948B551B619D65";

    const ERC20 = await ethers.getContractFactory("GenericERC20");
    const token = await ERC20.attach(daiAddr);
    console.log("token deployed to:", token.address);

    // let approveRes = await token.approve(swap.address, ethers.utils.parseEther("99999999999999999999"));
    // console.log("Approve Res :", approveRes.hash);
    // return;

    // let allowRes = await token.allowance(admin.address, swap.address);
    // console.log("Allow Res :", allowRes.toString());
    // return;
    
    let addAmount = [
        ethers.utils.parseEther("1000000000"),
        ethers.utils.parseUnits("1000000000", 6),
        ethers.utils.parseUnits("1000000000", 6)
    ];

    // let tokenAmountRes = await swap.calculateTokenAmount(addAmount, true);
    // console.log("Token Amount :", tokenAmountRes.toString());
    // return;

    // let depositRes = await swap.addLiquidity(addAmount, 0, 4801993200);

    // console.log("Deposit Res :" + depositRes.hash);


}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
