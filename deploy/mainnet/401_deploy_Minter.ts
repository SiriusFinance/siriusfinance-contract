import { HardhatRuntimeEnvironment } from "hardhat/types"
import { DeployFunction } from "hardhat-deploy/types"
import { isTestNetwork } from "../../utils/network"

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deployments, getNamedAccounts, getChainId } = hre
  const { deploy, get, execute, getOrNull, log } = deployments
  const { deployer } = await getNamedAccounts()

  let SRSAddr = (await get("SRS")).address;
  let GaugeControllerAddr = (await get("GaugeController")).address;
  const minter = await getOrNull("Minter");
  if (minter) {
    log(`reusing "Minter" at ${minter.address}`)
  } else {
    await deploy("Minter", {
      from: deployer,
      log: true,
      skipIfAlreadyDeployed: true,
    })

    await execute(
      "Minter",
      { from: deployer, log: true },
      "__Minter_init",
      SRSAddr,
      GaugeControllerAddr,
    )
    let minterAddr = (await get("Minter")).address;
    await execute(
      "SRS",
      { from: deployer, log: true },
      "setMinter",
      minterAddr
    );
  }

}
export default func
func.tags = ["Minter"]
