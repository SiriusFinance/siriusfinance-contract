
const {ethers} = require("hardhat");

async function main() {
  
    const [deployer] = await ethers.getSigners();
    const admin = deployer;
    console.log("deployer:", admin.address);
    let daiAddr = "0x9FedA35DB1094F344520EE49742752bE84e5B15A";
    let usdcAddr = "0x80F80a018951102341f792c992C66A402b2a26a3";
    let usdtAddr = "0x8c5107D62cb93eBeFf59061cACc4655A677c2aF5";

    const ERC20 = await ethers.getContractFactory("GenericERC20");
    const token = await ERC20.attach(usdtAddr);
    console.log("token deployed to:", token.address);

    let users = [
      // "0xDaC8AF1ec625E9a00746D94C7478bb18dBe51DDF",
      // "0x09962FB9f0ce59AB20F9aF66302Da3D534efAA4C",
      // "0xb1fd19e7f7a6B79fA05A535798B5da08C13CB786",
      // "0xeB2b9311fc972e82c313B9399d7566Be2B56e276",
      // "0xe015CF9cFa0d8989034302Ae0391454aB950f919",
      // "0xFB1F3B62E14180dc29e669E52975C38b1F675D70",
      // "0x2852Ce37F16693B4159246D567A3a89f59511DBd",
      // "0xC22A8fcEF8775641073a41118a43415312a11CC6",
      "0x2c45869703bf137050637f1C48d1A0C71e151Ac6"
    ];
    for(var i in users) {
      let mintRes = await token.mint(users[i], ethers.utils.parseEther("10000000000000"));
      console.log("User["+users[i]+"] :" + mintRes.hash);
    }

}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
