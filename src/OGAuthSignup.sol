// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @notice Minimal Merkle proof verification for sorted pair trees.
library MerkleProofLib {
    function verifyCalldata(
        bytes32[] calldata proof,
        bytes32 root,
        bytes32 leaf
    ) internal pure returns (bool) {
        return processProofCalldata(proof, leaf) == root;
    }

    function processProofCalldata(
        bytes32[] calldata proof,
        bytes32 leaf
    ) internal pure returns (bytes32 computedHash) {
        computedHash = leaf;
        for (uint256 i = 0; i < proof.length; i++) {
            computedHash = _hashPair(computedHash, proof[i]);
        }
    }

    function _hashPair(bytes32 a, bytes32 b) private pure returns (bytes32) {
        return a < b ? keccak256(abi.encodePacked(a, b)) : keccak256(abi.encodePacked(b, a));
    }
}

/// @title OGAuthSignup
/// @notice Accepts a fixed deposit from addresses proven in a snapshot Merkle root.
contract OGAuthSignup {
    using MerkleProofLib for bytes32[];

    error IncorrectDeposit();
    error AlreadySignedUp();
    error InvalidProof();
    error SignupSlotsFull();
    error NotOwner();
    error InvalidOwner();
    error SlotsBelowCurrentSignups();
    error NotSignedUp();
    error RefundFailed();

    address public owner;
    uint256 public depositAmountWei;
    bytes32 public rootHash;
    uint256 public signupSlots;

    // Tracks how much each address deposited. 0 means not signed up (or removed).
    mapping(address => uint256) public depositedAmountByAddress;
    // 0-based iterative storage: 0,1,2,3...
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
        owner = msg.sender;
        rootHash = _rootHash;
        depositAmountWei = _depositAmountWei;
        signupSlots = _signupSlots;
    }

    /// @notice Sign up by posting a Merkle proof that msg.sender is in the configured root hash.
    /// @dev Leaf format: keccak256(abi.encodePacked(account)).
    function signup(bytes32[] calldata proof) external payable {
        if (signupCount >= signupSlots) revert SignupSlotsFull();
        if (msg.value != depositAmountWei) revert IncorrectDeposit();
        if (depositedAmountByAddress[msg.sender] != 0) revert AlreadySignedUp();

        bytes32 leaf = keccak256(abi.encodePacked(msg.sender));
        bool valid = proof.verifyCalldata(rootHash, leaf);
        if (!valid) revert InvalidProof();

        uint256 index = signupCount;
        signupByIndex[index] = msg.sender;
        depositedAmountByAddress[msg.sender] = msg.value;
        signupCount = index + 1;

        emit SignedUp(msg.sender, index, msg.value);
    }

    function isSignedUp(address account) external view returns (bool) {
        return depositedAmountByAddress[account] != 0;
    }

    /// @notice Owner removes a signup, refunds the user's deposit, and clears indexed slot.
    function removeSignup(address account) external onlyOwner {
        uint256 amount = depositedAmountByAddress[account];
        if (amount == 0) revert NotSignedUp();

        depositedAmountByAddress[account] = 0;

        for (uint256 i = 0; i < signupCount; i++) {
            if (signupByIndex[i] == account) {
                signupByIndex[i] = address(0);
                break;
            }
        }

        (bool ok, ) = payable(account).call{value: amount}("");
        if (!ok) revert RefundFailed();
    }

    function setDepositAmountWei(uint256 newDepositAmountWei) external onlyOwner {
        uint256 previousAmountWei = depositAmountWei;
        depositAmountWei = newDepositAmountWei;
        emit DepositAmountUpdated(previousAmountWei, newDepositAmountWei);
    }

    function setRootHash(bytes32 newRootHash) external onlyOwner {
        bytes32 previousRootHash = rootHash;
        rootHash = newRootHash;
        emit RootHashUpdated(previousRootHash, newRootHash);
    }

    function setSignupSlots(uint256 newSignupSlots) external onlyOwner {
        if (newSignupSlots < signupCount) revert SlotsBelowCurrentSignups();
        uint256 previousSlots = signupSlots;
        signupSlots = newSignupSlots;
        emit SignupSlotsUpdated(previousSlots, newSignupSlots);
    }

    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert InvalidOwner();
        address previousOwner = owner;
        owner = newOwner;
        emit OwnerUpdated(previousOwner, newOwner);
    }

    function withdraw(address payable to, uint256 amount) external onlyOwner {
        (bool ok, ) = to.call{value: amount}("");
        require(ok, "Withdraw failed");
        emit Withdrawn(to, amount);
    }
}
