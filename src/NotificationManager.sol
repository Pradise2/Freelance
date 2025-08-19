// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/Ownable.sol";

interface IUserRegistry {
    function isActiveUser(address _userAddress) external view returns (bool);
}

/**
 * @title NotificationManager
 * @dev Manages platform-wide notifications and alerts for users
 * Handles different types of notifications and user preferences
 */
contract NotificationManager is Ownable {
    // Notification types
    enum NotificationType {
        JobPosted,          // 0 - New job posted
        ProposalReceived,   // 1 - Proposal received on job
        ProposalAccepted,   // 2 - Proposal accepted
        ProposalRejected,   // 3 - Proposal rejected
        MilestoneCompleted, // 4 - Milestone marked as completed
        MilestoneApproved,  // 5 - Milestone approved
        PaymentReceived,    // 6 - Payment received
        DisputeStarted,     // 7 - Dispute initiated
        DisputeResolved,    // 8 - Dispute resolved
        MessageReceived,    // 9 - New message received
        SystemUpdate        // 10 - System/platform update
    }

    // Notification structure
    struct Notification {
        uint256 id;
        address recipient;
        NotificationType notificationType;
        string title;
        string contentHash; // IPFS hash of notification content
        uint256 timestamp;
        bool isRead;
        bool isActive;
    }

    // User notification preferences
    struct NotificationPreferences {
        mapping(NotificationType => bool) enabledTypes;
        bool emailNotifications;
        bool pushNotifications;
    }

    // State variables
    mapping(uint256 => Notification) public notifications;
    mapping(address => uint256[]) public userNotifications;
    mapping(address => NotificationPreferences) public userPreferences;
    mapping(address => uint256) public unreadNotificationCount;
    
    uint256 public nextNotificationId = 1;

    IUserRegistry public userRegistry;

    // Events
    event NotificationSent(
        uint256 indexed notificationId,
        address indexed recipient,
        NotificationType indexed notificationType,
        string title,
        uint256 timestamp
    );

    event NotificationRead(
        uint256 indexed notificationId,
        address indexed recipient,
        uint256 timestamp
    );

    event NotificationPreferencesUpdated(
        address indexed user,
        uint256 timestamp
    );

    // Modifiers
    modifier onlyRegisteredUser() {
        require(userRegistry.isActiveUser(msg.sender), "User not registered or active");
        _;
    }

    modifier onlyNotificationRecipient(uint256 _notificationId) {
        require(
            notifications[_notificationId].recipient == msg.sender,
            "Not the recipient of this notification"
        );
        _;
    }

    constructor(address _userRegistryAddress) Ownable(msg.sender) {
        require(_userRegistryAddress != address(0), "Invalid UserRegistry address");
        userRegistry = IUserRegistry(_userRegistryAddress);
    }

    /**
     * @dev Send a notification to a user
     * @param _recipient Address of the notification recipient
     * @param _notificationType Type of notification
     * @param _title Title of the notification
     * @param _contentHash IPFS hash of detailed notification content
     */
    function sendNotification(
        address _recipient,
        NotificationType _notificationType,
        string calldata _title,
        string calldata _contentHash
    ) 
        external 
        onlyOwner 
    {
        require(_recipient != address(0), "Invalid recipient address");
        require(userRegistry.isActiveUser(_recipient), "Recipient not registered or active");
        require(bytes(_title).length > 0, "Title cannot be empty");
        require(bytes(_contentHash).length > 0, "Content hash cannot be empty");

        // Check if user has enabled this notification type
        if (!userPreferences[_recipient].enabledTypes[_notificationType]) {
            return; // User has disabled this notification type
        }

        uint256 notificationId = nextNotificationId++;

        notifications[notificationId] = Notification({
            id: notificationId,
            recipient: _recipient,
            notificationType: _notificationType,
            title: _title,
            contentHash: _contentHash,
            timestamp: block.timestamp,
            isRead: false,
            isActive: true
        });

        userNotifications[_recipient].push(notificationId);
        unreadNotificationCount[_recipient]++;

        emit NotificationSent(notificationId, _recipient, _notificationType, _title, block.timestamp);
    }

    /**
     * @dev Mark a notification as read
     * @param _notificationId ID of the notification to mark as read
     */
    function markNotificationAsRead(uint256 _notificationId) 
        external 
        onlyRegisteredUser
        onlyNotificationRecipient(_notificationId)
    {
        require(notifications[_notificationId].id != 0, "Notification does not exist");
        require(!notifications[_notificationId].isRead, "Notification already marked as read");

        notifications[_notificationId].isRead = true;
        unreadNotificationCount[msg.sender]--;

        emit NotificationRead(_notificationId, msg.sender, block.timestamp);
    }

    /**
     * @dev Mark multiple notifications as read
     * @param _notificationIds Array of notification IDs to mark as read
     */
    function markMultipleNotificationsAsRead(uint256[] calldata _notificationIds) 
        external 
        onlyRegisteredUser
    {
        for (uint256 i = 0; i < _notificationIds.length; i++) {
            uint256 notificationId = _notificationIds[i];
            
            if (notifications[notificationId].recipient == msg.sender &&
                notifications[notificationId].id != 0 &&
                !notifications[notificationId].isRead) {
                
                notifications[notificationId].isRead = true;
                unreadNotificationCount[msg.sender]--;
                
                emit NotificationRead(notificationId, msg.sender, block.timestamp);
            }
        }
    }

    /**
     * @dev Update notification preferences for a user
     * @param _notificationTypes Array of notification types to enable/disable
     * @param _enabled Array of boolean values corresponding to notification types
     * @param _emailNotifications Enable/disable email notifications
     * @param _pushNotifications Enable/disable push notifications
     */
    function updateNotificationPreferences(
        NotificationType[] calldata _notificationTypes,
        bool[] calldata _enabled,
        bool _emailNotifications,
        bool _pushNotifications
    ) 
        external 
        onlyRegisteredUser
    {
        require(_notificationTypes.length == _enabled.length, "Arrays length mismatch");

        for (uint256 i = 0; i < _notificationTypes.length; i++) {
            userPreferences[msg.sender].enabledTypes[_notificationTypes[i]] = _enabled[i];
        }

        userPreferences[msg.sender].emailNotifications = _emailNotifications;
        userPreferences[msg.sender].pushNotifications = _pushNotifications;

        emit NotificationPreferencesUpdated(msg.sender, block.timestamp);
    }

    /**
     * @dev Get all notifications for a user
     * @param _user Address of the user
     * @return Array of notification IDs
     */
    function getUserNotifications(address _user) 
        external 
        view 
        returns (uint256[] memory) 
    {
        return userNotifications[_user];
    }

    /**
     * @dev Get unread notifications for a user
     * @param _user Address of the user
     * @return Array of unread notification IDs
     */
    function getUnreadNotifications(address _user) 
        external 
        view 
        returns (uint256[] memory) 
    {
        uint256[] memory allNotifications = userNotifications[_user];
        uint256 unreadCount = 0;

        // Count unread notifications
        for (uint256 i = 0; i < allNotifications.length; i++) {
            if (!notifications[allNotifications[i]].isRead && 
                notifications[allNotifications[i]].isActive) {
                unreadCount++;
            }
        }

        // Create array of unread notification IDs
        uint256[] memory unreadNotifications = new uint256[](unreadCount);
        uint256 currentIndex = 0;

        for (uint256 i = 0; i < allNotifications.length; i++) {
            if (!notifications[allNotifications[i]].isRead && 
                notifications[allNotifications[i]].isActive) {
                unreadNotifications[currentIndex] = allNotifications[i];
                currentIndex++;
            }
        }

        return unreadNotifications;
    }

    /**
     * @dev Get notification details
     * @param _notificationId ID of the notification
     * @return Notification details
     */
    function getNotification(uint256 _notificationId) 
        external 
        view 
        returns (
            uint256 id,
            address recipient,
            NotificationType notificationType,
            string memory title,
            string memory contentHash,
            uint256 timestamp,
            bool isRead,
            bool isActive
        ) 
    {
        require(notifications[_notificationId].id != 0, "Notification does not exist");
        
        Notification memory notification = notifications[_notificationId];
        return (
            notification.id,
            notification.recipient,
            notification.notificationType,
            notification.title,
            notification.contentHash,
            notification.timestamp,
            notification.isRead,
            notification.isActive
        );
    }

    /**
     * @dev Get unread notification count for a user
     * @param _user Address of the user
     * @return Number of unread notifications
     */
    function getUnreadNotificationCount(address _user) 
        external 
        view 
        returns (uint256) 
    {
        return unreadNotificationCount[_user];
    }

    /**
     * @dev Check if a notification type is enabled for a user
     * @param _user Address of the user
     * @param _notificationType Type of notification to check
     * @return Whether the notification type is enabled
     */
    function isNotificationTypeEnabled(address _user, NotificationType _notificationType) 
        external 
        view 
        returns (bool) 
    {
        return userPreferences[_user].enabledTypes[_notificationType];
    }

    /**
     * @dev Broadcast notification to multiple users (only owner)
     * @param _recipients Array of recipient addresses
     * @param _notificationType Type of notification
     * @param _title Title of the notification
     * @param _contentHash IPFS hash of detailed notification content
     */
    function broadcastNotification(
        address[] calldata _recipients,
        NotificationType _notificationType,
        string calldata _title,
        string calldata _contentHash
    ) 
        external 
        onlyOwner 
    {
        require(_recipients.length > 0, "No recipients specified");
        require(bytes(_title).length > 0, "Title cannot be empty");
        require(bytes(_contentHash).length > 0, "Content hash cannot be empty");

        for (uint256 i = 0; i < _recipients.length; i++) {
            if (userRegistry.isActiveUser(_recipients[i]) && 
                userPreferences[_recipients[i]].enabledTypes[_notificationType]) {
                
                uint256 notificationId = nextNotificationId++;

                notifications[notificationId] = Notification({
                    id: notificationId,
                    recipient: _recipients[i],
                    notificationType: _notificationType,
                    title: _title,
                    contentHash: _contentHash,
                    timestamp: block.timestamp,
                    isRead: false,
                    isActive: true
                });

                userNotifications[_recipients[i]].push(notificationId);
                unreadNotificationCount[_recipients[i]]++;

                emit NotificationSent(notificationId, _recipients[i], _notificationType, _title, block.timestamp);
            }
        }
    }

    /**
     * @dev Update UserRegistry address (only owner)
     * @param _userRegistryAddress New UserRegistry contract address
     */
    function setUserRegistryAddress(address _userRegistryAddress) external onlyOwner {
        require(_userRegistryAddress != address(0), "Invalid address");
        userRegistry = IUserRegistry(_userRegistryAddress);
    }
}

