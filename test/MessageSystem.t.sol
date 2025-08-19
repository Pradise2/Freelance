// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../src/MessageSystem.sol";
import "../src/UserRegistry.sol";

contract MessageSystemTest is Test {
    MessageSystem messageSystem;
    UserRegistry userRegistry;

    address public deployer;
    address public user1;
    address public user2;
    address public user3;

    function setUp() public {
        deployer = makeAddr("deployer");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        user3 = makeAddr("user3");

        vm.startPrank(deployer);
        userRegistry = new UserRegistry();
        messageSystem = new MessageSystem(address(userRegistry));
        vm.stopPrank();

        // Register users
        vm.startPrank(user1);
        userRegistry.registerUser(UserRegistry.UserRole.Freelancer);
        vm.stopPrank();

        vm.startPrank(user2);
        userRegistry.registerUser(UserRegistry.UserRole.Client);
        vm.stopPrank();

        vm.startPrank(user3);
        userRegistry.registerUser(UserRegistry.UserRole.Arbitrator);
        vm.stopPrank();
    }

    function testSendMessage() public {
        string memory contentHash = "ipfs://QmMessage1";

        vm.startPrank(user1);
        messageSystem.sendMessage(user2, contentHash);
        vm.stopPrank();

        MessageSystem.Message memory message = messageSystem.messages(1);
        assertEq(message.sender, user1);
        assertEq(message.recipient, user2);
        assertEq(message.encryptedContentHash, contentHash);
        assertFalse(message.isRead);
        assertTrue(message.timestamp > 0);

        MessageSystem.Conversation memory conv = messageSystem.getConversation(user1, user2);
        assertEq(conv.participant1, user1);
        assertEq(conv.participant2, user2);
        assertEq(conv.messageIds.length, 1);
        assertEq(conv.messageIds[0], 1);
        assertTrue(conv.isActive);

        assertEq(messageSystem.getUserConversations(user1).length, 1);
        assertEq(messageSystem.getUserConversations(user2).length, 1);
        assertEq(messageSystem.getUnreadMessageCount(user2), 1);
    }

    function testRevertSendMessageNotRegistered() public {
        string memory contentHash = "ipfs://QmMessage1";
        address unregisteredUser = makeAddr("unregistered");

        vm.startPrank(unregisteredUser);
        vm.expectRevert("User not registered or active");
        messageSystem.sendMessage(user2, contentHash);
        vm.stopPrank();
    }

    function testRevertSendMessageToSelf() public {
        string memory contentHash = "ipfs://QmMessage1";

        vm.startPrank(user1);
        vm.expectRevert("Cannot send message to yourself");
        messageSystem.sendMessage(user1, contentHash);
        vm.stopPrank();
    }

    function testRevertSendMessageEmptyContent() public {
        vm.startPrank(user1);
        vm.expectRevert("Message content hash cannot be empty");
        messageSystem.sendMessage(user2, "");
        vm.stopPrank();
    }

    function testMarkMessageAsRead() public {
        testSendMessage();

        vm.startPrank(user2);
        messageSystem.markMessageAsRead(1);
        vm.stopPrank();

        MessageSystem.Message memory message = messageSystem.messages(1);
        assertTrue(message.isRead);
        assertEq(messageSystem.getUnreadMessageCount(user2), 0);
    }

    function testRevertMarkMessageAsReadNotRecipient() public {
        testSendMessage();

        vm.startPrank(user1);
        vm.expectRevert("Only recipient can mark message as read");
        messageSystem.markMessageAsRead(1);
        vm.stopPrank();
    }

    function testRevertMarkMessageAsReadAlreadyRead() public {
        testMarkMessageAsRead();

        vm.startPrank(user2);
        vm.expectRevert("Message already marked as read");
        messageSystem.markMessageAsRead(1);
        vm.stopPrank();
    }

    function testGetConversation() public {
        testSendMessage();

        (address p1, address p2, uint256[] memory msgIds, uint256 lastTime, bool active) = messageSystem.getConversation(user1, user2);
        assertEq(p1, user1);
        assertEq(p2, user2);
        assertEq(msgIds.length, 1);
        assertEq(msgIds[0], 1);
        assertTrue(lastTime > 0);
        assertTrue(active);
    }

    function testGetMessage() public {
        testSendMessage();

        (address sender, address recipient, string memory contentHash, uint256 timestamp, bool isRead) = messageSystem.getMessage(1);
        assertEq(sender, user1);
        assertEq(recipient, user2);
        assertEq(contentHash, "ipfs://QmMessage1");
        assertTrue(timestamp > 0);
        assertFalse(isRead);
    }

    function testSetUserRegistryAddress() public {
        address newUserRegistry = makeAddr("newUserRegistry");
        vm.startPrank(deployer);
        messageSystem.setUserRegistryAddress(newUserRegistry);
        vm.stopPrank();

        assertEq(address(messageSystem.userRegistry()), newUserRegistry);
    }
}


