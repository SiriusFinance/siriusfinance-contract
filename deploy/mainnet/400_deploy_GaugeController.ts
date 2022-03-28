import { HardhatRuntimeEnvironment } from "hardhat/types"
import { DeployFunction } from "hardhat-deploy/types"
import { isTestNetwork } from "../../utils/network"

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deployments, getNamedAccounts, getChainId } = hre
  const { deploy, get, execute, getOrNull, log } = deployments
  const { libraryDeployer } = await getNamedAccounts()

  let SRSAddr = (await get("SRS")).address;
  let VeSRSAddr = (await get("VotingEscrow")).address;
  const gaugeController = await getOrNull("GaugeController");
  if (gaugeController) {
    log(`reusing "GaugeController" at ${gaugeController.address}`)
  } else {
    
    await deploy("GaugeController", {
      from: libraryDeployer,
      log: true,
      skipIfAlreadyDeployed: true,
    })

    await execute(
      "GaugeController",
      { from: libraryDeployer, log: true },
      "__GaugeController_init",
      SRSAddr,
      VeSRSAddr,
    )
  }
}
export default func
func.tags = ["GaugeController"]