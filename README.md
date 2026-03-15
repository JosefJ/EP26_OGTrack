# EP26 OGTrack

This repository is for the **"OGs aren't jaded"** track of the **ETHPrague 2026** hackathon.

## Goal

The project explores an on-chain signup flow that should require proof that an address was valid prior to a specific historical block.

For this track, the reference point is:

- **Block number:** `69420067`
- **Date mined:** Dec 24, 2018

## What This Repo Contains

- `src/OGAuthSignup.sol` - signup contract with:
  - owner-controlled configuration
  - deposit requirement
  - Merkle proof validation
  - indexed signup storage for iteration
- `test/OGAuthSignup.t.sol` - Foundry tests for signup behavior, ownership controls, and proof validation paths
- `docs/merkle-proof-frontend.md` - frontend guide for Merkle tree/proof generation

## Note on Proof Model

The current implementation validates against a configured Merkle root (`rootHash`).
To prove historical Ethereum state inclusion at a specific block in a trust-minimized way, you would typically need EIP-1186 account/storage proof verification (Merkle-Patricia trie), which is a different and more complex proof system.
