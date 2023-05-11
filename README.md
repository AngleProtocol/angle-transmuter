# <img src="logo.svg" alt="Kheops" height="40px"> Angle - Kheops

[![CI](https://github.com/AngleProtocol/kheops/workflows/CI/badge.svg)](https://github.com/AngleProtocol/kheops/actions?query=workflow%3ACI)

## What is Kheops?

Kheops is an autonomous and modular price stability module for decentralized stablecoin protocols.

- It suppor
- It

It is composable with any stablecoin systems. It should notably be used as a standalone module within the Angle Protocol for agEUR in parallel notably with the

---

## Contracts Architecture

The Kheops system relies on a [diamond proxy pattern](https://eips.ethereum.org/EIPS/eip-2535). There is as such only one main contract (the `Kheops` contract) which delegates calls to different facets each with their own implementation. The main facets of the system are:

- the [`Swapper`](./contracts/kheops/facets/Swapper.sol) facet with the logic associated to the mint and burn functionalities of the system
- the [`Redeemer`](./contracts/kheops/facets/Redeemer.sol) facet for redemptions
- the [`Getters`](./contracts/kheops/facets/Swapper.sol) facet with external getters for UIs and contracts built on top of `Kheops`
- the [`Setters`] facet governance can use to update system parameters.

The storage parameters of the system are defined in the [`Storage`](./contracts/kheops/Storage.sol).

The Kheops system can come with optional [ERC4626](https://eips.ethereum.org/EIPS/eip-4626) [savings contracts](./contracts/savings/) which can be used to distribute a yield to the holders of the stablecoin issued through Kheops.

---

## Documentation

- [Kheops Whitepaper](https://docs.angle.money/overview/whitepapers)
- [Angle Documentation](https://docs.angle.money)
- [Angle Developers Documentation](https://developers.angle.money)

---

## Security

### Audits

Audits for Kheops smart contracts can be found in the [audits](./audits/)' folder.

### Bug Bounty

A bug bounty is open on Immunefi and Hats Finance. The rewards and scope of the Immunefi are defined here.

---

## Deployment Addresses

### agEUR - Kheops (Ethereum)

- Kheops (agEUR):

---

## Development

---

## Questions & Feedback

For any question or feedback you can send an email to [contact@angle.money](mailto:contact@angle.money).

---

## Licensing

The primary license for this repository is the Business Source License 1.1 (`BUSL-1.1`). See [`LICENSE`](./LICENSE).

This repository proposes a template that mixes hardhat and foundry frameworks. It also provides templates for EVM compatible smart contracts (in `./contracts/examples`), tests and deployment scripts.

### Getting started

### Install packages

You can install all dependencies by running

```bash
yarn
forge i
```

### Create `.env` file

In order to interact with non local networks, you must create an `.env` that has:

- `PRIVATE_KEY`
- `MNEMONIC`
- network key (eg. `ALCHEMY_NETWORK_KEY`)
- `ETHERSCAN_API_KEY`

For additional keys, you can check the `.env.example` file.

Warning: always keep your confidential information safe.

## Headers

To automatically create headers, follow: <https://github.com/Picodes/headers>

## Hardhat Command line completion

Follow these instructions to have hardhat command line arguments completion: <https://hardhat.org/hardhat-runner/docs/guides/command-line-completion>

## Foundry Installation

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

### Foundry on Docker 🐳

**If you don’t want to install Rust and Foundry on your computer, you can use Docker**
Image is available here [ghcr.io/foundry-rs/foundry](http://ghcr.io/foundry-rs/foundry).

```bash
docker pull ghcr.io/foundry-rs/foundry
docker tag ghcr.io/foundry-rs/foundry:latest foundry:latest
```

To run the container:

```bash
docker run -it --rm -v $(pwd):/app -w /app foundry sh
```

Then you are inside the container and can run Foundry’s commands.

### Tests

You can run tests as follows:

```bash
forge test -vvvv --watch
forge test -vvvv --match-path contracts/forge-tests/KeeperMulticall.t.sol
forge test -vvvv --match-test "testAbc*"
forge test -vvvv --fork-url https://eth-mainnet.alchemyapi.io/v2/Lc7oIGYeL_QvInzI0Wiu_pOZZDEKBrdf
```

You can also list tests:

```bash
forge test --list
forge test --list --json --match-test "testXXX*"
```

### Deploying

There is an example script in the `scripts/foundry` folder. Then you can run:

```bash
yarn foundry:deploy <FILE_NAME> --rpc-url <NETWORK_NAME>
```

Example:

```bash
yarn foundry:deploy scripts/foundry/DeployMockAgEUR.s.sol --rpc-url goerli
```

### Coverage

We recommend the use of this [vscode extension](ryanluker.vscode-coverage-gutters).

```bash
yarn hardhat:coverage
yarn foundry:coverage
```

Otherwise you can install lcov `brew install lcov`:

```bash
genhtml lcov.info --output=coverage
```

### Gas report

```bash
yarn foundry:gas
```

## Slither

```bash
pip3 install slither-analyzer
pip3 install solc-select
solc-select install 0.8.11
solc-select use 0.8.11
slither .
```

## Media

Don't hesitate to reach out on [Twitter](https://twitter.com/AngleProtocol) 🐦
