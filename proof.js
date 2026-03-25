#!/usr/bin/env node
// Requires: Node 18+  (no extra deps — raw RLP nodes are passed as-is)
// Reads ETH_MAINNET_RPC from .env — needs an archive-capable mainnet node.

import { config } from "dotenv";
config();

const RPC_URL = process.env.ETH_MAINNET_RPC;
if (!RPC_URL) { console.error("Error: ETH_MAINNET_RPC not set in .env"); process.exit(1); }

const TARGET        = "0x978452C747ee0B617285cAf3c50Cae0103aF5656";
const EXPECTED_ROOT = "0x5038ecf2e77e42cd3f8290e61388bb297250ae25fb11e64f94472ab4a9d57a57";
const BLOCK_NUMBER  = 24735342;
const BLOCK_HEX     = "0x" + BLOCK_NUMBER.toString(16);

async function rpc(method, params) {
  const res = await fetch(RPC_URL, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ jsonrpc: "2.0", id: 1, method, params }),
  });
  const data = await res.json();
  if (data.error) throw new Error(JSON.stringify(data.error, null, 2));
  return data.result;
}

async function main() {
  const block = await rpc("eth_getBlockByNumber", [BLOCK_HEX, false]);

  if (block.stateRoot.toLowerCase() !== EXPECTED_ROOT.toLowerCase()) {
    throw new Error(
      `stateRoot mismatch:\n  got:      ${block.stateRoot}\n  expected: ${EXPECTED_ROOT}`
    );
  }

  const proof = await rpc("eth_getProof", [TARGET, [], BLOCK_HEX]);
  const nodes = proof.accountProof; // raw hex-encoded RLP nodes — passed as-is to contract

  const balance = BigInt(proof.balance);

  console.log("\n=== eth_getProof result ===");
  console.log("address:    ", TARGET);
  console.log("block:      ", BLOCK_NUMBER, `(${block.hash})`);
  console.log("state_root: ", block.stateRoot);
  console.log("balance:    ", balance.toString(), "wei");
  console.log("proof nodes:", nodes.length);

  if (balance === 0n) {
    console.error("\nERROR: account has zero balance at this block — contract will revert with ZeroBalance()");
    process.exit(1);
  }

  // Etherscan accepts bytes[] as: ["0xaabbcc...","0xddeeff...",...]
  const etherscanParam = '["' + nodes.join('","') + '"]';

  console.log("\n=== Paste this into the `proof` field on Etherscan ===");
  console.log(etherscanParam);
}

main().catch((e) => { console.error("\nError:", e.message); process.exit(1); });
