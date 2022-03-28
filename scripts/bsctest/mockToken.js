
const {ethers} = require("hardhat");

async function main() {
  
    const [deployer] = await ethers.getSigners();
    const admin = deployer;
    console.log("deployer:", admin.address);
    let daiAddr = "0xfc7aF6Cd95f7426A308520F4ed3eF346FC18E4Cf";
    let usdcAddr = "0x6F37340aD2a3Baff9c10d6237590098e269f4cE9";
    let usdtAddr = "0x38c94B15154e32D06747F24216c3A2008C5ea98e";
    let busdAddr = "0x1991F66054Cf60663e76969a11E50bEC5F6Fae99";
    let lqToken = "0x308D46AF1b61b77d31128B92f3e559f5b7A4fB1A";
    let srsAddr = "0xf6c1C296F972999ea6Efb08fb3d84337b137Cb40";

    const ERC20 = await ethers.getContractFactory("GenericERC20");
    const token = await ERC20.attach(srsAddr);
    console.log("token deployed to:", token.address);

    let users = [
      "0xDaC8AF1ec625E9a00746D94C7478bb18dBe51DDF",
      "0x09962FB9f0ce59AB20F9aF66302Da3D534efAA4C",
      "0xb1fd19e7f7a6B79fA05A535798B5da08C13CB786",
      "0xeB2b9311fc972e82c313B9399d7566Be2B56e276",
      "0xe015CF9cFa0d8989034302Ae0391454aB950f919",
      "0xFB1F3B62E14180dc29e669E52975C38b1F675D70",
      "0x2852Ce37F16693B4159246D567A3a89f59511DBd",
      "0xC22A8fcEF8775641073a41118a43415312a11CC6",
      "0x2c45869703bf137050637f1C48d1A0C71e151Ac6",
      "0x6710903935858c1E790D86Bea9F9946fD7f4a981",
      "0xa807c913cb59d4ad3c8239ab726ecd9b83b6cd03",
      "0x32444Db1e27a2997E166C42fD5162117225853f4"
    ];
    // for(var i in users) {
    //   let mintRes = await token.mint(users[i], ethers.utils.parseEther("10000000"));
    //   console.log("User["+users[i]+"] :" + mintRes.hash);
    // }

    for(var i in users) {
      let transRes = await token.transfer( users[i], ethers.utils.parseEther("20000000"));
      console.log("User["+users[i]+"] :" + transRes.hash);
    }

}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
