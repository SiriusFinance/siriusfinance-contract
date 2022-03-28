const {ethers} = require("hardhat");

async function main() {
  
    const [deployer] = await ethers.getSigners();
    const admin = deployer;
    console.log("deployer:", admin.address);
    let poolAddr = "0xEfb7F918b902de86AB022a5330A99c678894779A";
    let swapUtilsAddr = "0xa1Ee9E2F4295A073774647eBe0e47dAB2EfF28E6";
    let amplificationUtilsAddr = "0x16C2787Bf5D1d9bbe82544980D75939706b85Bd9";

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

    
    let daiAddr = "0xfc7aF6Cd95f7426A308520F4ed3eF346FC18E4Cf";
    let usdcAddr = "0xf74fA4288fb6Ec6031e4A971B92e7a919f41DE98";
    let usdtAddr = "0xB2ceA900E13BAbCFd8D8fd795ad101e1B91763Fd";
    let busdAddr = "0x1991F66054Cf60663e76969a11E50bEC5F6Fae99";

    const ERC20 = await ethers.getContractFactory("GenericERC20");
    const token = await ERC20.attach(busdAddr);
    console.log("token deployed to:", token.address);

    // let approveRes = await token.approve(swap.address, ethers.utils.parseEther("99999999999999999999"));
    // console.log("Approve Res :", approveRes.hash);
    // return;

    // let allowRes = await token.allowance(admin.address, swap.address);
    // console.log("Allow Res :", allowRes.toString());
    // return;
    
    let addAmount = [
        ethers.utils.parseEther("10000000"),
        ethers.utils.parseUnits("10000000", 6),
        ethers.utils.parseUnits("10000000", 6),
        ethers.utils.parseEther("10000000"),
    ];

    // let tokenAmountRes = await swap.calculateTokenAmount(addAmount, true);
    // console.log("Token Amount :", tokenAmountRes.toString());
    // return;

    let depositRes = await swap.addLiquidity(addAmount, 0, 4801993200);

    console.log("Deposit Res :" + depositRes.hash);

}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
