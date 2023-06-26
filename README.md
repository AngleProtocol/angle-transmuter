# <img src="logo.svg" alt="Transmuter" height="40px"> Angle - Transmuter

[![Transmuter CI](https://github.com/AngleProtocol/angle-transmuter/workflows/Transmuter%20CI/badge.svg)](https://github.com/AngleProtocol/angle-transmuter/actions)

## What is Transmuter?

Transmuter is an autonomous and modular price stability module for decentralized stablecoin protocols.

- It is conceived as a basket of different assets (normally stablecoins) backing a stablecoin and comes with guarantees on the maximum exposure the stablecoin can have to each asset in the basket.
- A stablecoin issued through the Transmuter system can be minted at oracle value from any of the assets with adaptive fees, and it can be burnt for any of the assets in the backing with variable fees as well. It can also be redeemed at any time against a proportional amount of each asset in the backing.

Transmuter is compatible with other common mechanisms often used to issue stablecoins like collateralized-debt position models. It should notably be used as a standalone module within the Angle Protocol for agEUR in parallel with the Borrowing module.

---

## Contracts Architecture 🏘️

The Transmuter system relies on a [diamond proxy pattern](https://eips.ethereum.org/EIPS/eip-2535). There is as such only one main contract (the `Transmuter` contract) which delegates calls to different facets each with their own implementation. The main facets of the system are:

- the [`Swapper`](./contracts/transmuter/facets/Swapper.sol) facet with the logic associated to the mint and burn functionalities of the system
- the [`Redeemer`](./contracts/transmuter/facets/Redeemer.sol) facet for redemptions
- the [`Getters`](./contracts/transmuter/facets/Getters.sol) facet with external getters for UIs and contracts built on top of `Transmuter`
- the [`SettersGovernor`](./contracts/transmuter/facets/SettersGovernor.sol) facet protocols' governance can use to update system parameters.
- the [`SettersGuardian`](./contracts/transmuter/facets/SettersGuardian.sol) facet protocols' guardian can use to update system parameters.

The storage parameters of the system are defined in the [`Storage`](./contracts/transmuter/Storage.sol) file.

The Transmuter system can come with optional [ERC4626](https://eips.ethereum.org/EIPS/eip-4626) [savings contracts](./contracts/savings/) which can be used to distribute a yield to the holders of the stablecoin issued through the Transmuter.

---

## Documentation 📚

- [Transmuter Whitepaper](https://docs.angle.money/overview/whitepapers)
- [Angle Documentation](https://docs.angle.money)
- [Angle Developers Documentation](https://developers.angle.money)

---

## Security ⛑️

### Trust assumptions of the Transmuter system

The governor role, which will be a multisig or an onchain governance, has all rights, including upgrading contracts, removing funds, changing the code, etc.

The guardian role, which will be a multisig, has the right to: freeze assets, and potentially impact transient funds. The idea is that any malicious behavior of the guardian should be fixable by the governor, and that the guardian shouldn't be able to extract funds from the system.

### Known Issues

- Lack of support for ERC165
- At initialization, fees need to be < 100% for 100% exposure because the first exposures will be ~100%
- If at some point there are 0 funds in the system it’ll break as `amountToNextBreakPoint` will be 0
- In the burn, if there is one asset which is making 99% of the basket, and another one 1%: if the one making 1% depegs, it still impacts the burn for the asset that makes the majority of the funds
- The whitelist function for burns and redemptions are somehow breaking the fairness of the system as whitelisted actors will redeem more value

### Audits

Audits for Transmuter smart contracts can be found in the [audits](./audits/)' folder.

---

### Bug Bounty

For contracts deployed for the Angle Protocol, a bug bounty is open on [Immunefi](https://immunefi.com) and [Hats Finance](https://hats.finance). The rewards and scope of the Angle Immunefi are defined [here](https://immunefi.com/bounty/angleprotocol/).

---

## Deployment Addresses 🚦

### agEUR - Transmuter (Ethereum)

- Transmuter (agEUR):

---

## Development 🛠️

This repository is built on [Foundry](https://github.com/foundry-rs/foundry).

### Getting started

#### Install Foundry

If you don't have Foundry:

```bash
curl -L https://foundry.paradigm.xyz | bash

source /root/.zshrc
# or, if you're under bash: source /root/.bashrc

foundryup
```

To install the standard library:

```bash
forge install foundry-rs/forge-std
```

To update libraries:

```bash
forge update
```

#### Install packages

You can install all dependencies by running

```bash
yarn
forge i
```

### Warning

This repository uses [`ffi`](https://book.getfoundry.sh/cheatcodes/ffi) in its test suite. Beware as a malicious actor forking this repo could add malicious commands using this.

#### Create `.env` file

In order to interact with non local networks, you must create an `.env` that has:

- a `MNEMONIC` for each of the chain you
- a network key
- an `ETHERSCAN_API_KEY`

For additional keys, you can check the [`.env.example`](/.env.example) file.

Warning:

- always keep your confidential information safe
- this repository uses [`ffi`](https://book.getfoundry.sh/cheatcodes/ffi) in its test suite. Beware as a malicious actor forking this repo may execute malicious commands on your machine

---

### Compilation

Compilation of production contracts will be done using the via-ir pipeline.

However, tests do not compile with via-ir, and to run coverage the optimizer needs to be off. Therefore for development and test purposes you can compile without optimizer.

```bash
yarn compile # with via-ir but without compiling tests files
yarn compile:dev # without optimizer
```

### Testing

Here are examples of how to run the test suite:

```bash
yarn test
FOUNDRY_PROFILE=dev forge test -vvv --watch # To watch changing files
FOUNDRY_PROFILE=dev forge test -vvv --match-path test/fuzz/Redeemer.test.sol
FOUNDRY_PROFILE=dev forge test -vvv --match-test "testAbc*"
FOUNDRY_PROFILE=dev forge test -vvv --fork-url <RPC_URL>
```

You can also list tests:

```bash
FOUNDRY_PROFILE=dev forge test --list
FOUNDRY_PROFILE=dev forge test --list --json --match-test "testXXX*"
```

---

### Deploying

There is an example script in the `scripts/foundry` folder. Then you can run:

```bash
yarn foundry:deploy <FILE_NAME> --rpc-url <NETWORK_NAME>
```

---

### Coverage

We recommend the use of this [vscode extension](ryanluker.vscode-coverage-gutters).

```bash
yarn coverage
```

You'll need to install lcov `brew install lcov` to visualize the coverage report.

---

### Gas report ⛽️

```bash
yarn gas
```

---

### [Slither](https://github.com/crytic/slither)

```bash
yarn slither
```

---

## Contributing

If you're interested in contributing, please see our [contributions guidelines](./CONTRIBUTING.md).

---

## Questions & Feedback

For any question or feedback you can send an email to [contact@angle.money](mailto:contact@angle.money). Don't hesitate to reach out on [Twitter](https://twitter.com/AngleProtocol)🐦 as well.

---

## Licensing

The primary license for this repository is the Business Source License 1.1 (`BUSL-1.1`). See [`LICENSE`](./LICENSE). Minus the following exceptions:

- [Interfaces](contracts/interfaces/) have a General Public License
- [Some libraries](contracts/transmuter/libraries/LibHelpers.sol) have a General Public License

Each of these files states their license type.
