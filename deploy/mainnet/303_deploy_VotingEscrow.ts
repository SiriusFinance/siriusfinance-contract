import { HardhatRuntimeEnvironment } from "hardhat/types"
import { DeployFunction } from "hardhat-deploy/types"
import { ethers } from "hardhat"

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deployments, getNamedAccounts, getChainId } = hre
  const { deploy, get, execute, getOrNull } = deployments
  const { deployer } = await getNamedAccounts()

  let SRSAddr = (await get("SRS")).address;
  // console.log("Deploying VeSRS' address:", SRSAddr);
  await deploy("VotingEscrow", {
    from: deployer,
    log: true,
    skipIfAlreadyDeployed: true,
    args: [
      SRSAddr,
      "Voting Escrow", 
      "veSRS"
    ],
  })
}
export default func
func.tags = ["VotingEscrow"]
