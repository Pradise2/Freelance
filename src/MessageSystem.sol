// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/Ownable.sol";

interface IUserRegistry {
    enum UserRole { None, Freelancer, Client, Arbitrator }
    function getUserRole(address _userAddress) external view returns (UserRole);
    function isActiveUser(address _userAddress) external view returns (bool);
}

/**
 * @title MessageSystem
 * @dev Facilitates secure communication between platform users
 * Stores encrypted message hashes and manages conversation threads
 */
contract MessageSystem is Ownable {
    // Message structure
    struct Message {
        address sender;
        address recipient;
        string encryptedContentHash; // IPFS hash of encrypted message content
        uint256 timestamp;
        bool isRead;
    }

    // Conversation structure
    struct Conversation {
        address participant1;
        address participant2;
        uint256[] messageIds;
        uint256 lastMessageTime;
        bool isActive;
    }

    // State variables
    mapping(uint256 => Message) public messages;
    mapping(bytes32 => Conversation) public conversations;
    mapping(address => bytes32[]) public userConversations;
    mapping(address => uint256) public unreadMessageCount;
    
    uint256 public nextMessageId = 1;

    IUserRegistry public userRegistry;

    // Events
    event MessageSent(
        uint256 indexed messageId,
        address indexed sender,
        address indexed recipient,
        bytes32 conversationId,
        uint256 timestamp
    );

    event MessageRead(
        uint256 indexed messageId,
        address indexed reader,
        uint256 timestamp
    );

    event ConversationStarted(
        bytes32 indexed conversationId,
        address indexed participant1,
        address indexed participant2,
        uint256 timestamp
    );

    // Modifiers
    modifier onlyRegisteredUser() {
        require(userRegistry.isActiveUser(msg.sender), "User not registered or active");
        _;
    }

    modifier onlyMessageParticipant(uint256 _messageId) {
        require(
            messages[_messageId].sender == msg.sender || 
            messages[_messageId].recipient == msg.sender,
            "Not a participant in this message"
        );
        _;
    }

    constructor(address _userRegistryAddress) Ownable(msg.sender) {
        require(_userRegistryAddress != address(0), "Invalid UserRegistry address");
        userRegistry = IUserRegistry(_userRegistryAddress);
    }

    /**
     * @dev Send a message to another user
     * @param _recipient Address of the message recipient
     * @param _encryptedContentHash IPFS hash of the encrypted message content
     */
    function sendMessage(
        address _recipient,
        string calldata _encryptedContentHash
    ) 
        external 
        onlyRegisteredUser 
    {
        require(_recipient != address(0), "Invalid recipient address");
        require(_recipient != msg.sender, "Cannot send message to yourself");
        require(userRegistry.isActiveUser(_recipient), "Recipient not registered or active");
        require(bytes(_encryptedContentHash).length > 0, "Message content hash cannot be empty");

        uint256 messageId = nextMessageId++;
        bytes32 conversationId = _getConversationId(msg.sender, _recipient);

        // Create message
        messages[messageId] = Message({
            sender: msg.sender,
            recipient: _recipient,
            encryptedContentHash: _encryptedContentHash,
            timestamp: block.timestamp,
            isRead: false
        });

        // Update or create conversation
        if (conversations[conversationId].participant1 == address(0)) {
            // New conversation
            conversations[conversationId] = Conversation({
                participant1: msg.sender,
                participant2: _recipient,
                messageIds: new uint256[](0),
                lastMessageTime: block.timestamp,
                isActive: true
            });

            userConversations[msg.sender].push(conversationId);
            userConversations[_recipient].push(conversationId);

            emit ConversationStarted(conversationId, msg.sender, _recipient, block.timestamp);
        }

        // Add message to conversation
        conversations[conversationId].messageIds.push(messageId);
        conversations[conversationId].lastMessageTime = block.timestamp;

        // Update unread message count for recipient
        unreadMessageCount[_recipient]++;

        emit MessageSent(messageId, msg.sender, _recipient, conversationId, block.timestamp);
    }

    /**
     * @dev Mark a message as read
     * @param _messageId ID of the message to mark as read
     */
    function markMessageAsRead(uint256 _messageId) 
        external 
        onlyMessageParticipant(_messageId)
    {
        require(messages[_messageId].sender != address(0), "Message does not exist");
        require(!messages[_messageId].isRead, "Message already marked as read");
        require(messages[_messageId].recipient == msg.sender, "Only recipient can mark message as read");

        messages[_messageId].isRead = true;
        unreadMessageCount[msg.sender]--;

        emit MessageRead(_messageId, msg.sender, block.timestamp);
    }

    /**
     * @dev Get conversation ID between two users
     * @param _user1 Address of first user
     * @param _user2 Address of second user
     * @return Conversation ID
     */
    function _getConversationId(address _user1, address _user2) 
        internal 
        pure 
        returns (bytes32) 
    {
        // Ensure consistent ordering for conversation ID
        if (_user1 < _user2) {
            return keccak256(abi.encodePacked(_user1, _user2));
        } else {
            return keccak256(abi.encodePacked(_user2, _user1));
        }
    }

    /**
     * @dev Get conversation details
     * @param _participant1 Address of first participant
     * @param _participant2 Address of second participant
     * @return Conversation details
     */
    function getConversation(address _participant1, address _participant2) 
        external 
        view 
        returns (
            address participant1,
            address participant2,
            uint256[] memory messageIds,
            uint256 lastMessageTime,
            bool isActive
        ) 
    {
        bytes32 conversationId = _getConversationId(_participant1, _participant2);
        Conversation memory conv = conversations[conversationId];
        
        return (
            conv.participant1,
            conv.participant2,
            conv.messageIds,
            conv.lastMessageTime,
            conv.isActive
        );
    }

    /**
     * @dev Get all conversations for a user
     * @param _user Address of the user
     * @return Array of conversation IDs
     */
    function getUserConversations(address _user) 
        external 
        view 
        returns (bytes32[] memory) 
    {
        return userConversations[_user];
    }

    /**
     * @dev Get message details
     * @param _messageId ID of the message
     * @return Message details
     */
    function getMessage(uint256 _messageId) 
        external 
        view 
        onlyMessageParticipant(_messageId)
        returns (
            address sender,
            address recipient,
            string memory encryptedContentHash,
            uint256 timestamp,
            bool isRead
        ) 
    {
        Message memory message = messages[_messageId];
        return (
            message.sender,
            message.recipient,
            message.encryptedContentHash,
            message.timestamp,
            message.isRead
        );
    }

    /**
     * @dev Get unread message count for a user
     * @param _user Address of the user
     * @return Number of unread messages
     */
    function getUnreadMessageCount(address _user) 
        external 
        view 
        returns (uint256) 
    {
        return unreadMessageCount[_user];
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

