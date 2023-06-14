# <img src="logo.svg" alt="Transmuter" height="40px"> Angle - Transmuter

[![CI](https://github.com/AngleProtocol/angle-transmuter/workflows/CI/badge.svg)](https://github.com/AngleProtocol/angle-transmuter/actions?query=workflow%3ACI)

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
- the [`Getters`](./contracts/transmuter/facets/Swapper.sol) facet with external getters for UIs and contracts built on top of `Transmuter`
- the [`Setters`](./contracts/transmuter/facets/Setters.sol) facet protocols' governance can use to update system parameters.

The storage parameters of the system are defined in the [`Storage`](./contracts/transmuter/Storage.sol) file.

The Transmuter system can come with optional [ERC4626](https://eips.ethereum.org/EIPS/eip-4626) [savings contracts](./contracts/savings/) which can be used to distribute a yield to the holders of the stablecoin issued through Transmuter.

---

## Documentation 📚

- [Transmuter Whitepaper](https://docs.angle.money/overview/whitepapers)
- [Angle Documentation](https://docs.angle.money)
- [Angle Developers Documentation](https://developers.angle.money)

---

## Security ⛑️

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

#### Create `.env` file

In order to interact with non local networks, you must create an `.env` that has:

- a `MNEMONIC` for each of the chain you
- a network key
- an `ETHERSCAN_API_KEY`

For additional keys, you can check the [`.env.example`](/.env.example) file.

Warning: always keep your confidential information safe.

---

### Testing

You can run tests as follows:

```bash
forge test -vvvv --watch
forge test -vvvv --match-path test/fuzz/Redeemer.test.sol
forge test -vvvv --match-test "testAbc*"
forge test -vvvv --fork-url https://eth-mainnet.alchemyapi.io/v2/Lc7oIGYeL_QvInzI0Wiu_pOZZDEKBrdf
```

You can also list tests:

```bash
forge test --list
forge test --list --json --match-test "testXXX*"
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
yarn foundry:coverage
```

Otherwise you can install lcov `brew install lcov`:

```bash
genhtml lcov.info --output=coverage
```

---

### Gas report ⛽️

```bash
yarn foundry:gas
```

---

### [Slither](https://github.com/crytic/slither)

```bash
pip3 install slither-analyzer
pip3 install solc-select
solc-select install 0.8.17
solc-select use 0.8.17
slither .
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
