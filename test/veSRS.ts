import {
  BIG_NUMBER_1E18,
  BIG_NUMBER_ZERO,
  MAX_UINT256,
  ZERO_ADDRESS,
  getCurrentBlockTimestamp,
  setTimestamp,
} from "./testUtils"
import { BigNumber, Signer } from "ethers"
import { SRS, Vesting, VeSRS } from "../build/typechain/"
import { deployments, ethers } from "hardhat"

import { DeployResult } from "hardhat-deploy/dist/types"
import chai from "chai"
import { solidity } from "ethereum-waffle"

chai.use(solidity)
const { expect } = chai

describe("veToken", () => {
  let signers: Array<Signer>
  let deployer: Signer
  let deployerAddress: string
  let governance: Signer
  let governanceAddress: string
  let vesting: Vesting
  let siriusToken: SRS
  let veToken: VeSRS
  let startTimestamp: number
  const PAUSE_PERIOD = 1800
  const vestingContracts: Vesting[] = []

  interface Recipient {
    to: string
    amount: BigNumber
    startTimestamp: BigNumber
    cliffPeriod: BigNumber
    durationPeriod: BigNumber
  }

  const setupTest = deployments.createFixture(
    async ({ deployments, ethers }) => {
      const { deploy, deterministic } = deployments
      await deployments.fixture() // ensure you start from a fresh deployments

      signers = await ethers.getSigners()
      deployer = signers[0]
      deployerAddress = await deployer.getAddress()
      governance = signers[1]
      governanceAddress = await governance.getAddress()

      // Signers [10, 11, 12] are vested, [13, 14] are not vested
      const vestingStartTimestamp = BigNumber.from(
        await getCurrentBlockTimestamp(),
      ).sub(1000)
      const vestingRecipients: Recipient[] = [
        {
          to: await signers[10].getAddress(),
          amount: BIG_NUMBER_1E18.mul(2e8),
          startTimestamp: vestingStartTimestamp,
          cliffPeriod: BigNumber.from(3600),
          durationPeriod: BigNumber.from(7200),
        },
        {
          to: await signers[11].getAddress(),
          amount: BIG_NUMBER_1E18.mul(2e8),
          startTimestamp: vestingStartTimestamp,
          cliffPeriod: BigNumber.from(3600),
          durationPeriod: BigNumber.from(7200),
        },
        {
          to: await signers[12].getAddress(),
          amount: BIG_NUMBER_1E18.mul(2e8),
          startTimestamp: vestingStartTimestamp,
          cliffPeriod: BigNumber.from(3600),
          durationPeriod: BigNumber.from(7200),
        },
      ]

      const nonVestingRecipients = [
        {
          to: await signers[13].getAddress(),
          amount: BIG_NUMBER_1E18.mul(2e8),
        },
        {
          to: await signers[14].getAddress(),
          amount: BIG_NUMBER_1E18.mul(2e8),
        },
      ]

      await deploy("Vesting", {
        from: deployerAddress,
        log: true,
        skipIfAlreadyDeployed: true,
      })

      vesting = await ethers.getContract("Vesting")

      // Calculate deterministic deployment address
      const determinedDeployment = await deterministic("SRS", {
        from: deployerAddress,
        args: [governanceAddress, PAUSE_PERIOD, vesting.address],
        log: true,
      })

      // Send couple ether to the predicted address (for testing eth rescue)
      const tx = {
        to: determinedDeployment.address,
        // Convert currency unit from ether to wei
        value: ethers.utils.parseEther("5"),
      }
      await deployer.sendTransaction(tx)

      // Deploy the token contract
      const deployResult: DeployResult = await determinedDeployment.deploy()
      startTimestamp = await getCurrentBlockTimestamp()

      console.log(`Gas used to deploy token: ${deployResult.receipt?.gasUsed}`)

      // Find the sirius token deployment
      siriusToken = await ethers.getContract("SRS")

      // Approve the token usage for deploying vesting contracts
      await siriusToken
        .connect(governance)
        .approve(siriusToken.address, MAX_UINT256)

      // Call `deployNewVestingContract` for each vesting recipient
      for (const vestingReciepient of vestingRecipients) {
        // Preview the address
        const cloneAddress = await siriusToken
          .connect(governance)
          .callStatic.deployNewVestingContract(vestingReciepient)

        // Push the address to vesting contracts array
        vestingContracts.push(
          (await ethers.getContractAt("Vesting", cloneAddress)) as Vesting,
        )

        await siriusToken
          .connect(governance)
          .deployNewVestingContract(vestingReciepient)
      }

      // Send the token to addresses without vesting
      const approvedTransferees = []
      for (const nonVestingRecipient of nonVestingRecipients) {
        await siriusToken
          .connect(governance)
          .transfer(nonVestingRecipient.to, nonVestingRecipient.amount)
        approvedTransferees.push(nonVestingRecipient.to)
      }

      // Let those addresses transfer the token
      await siriusToken
        .connect(governance)
        .addToAllowedList(approvedTransferees)
      

      // Calculate deterministic deployment address
      const determinedDeployment2 = await deterministic("veSRS", {
        from: deployerAddress,
        args: [siriusToken.address, ethers.utils.parseEther("2000")],
        log: true,
      })

      const deployResult2: DeployResult = await determinedDeployment2.deploy()
      console.log(`Gas used to deploy veToken: ${deployResult2.receipt?.gasUsed}`)

      // Find the veToken deployment
      veToken = await ethers.getContract("veSRS")
      console.log(`veToken contract address is ${veToken.address}`)

      // Allow veToken contract to transfer the SRS token
      await siriusToken
        .connect(governance)
        .addToAllowedList([veToken.address])

      // Approve veToken contract to transfer signer 13's SRS token
      await siriusToken
        .connect(signers[13])
        .approve(veToken.address, MAX_UINT256)
      
      // Signer 13 create lock
      await veToken
        .connect(signers[13])
        .create_lock(ethers.utils.parseEther("2000"), 30)
    },
  )

  beforeEach(async () => {
    await setupTest()
  })

  describe("locked of", () => {
    it("Successfully get the correct locked token amount", async () => {
      expect(await veToken.locked__of(await signers[13].getAddress())).to.eq(ethers.utils.parseEther("2000"))
    })
  })

  describe("locked end", () => {
    it("Successfully get the correct locked end time", async () => {
      const end1 = await veToken.locked__end(await signers[13].getAddress());
      await veToken
        .connect(signers[13])
        .increase_unlock_time(10);
      const end2 = await veToken.locked__end(await signers[13].getAddress());
      expect(end2.sub(end1)).to.eq(10 * 24 * 3600)
    })
  })

  describe("voting power unlock time", () => {
    it("Get the correct voting power at unlock time", async () => {
      const power = await veToken
        .connect(signers[13])
        .voting_power_unlock_time("2000", await getCurrentBlockTimestamp() + 3 * 365 * 24 * 3600 * 1000)
      expect(power).to.eq(2000)
    })
    it("If unlock time is less than current time", async () => {
      const power = await veToken
        .connect(signers[13])
        .voting_power_unlock_time("2000", await getCurrentBlockTimestamp() - 1)
      expect(power).to.eq(0)
    })
    it("If locket time exceed maximum seconds", async () => {
      const power = await veToken
        .connect(signers[13])
        .voting_power_unlock_time("2000", await getCurrentBlockTimestamp() + 4 * 365 * 24 * 3600 * 1000)
      expect(power).to.eq(2000)
    })
  })

  describe("voting power locked days", () => {
    it("Get all voting power for 3 years", async () => {
      const power = await veToken
        .connect(signers[13])
        .voting_power_locked_days("3000", 3 * 365)
      expect(power).to.eq(3000)
    })
    it("Get 2/3 voting power for 2 years", async () => {
      const power = await veToken
        .connect(signers[13])
        .voting_power_locked_days("3000", 2 * 365)
      expect(power).to.eq(2000)
    })
    it("Get maximum voting power for more than 3 years", async () => {
      const power = await veToken
        .connect(signers[13])
        .voting_power_locked_days("3000", 4 * 365)
      expect(power).to.eq(3000)
    })
  })

  describe("deposit for", () => {
    it("If deposit value is less than minimal lock amount", async () => {
      await expect(
        veToken
        .connect(signers[13])
        .deposit_for(await signers[13].getAddress(), 1)
      ).to.be.revertedWith("less than min amount")
    })
    it("If deposit value is larger than minimal lock amount", async () => {
      await veToken
        .connect(signers[13])
        .deposit_for(await signers[13].getAddress(), ethers.utils.parseEther("2000"))
      expect(await veToken.locked__of(await signers[13].getAddress())).to.eq(ethers.utils.parseEther("4000")) 
    })
  })

  describe("create lock", () => {
    it("If deposite amount is less than min amount", async () => {
      await expect(
        veToken
          .connect(signers[13])
          .create_lock(ethers.utils.parseEther("1999"), 30)
      ).to.be.revertedWith("less than min amount")
    })
    it("If the account already has deposit", async () => {
      await expect(
        veToken
          .connect(signers[13])
          .create_lock(ethers.utils.parseEther("2000"), 30)
      ).to.be.revertedWith("Withdraw old tokens first")
    })
    it("If locking days is less than minimal required days", async () => {
      await expect(
        veToken
          .connect(signers[14])
          .create_lock(ethers.utils.parseEther("2000"), 3)
      ).to.be.revertedWith("Voting lock can be 7 days min") 
    })
    it("If locking days is larger than maximum days", async () => {
      await expect(
        veToken
          .connect(signers[14])
          .create_lock(ethers.utils.parseEther("2000"), 3 * 365 + 1)
      ).to.be.revertedWith("Voting lock can be 3 years max") 
    })
  })

  describe("increase_amount", () => {
    it("If increase amount is less than min amount", async () => {
      await expect(
        veToken
          .connect(signers[13])
          .increase_amount(1)
      ).to.be.revertedWith("less than min amount")
    })
    it("If increase amount is larger than min amount", async () => {
      veToken
        .connect(signers[13])
        .increase_amount(ethers.utils.parseEther("2000"))
      expect(await veToken.locked__of(await signers[13].getAddress())).to.eq(ethers.utils.parseEther("4000")) 
    })
  })

  describe("increase_unlock_time", () => {
    it("If increase unlock time is less than min days", async () => {
      await expect(
        veToken
          .connect(signers[13])
          .increase_unlock_time(6)
      ).to.be.revertedWith("Voting lock can be 7 days min")
    })
    it("If increase unlock time is larger than max days", async () => {
      await expect(
        veToken
          .connect(signers[13])
          .increase_unlock_time(3 * 365 + 1)
      ).to.be.revertedWith("Voting lock can be 3 years max")
    })
  })

  describe("withdraw", () => {
    it("if lock didn't expire", async () => {
      await expect(
        veToken
          .connect(signers[13])
          .withdraw()
      ).to.be.revertedWith("The lock didn't expire")
    })
    it("If lock has expired", async () => {
      await setTimestamp(
        (await veToken.locked__end(await signers[13].getAddress())).add(1).toNumber(),
      )
      veToken
        .connect(signers[13])
        .withdraw()
      expect(await veToken.mintedForLock(await signers[13].getAddress())).to.eq(0)
    })
  })

  describe("withdraw", () => {
    it("if lock didn't expire", async () => {
      await expect(
        veToken
          .connect(signers[13])
          .withdraw()
      ).to.be.revertedWith("The lock didn't expire")
      expect(await veToken.mintedForLock(await signers[13].getAddress())).to.eq(ethers.utils.parseEther("2000").mul(30).div(3 * 365))
    })
    it("If lock has expired", async () => {
      await setTimestamp(
        (await veToken.locked__end(await signers[13].getAddress())).add(1).toNumber(),
      )
      await veToken
        .connect(signers[13])
        .withdraw()
      expect(await veToken.mintedForLock(await signers[13].getAddress())).to.eq(0)
    })
  })

  // describe("emergency withdraw", () => {
  //   it("If withdraw in advance", async () => {
  //     await setTimestamp(
  //       (await veToken.locked__end(await signers[13].getAddress())).sub(3600 * 24).toNumber(),
  //     )
  //     const address = await signers[13].getAddress()
  //     const balance = await siriusToken.balanceOf(address)
  //     await veToken
  //       .connect(signers[13])
  //       .emergencyWithdraw()
  //     const balance2 = await siriusToken.balanceOf(address)

  //     expect(balance2.sub(balance)).to.eq(ethers.utils.parseEther("1400"))
  //   })
  // })

})
