import { HardhatRuntimeEnvironment } from "hardhat/types"
import { DeployFunction } from "hardhat-deploy/types"

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deployments, getNamedAccounts } = hre
  const { execute, get, getOrNull, log, read, save } = deployments
  const { deployer } = await getNamedAccounts()

  // Manually check if the pool is already deployed
  const SiriusUSDPool = await getOrNull("SiriusUSDPool")
  if (SiriusUSDPool) {
    log(`reusing "SiriusUSDPool" at ${SiriusUSDPool.address}`)
  } else {
    // Constructor arguments
    const TOKEN_ADDRESSES = [
      (await get("DAI")).address,
      (await get("USDC")).address,
      (await get("USDT")).address,
      (await get("BUSD")).address,
    ]
    const TOKEN_DECIMALS = [18, 6, 6, 18]
    const LP_TOKEN_NAME = "Sirius DAI/USDC/USDT/BUSD LP Token"
    const LP_TOKEN_SYMBOL = "Sirius4ULP"
    const INITIAL_A = 200
    const SWAP_FEE = 4e6 // 4bps
    const ADMIN_FEE = 0

    console.log("[111] Swap Address:", (await get("Swap")).address);

    const receipt = await execute(
      "SwapDeployer",
      { from: deployer, log: true },
      "deploy",
      (
        await get("Swap")
      ).address,
      TOKEN_ADDRESSES,
      TOKEN_DECIMALS,
      LP_TOKEN_NAME,
      LP_TOKEN_SYMBOL,
      INITIAL_A,
      SWAP_FEE,
      ADMIN_FEE,
      (
        await get("LPToken")
      ).address,
    )

    const newPoolEvent = receipt?.events?.find(
      (e: any) => e["event"] == "NewSwapPool",
    )
    const usdSwapAddress = newPoolEvent["args"]["swapAddress"]
    log(`deployed USD pool (targeting "Swap") at ${usdSwapAddress}`)
    await save("SiriusUSDPool", {
      abi: (await get("Swap")).abi,
      address: usdSwapAddress,
    })
  }

  const lpTokenAddress = (await read("SiriusUSDPool", "swapStorage")).lpToken
  log(`USD pool LP Token at ${lpTokenAddress}`)

  await save("SiriusUSDPoolLPToken", {
    abi: (await get("LPToken")).abi, // LPToken ABI
    address: lpTokenAddress,
  })
}
export default func
func.tags = ["USDPool"]
func.dependencies = [
  "SwapUtils",
  "SwapDeployer",
  "Swap",
  "USDPoolTokens",
]
