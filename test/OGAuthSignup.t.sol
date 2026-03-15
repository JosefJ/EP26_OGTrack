// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {OGAuthSignup} from "../src/OGAuthSignup.sol";

interface Vm {
    function prank(address msgSender) external;
    function deal(address account, uint256 newBalance) external;
}

contract OGAuthSignupTest {
    Vm internal constant vm =
        Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    bytes32 internal constant BLOCK_ROOT_HASH =
        0xe4a94c444f3bec7418611d2600726be173c56a01b6b0d297436fb54d360e1151;

    address internal constant ALICE = address(0xA11CE);
    address internal constant BOB = address(0xB0B);
    address internal constant TARGET =
        0x978452C747ee0B617285cAf3c50Cae0103aF5656;

    function testConstructorUsesProvidedBlockRoot() external {
        OGAuthSignup signup = new OGAuthSignup(BLOCK_ROOT_HASH, 0.1 ether, 10);
        require(signup.rootHash() == BLOCK_ROOT_HASH, "root hash mismatch");
    }

    function testRejectsInvalidProofForProvidedBlockRoot() external {
        OGAuthSignup signup = new OGAuthSignup(BLOCK_ROOT_HASH, 0.1 ether, 10);
        bytes32[] memory emptyProof = new bytes32[](0);

        vm.deal(ALICE, 1 ether);
        vm.prank(ALICE);
        (bool ok, bytes memory returndata) = address(signup).call{value: 0.1 ether}(
            abi.encodeWithSelector(signup.signup.selector, emptyProof)
        );

        require(!ok, "expected signup to revert");
        _assertRevertSelector(returndata, OGAuthSignup.InvalidProof.selector);
    }

    function testTargetAddressAgainstProvidedRootWithoutProofReverts() external {
        OGAuthSignup signup = new OGAuthSignup(BLOCK_ROOT_HASH, 0.1 ether, 10);
        bytes32[] memory emptyProof = new bytes32[](0);

        vm.deal(TARGET, 1 ether);
        vm.prank(TARGET);
        (bool ok, bytes memory returndata) = address(signup).call{value: 0.1 ether}(
            abi.encodeWithSelector(signup.signup.selector, emptyProof)
        );

        require(!ok, "expected signup to revert without valid proof");
        _assertRevertSelector(returndata, OGAuthSignup.InvalidProof.selector);
    }

    function testSignupStoresAddressAndIncrementsCounter() external {
        bytes32 aliceLeaf = keccak256(abi.encodePacked(ALICE));
        OGAuthSignup signup = new OGAuthSignup(aliceLeaf, 0.1 ether, 5);
        bytes32[] memory emptyProof = new bytes32[](0);

        vm.deal(ALICE, 1 ether);
        vm.prank(ALICE);
        signup.signup{value: 0.1 ether}(emptyProof);

        require(signup.depositedAmountByAddress(ALICE) == 0.1 ether, "alice deposit mismatch");
        require(signup.signupByIndex(0) == ALICE, "index 0 should be alice");
        require(signup.signupCount() == 1, "signup count should be 1");
    }

    function testSignupRevertsWhenSlotsAreFull() external {
        bytes32 aliceLeaf = keccak256(abi.encodePacked(ALICE));
        OGAuthSignup signup = new OGAuthSignup(aliceLeaf, 0.1 ether, 1);
        bytes32[] memory emptyProof = new bytes32[](0);

        vm.deal(ALICE, 1 ether);
        vm.prank(ALICE);
        signup.signup{value: 0.1 ether}(emptyProof);

        vm.deal(BOB, 1 ether);
        vm.prank(BOB);
        (bool ok, bytes memory returndata) = address(signup).call{value: 0.1 ether}(
            abi.encodeWithSelector(signup.signup.selector, emptyProof)
        );

        require(!ok, "expected slots full revert");
        _assertRevertSelector(returndata, OGAuthSignup.SignupSlotsFull.selector);
    }

    function testOwnerCanEditConfigAndNonOwnerCannot() external {
        OGAuthSignup signup = new OGAuthSignup(BLOCK_ROOT_HASH, 0.1 ether, 10);

        vm.prank(ALICE);
        (bool notOwnerOk, bytes memory notOwnerData) = address(signup).call(
            abi.encodeWithSelector(signup.setDepositAmountWei.selector, 0.2 ether)
        );
        require(!notOwnerOk, "non-owner update should revert");
        _assertRevertSelector(notOwnerData, OGAuthSignup.NotOwner.selector);

        signup.setDepositAmountWei(0.2 ether);
        require(signup.depositAmountWei() == 0.2 ether, "deposit amount not updated");

        signup.setRootHash(BLOCK_ROOT_HASH);
        require(signup.rootHash() == BLOCK_ROOT_HASH, "root hash not updated");

        signup.setSignupSlots(20);
        require(signup.signupSlots() == 20, "signup slots not updated");
    }

    function testCannotReduceSlotsBelowCurrentSignups() external {
        bytes32 aliceLeaf = keccak256(abi.encodePacked(ALICE));
        OGAuthSignup signup = new OGAuthSignup(aliceLeaf, 0.1 ether, 2);
        bytes32[] memory emptyProof = new bytes32[](0);

        vm.deal(ALICE, 1 ether);
        vm.prank(ALICE);
        signup.signup{value: 0.1 ether}(emptyProof);

        (bool ok, bytes memory returndata) = address(signup).call(
            abi.encodeWithSelector(signup.setSignupSlots.selector, 0)
        );
        require(!ok, "expected slots below signups revert");
        _assertRevertSelector(returndata, OGAuthSignup.SlotsBelowCurrentSignups.selector);
    }

    function testOwnerCanRemoveSignupRefundAndClearIndex() external {
        bytes32 aliceLeaf = keccak256(abi.encodePacked(ALICE));
        OGAuthSignup signup = new OGAuthSignup(aliceLeaf, 0.1 ether, 5);
        bytes32[] memory emptyProof = new bytes32[](0);

        vm.deal(ALICE, 1 ether);
        vm.prank(ALICE);
        signup.signup{value: 0.1 ether}(emptyProof);

        require(ALICE.balance == 0.9 ether, "alice balance should reflect deposit");
        require(signup.depositedAmountByAddress(ALICE) == 0.1 ether, "deposit should be stored");
        require(signup.signupByIndex(0) == ALICE, "index should point to alice");

        signup.removeSignup(ALICE);

        require(ALICE.balance == 1 ether, "alice should receive refund");
        require(signup.depositedAmountByAddress(ALICE) == 0, "deposit should be zeroed");
        require(signup.signupByIndex(0) == address(0), "index should be cleared");
    }

    function testRemoveSignupIsOwnerOnly() external {
        bytes32 aliceLeaf = keccak256(abi.encodePacked(ALICE));
        OGAuthSignup signup = new OGAuthSignup(aliceLeaf, 0.1 ether, 5);
        bytes32[] memory emptyProof = new bytes32[](0);

        vm.deal(ALICE, 1 ether);
        vm.prank(ALICE);
        signup.signup{value: 0.1 ether}(emptyProof);

        vm.prank(BOB);
        (bool ok, bytes memory returndata) = address(signup).call(
            abi.encodeWithSelector(signup.removeSignup.selector, ALICE)
        );
        require(!ok, "non-owner remove should revert");
        _assertRevertSelector(returndata, OGAuthSignup.NotOwner.selector);
    }

    function _assertRevertSelector(bytes memory returndata, bytes4 expectedSelector) internal pure {
        require(returndata.length >= 4, "missing revert selector");
        bytes4 actualSelector;
        assembly {
            actualSelector := mload(add(returndata, 0x20))
        }
        require(actualSelector == expectedSelector, "unexpected revert selector");
    }
}
