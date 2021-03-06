const { toGD } = require("./helpers");
const settings = require("./deploy-settings.json");
const Identity = artifacts.require("./Identity");
const Avatar = artifacts.require("./Avatar.sol");
const AbsoluteVote = artifacts.require("./AbsoluteVote.sol");
const SchemeRegistrar = artifacts.require("./SchemeRegistrar.sol");
const SignupBonus = artifacts.require("./SignUpBonus.sol");
const AdminWallet = artifacts.require("./AdminWallet.sol");

const releaser = require("../scripts/releaser.js");
const fse = require("fs-extra");

const NULL_ADDRESS = "0x0000000000000000000000000000000000000000";
const NULL_HASH = "0x0000000000000000000000000000000000000000000000000000000000000000";

module.exports = async function (deployer, network) {
  if (network.indexOf("test") < 0) {
    console.log("Depracted old signup bonus scheme");
    return;
  }
  if (network.indexOf("mainnet") >= 0) {
    console.log("Skipping signup bonus for mainnet");
    return;
  }
  const networkSettings = { ...settings["default"], ...settings[network] };
  const file = await fse.readFile("releases/deployment.json", "utf8");
  const previousDeployment = await JSON.parse(file);
  const networkAddresses = previousDeployment[network];

  const avataraddr = await networkAddresses.Avatar;
  const voteaddr = await networkAddresses.AbsoluteVote;
  const schemeaddr = await networkAddresses.SchemeRegistrar;
  const identityaddr = await networkAddresses.Identity;
  const walletaddr = await networkAddresses.AdminWallet;

  await web3.eth.getAccounts(function (err, res) {
    accounts = res;
  });
  const founders = [accounts[0]];

  const avatar = await Avatar.at(avataraddr);
  const identity = await Identity.at(identityaddr);
  const absoluteVote = await AbsoluteVote.at(voteaddr);
  const schemeRegistrar = await SchemeRegistrar.at(schemeaddr);
  const adminWallet = await AdminWallet.at(walletaddr);

  const signupBonus = await deployer.deploy(
    SignupBonus,
    avatar.address,
    identity.address,
    toGD(networkSettings.totalRewards),
    toGD(networkSettings.maxUserRewards)
  );

  await adminWallet.setBonusContract(await signupBonus.address);

  let transaction = await schemeRegistrar.proposeScheme(
    avatar.address,
    signupBonus.address,
    NULL_HASH,
    "0x00000010",
    NULL_HASH
  );

  let proposalId = transaction.logs[0].args._proposalId;

  await Promise.all(
    founders.map(f => absoluteVote.vote(proposalId, 1, 0, f, { from: f, gas: 500000 }))
  );

  await signupBonus.start();

  let releasedContracts = {
    ...networkAddresses,
    SignupBonus: await signupBonus.address
  };

  console.log("Rewriting deployment file...\n", { releasedContracts });
  await releaser(releasedContracts, network);
};
