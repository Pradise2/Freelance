// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/Ownable.sol";

interface IUserRegistry {
    enum UserRole { None, Freelancer, Client, Arbitrator }
    function getUserRole(address _userAddress) external view returns (UserRole);
    function isActiveUser(address _userAddress) external view returns (bool);
}

interface IReputationSystem {
    function getReputation(address _userAddress) external view returns (uint256);
}

/**
 * @title ArbitratorRegistry
 * @dev Manages the pool of qualified arbitrators for the platform's dispute resolution system
 * Allows for registration, de-registration, and selection of arbitrators
 */
contract ArbitratorRegistry is Ownable {
    // Arbitrator status
    enum ArbitratorStatus {
        Inactive,   // 0 - Not active or deregistered
        Active      // 1 - Active and available for selection
    }

    // Arbitrator profile structure
    struct ArbitratorProfile {
        string profileHash; // IPFS hash of detailed arbitrator profile
        ArbitratorStatus status;
        uint256 registrationTime;
        uint256 lastStatusChange;
    }

    // State variables
    mapping(address => ArbitratorProfile) public arbitrators;
    address[] public activeArbitratorAddresses; // List of active arbitrators for selection
    mapping(address => bool) public isArbitratorActive;

    uint256 public minReputationToRegister = 100; // Minimum reputation score to register as arbitrator
    uint256 public minStakeAmount = 0; // Minimum token stake required (if using a native token)

    IUserRegistry public userRegistry;
    IReputationSystem public reputationSystem;

    // Events
    event ArbitratorRegistered(
        address indexed arbitratorAddress,
        string profileHash,
        uint256 timestamp
    );

    event ArbitratorDeregistered(
        address indexed arbitratorAddress,
        uint256 timestamp
    );

    event ArbitratorStatusChanged(
        address indexed arbitratorAddress,
        ArbitratorStatus oldStatus,
        ArbitratorStatus newStatus,
        uint256 timestamp
    );

    event ArbitratorSelected(
        uint256 indexed disputeId,
        address[] selectedArbitrators,
        uint256 timestamp
    );

    constructor(
        address _userRegistryAddress,
        address _reputationSystemAddress
    ) Ownable(msg.sender) {
        require(_userRegistryAddress != address(0), "Invalid UserRegistry address");
        require(_reputationSystemAddress != address(0), "Invalid ReputationSystem address");
        userRegistry = IUserRegistry(_userRegistryAddress);
        reputationSystem = IReputationSystem(_reputationSystemAddress);
    }

    /**
     * @dev Register as an arbitrator
     * Requires minimum reputation and (optional) stake
     * @param _profileHash IPFS hash of the arbitrator's detailed profile
     */
    function registerArbitrator(string calldata _profileHash) external {
        require(userRegistry.isActiveUser(msg.sender), "User not registered or active");
        require(userRegistry.getUserRole(msg.sender) == IUserRegistry.UserRole.Arbitrator, "User is not an Arbitrator role");
        require(arbitrators[msg.sender].status == ArbitratorStatus.Inactive, "Already registered as an active arbitrator");
        require(bytes(_profileHash).length > 0, "Profile hash cannot be empty");

        // Check reputation requirement
        require(reputationSystem.getReputation(msg.sender) >= minReputationToRegister, "Insufficient reputation to register");

        // Check stake requirement (if applicable, would involve a token contract interaction)
        // require(IERC20(tokenAddress).balanceOf(msg.sender) >= minStakeAmount, "Insufficient stake amount");

        arbitrators[msg.sender] = ArbitratorProfile({
            profileHash: _profileHash,
            status: ArbitratorStatus.Active,
            registrationTime: block.timestamp,
            lastStatusChange: block.timestamp
        });

        activeArbitratorAddresses.push(msg.sender);
        isArbitratorActive[msg.sender] = true;

        emit ArbitratorRegistered(msg.sender, _profileHash, block.timestamp);
        emit ArbitratorStatusChanged(msg.sender, ArbitratorStatus.Inactive, ArbitratorStatus.Active, block.timestamp);
    }

    /**
     * @dev Deregister as an arbitrator
     * Removes arbitrator from the active pool
     */
    function deregisterArbitrator() external {
        require(arbitrators[msg.sender].status == ArbitratorStatus.Active, "Not an active arbitrator");

        arbitrators[msg.sender].status = ArbitratorStatus.Inactive;
        arbitrators[msg.sender].lastStatusChange = block.timestamp;

        // Remove from activeArbitratorAddresses array
        for (uint256 i = 0; i < activeArbitratorAddresses.length; i++) {
            if (activeArbitratorAddresses[i] == msg.sender) {
                activeArbitratorAddresses[i] = activeArbitratorAddresses[activeArbitratorAddresses.length - 1];
                activeArbitratorAddresses.pop();
                break;
            }
        }
        isArbitratorActive[msg.sender] = false;

        emit ArbitratorDeregistered(msg.sender, block.timestamp);
        emit ArbitratorStatusChanged(msg.sender, ArbitratorStatus.Active, ArbitratorStatus.Inactive, block.timestamp);
    }

    /**
     * @dev Select a panel of arbitrators for a dispute
     * Called by ArbitrationCourt.sol
     * @param _numberOfArbitrators Number of arbitrators to select
     * @return Array of selected arbitrator addresses
     */
    function selectArbitrators(uint256 _numberOfArbitrators) 
        external 
        view 
        returns (address[] memory) 
    {
        require(msg.sender == owner(), "Only owner can call this function"); // Only ArbitrationCourt (owner) can call
        require(activeArbitratorAddresses.length >= _numberOfArbitrators, "Not enough active arbitrators available");
        require(_numberOfArbitrators > 0, "Number of arbitrators must be greater than zero");

        address[] memory selected = new address[](_numberOfArbitrators);
        uint256 numActive = activeArbitratorAddresses.length;

        // Simple random selection (can be improved with more sophisticated logic)
        // For production, consider Chainlink VRF or similar for true randomness
        for (uint256 i = 0; i < _numberOfArbitrators; i++) {
            uint256 randomIndex = uint256(keccak256(abi.encodePacked(block.timestamp, i, numActive))) % numActive;
            selected[i] = activeArbitratorAddresses[randomIndex];
            // To avoid selecting the same arbitrator multiple times in a small pool,
            // a more complex shuffle or removal from pool would be needed.
            // For now, this simple approach is sufficient for conceptual design.
        }

        // Note: Emitting an event for selection is handled by ArbitrationCourt for dispute-specific context
        return selected;
    }

    /**
     * @dev Check if an address is an active arbitrator
     * @param _userAddress Address to check
     * @return True if the address is an active arbitrator, false otherwise
     */
    function isArbitrator(address _userAddress) external view returns (bool) {
        return isArbitratorActive[_userAddress];
    }

    /**
     * @dev Get arbitrator profile details
     * @param _arbitratorAddress Address of the arbitrator
     * @return profileHash IPFS hash of profile
     * @return status Arbitrator's status
     * @return registrationTime When arbitrator registered
     */
    function getArbitratorProfile(address _arbitratorAddress) 
        external 
        view 
        returns (
            string memory profileHash,
            ArbitratorStatus status,
            uint256 registrationTime
        ) 
    {
        ArbitratorProfile memory profile = arbitrators[_arbitratorAddress];
        return (
            profile.profileHash,
            profile.status,
            profile.registrationTime
        );
    }

    /**
     * @dev Update minimum reputation to register (only owner)
     * @param _newMinReputation New minimum reputation score
     */
    function setMinReputationToRegister(uint256 _newMinReputation) external onlyOwner {
        minReputationToRegister = _newMinReputation;
    }

    /**
     * @dev Update minimum stake amount (only owner)
     * @param _newMinStake New minimum stake amount
     */
    function setMinStakeAmount(uint256 _newMinStake) external onlyOwner {
        minStakeAmount = _newMinStake;
    }

    /**
     * @dev Update contract addresses (only owner)
     */
    function setContractAddresses(
        address _userRegistryAddress,
        address _reputationSystemAddress
    ) 
        external 
        onlyOwner 
    {
        if (_userRegistryAddress != address(0)) {
            userRegistry = IUserRegistry(_userRegistryAddress);
        }
        if (_reputationSystemAddress != address(0)) {
            reputationSystem = IReputationSystem(_reputationSystemAddress);
        }
    }
}

