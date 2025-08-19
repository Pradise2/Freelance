// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title ProfileStorage
 * @dev Secure, on-chain reference for off-chain user profile data
 * Stores IPFS hashes pointing to actual profile content for data integrity
 */
contract ProfileStorage is Ownable {
    // State variables
    mapping(address => string) public profiles;
    mapping(address => uint256) public lastUpdated;
    
    address public userRegistryAddress;
    uint256 public totalProfiles;

    // Events
    event ProfileHashUpdated(
        address indexed userAddress,
        string oldProfileHash,
        string newProfileHash,
        uint256 timestamp
    );

    event ProfileDeleted(
        address indexed userAddress,
        uint256 timestamp
    );

    // Modifiers
    modifier onlyAuthorized() {
        require(
            msg.sender == userRegistryAddress || 
            msg.sender == owner(),
            "Not authorized to modify profiles"
        );
        _;
    }

    modifier validProfileHash(string calldata _profileHash) {
        require(bytes(_profileHash).length > 0, "Profile hash cannot be empty");
        require(bytes(_profileHash).length <= 100, "Profile hash too long");
        _;
    }

    constructor() Ownable(msg.sender) {}

    /**
     * @dev Set UserRegistry contract address
     * @param _userRegistryAddress Address of the UserRegistry contract
     */
    function setUserRegistryAddress(address _userRegistryAddress) 
        external 
        onlyOwner 
    {
        require(_userRegistryAddress != address(0), "Invalid address");
        userRegistryAddress = _userRegistryAddress;
    }

    /**
     * @dev Set or update profile hash for a user
     * @param _userAddress Address of the user
     * @param _newProfileHash New IPFS hash for the profile
     */
    function setProfileHash(
        address _userAddress, 
        string calldata _newProfileHash
    ) 
        external 
        onlyAuthorized 
        validProfileHash(_newProfileHash)
    {
        require(_userAddress != address(0), "Invalid user address");
        
        string memory oldProfileHash = profiles[_userAddress];
        
        // If this is a new profile, increment counter
        if (bytes(oldProfileHash).length == 0) {
            totalProfiles++;
        }
        
        profiles[_userAddress] = _newProfileHash;
        lastUpdated[_userAddress] = block.timestamp;
        
        emit ProfileHashUpdated(
            _userAddress, 
            oldProfileHash, 
            _newProfileHash, 
            block.timestamp
        );
    }

    /**
     * @dev Get profile hash for a user
     * @param _userAddress Address of the user
     * @return IPFS hash of the user's profile
     */
    function getProfileHash(address _userAddress) 
        external 
        view 
        returns (string memory) 
    {
        return profiles[_userAddress];
    }

    /**
     * @dev Get profile details including last update time
     * @param _userAddress Address of the user
     * @return profileHash IPFS hash of the profile
     * @return lastUpdateTime When the profile was last updated
     */
    function getProfileDetails(address _userAddress) 
        external 
        view 
        returns (string memory profileHash, uint256 lastUpdateTime) 
    {
        return (profiles[_userAddress], lastUpdated[_userAddress]);
    }

    /**
     * @dev Check if user has a profile
     * @param _userAddress Address to check
     * @return bool indicating if user has a profile
     */
    function hasProfile(address _userAddress) 
        external 
        view 
        returns (bool) 
    {
        return bytes(profiles[_userAddress]).length > 0;
    }

    /**
     * @dev Delete a user's profile (only authorized)
     * @param _userAddress Address of the user whose profile to delete
     */
    function deleteProfile(address _userAddress) 
        external 
        onlyAuthorized 
    {
        require(bytes(profiles[_userAddress]).length > 0, "Profile does not exist");
        
        delete profiles[_userAddress];
        delete lastUpdated[_userAddress];
        totalProfiles--;
        
        emit ProfileDeleted(_userAddress, block.timestamp);
    }

    /**
     * @dev Batch update multiple profiles (only owner)
     * @param _userAddresses Array of user addresses
     * @param _profileHashes Array of corresponding profile hashes
     */
    function batchUpdateProfiles(
        address[] calldata _userAddresses,
        string[] calldata _profileHashes
    ) 
        external 
        onlyOwner 
    {
        require(
            _userAddresses.length == _profileHashes.length,
            "Arrays length mismatch"
        );
        require(_userAddresses.length > 0, "Empty arrays");
        
        for (uint256 i = 0; i < _userAddresses.length; i++) {
            require(_userAddresses[i] != address(0), "Invalid user address");
            require(bytes(_profileHashes[i]).length > 0, "Empty profile hash");
            require(bytes(_profileHashes[i]).length <= 100, "Profile hash too long");
            
            string memory oldHash = profiles[_userAddresses[i]];
            
            // If this is a new profile, increment counter
            if (bytes(oldHash).length == 0) {
                totalProfiles++;
            }
            
            profiles[_userAddresses[i]] = _profileHashes[i];
            lastUpdated[_userAddresses[i]] = block.timestamp;
            
            emit ProfileHashUpdated(
                _userAddresses[i],
                oldHash,
                _profileHashes[i],
                block.timestamp
            );
        }
    }
}

