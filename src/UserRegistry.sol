// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title UserRegistry
 * @dev Manages decentralized identities (DIDs) of users on the freelance platform
 * Links unique user IDs to self-sovereign identities and manages user roles
 */
contract UserRegistry is Ownable {
    // User roles
    enum UserRole { 
        None,       // 0 - Not registered
        Freelancer, // 1 - Freelancer
        Client,     // 2 - Client
        Arbitrator  // 3 - Arbitrator
    }

    // User profile structure
    struct UserProfile {
        UserRole role;
        string profileHash; // IPFS hash of detailed profile
        bool isActive;
        uint256 registrationTime;
    }

    // State variables
    mapping(address => UserProfile) public users;
    mapping(address => bool) public isRegistered;
    
    address public profileStorageAddress;
    uint256 public totalUsers;

    // Events
    event UserRegistered(
        address indexed userAddress, 
        UserRole role, 
        uint256 timestamp
    );
    
    event UserRoleUpdated(
        address indexed userAddress, 
        UserRole oldRole, 
        UserRole newRole, 
        uint256 timestamp
    );
    
    event ProfileHashUpdated(
        address indexed userAddress, 
        string newProfileHash, 
        uint256 timestamp
    );

    event UserDeactivated(
        address indexed userAddress,
        uint256 timestamp
    );

    event UserReactivated(
        address indexed userAddress,
        uint256 timestamp
    );

    // Modifiers
    modifier onlyRegisteredUser() {
        require(isRegistered[msg.sender], "User not registered");
        require(users[msg.sender].isActive, "User account is deactivated");
        _;
    }

    modifier validRole(UserRole _role) {
        require(_role != UserRole.None, "Invalid role");
        _;
    }

    constructor() Ownable(msg.sender) {}

    /**
     * @dev Register a new user with a specific role
     * @param _role The role to assign to the user
     */
    function registerUser(UserRole _role) 
        external 
        validRole(_role) 
    {
        require(!isRegistered[msg.sender], "User already registered");
        
        users[msg.sender] = UserProfile({
            role: _role,
            profileHash: "",
            isActive: true,
            registrationTime: block.timestamp
        });
        
        isRegistered[msg.sender] = true;
        totalUsers++;
        
        emit UserRegistered(msg.sender, _role, block.timestamp);
    }

    /**
     * @dev Update user role (with restrictions)
     * @param _newRole The new role to assign
     */
    function updateRole(UserRole _newRole) 
        external 
        onlyRegisteredUser 
        validRole(_newRole) 
    {
        UserRole oldRole = users[msg.sender].role;
        require(oldRole != _newRole, "Role is already set to this value");
        
        users[msg.sender].role = _newRole;
        
        emit UserRoleUpdated(msg.sender, oldRole, _newRole, block.timestamp);
    }

    /**
     * @dev Set or update user profile hash
     * @param _profileHash IPFS hash of the user's detailed profile
     */
    function setProfileHash(string calldata _profileHash) 
        external 
        onlyRegisteredUser 
    {
        require(bytes(_profileHash).length > 0, "Profile hash cannot be empty");
        
        users[msg.sender].profileHash = _profileHash;
        
        emit ProfileHashUpdated(msg.sender, _profileHash, block.timestamp);
    }

    /**
     * @dev Deactivate user account
     */
    function deactivateAccount() external onlyRegisteredUser {
        users[msg.sender].isActive = false;
        emit UserDeactivated(msg.sender, block.timestamp);
    }

    /**
     * @dev Reactivate user account
     */
    function reactivateAccount() external {
        require(isRegistered[msg.sender], "User not registered");
        require(!users[msg.sender].isActive, "Account is already active");
        
        users[msg.sender].isActive = true;
        emit UserReactivated(msg.sender, block.timestamp);
    }

    /**
     * @dev Get user role
     * @param _userAddress Address of the user
     * @return UserRole of the specified user
     */
    function getUserRole(address _userAddress) 
        external 
        view 
        returns (UserRole) 
    {
        return users[_userAddress].role;
    }

    /**
     * @dev Get user profile hash
     * @param _userAddress Address of the user
     * @return IPFS hash of the user's profile
     */
    function getProfileHash(address _userAddress) 
        external 
        view 
        returns (string memory) 
    {
        return users[_userAddress].profileHash;
    }

    /**
     * @dev Check if user is registered and active
     * @param _userAddress Address to check
     * @return bool indicating if user is registered and active
     */
    function isActiveUser(address _userAddress) 
        external 
        view 
        returns (bool) 
    {
        return isRegistered[_userAddress] && users[_userAddress].isActive;
    }

    /**
     * @dev Get user profile details
     * @param _userAddress Address of the user
     * @return role User's role
     * @return profileHash IPFS hash of profile
     * @return isActive Whether account is active
     * @return registrationTime When user registered
     */
    function getUserProfile(address _userAddress) 
        external 
        view 
        returns (
            UserRole role,
            string memory profileHash,
            bool isActive,
            uint256 registrationTime
        ) 
    {
        UserProfile memory profile = users[_userAddress];
        return (
            profile.role,
            profile.profileHash,
            profile.isActive,
            profile.registrationTime
        );
    }

    /**
     * @dev Set profile storage contract address (only owner)
     * @param _profileStorageAddress Address of the ProfileStorage contract
     */
    function setProfileStorageAddress(address _profileStorageAddress) 
        external 
        onlyOwner 
    {
        require(_profileStorageAddress != address(0), "Invalid address");
        profileStorageAddress = _profileStorageAddress;
    }
}

