// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../src/FeedbackStorage.sol";

contract FeedbackStorageTest is Test {
    FeedbackStorage feedbackStorage;

    address public deployer;
    address public reputationSystemMock;
    address public user1;
    address public user2;

    function setUp() public {
        deployer = makeAddr("deployer");
        reputationSystemMock = makeAddr("reputationSystemMock");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");

        vm.startPrank(deployer);
        feedbackStorage = new FeedbackStorage(reputationSystemMock);
        vm.stopPrank();
    }

    function testStoreFeedback() public {
        uint256 projectId = 1;
        string memory feedbackHash = "ipfs://QmFeedbackHash1";

        vm.startPrank(reputationSystemMock);
        feedbackStorage.storeFeedback(projectId, user1, user2, feedbackHash);
        vm.stopPrank();

        assertEq(feedbackStorage.projectFeedbackHashes(projectId, user1, user2), feedbackHash);
        assertEq(feedbackStorage.getFeedbackHash(projectId, user1, user2), feedbackHash);
    }

    function testUpdateFeedback() public {
        uint256 projectId = 1;
        string memory feedbackHash1 = "ipfs://QmFeedbackHash1";
        string memory feedbackHash2 = "ipfs://QmFeedbackHash2";

        vm.startPrank(reputationSystemMock);
        feedbackStorage.storeFeedback(projectId, user1, user2, feedbackHash1);
        feedbackStorage.storeFeedback(projectId, user1, user2, feedbackHash2);
        vm.stopPrank();

        assertEq(feedbackStorage.projectFeedbackHashes(projectId, user1, user2), feedbackHash2);
    }

    function testRevertStoreFeedbackEmptyHash() public {
        uint256 projectId = 1;

        vm.startPrank(reputationSystemMock);
        vm.expectRevert("Feedback hash cannot be empty");
        feedbackStorage.storeFeedback(projectId, user1, user2, "");
        vm.stopPrank();
    }

    function testRevertStoreFeedbackUnauthorized() public {
        uint256 projectId = 1;
        string memory feedbackHash = "ipfs://QmFeedbackHash1";

        vm.startPrank(user1);
        vm.expectRevert("Only ReputationSystem can call this function");
        feedbackStorage.storeFeedback(projectId, user1, user2, feedbackHash);
        vm.stopPrank();
    }

    function testSetReputationSystemAddress() public {
        address newAddress = makeAddr("newReputationSystem");
        vm.startPrank(deployer);
        feedbackStorage.setReputationSystemAddress(newAddress);
        vm.stopPrank();

        assertEq(feedbackStorage.reputationSystemAddress(), newAddress);
    }

    function testRevertSetReputationSystemAddressNotOwner() public {
        address newAddress = makeAddr("newReputationSystem");
        vm.startPrank(user1);
        vm.expectRevert("Ownable: caller is not the owner");
        feedbackStorage.setReputationSystemAddress(newAddress);
        vm.stopPrank();
    }

    function testRevertSetReputationSystemAddressInvalid() public {
        vm.startPrank(deployer);
        vm.expectRevert("Invalid address");
        feedbackStorage.setReputationSystemAddress(address(0));
        vm.stopPrank();
    }
}


