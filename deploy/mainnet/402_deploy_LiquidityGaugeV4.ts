import { HardhatRuntimeEnvironment } from "hardhat/types"
import { DeployFunction } from "hardhat-deploy/types"

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deployments, getNamedAccounts, getChainId,ethers } = hre
  const { deploy, get, execute, getOrNull, log } = deployments
  const { libraryDeployer } = await getNamedAccounts()

  let SiriusUSDPoolLPTokenAddr = (await get("SiriusUSDPoolLPToken")).address;
  let MinterAddr = (await get("Minter")).address;
  let SrsAddr = (await get("SRS")).address;
  let VotingEscrowAddr = (await get("VotingEscrow")).address;
  let GaugeControllerAddr = (await get("GaugeController")).address;
  console.log("[402] Deployed SiriusUSDPoolLPToken's address:", SiriusUSDPoolLPTokenAddr);
  console.log("[402] Deployed Minter's address:", MinterAddr);
  console.log("[402] Deployed SRS's address:", SrsAddr);
  console.log("[402] Deployed VotingEscrow's address:", VotingEscrowAddr);
  console.log("[402] Deployed GaugeController's address:", GaugeControllerAddr);

  const liquidityGauge = await getOrNull("LiquidityGauge");
  if (liquidityGauge) {
    log(`reusing "LiquidityGauge" at ${liquidityGauge.address}`);
  } else {
    await deploy("LiquidityGauge", {
      from: libraryDeployer,
      log: true,  
      skipIfAlreadyDeployed: true,
    })
    
    await execute(
      "LiquidityGauge",
      { from: libraryDeployer, log: true },
      "__LiquidityGauge_init",
      SiriusUSDPoolLPTokenAddr,
      MinterAddr,
      SrsAddr,
      VotingEscrowAddr,
      GaugeControllerAddr
    )

    
  }
  let gaugeAddr = (await get("LiquidityGauge")).address;
  await execute(
    "GaugeController",
    { from: libraryDeployer, log: true },
    "addType",
    "LiquidityGaugeV4",
    ethers.utils.parseEther("1")
  );

  await execute(
    "GaugeController",
    { from: libraryDeployer, log: true },
    "addGauge",
    gaugeAddr,
    0,
    ethers.utils.parseEther("1")
  );
}
export default func
func.tags = ["LiquidityGauge"]
