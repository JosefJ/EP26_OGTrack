// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @notice Minimal RLP decoder — only the operations needed for MPT account proofs.
library RLP {
    struct Item {
        uint256 offset;
        uint256 length;
        bool    isList;
    }

    function decode(bytes memory b, uint256 off)
        internal pure returns (Item memory it, uint256 next)
    {
        uint8 p = uint8(b[off]);
        if (p < 0x80) {
            it = Item(off, 1, false);   next = off + 1;
        } else if (p <= 0xb7) {
            uint256 l = p - 0x80;
            it = Item(off + 1, l, false); next = off + 1 + l;
        } else if (p <= 0xbf) {
            uint256 ll = p - 0xb7; uint256 l = _uint(b, off + 1, ll);
            it = Item(off + 1 + ll, l, false); next = off + 1 + ll + l;
        } else if (p <= 0xf7) {
            uint256 l = p - 0xc0;
            it = Item(off + 1, l, true); next = off + 1 + l;
        } else {
            uint256 ll = p - 0xf7; uint256 l = _uint(b, off + 1, ll);
            it = Item(off + 1 + ll, l, true); next = off + 1 + ll + l;
        }
    }

    /// @dev nth item (0-indexed) inside a list item.
    function nth(bytes memory b, Item memory list, uint256 n)
        internal pure returns (Item memory it)
    {
        uint256 off = list.offset;
        uint256 end = list.offset + list.length;
        for (uint256 i = 0; ; i++) {
            require(off < end, "RLP: oob");
            uint256 next;
            (it, next) = decode(b, off);
            if (i == n) return it;
            off = next;
        }
    }

    /// @dev Count items in a list.
    function listLen(bytes memory b, Item memory list)
        internal pure returns (uint256 n)
    {
        uint256 off = list.offset;
        uint256 end = list.offset + list.length;
        while (off < end) { (, uint256 next) = decode(b, off); n++; off = next; }
    }

    function toBytes(bytes memory b, Item memory it)
        internal pure returns (bytes memory r)
    {
        r = new bytes(it.length);
        for (uint256 i = 0; i < it.length; i++) r[i] = b[it.offset + i];
    }

    function toBytes32(bytes memory b, Item memory it)
        internal pure returns (bytes32 v)
    {
        require(it.length == 32, "RLP: not bytes32");
        uint256 off = it.offset;
        assembly { v := mload(add(add(b, 0x20), off)) }
    }

    function toUint(bytes memory b, Item memory it)
        internal pure returns (uint256 v)
    {
        for (uint256 i = 0; i < it.length; i++)
            v = (v << 8) | uint8(b[it.offset + i]);
    }

    function _uint(bytes memory b, uint256 off, uint256 len)
        private pure returns (uint256 v)
    {
        for (uint256 i = 0; i < len; i++) v = (v << 8) | uint8(b[off + i]);
    }
}

/// @notice Verifies Ethereum MPT account proofs (output of eth_getProof).
library MPTVerifier {
    using RLP for bytes;

    error HashMismatch(uint256 index);
    error PathMismatch();
    error ProofIncomplete();

    /// @notice Walk the proof and return the balance of `account` at `stateRoot`.
    ///         Reverts if the proof is invalid or the account is not found.
    function accountBalance(
        bytes32 stateRoot,
        address account,
        bytes[] calldata proof
    ) internal pure returns (uint256 balance) {
        // MPT key = keccak256(address) — 32 bytes / 64 nibbles
        bytes memory key = abi.encodePacked(keccak256(abi.encodePacked(account)));
        bytes memory accountRLP = _walk(stateRoot, key, proof);
        // Account RLP: [nonce, balance, storageHash, codeHash]
        (RLP.Item memory list,) = accountRLP.decode(0);
        RLP.Item memory balItem = accountRLP.nth(list, 1);
        balance = accountRLP.toUint(balItem);
    }

    function _walk(
        bytes32 root,
        bytes memory key,
        bytes[] calldata proof
    ) private pure returns (bytes memory) {
        bytes32 expected = root;
        uint256 nibIdx   = 0; // current nibble index into key (0..63)

        for (uint256 i = 0; i < proof.length; i++) {
            bytes memory node = proof[i];
            if (keccak256(node) != expected) revert HashMismatch(i);

            (RLP.Item memory nodeItem,) = node.decode(0);
            uint256 nLen = node.listLen(nodeItem);

            if (nLen == 17) {
                // ── Branch node ────────────────────────────────────────────
                if (nibIdx == 64) {
                    return node.toBytes(node.nth(nodeItem, 16));
                }
                uint256 nib   = _nibble(key, nibIdx++);
                RLP.Item memory child = node.nth(nodeItem, nib);
                if (child.length == 0) revert ProofIncomplete();
                expected = node.toBytes32(child);

            } else if (nLen == 2) {
                // ── Extension / Leaf node ───────────────────────────────────
                bytes memory enc   = node.toBytes(node.nth(nodeItem, 0));
                uint8  flags       = uint8(enc[0]) >> 4;
                bool   isLeaf      = flags >= 2;
                bool   isOdd       = (flags & 1) == 1;
                uint256 pStart     = isOdd ? 1 : 2; // nibble index in enc where path starts
                uint256 pLen       = enc.length * 2 - pStart;

                for (uint256 j = 0; j < pLen; j++) {
                    if (_nibble(enc, pStart + j) != _nibble(key, nibIdx + j))
                        revert PathMismatch();
                }
                nibIdx += pLen;

                RLP.Item memory second = node.nth(nodeItem, 1);
                if (isLeaf) return node.toBytes(second);
                expected = node.toBytes32(second); // extension → follow hash

            } else {
                revert("MPT: bad node");
            }
        }
        revert ProofIncomplete();
    }

    function _nibble(bytes memory b, uint256 i) private pure returns (uint256) {
        return (i & 1 == 0) ? (uint8(b[i >> 1]) >> 4) : (uint8(b[i >> 1]) & 0x0f);
    }
}

/// @title OGAuthSignup
/// @notice Accepts a fixed deposit from addresses proven to have had a balance
///         at the Ethereum block whose state root equals `rootHash`.
///         Proof = accountProof array from eth_getProof (raw RLP-encoded nodes).
contract OGAuthSignup {
    error IncorrectDeposit();
    error AlreadySignedUp();
    error InvalidProof();
    error ZeroBalance();
    error SignupSlotsFull();
    error NotOwner();
    error InvalidOwner();
    error SlotsBelowCurrentSignups();
    error NotSignedUp();
    error RefundFailed();

    address public owner;
    uint256 public depositAmountWei;
    bytes32 public rootHash;   // Ethereum block state root
    uint256 public signupSlots;

    mapping(address => uint256) public depositedAmountByAddress;
    mapping(uint256 => address) public signupByIndex;
    uint256 public signupCount;

    event SignedUp(address indexed account, uint256 indexed index, uint256 amount);
    event Withdrawn(address indexed to, uint256 amount);
    event OwnerUpdated(address indexed previousOwner, address indexed newOwner);
    event DepositAmountUpdated(uint256 previousAmountWei, uint256 newAmountWei);
    event RootHashUpdated(bytes32 previousRootHash, bytes32 newRootHash);
    event SignupSlotsUpdated(uint256 previousSlots, uint256 newSlots);

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    constructor(bytes32 _rootHash, uint256 _depositAmountWei, uint256 _signupSlots) {
        owner            = msg.sender;
        rootHash         = _rootHash;
        depositAmountWei = _depositAmountWei;
        signupSlots      = _signupSlots;
    }

    /// @notice Sign up by providing an MPT account proof (accountProof from eth_getProof)
    ///         proving msg.sender had a non-zero ETH balance at the snapshot block.
    /// @param proof Raw RLP-encoded MPT nodes (accountProof field from eth_getProof).
    function signup(bytes[] calldata proof) external payable {
        if (signupCount >= signupSlots)               revert SignupSlotsFull();
        if (msg.value != depositAmountWei)            revert IncorrectDeposit();
        if (depositedAmountByAddress[msg.sender] != 0) revert AlreadySignedUp();

        uint256 bal = MPTVerifier.accountBalance(rootHash, msg.sender, proof);
        if (bal == 0) revert ZeroBalance();

        uint256 index                           = signupCount;
        signupByIndex[index]                    = msg.sender;
        depositedAmountByAddress[msg.sender]    = msg.value;
        signupCount                             = index + 1;

        emit SignedUp(msg.sender, index, msg.value);
    }

    function isSignedUp(address account) external view returns (bool) {
        return depositedAmountByAddress[account] != 0;
    }

    function removeSignup(address account) external onlyOwner {
        uint256 amount = depositedAmountByAddress[account];
        if (amount == 0) revert NotSignedUp();
        depositedAmountByAddress[account] = 0;
        for (uint256 i = 0; i < signupCount; i++) {
            if (signupByIndex[i] == account) { signupByIndex[i] = address(0); break; }
        }
        (bool ok,) = payable(account).call{value: amount}("");
        if (!ok) revert RefundFailed();
    }

    function setDepositAmountWei(uint256 v) external onlyOwner {
        emit DepositAmountUpdated(depositAmountWei, v);
        depositAmountWei = v;
    }

    function setRootHash(bytes32 v) external onlyOwner {
        emit RootHashUpdated(rootHash, v);
        rootHash = v;
    }

    function setSignupSlots(uint256 v) external onlyOwner {
        if (v < signupCount) revert SlotsBelowCurrentSignups();
        emit SignupSlotsUpdated(signupSlots, v);
        signupSlots = v;
    }

    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert InvalidOwner();
        emit OwnerUpdated(owner, newOwner);
        owner = newOwner;
    }

    function withdraw(address payable to, uint256 amount) external onlyOwner {
        (bool ok,) = to.call{value: amount}("");
        require(ok, "Withdraw failed");
        emit Withdrawn(to, amount);
    }
}
