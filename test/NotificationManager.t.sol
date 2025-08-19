// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../src/NotificationManager.sol";
import "../src/UserRegistry.sol";

contract NotificationManagerTest is Test {
    NotificationManager notificationManager;
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
        notificationManager = new NotificationManager(address(userRegistry));
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

        // Set default preferences for user1 (all enabled)
        vm.startPrank(user1);
        NotificationManager.NotificationType[] memory allTypes = new NotificationManager.NotificationType[](11);
        bool[] memory enabled = new bool[](11);
        for (uint i = 0; i < 11; i++) {
            allTypes[i] = NotificationManager.NotificationType(i);
            enabled[i] = true;
        }
        notificationManager.updateNotificationPreferences(allTypes, enabled, true, true);
        vm.stopPrank();
    }

    function testSendNotification() public {
        string memory title = "New Job Posted";
        string memory contentHash = "ipfs://QmNotification1";

        vm.startPrank(deployer); // Only owner can send notifications
        notificationManager.sendNotification(user1, NotificationManager.NotificationType.JobPosted, title, contentHash);
        vm.stopPrank();

        NotificationManager.Notification memory notification = notificationManager.notifications(1);
        assertEq(notification.recipient, user1);
        assertEq(uint8(notification.notificationType), uint8(NotificationManager.NotificationType.JobPosted));
        assertEq(notification.title, title);
        assertEq(notification.contentHash, contentHash);
        assertFalse(notification.isRead);
        assertTrue(notification.isActive);
        assertTrue(notification.timestamp > 0);

        assertEq(notificationManager.getUserNotifications(user1).length, 1);
        assertEq(notificationManager.getUserNotifications(user1)[0], 1);
        assertEq(notificationManager.getUnreadNotificationCount(user1), 1);
    }

    function testRevertSendNotificationNotOwner() public {
        string memory title = "New Job Posted";
        string memory contentHash = "ipfs://QmNotification1";

        vm.startPrank(user1);
        vm.expectRevert("Ownable: caller is not the owner");
        notificationManager.sendNotification(user1, NotificationManager.NotificationType.JobPosted, title, contentHash);
        vm.stopPrank();
    }

    function testRevertSendNotificationRecipientNotActive() public {
        string memory title = "New Job Posted";
        string memory contentHash = "ipfs://QmNotification1";

        vm.startPrank(user1);
        userRegistry.deactivateAccount();
        vm.stopPrank();

        vm.startPrank(deployer);
        vm.expectRevert("Recipient not registered or active");
        notificationManager.sendNotification(user1, NotificationManager.NotificationType.JobPosted, title, contentHash);
        vm.stopPrank();
    }

    function testSendNotificationDisabledType() public {
        // Disable JobPosted notifications for user1
        vm.startPrank(user1);
        NotificationManager.NotificationType[] memory typesToDisable = new NotificationManager.NotificationType[](1);
        typesToDisable[0] = NotificationManager.NotificationType.JobPosted;
        bool[] memory enabled = new bool[](1);
        enabled[0] = false;
        notificationManager.updateNotificationPreferences(typesToDisable, enabled, true, true);
        vm.stopPrank();

        string memory title = "New Job Posted";
        string memory contentHash = "ipfs://QmNotification1";

        vm.startPrank(deployer);
        notificationManager.sendNotification(user1, NotificationManager.NotificationType.JobPosted, title, contentHash);
        vm.stopPrank();

        assertEq(notificationManager.getUserNotifications(user1).length, 0); // No notification sent
        assertEq(notificationManager.getUnreadNotificationCount(user1), 0);
    }

    function testMarkNotificationAsRead() public {
        testSendNotification();

        vm.startPrank(user1);
        notificationManager.markNotificationAsRead(1);
        vm.stopPrank();

        NotificationManager.Notification memory notification = notificationManager.notifications(1);
        assertTrue(notification.isRead);
        assertEq(notificationManager.getUnreadNotificationCount(user1), 0);
    }

    function testRevertMarkNotificationAsReadNotRecipient() public {
        testSendNotification();

        vm.startPrank(user2);
        vm.expectRevert("Not the recipient of this notification");
        notificationManager.markNotificationAsRead(1);
        vm.stopPrank();
    }

    function testRevertMarkNotificationAsReadAlreadyRead() public {
        testMarkNotificationAsRead();

        vm.startPrank(user1);
        vm.expectRevert("Notification already marked as read");
        notificationManager.markNotificationAsRead(1);
        vm.stopPrank();
    }

    function testMarkMultipleNotificationsAsRead() public {
        string memory title = "Notification";
        string memory contentHash = "ipfs://QmNotification";

        vm.startPrank(deployer);
        notificationManager.sendNotification(user1, NotificationManager.NotificationType.SystemUpdate, title, contentHash);
        notificationManager.sendNotification(user1, NotificationManager.NotificationType.MessageReceived, title, contentHash);
        notificationManager.sendNotification(user1, NotificationManager.NotificationType.JobPosted, title, contentHash);
        vm.stopPrank();

        assertEq(notificationManager.getUnreadNotificationCount(user1), 3);

        uint256[] memory notificationIds = new uint256[](2);
        notificationIds[0] = 1;
        notificationIds[1] = 2;

        vm.startPrank(user1);
        notificationManager.markMultipleNotificationsAsRead(notificationIds);
        vm.stopPrank();

        assertEq(notificationManager.getUnreadNotificationCount(user1), 1);
        assertTrue(notificationManager.notifications(1).isRead);
        assertTrue(notificationManager.notifications(2).isRead);
        assertFalse(notificationManager.notifications(3).isRead);
    }

    function testUpdateNotificationPreferences() public {
        vm.startPrank(user1);
        NotificationManager.NotificationType[] memory typesToUpdate = new NotificationManager.NotificationType[](2);
        typesToUpdate[0] = NotificationManager.NotificationType.JobPosted;
        typesToUpdate[1] = NotificationManager.NotificationType.ProposalReceived;

        bool[] memory enabled = new bool[](2);
        enabled[0] = false;
        enabled[1] = true;

        notificationManager.updateNotificationPreferences(typesToUpdate, enabled, false, true);
        vm.stopPrank();

        assertFalse(notificationManager.isNotificationTypeEnabled(user1, NotificationManager.NotificationType.JobPosted));
        assertTrue(notificationManager.isNotificationTypeEnabled(user1, NotificationManager.NotificationType.ProposalReceived));
        assertFalse(notificationManager.userPreferences(user1).emailNotifications);
        assertTrue(notificationManager.userPreferences(user1).pushNotifications);
    }

    function testGetUnreadNotifications() public {
        string memory title = "Notification";
        string memory contentHash = "ipfs://QmNotification";

        vm.startPrank(deployer);
        notificationManager.sendNotification(user1, NotificationManager.NotificationType.SystemUpdate, title, contentHash);
        notificationManager.sendNotification(user1, NotificationManager.NotificationType.MessageReceived, title, contentHash);
        notificationManager.sendNotification(user1, NotificationManager.NotificationType.JobPosted, title, contentHash);
        vm.stopPrank();

        // Mark one as read
        vm.startPrank(user1);
        notificationManager.markNotificationAsRead(1);
        vm.stopPrank();

        uint256[] memory unread = notificationManager.getUnreadNotifications(user1);
        assertEq(unread.length, 2);
        assertEq(unread[0], 2);
        assertEq(unread[1], 3);
    }

    function testBroadcastNotification() public {
        string memory title = "Platform Maintenance";
        string memory contentHash = "ipfs://QmBroadcast";

        vm.startPrank(deployer);
        notificationManager.broadcastNotification(new address[](2), NotificationManager.NotificationType.SystemUpdate, title, contentHash);
        vm.stopPrank();

        // user1 has SystemUpdate enabled by default
        assertEq(notificationManager.getUserNotifications(user1).length, 1);
        assertEq(notificationManager.getUnreadNotificationCount(user1), 1);

        // user2 has all types enabled by default
        assertEq(notificationManager.getUserNotifications(user2).length, 1);
        assertEq(notificationManager.getUnreadNotificationCount(user2), 1);

        // user3 has all types enabled by default
        assertEq(notificationManager.getUserNotifications(user3).length, 1);
        assertEq(notificationManager.getUnreadNotificationCount(user3), 1);
    }

    function testSetUserRegistryAddress() public {
        address newUserRegistry = makeAddr("newUserRegistry");
        vm.startPrank(deployer);
        notificationManager.setUserRegistryAddress(newUserRegistry);
        vm.stopPrank();

        assertEq(address(notificationManager.userRegistry()), newUserRegistry);
    }
}


