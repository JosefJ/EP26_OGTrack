# Generating Merkle Proofs on the Frontend

This guide shows how to generate a proof for `OGAuthSignup` from a frontend app.

Your contract expects:

- leaf format: `keccak256(abi.encodePacked(address))`
- sorted pair hashing (because contract sorts pair values before hashing)
- `signup(bytes32[] proof)` with exact `depositAmountWei`

---

## 1) Install Dependencies

```bash
npm install merkletreejs viem
```

---

## 2) Frontend Utility (TypeScript)

Create a utility like `src/lib/merkle.ts`:

```ts
import { MerkleTree } from "merkletreejs";
import { encodePacked, keccak256, isAddress, getAddress, type Hex } from "viem";

// Must match Solidity:
// bytes32 leaf = keccak256(abi.encodePacked(account));
export function addressLeaf(account: string): Hex {
  const checksum = getAddress(account); // normalizes 0x address
  return keccak256(encodePacked(["address"], [checksum]));
}

export function buildMerkleTree(addresses: string[]) {
  const normalized = addresses.map((a) => getAddress(a));
  const leaves = normalized.map((a) => Buffer.from(addressLeaf(a).slice(2), "hex"));

  // Important: sortPairs true must match contract pair sorting
  const tree = new MerkleTree(leaves, (data: Buffer) => {
    const hex = `0x${data.toString("hex")}` as Hex;
    return Buffer.from(keccak256(hex).slice(2), "hex");
  }, { sortPairs: true });

  const root = `0x${tree.getRoot().toString("hex")}` as Hex;
  return { tree, root };
}

export function generateProofForAddress(tree: MerkleTree, account: string): Hex[] {
  if (!isAddress(account)) throw new Error("Invalid address");
  const leaf = Buffer.from(addressLeaf(account).slice(2), "hex");
  return tree.getHexProof(leaf) as Hex[];
}
```

---

## 3) Build the Tree from Your Snapshot

You need a snapshot list of eligible addresses (JSON, API, or static file). Example:

```ts
import { buildMerkleTree, generateProofForAddress } from "./lib/merkle";

const eligibleAddresses = [
  "0x1111111111111111111111111111111111111111",
  "0x2222222222222222222222222222222222222222",
  // ...
];

const { tree, root } = buildMerkleTree(eligibleAddresses);
console.log("Merkle root:", root);
```

Deploy your contract with this root, or update with `setRootHash(root)`.

---

## 4) Generate Proof for Connected Wallet

```ts
const proof = generateProofForAddress(tree, userWalletAddress);
console.log("Proof:", proof);
```

If wallet is not in the snapshot list, proof will be empty/invalid and `signup` will revert with `InvalidProof()`.

---

## 5) Call `signup` from Frontend

Example with `viem` wallet client:

```ts
import { parseEther } from "viem";

// If your contract deposit is configurable, read it from contract first:
// const depositAmountWei = await publicClient.readContract({ ... , functionName: "depositAmountWei" });

const txHash = await walletClient.writeContract({
  address: contractAddress,
  abi: ogAuthSignupAbi,
  functionName: "signup",
  args: [proof],
  value: parseEther("0.1"), // or depositAmountWei read from contract
});
```

---

## Common Pitfalls

- **Wrong leaf encoding**: must be `abi.encodePacked(address)` style.
- **Pair sorting mismatch**: frontend tree must use sorted pairs (`sortPairs: true`).
- **Different address format**: normalize to checksum (`getAddress`) before hashing.
- **Wrong root on contract**: contract `rootHash` must equal the tree root used to build proofs.
- **Wrong deposit value**: `msg.value` must equal `depositAmountWei`.

---

## About Historical Block-State Proofs

This frontend flow is for a **snapshot Merkle tree** (allowlist model).

If you want true Ethereum historical account inclusion proofs (state trie at old block), that is a different proof system (EIP-1186 / Merkle-Patricia trie) and is significantly more complex than `merkletreejs` snapshots.
