# Test

## Storage layout

To be able to test the storage layout, you can run the following command:

```bash
forge inspect Savings storageLayout > old
forge inspect SavingsNameable storageLayout > new
```

You can then compare the two files to see for possible storage collisions.

# Deploy

## Implementation

To deploy the contracts, you can run the following command:

```bash
CHAIN_ID=ID forge script DeploySavingsNameable
```

## Foundry

Then, head over to angle-multisig or angle-goverance repository and you can use the UpgradeAgTokenNameable script witht the new implementation address and the desired name and symbol.
