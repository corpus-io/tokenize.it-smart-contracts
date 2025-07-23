// test/PrivateOfferGasTest.js
const { expect } = require('chai');
const { ethers } = require('hardhat');
const {
  loadFixture,
} = require('@nomicfoundation/hardhat-toolbox/network-helpers');

// Constants from your Foundry tests
const TRUSTED_CURRENCY = BigInt(2n ** 255n); // From AllowList.sol
const paymentTokenAmount = ethers.parseUnits('1000', 6);
const price = ethers.parseUnits('7', 6); // 7 payment tokens per token
const tokenBuyAmount = ethers.parseUnits('5', 18); // 5 tokens
const deadline = Math.floor(Date.now() / 1000) + 30 * 24 * 60 * 60; // 30 days from now

async function deployAllFixture() {
  const [
    platformAdmin,
    companyAdmin,
    investor,
    platformHotWallet,
    paymentTokenProvider,
    feeCollector,
    mintAllower,
  ] = await ethers.getSigners();

  // Deploy DummyForwarder (to replace OpenGSN Forwarder)
  const DummyForwarder = await ethers.getContractFactory('DummyForwarder');
  const forwarder = await DummyForwarder.deploy();
  await forwarder.waitForDeployment();

  // Deploy AllowList implementation
  const AllowList = await ethers.getContractFactory('AllowList');
  const allowListImpl = await AllowList.deploy(forwarder.target);
  await allowListImpl.waitForDeployment();

  // Deploy AllowListCloneFactory
  const AllowListCloneFactory = await ethers.getContractFactory(
    'AllowListCloneFactory',
  );
  const allowListFactory = await AllowListCloneFactory.deploy(
    allowListImpl.target,
  );
  await allowListFactory.waitForDeployment();

  // Create AllowList clone with salt
  const salt = ethers.ZeroHash; // or ethers.keccak256(ethers.toUtf8Bytes('some salt'))
  const allowListTx = await allowListFactory.createAllowListClone(
    salt,
    forwarder.target,
    platformAdmin.address,
  );
  const allowListReceipt = await allowListTx.wait();

  // Extract clone address from NewClone event
  const iface = new ethers.Interface(['event NewClone(address clone)']);
  const cloneLog = allowListReceipt.logs.find(
    (log) => log.topics[0] === iface.getEvent('NewClone').topicHash,
  );
  const parsedLog = iface.parseLog(cloneLog);
  const allowListAddress = parsedLog.args.clone;

  const allowList = await ethers.getContractAt('AllowList', allowListAddress);

  // Deploy FeeSettings implementation
  const FeeSettingsImpl = await ethers.getContractFactory('FeeSettings');
  const feeSettingsImpl = await FeeSettingsImpl.deploy(forwarder.target);
  await feeSettingsImpl.waitForDeployment();

  // Deploy FeeSettingsCloneFactory (assume you have this contract; if not, create it similar to AllowListCloneFactory)
  const FeeSettingsCloneFactory = await ethers.getContractFactory(
    'FeeSettingsCloneFactory',
  ); // Add this contract if missing
  const feeSettingsFactory = await FeeSettingsCloneFactory.deploy(
    feeSettingsImpl.target,
  );
  await feeSettingsFactory.waitForDeployment();

  // Create FeeSettings clone
  const feeSalt = ethers.ZeroHash;
  const fees = {
    tokenFeeNumerator: 100,
    crowdinvestingFeeNumerator: 100,
    privateOfferFeeNumerator: 100,
    validityDate: 0,
  };
  const feeSettingsTx = await feeSettingsFactory.createFeeSettingsClone(
    feeSalt,
    forwarder.target,
    platformAdmin.address,
    fees,
    feeCollector.address,
    feeCollector.address,
    feeCollector.address,
  );
  const feeSettingsReceipt = await feeSettingsTx.wait();

  // Extract clone address from NewClone event (assume similar event)
  const feeIface = new ethers.Interface(['event NewClone(address clone)']);
  const feeCloneLog = feeSettingsReceipt.logs.find(
    (log) => log.topics[0] === feeIface.getEvent('NewClone').topicHash,
  );
  const feeParsedLog = feeIface.parseLog(feeCloneLog);
  const feeSettingsAddress = feeParsedLog.args.clone;

  const feeSettings = await ethers.getContractAt(
    'FeeSettings',
    feeSettingsAddress,
  );

  // Deploy Token implementation and factory
  const Token = await ethers.getContractFactory('Token');
  const tokenImpl = await Token.deploy(forwarder.target);
  await tokenImpl.waitForDeployment();

  const TokenProxyFactory =
    await ethers.getContractFactory('TokenProxyFactory');
  const tokenFactory = await TokenProxyFactory.deploy(tokenImpl.target);
  await tokenFactory.waitForDeployment();

  // Deploy Token proxy
  const token = await Token.attach(
    await tokenFactory.createTokenProxy(
      0,
      forwarder.target,
      feeSettings.target,
      companyAdmin.address,
      allowList.target,
      0,
      'TestToken',
      'TEST',
    ),
  );

  // Deploy fake currency (ERC20)
  const FakePaymentToken = await ethers.getContractFactory('FakePaymentToken');
  const paymentToken = await FakePaymentToken.connect(
    paymentTokenProvider,
  ).deploy(paymentTokenAmount, 6);
  await paymentToken.waitForDeployment();

  // Set trusted currency in AllowList
  await allowList
    .connect(platformAdmin)
    .set(paymentToken.target, TRUSTED_CURRENCY);

  // Transfer currency to investor
  await paymentToken
    .connect(paymentTokenProvider)
    .transfer(investor.address, paymentTokenAmount);

  // Deploy Vesting implementation and factory (needed for PrivateOfferFactory)
  const Vesting = await ethers.getContractFactory('Vesting');
  const vestingImpl = await Vesting.deploy(forwarder.target);
  await vestingImpl.waitForDeployment();

  const VestingCloneFactory = await ethers.getContractFactory(
    'VestingCloneFactory',
  );
  const vestingFactory = await VestingCloneFactory.deploy(vestingImpl.target);
  await vestingFactory.waitForDeployment();

  // Deploy PrivateOffer implementation and factory
  const PrivateOffer = await ethers.getContractFactory('PrivateOffer');
  const privateOfferImpl = await PrivateOffer.deploy();
  await privateOfferImpl.waitForDeployment();

  const PrivateOfferCloneFactory = await ethers.getContractFactory(
    'PrivateOfferCloneFactory',
  );
  const privateOfferFactory = await PrivateOfferCloneFactory.deploy(
    privateOfferImpl.target,
    vestingFactory.target,
  );
  await privateOfferFactory.waitForDeployment();

  return {
    platformAdmin,
    companyAdmin,
    investor,
    platformHotWallet,
    feeCollector,
    mintAllower,
    forwarder,
    allowList,
    feeSettings,
    token,
    paymentToken,
    privateOfferFactory,
  };
}

describe('PrivateOffer Gas Test', function () {
  it('Deploys, sets up, and executes Private Offer, logging gas cost', async function () {
    const {
      companyAdmin,
      investor,
      platformHotWallet,
      mintAllower,
      token,
      paymentToken,
      privateOfferFactory,
    } = await loadFixture(deployAllFixture);

    const investorColdWallet = ethers.Wallet.createRandom().address; // Simulated cold wallet

    // Calculate cost
    const costInPaymentToken =
      (tokenBuyAmount * price) / BigInt(10) ** BigInt(18);

    // Generate salt
    const salt = ethers.keccak256(ethers.toUtf8Bytes('random number'));

    // Prepare fixed and variable args
    const fixedArgs = [
      companyAdmin.address, // currencyReceiver
      ethers.ZeroAddress, // tokenHolder (0 for mint)
      tokenBuyAmount, // minTokenAmount
      tokenBuyAmount, // maxTokenAmount
      price, // tokenPrice
      deadline, // expiration
      paymentToken.target, // currency
      token.target, // token
    ];

    const variableArgs = [
      investor.address, // currencyPayer
      investorColdWallet, // tokenReceiver
      tokenBuyAmount, // tokenAmount
    ];

    // Predict PO address
    const predictedAddress = await privateOfferFactory.predictCloneAddress(
      salt,
      fixedArgs,
    );

    console.log('Predicted PrivateOffer address:', predictedAddress);

    // Grant mint allowance to predicted address
    await token
      .connect(companyAdmin)
      .grantRole(await token.MINTALLOWER_ROLE(), mintAllower.address);
    await token
      .connect(mintAllower)
      .increaseMintingAllowance(predictedAddress, tokenBuyAmount);

    // Sign EIP-2612 permit for currency allowance
    const domain = {
      name: await paymentToken.name(),
      version: '1',
      chainId: (await ethers.provider.getNetwork()).chainId,
      verifyingContract: paymentToken.target,
    };

    const types = {
      Permit: [
        { name: 'owner', type: 'address' },
        { name: 'spender', type: 'address' },
        { name: 'value', type: 'uint256' },
        { name: 'nonce', type: 'uint256' },
        { name: 'deadline', type: 'uint256' },
      ],
    };

    const value = {
      owner: investor.address,
      spender: predictedAddress,
      value: costInPaymentToken,
      nonce: await paymentToken.nonces(investor.address),
      deadline: deadline,
    };

    const signature = await investor._signTypedData(domain, types, value);
    const { v, r, s } = ethers.utils.splitSignature(signature);

    // Execute permit (via platformHotWallet)
    await paymentToken
      .connect(platformHotWallet)
      .permit(
        investor.address,
        predictedAddress,
        costInPaymentToken,
        deadline,
        v,
        r,
        s,
      );

    // Deploy PO clone and execute (get tx receipt for gas)
    const tx = await privateOfferFactory
      .connect(platformHotWallet)
      .createPrivateOfferClone(salt, fixedArgs, variableArgs);
    const receipt = await tx.wait();

    console.log(
      'Gas used for PrivateOffer deployment and execution:',
      receipt.gasUsed.toString(),
    );

    // Verify execution (optional assertions)
    expect(await token.balanceOf(investorColdWallet)).to.equal(tokenBuyAmount);
  });
});
