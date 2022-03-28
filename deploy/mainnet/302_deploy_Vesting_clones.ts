import {
  BIG_NUMBER_1E18,
  MAX_UINT256,
  getCurrentBlockTimestamp,
} from "../../test/testUtils"
import { BigNumber } from "ethers"

import { DeployFunction } from "hardhat-deploy/types"
import { HardhatRuntimeEnvironment } from "hardhat/types"

const getSeedRoundAllocation = function (amount: number): BigNumber {
  return BIG_NUMBER_1E18.mul(100_000_000).mul(amount).div(1500000)
}

const getPrivateRoundAllocation = function (amount: number): BigNumber {
  return BIG_NUMBER_1E18.mul(80_000_000).mul(amount).div(2400000)
}

const getStrategicRoundAllocation = function (amount: number): BigNumber {
  return BIG_NUMBER_1E18.mul(50_000_000).mul(amount).div(2300000)
}

const getPublicRoundAllocation = function (amount: number): BigNumber {
  return BIG_NUMBER_1E18.mul(10_000_000).mul(amount).div(800000)
}

// Seed Round 10%: 2 months cliff (20%), 2 years linear release 80%
const SEED_ROUND_INVESTORS: { [address: string]: number } = {
  "0x6710903935858c1E790D86Bea9F9946fD7f4a981": 1500000,
}

// Private Round 8%: 1 month cliff (10%), 1 year linear release 90%
const PRIVATE_ROUND_INVESTORS: { [address: string]: number } = {
  "0x6710903935858c1E790D86Bea9F9946fD7f4a981": 2400000,
}

// Strategic Round 5%: 1 month cliff (15%), 10 months linear release 85%
const STRATEGIC_ROUND_INVESTORS: { [address: string]: number } = {
  "0x6710903935858c1E790D86Bea9F9946fD7f4a981": 2300000, 
}

// PUBLIC Round 5%: Fully Unlocked
const PUBLIC_ROUND_INVESTORS: { [address: string]: number } = {
  "0x6710903935858c1E790D86Bea9F9946fD7f4a981": 800000, 
}

const MULTISIG_ADDRESS = "0x3F8E527aF4e0c6e763e8f368AC679c44C45626aE"

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deployments, getNamedAccounts, getChainId } = hre
  const { deploy, get, execute } = deployments
  const { deployer } = await getNamedAccounts()

  interface Recipient {
    to: string
    amount: BigNumber
    startTimestamp: BigNumber
    cliffPeriod: BigNumber
    durationPeriod: BigNumber
  }

  const ONE_MONTHS_IN_SEC = BigNumber.from(1).mul(30).mul(24).mul(60).mul(60)
  const TWO_MONTHS_IN_SEC = BigNumber.from(2).mul(30).mul(24).mul(60).mul(60)
  const TEN_MONTHS_IN_SEC = BigNumber.from(10).mul(30).mul(24).mul(60).mul(60)
  const ONE_YEARS_IN_SEC = BigNumber.from(1).mul(365).mul(24).mul(60).mul(60)
  const TWO_YEARS_IN_SEC = BigNumber.from(2).mul(365).mul(24).mul(60).mul(60)
  const THREE_YEARS_IN_SEC = BigNumber.from(3).mul(365).mul(24).mul(60).mul(60)


  // Tuesday, November 16, 2021 12:00:00 AM UTC
  // This cannot be set in the future!
  const TOKEN_LAUNCH_TIMESTAMP = BigNumber.from(
    await getCurrentBlockTimestamp(),
  )

  // Wednesday, July 7, 2021 12:00:00 AM UTC
  const FIRST_BATCH_TEAM_VESTING_START_TIMESTAMP = BigNumber.from(1625616000)

  // Monday, October 4, 2021 12:00:00 AM UTC
  const SECOND_BATCH_TEAM_VESTING_START_TIMESTAMP = BigNumber.from(1633305600)

  const seedRoundInvestorGrants: { [address: string]: BigNumber } = {}
  const privateRoundInvestorGrants: { [address: string]: BigNumber } = {}
  const strategicRoundInvestorGrants: { [address: string]: BigNumber } = {}
  const publicRoundInvestorGrants: { [address: string]: BigNumber } = {}

  for (const [address, amount] of Object.entries(SEED_ROUND_INVESTORS)) {
    seedRoundInvestorGrants[address] = getSeedRoundAllocation(amount)
  }

  for (const [address, amount] of Object.entries(PRIVATE_ROUND_INVESTORS)) {
    privateRoundInvestorGrants[address] = getPrivateRoundAllocation(amount)
  }

  for (const [address, amount] of Object.entries(STRATEGIC_ROUND_INVESTORS)) {
    strategicRoundInvestorGrants[address] = getStrategicRoundAllocation(amount)
  }

  for (const [address, amount] of Object.entries(PUBLIC_ROUND_INVESTORS)) {
    publicRoundInvestorGrants[address] = getPublicRoundAllocation(amount)
  }

  const seedRoundInvestorRecipients: Recipient[] = []
  const privateRoundInvestorRecipients: Recipient[] = []
  const strategicRoundInvestorRecipients: Recipient[] = []
  const publicRoundInvestorRecipients: Recipient[] = []

  // Seed Round 10%: 2 months cliff (20%), 2 years linear release 80%
  for (const [address, amount] of Object.entries(seedRoundInvestorGrants)) {
    seedRoundInvestorRecipients.push({
      to: address,
      amount: amount,
      startTimestamp: TOKEN_LAUNCH_TIMESTAMP,
      cliffPeriod: TWO_MONTHS_IN_SEC,
      durationPeriod: TWO_YEARS_IN_SEC,
    })
  }

  // Private Round 8%: 1 month cliff (10%), 1 year linear release 90%
  for (const [address, amount] of Object.entries(privateRoundInvestorGrants)) {
    privateRoundInvestorRecipients.push({
      to: address,
      amount: amount,
      startTimestamp: TOKEN_LAUNCH_TIMESTAMP,
      cliffPeriod: ONE_MONTHS_IN_SEC,
      durationPeriod: ONE_YEARS_IN_SEC,
    })
  }

  // Strategic Round 5%: 1 month cliff (15%), 10 months linear release 85%
  for (const [address, amount] of Object.entries(strategicRoundInvestorGrants)) {
    strategicRoundInvestorRecipients.push({
      to: address,
      amount: amount,
      startTimestamp: TOKEN_LAUNCH_TIMESTAMP,
      cliffPeriod: ONE_MONTHS_IN_SEC,
      durationPeriod: TEN_MONTHS_IN_SEC,
    })
  }

  // PUBLIC Round 5%: Fully Unlocked
  for (const [address, amount] of Object.entries(publicRoundInvestorGrants)) {
    publicRoundInvestorRecipients.push({
      to: address,
      amount: amount,
      startTimestamp: TOKEN_LAUNCH_TIMESTAMP,
      cliffPeriod: BigNumber.from(0),
      durationPeriod: BigNumber.from(0),
    })
  }

  // Team 12%
  const teamRecipients: Recipient[] = [
    {
      to: "0x27E2E09a84BaE20C2a9667594896EaF132c862b7",
      amount: BIG_NUMBER_1E18.mul(120_000_000),
      startTimestamp: FIRST_BATCH_TEAM_VESTING_START_TIMESTAMP,
      cliffPeriod: BigNumber.from(0),
      durationPeriod: THREE_YEARS_IN_SEC,
    },
    {
      to: "0xD9AED190e9Ae62b59808537D2EBD9E123eac4703",
      amount: BIG_NUMBER_1E18.mul(8_000_000),
      startTimestamp: FIRST_BATCH_TEAM_VESTING_START_TIMESTAMP,
      cliffPeriod: BigNumber.from(0),
      durationPeriod: THREE_YEARS_IN_SEC,
    },
    {
      to: "0x82AbEDF193942a6Cdc4704A8D49e54fE51160E99",
      amount: BIG_NUMBER_1E18.mul(12_000_000),
      startTimestamp: FIRST_BATCH_TEAM_VESTING_START_TIMESTAMP,
      cliffPeriod: BigNumber.from(0),
      durationPeriod: THREE_YEARS_IN_SEC,
    },
  ]

  let totalTeamAmount = BigNumber.from(0)
  for (const recipient of [...teamRecipients]) {
    totalTeamAmount = totalTeamAmount.add(recipient.amount)
  }
  console.assert(
    totalTeamAmount.eq(BIG_NUMBER_1E18.mul(259_000_000)),
    `team amounts did not match (got, expected): ${totalTeamAmount}, ${BIG_NUMBER_1E18.mul(
      259_000_000,
    )}`,
  )

  let totalInvestorAmount = BigNumber.from(0)
  for (const recipient of [
    ...seedRoundInvestorRecipients,
    ...privateRoundInvestorRecipients,
    ...strategicRoundInvestorRecipients,
    ...publicRoundInvestorRecipients,
  ]) {
    totalInvestorAmount = totalInvestorAmount.add(recipient.amount)
  }
  console.assert(
    totalInvestorAmount.eq(BIG_NUMBER_1E18.mul(240_000_000)),
    `investor amounts did not match (got, expected): ${totalInvestorAmount}, ${BIG_NUMBER_1E18.mul(
      240_000_000,
    )}`,
  )

  const vestingRecipients: Recipient[] = [
    ...seedRoundInvestorRecipients,
    ...privateRoundInvestorRecipients,
    ...strategicRoundInvestorRecipients,
    ...teamRecipients,
  ]

  // Approve the contract to use the token for deploying the vesting contracts
  await execute(
    "SRS",
    { from: deployer, log: true },
    "approve",
    (
      await get("SRS")
    ).address,
    MAX_UINT256,
  )

  // Deploy a new vesting contract clone for each recipient
  for (const recipient of vestingRecipients) {
    await execute(
      "SRS",
      {
        from: deployer,
        log: true,
      },
      "deployNewVestingContract",
      recipient,
    )
  }
}
export default func
func.tags = ["VestingClones"]
func.skip = async (env) => true