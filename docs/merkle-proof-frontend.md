# Generating MPT Account Proofs on the Frontend

This guide shows how to call `signup(bytes[] proof)` on `OGAuthSignup` from a frontend.

No address allowlist needed. Any address that had a non-zero ETH balance at the
snapshot block can prove inclusion directly from the Ethereum state trie using
`eth_getProof` (EIP-1186).

---

## How it works

1. The contract stores the **state root** of a specific mainnet block as `rootHash`.
2. `eth_getProof` returns an **MPT account proof** — the raw RLP-encoded nodes that
   walk from the state root down to the account leaf.
3. The contract's on-chain MPT verifier replays that walk, confirms the hash chain,
   and reads the account's balance from the leaf.
4. If `balance > 0`, the signup is accepted.

---

## Contract details (Sepolia)

| Field | Value |
|---|---|
| Address | `0xd43965821f8d40dd449760aA39a934Ff0b87dba7` |
| Snapshot block | `24735342` |
| State root | `0x5038ecf2e77e42cd3f8290e61388bb297250ae25fb11e64f94472ab4a9d57a57` |
| Deposit | `0.01 ETH` |
| Function | `signup(bytes[] proof)` |

---

## 1) Dependencies

```bash
npm install viem dotenv
```

---

## 2) Environment

Add to `.env`:

```
ETH_MAINNET_RPC=https://mainnet.infura.io/v3/YOUR_KEY
```

Needs an **archive-capable** mainnet RPC. The snapshot block must be within the
node's proof window. Infura free tier works for recent blocks.

---

## 3) Fetch the proof (TypeScript / viem)

```ts
import { createPublicClient, http, parseEther } from "viem";
import { mainnet } from "viem/chains";

const SNAPSHOT_BLOCK = 24735342n;

const publicClient = createPublicClient({
  chain: mainnet,
  transport: http(process.env.ETH_MAINNET_RPC),
});

async function getSignupProof(address: `0x${string}`): Promise<`0x${string}`[]> {
  const result = await publicClient.getProof({
    address,
    storageKeys: [],
    blockNumber: SNAPSHOT_BLOCK,
  });

  if (result.balance === 0n) {
    throw new Error("Address had no ETH balance at the snapshot block — not eligible");
  }

  // accountProof is already the right type: 0x-prefixed hex strings
  return result.accountProof;
}
```

---

## 4) Call `signup` from the frontend

```ts
import { parseEther } from "viem";

const CONTRACT_ADDRESS = "0xd43965821f8d40dd449760aA39a934Ff0b87dba7";
const DEPOSIT = parseEther("0.01");

const proof = await getSignupProof(walletAddress);

const txHash = await walletClient.writeContract({
  address: CONTRACT_ADDRESS,
  abi: ogAuthSignupAbi,
  functionName: "signup",
  args: [proof],
  value: DEPOSIT,
});
```

---

## 5) ABI (signup function only)

```json
[
  {
    "type": "function",
    "name": "signup",
    "stateMutability": "payable",
    "inputs": [{ "name": "proof", "type": "bytes[]" }],
    "outputs": []
  }
]
```

---

## Manual verification (Etherscan)

Run `node proof.js` (with `ETH_MAINNET_RPC` in `.env`) to get the proof for the
configured address. The script prints a single line ready to paste into the
`proof` field on Etherscan:

```
["0xf90211a0...","0xf90211a0...","0xf851..."]
```

---

## Common errors

| Revert | Cause |
|---|---|
| `ZeroBalance()` | Address had no ETH at the snapshot block |
| `HashMismatch(n)` | Wrong RPC block / proof nodes corrupted |
| `PathMismatch()` | Proof is for a different address |
| `ProofIncomplete()` | Empty or truncated proof array |
| `IncorrectDeposit()` | `msg.value` ≠ `depositAmountWei` |
| `AlreadySignedUp()` | Address already called `signup` |
| `SignupSlotsFull()` | All slots taken |
