const hre = require('hardhat')
const { expect, should } = require('chai')
const { ethers } = require('ethers')
const { network } = require('hardhat')

describe('Beeper Dao Contracts', function () {
  before(async () => {
    //Preparing the env
    ;[
      this.deployer,
      this.creator,
      this.platform,
      this.user1,
      this.user2,
      this.user3,
      this.platform,
      this.beneficiary,
    ] = await hre.ethers.getSigners()

    this.ERC20Factory = await hre.ethers.getContractFactory('ERC20Token')

    this.TokenBaseDeployer = await hre.ethers.getContractFactory(
      'TokenBaseDeployer'
    )
    this.NFTBaseDeployer = await hre.ethers.getContractFactory(
      'NFTBaseDeployer'
    )
    this.FixedPeriodDeployer = await hre.ethers.getContractFactory(
      'FixedPeriodDeployer'
    )
    this.FixedPriceDeployer = await hre.ethers.getContractFactory(
      'FixedPriceDeployer'
    )
    this.Factory = await hre.ethers.getContractFactory('Factory')

    //Deploy Factory & Four deployer & ERC20Token
    this.tokenBaseDeployer = await this.TokenBaseDeployer.deploy()
    this.nftBaseDeployer = await this.NFTBaseDeployer.deploy()
    this.fixedPeriodDeployer = await this.FixedPeriodDeployer.deploy()
    this.fixedPriceDeployer = await this.FixedPriceDeployer.deploy()
    this.erc20 = await this.ERC20Factory.deploy('Test Token', 'TT')

    await this.tokenBaseDeployer.deployed()
    await this.nftBaseDeployer.deployed()
    await this.fixedPeriodDeployer.deployed()
    await this.fixedPriceDeployer.deployed()
    await this.erc20.deployed()

    this.factory = await this.Factory.deploy(
      this.tokenBaseDeployer.address,
      this.nftBaseDeployer.address,
      this.fixedPeriodDeployer.address,
      this.fixedPriceDeployer.address
    )
  })

  describe('FixedPeriod Test (without platform fee)', () => {
    beforeEach(async () => {
      // price = slope * (termOfValidity - now)

      this.initialRateBN = ethers.utils.parseEther('100')
      this.initialRate = this.initialRateBN.toString()
      this.termOfValidityBN = ethers.BigNumber.from('3600')
      this.termOfValidity = this.termOfValidityBN.toString()
      this.startTime = Date.parse(new Date()) / 1000 + 360
      this.endTimeBN =
        ethers.BigNumber.from(this.startTime) + this.termOfValidityBN
      this.endTime = this.endTimeBN.toString()
      this.slopeBN = this.initialRateBN.div(this.termOfValidityBN)
      this.slope = this.slopeBN.toString()
      this.maxSupply = 100

      this.constructorParameter = [
        'test_name',
        'test_symbol',
        'https://test_url.com/',
        this.erc20.address,
        this.beneficiary.address,
        this.initialRate,
        this.startTime,
        this.termOfValidity,
        this.maxSupply,
      ]

      const tx = await this.factory
        .connect(this.creator)
        .fixedPeriodDeploy(...this.constructorParameter)

      const receipt = await tx.wait()
      for (const event of receipt.events) {
        switch (event.event) {
          case 'FixedPeriodDeploy': {
            this.fixedPriceAddr = event.args[0]
          }
        }
      }

      let fixedPricePeriodFactory = await hre.ethers.getContractFactory(
        'FixedPeriod'
      )
      this.fixedPeriod = fixedPricePeriodFactory.attach(this.fixedPriceAddr)
    })

    describe('Public Info Check', () => {
      it('check base info', async () => {
        expect(await this.fixedPeriod.owner()).to.eq(this.creator.address)
        expect(await this.fixedPeriod.erc20()).to.eq(this.erc20.address)
        expect(await this.fixedPeriod.maxSupply()).to.eq(this.maxSupply)
        expect(await this.fixedPeriod.platform()).to.eq(
          ethers.constants.AddressZero
        )
        expect(await this.fixedPeriod.platformRate()).to.eq(0)
      })

      it('only owner can set baseUrl', async () => {
        const newBaseUrl = 'https://newBaserul.com/'
        await expect(
          this.fixedPeriod.setBaseURI(newBaseUrl)
        ).to.be.revertedWith(
          `AccessControl: account ${this.deployer.address.toLowerCase()} is missing role ${
            ethers.constants.HashZero
          }`
        )
      })
    })

    describe('Mint Burn (Price Period decline) Test', () => {
      const testPrice = async time => {
        try {
          await network.provider.send('evm_setNextBlockTimestamp', [
            this.startTime + time,
          ])
          await network.provider.send('evm_mine')

          const price = ethers.utils.formatEther(
            await this.fixedPeriod.getCurrentCostToMint()
          )
          let expectPrice = ethers.utils.formatEther(
            this.initialRateBN.sub(
              this.slopeBN.mul(ethers.BigNumber.from(time))
            )
          )
          expect(price).to.eq(expectPrice)
        } catch (error) {
          console.log(error)
        }
      }

      it('reverted when not begin', async () => {
        await network.provider.send('evm_setNextBlockTimestamp', [
          this.startTime - 100,
        ])
        await network.provider.send('evm_mine')

        await expect(
          this.fixedPeriod.getCurrentCostToMint()
        ).to.be.revertedWith('FixedPrice: not in time')
      })
      it('just begin time', async () => {
        await testPrice(0)
      })
      it('last 200 second', async () => {
        await testPrice(200)
      })

      it('mint succeeds when receive erc20', async () => {
        // mock erc20 balance
        await this.erc20.mint(this.user1.address, this.initialRate)
        await this.erc20.mint(this.user3.address, this.initialRate)
        await this.erc20
          .connect(this.user1)
          .approve(this.fixedPriceAddr, this.initialRate)
        await this.erc20
          .connect(this.user3)
          .approve(this.fixedPriceAddr, this.initialRate)

        // user 1 mint with token id 1
        await expect(this.fixedPeriod.connect(this.user1).mint())
          .to.emit(this.fixedPeriod, 'Mint')
          .withArgs(this.user1.address, 1)

        //user 3 mint with token id 2
        await expect(this.fixedPeriod.connect(this.user3).mint())
          .to.emit(this.fixedPeriod, 'Mint')
          .withArgs(this.user3.address, 2)
      })

      it('mint reverted when receive erc20 failed', async () => {
        // user 2 failed

        const price = ethers.utils.formatEther(
          await this.fixedPeriod.getCurrentCostToMint()
        )
        await expect(this.fixedPeriod.connect(this.user2).mint()).to.be.reverted
      })

      it('succeeds when user1 mint (no platform fee)', async () => {
        // mock erc20 balance
        await this.erc20.mint(this.user1.address, this.initialRate)
        await this.erc20
          .connect(this.user1)
          .approve(this.fixedPriceAddr, this.initialRate)

        // user 1 mint a token
        await expect(this.fixedPeriod.connect(this.user1).mint())
          .to.emit(this.fixedPeriod, 'Mint')
          .withArgs(this.user1.address, 1)

        const price = (await this.fixedPeriod.getCurrentCostToMint()).toString()

        await expect(
          this.fixedPeriod
            .connect(this.user3)
            .changeBeneficiary(this.user3.address)
        ).to.be.revertedWith(
          `AccessControl: account ${this.user3.address.toLowerCase()} is missing role ${
            ethers.constants.HashZero
          }`
        )

        await this.fixedPeriod
          .connect(this.creator)
          .changeBeneficiary(this.user3.address)

        await expect(this.fixedPeriod.connect(this.user1).withdraw())
          .to.emit(this.fixedPeriod, 'Withdraw')
          .withArgs(this.user3.address, price)
      })

      it('succeeds when user1 mint (with platform fee)', async () => {
        // mock erc20 balance
        await this.erc20.mint(this.user1.address, this.initialRate)
        await this.erc20
          .connect(this.user1)
          .approve(this.fixedPriceAddr, this.initialRate)
        await this.erc20.mint(this.user2.address, this.initialRate)
        await this.erc20
          .connect(this.user2)
          .approve(this.fixedPriceAddr, this.initialRate)

        // user 1 mint a token
        await expect(this.fixedPeriod.connect(this.user1).mint())
          .to.emit(this.fixedPeriod, 'Mint')
          .withArgs(this.user1.address, 1)
        await expect(this.fixedPeriod.connect(this.user2).mint())
          .to.emit(this.fixedPeriod, 'Mint')
          .withArgs(this.user2.address, 2)
      })

      it('last 1600 second', async () => {
        await testPrice(800)
      })

      it('last 3422 second', async () => {
        await testPrice(3422)
      })

      it('last 3700 second', async () => {
        let time = 3700
        await network.provider.send('evm_setNextBlockTimestamp', [
          this.startTime + time,
        ])
        await network.provider.send('evm_mine')

        await expect(
          this.fixedPeriod.getCurrentCostToMint()
        ).to.be.revertedWith('FixedPrice: not in time')
      })
    })
  })

  describe('FixedPeriod Test (whit olatform fee)', () => {
    beforeEach(async () => {
      this.platformRate = 5
      await this.factory.setPlatform(this.platform.address)
      await this.factory.setPlatformRate(5)

      this.initialRateBN = ethers.utils.parseEther('100')
      this.initialRate = this.initialRateBN.toString()
      this.termOfValidityBN = ethers.BigNumber.from('3600')
      this.termOfValidity = this.termOfValidityBN.toString()
      this.startTime = Date.parse(new Date()) / 1000 + 7200
      this.endTimeBN =
        ethers.BigNumber.from(this.startTime) + this.termOfValidityBN
      this.endTime = this.endTimeBN.toString()
      this.slopeBN = this.initialRateBN.div(this.termOfValidityBN)
      this.slope = this.slopeBN.toString()
      this.maxSupply = 100

      this.constructorParameter = [
        'test_name',
        'test_symbol',
        'https://test_url.com/',
        this.erc20.address,
        this.beneficiary.address,
        this.initialRate,
        this.startTime,
        this.termOfValidity,
        this.maxSupply,
      ]

      const tx = await this.factory
        .connect(this.creator)
        .fixedPeriodDeploy(...this.constructorParameter)

      const receipt = await tx.wait()
      for (const event of receipt.events) {
        switch (event.event) {
          case 'FixedPeriodDeploy': {
            this.fixedPriceAddr = event.args[0]
          }
        }
      }

      let fixedPricePeriodFactory = await hre.ethers.getContractFactory(
        'FixedPeriod'
      )
      this.fixedPeriod = fixedPricePeriodFactory.attach(this.fixedPriceAddr)
    })

    describe('Mint Burn (Price Period decline) Test', () => {
      const testPrice = async time => {
        try {
          await network.provider.send('evm_setNextBlockTimestamp', [
            this.startTime + time,
          ])
          await network.provider.send('evm_mine')

          const price = ethers.utils.formatEther(
            await this.fixedPeriod.getCurrentCostToMint()
          )
          let expectPrice = ethers.utils.formatEther(
            this.initialRateBN.sub(
              this.slopeBN.mul(ethers.BigNumber.from(time))
            )
          )
          // console.log(`price: ${price}, expectPrice: ${expectPrice}`);
          expect(price).to.eq(expectPrice)
        } catch (error) {
          console.log(error)
        }
      }

      it('reverted when not begin', async () => {
        await network.provider.send('evm_setNextBlockTimestamp', [
          this.startTime - 100,
        ])
        await network.provider.send('evm_mine')

        await expect(
          this.fixedPeriod.getCurrentCostToMint()
        ).to.be.revertedWith('FixedPrice: not in time')
      })
      it('just begin time', async () => {
        await testPrice(0)
      })
      it('last 200 second', async () => {
        await testPrice(200)
      })

      it('mint succeeds when receive erc20', async () => {
        // mock erc20 balance
        await this.erc20.mint(this.user1.address, this.initialRate)
        await this.erc20.mint(this.user3.address, this.initialRate)
        await this.erc20
          .connect(this.user1)
          .approve(this.fixedPriceAddr, this.initialRate)
        await this.erc20
          .connect(this.user3)
          .approve(this.fixedPriceAddr, this.initialRate)

        // user 1 mint with token id 1
        await expect(this.fixedPeriod.connect(this.user1).mint())
          .to.emit(this.fixedPeriod, 'Mint')
          .withArgs(this.user1.address, 1)

        //user 3 mint with token id 2
        await expect(this.fixedPeriod.connect(this.user3).mint())
          .to.emit(this.fixedPeriod, 'Mint')
          .withArgs(this.user3.address, 2)
      })

      it('last 1600 second', async () => {
        await testPrice(1600)
        it('mint reverted when receive erc20 failed', async () => {
          // user 2 failed

          const price = ethers.utils.formatEther(
            await this.fixedPeriod.getCurrentCostToMint()
          )
          await expect(this.fixedPeriod.connect(this.user2).mint()).to.be
            .reverted
        })

        it('succeeds mint & withdraaw', async () => {
          // mock erc20 balance
          await this.erc20.mint(this.user1.address, this.initialRate)
          await this.erc20
            .connect(this.user1)
            .approve(this.fixedPriceAddr, this.initialRate)

          // user 1 mint a token
          await expect(this.fixedPeriod.connect(this.user1).mint())
            .to.emit(this.fixedPeriod, 'Mint')
            .withArgs(this.user1.address, 1)

          const price = (
            await this.fixedPeriod.getCurrentCostToMint()
          ).toString()

          await expect(
            this.fixedPeriod
              .connect(this.user3)
              .changeBeneficiary(this.user3.address)
          ).to.be.revertedWith(
            `AccessControl: account ${this.user3.address.toLowerCase()} is missing role ${
              ethers.constants.HashZero
            }`
          )

          await this.fixedPeriod
            .connect(this.creator)
            .changeBeneficiary(this.user3.address)

          await expect(this.fixedPeriod.connect(this.user1).withdraw())
            .to.emit(this.fixedPeriod, 'Withdraw')
            .withArgs(
              this.user3.address,
              ethers.utils
                .parseEther(price)
                .sub(
                  ethers.utils
                    .parseEther(price)
                    .mul(ethers.BigNumber.from(this.platformRate))
                    .div(eth.BigNumber.from(100))
                )
            )
        })
      })

      it('last 3422 second', async () => {
        await testPrice(3422)
      })

      it('last 3700 second', async () => {
        let time = 3700
        await network.provider.send('evm_setNextBlockTimestamp', [
          this.startTime + time,
        ])
        await network.provider.send('evm_mine')

        await expect(
          this.fixedPeriod.getCurrentCostToMint()
        ).to.be.revertedWith('FixedPrice: not in time')
      })
    })
  })

  describe('FixedPeriod with ether (without platform fee)', () => {
    beforeEach(async () => {
      this.initialRateBN = ethers.utils.parseEther('100')
      this.initialRate = this.initialRateBN.toString()
      this.termOfValidityBN = ethers.BigNumber.from('3600')
      this.termOfValidity = this.termOfValidityBN.toString()
      this.startTime = Date.parse(new Date()) / 1000 + 13600
      this.endTimeBN =
        ethers.BigNumber.from(this.startTime) + this.termOfValidityBN
      this.endTime = this.endTimeBN.toString()
      this.slopeBN = this.initialRateBN.div(this.termOfValidityBN)
      this.slope = this.slopeBN.toString()
      this.maxSupply = 100

      this.constructorParameter = [
        'test_name',
        'test_symbol',
        'https://test_url.com/',
        ethers.constants.AddressZero,
        this.beneficiary.address,
        this.initialRate,
        this.startTime,
        this.termOfValidity,
        this.maxSupply,
      ]

      const tx = await this.factory
        .connect(this.creator)
        .fixedPeriodDeploy(...this.constructorParameter)

      const receipt = await tx.wait()
      for (const event of receipt.events) {
        switch (event.event) {
          case 'FixedPeriodDeploy': {
            this.fixedPriceAddr = event.args[0]
          }
        }
      }

      this.options = {
        value: this.initialRate,
      }
      this.shortOptions = {
        value: (this.initialRateBN / 2).toString(),
      }

      let fixedPricePeriodFactory = await hre.ethers.getContractFactory(
        'FixedPeriod'
      )
      this.fixedPeriod = fixedPricePeriodFactory.attach(this.fixedPriceAddr)
    })

    describe('Public Info Check: owner, erc20 Address, rate, maxSupply, platform, platformRate', () => {
      it('check base info', async () => {
        expect(await this.fixedPeriod.owner()).to.eq(this.creator.address)
        expect(await this.fixedPeriod.erc20()).to.eq(
          ethers.constants.AddressZero
        )
        // expect(await this.fixedPeriod.rate()).to.eq(
        //   ethers.utils.parseEther(this.initialRate)
        // )
        expect(await this.fixedPeriod.maxSupply()).to.eq(this.maxSupply)
        expect(await this.fixedPeriod.platform()).to.eq(this.platform.address)
        expect(await this.fixedPeriod.platformRate()).to.eq(this.platformRate)
      })

      it('only owner can set baseUrl', async () => {
        const newBaseUrl = 'https://newBaserul.com/'
        await expect(
          this.fixedPeriod.setBaseURI(newBaseUrl)
        ).to.be.revertedWith(
          `AccessControl: account ${this.deployer.address.toLowerCase()} is missing role ${
            ethers.constants.HashZero
          }`
        )
      })
    })

    describe('Mint & Burn', () => {
      it('succeeds when receive ether', async () => {
        await network.provider.send('evm_setNextBlockTimestamp', [
          this.startTime + 660,
        ])
        await network.provider.send('evm_mine')

        // user 1 mint with token id 1
        await expect(this.fixedPeriod.connect(this.user1).mintEth(this.options))
          .to.emit(this.fixedPeriod, 'Mint')
          .withArgs(this.user1.address, 1)

        //user 3 mint with token id 2
        await expect(this.fixedPeriod.connect(this.user3).mintEth(this.options))
          .to.emit(this.fixedPeriod, 'Mint')
          .withArgs(this.user3.address, 2)
      })

      it('reverted when receive erc20 failed', async () => {
        // user 2 failed
        await expect(
          this.fixedPeriod.connect(this.user2).mintEth(),
          this.shortOptions
        ).to.be.reverted
      })

      it('succeeds when user1 mint (no platform fee)', async () => {
        // user 1 mint a token
        await expect(this.fixedPeriod.connect(this.user1).mintEth(this.options))
          .to.emit(this.fixedPeriod, 'Mint')
          .withArgs(this.user1.address, 1)

        await expect(this.fixedPeriod.connect(this.user1).withdraw())
          .to.emit(this.fixedPeriod, 'Withdraw')
          .withArgs(
            this.beneficiary.address,
            this.initialRateBN.sub(this.initialRateBN.mul(this.platformRate))
              .toString
          )

        //user 3 mint with token id 2
        await expect(this.fixedPeriod.connect(this.user3).mintEth(this.options))
          .to.emit(this.fixedPeriod, 'Mint')
          .withArgs(this.user3.address, 2)

        //user 3 mint with token id 3
        await expect(this.fixedPeriod.connect(this.user3).mintEth(this.options))
          .to.emit(this.fixedPeriod, 'Mint')
          .withArgs(this.user3.address, 3)

        await expect(this.fixedPeriod.connect(this.creator).withdraw())
          .to.emit(this.fixedPeriod, 'Withdraw')
          .withArgs(
            this.beneficiary.address,
            this.initialRateBN
              .sub(this.initialRateBN.mul(this.platformRate))
              .sub(ethers.BigNumber.from(2)).toString
          )
      })
    })
  })
})