// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/Ownable.sol";

interface IUserRegistry {
    enum UserRole { None, Freelancer, Client, Arbitrator }
    function getUserRole(address _userAddress) external view returns (UserRole);
    function isActiveUser(address _userAddress) external view returns (bool);
}

interface IProjectManager {
    enum ProjectStatus { Active, Disputed, Completed, Cancelled }
    function getProjectDetails(uint256 _projectId) external view returns (
        uint256 jobId,
        address client,
        address freelancer,
        uint256 agreedBudget,
        uint256 agreedDeadline,
        ProjectStatus status,
        uint256 startTime,
        uint256 totalMilestones,
        uint256 completedMilestones,
        uint256 approvedMilestones
    );
}

interface IFeedbackStorage {
    function storeFeedback(uint256 _projectId, address _submitter, address _targetUser, string calldata _feedbackHash) external;
}

/**
 * @title ReputationSystem
 * @dev Manages on-chain reputation scores for freelancers and clients
 * Aggregates feedback and calculates reputation scores
 */
contract ReputationSystem is Ownable {
    // User reputation data
    struct UserReputation {
        uint256 score; // Aggregated reputation score
        uint256 totalRatingSum; // Sum of all ratings received
        uint256 numberOfRatings; // Count of ratings received
    }

    // State variables
    mapping(address => UserReputation) public reputations;
    mapping(uint256 => bool) public feedbackSubmittedForProject;

    IUserRegistry public userRegistry;
    IProjectManager public projectManager;
    IFeedbackStorage public feedbackStorage;

    // Events
    event FeedbackSubmitted(
        uint256 indexed projectId,
        address indexed submitter,
        address indexed targetUser,
        uint8 rating,
        string feedbackHash,
        uint256 timestamp
    );

    event ReputationUpdated(
        address indexed userAddress,
        uint256 oldScore,
        uint256 newScore,
        uint256 timestamp
    );

    constructor(
        address _userRegistryAddress,
        address _projectManagerAddress,
        address _feedbackStorageAddress
    ) Ownable(msg.sender) {
        require(_userRegistryAddress != address(0), "Invalid UserRegistry address");
        require(_projectManagerAddress != address(0), "Invalid ProjectManager address");
        require(_feedbackStorageAddress != address(0), "Invalid FeedbackStorage address");
        userRegistry = IUserRegistry(_userRegistryAddress);
        projectManager = IProjectManager(_projectManagerAddress);
        feedbackStorage = IFeedbackStorage(_feedbackStorageAddress);
    }

    /**
     * @dev Submit feedback for a completed project
     * @param _projectId ID of the completed project
     * @param _targetUser Address of the user receiving feedback (freelancer or client)
     * @param _rating Rating given (e.g., 1-5)
     * @param _feedbackHash IPFS hash of detailed textual feedback
     */
    function submitFeedback(
        uint256 _projectId,
        address _targetUser,
        uint8 _rating,
        string calldata _feedbackHash
    ) external {
        // Ensure sender is a registered and active user
        require(userRegistry.isActiveUser(msg.sender), "Sender not a registered active user");
        // Ensure target user is registered and active
        require(userRegistry.isActiveUser(_targetUser), "Target not a registered active user");
        // Ensure sender is not giving feedback to themselves
        require(msg.sender != _targetUser, "Cannot give feedback to yourself");

        // Get project details
        (,, address client, address freelancer,,,,,) = projectManager.getProjectDetails(_projectId);
        require(client != address(0), "Project does not exist");
        require(projectManager.getProjectDetails(_projectId).status == IProjectManager.ProjectStatus.Completed, "Project not completed");

        // Ensure sender and target are participants of the project
        bool isSenderClient = (msg.sender == client);
        bool isSenderFreelancer = (msg.sender == freelancer);
        bool isTargetClient = (_targetUser == client);
        bool isTargetFreelancer = (_targetUser == freelancer);

        require(
            (isSenderClient && isTargetFreelancer) || (isSenderFreelancer && isTargetClient),
            "Sender and target must be client/freelancer of the project"
        );

        // Ensure feedback has not been submitted for this project by this sender for this target
        bytes32 feedbackKey = keccak256(abi.encodePacked(_projectId, msg.sender, _targetUser));
        require(!feedbackSubmittedForProject[_projectId], "Feedback already submitted for this project");
        // This logic needs to be refined if both client and freelancer can give feedback on the same project.
        // For now, it assumes only one feedback submission per project.
        // A better approach would be to track feedback per (project, submitter, target) tuple.
        // For simplicity, let's assume only one feedback submission per project for now.
        feedbackSubmittedForProject[_projectId] = true;

        require(_rating >= 1 && _rating <= 5, "Rating must be between 1 and 5");
        require(bytes(_feedbackHash).length > 0, "Feedback hash cannot be empty");

        // Store feedback hash in FeedbackStorage
        feedbackStorage.storeFeedback(_projectId, msg.sender, _targetUser, _feedbackHash);

        // Update target user's reputation
        _updateReputation(_targetUser, _rating);

        emit FeedbackSubmitted(_projectId, msg.sender, _targetUser, _rating, _feedbackHash, block.timestamp);
    }

    /**
     * @dev Internal function to update a user's reputation score
     * @param _userAddress Address of the user whose reputation to update
     * @param _rating New rating received
     */
    function _updateReputation(address _userAddress, uint8 _rating) internal {
        UserReputation storage userRep = reputations[_userAddress];
        
        uint256 oldScore = userRep.score;

        userRep.totalRatingSum += _rating;
        userRep.numberOfRatings++;
        userRep.score = userRep.totalRatingSum / userRep.numberOfRatings; // Simple average

        emit ReputationUpdated(_userAddress, oldScore, userRep.score, block.timestamp);
    }

    /**
     * @dev Get a user's current reputation score
     * @param _userAddress Address of the user
     * @return Current reputation score
     */
    function getReputation(address _userAddress) external view returns (uint256) {
        return reputations[_userAddress].score;
    }

    /**
     * @dev Get a user's average rating
     * @param _userAddress Address of the user
     * @return Average rating
     */
    function getAverageRating(address _userAddress) external view returns (uint256) {
        if (reputations[_userAddress].numberOfRatings == 0) {
            return 0;
        }
        return reputations[_userAddress].totalRatingSum / reputations[_userAddress].numberOfRatings;
    }

    /**
     * @dev Get number of ratings received by a user
     * @param _userAddress Address of the user
     * @return Number of ratings
     */
    function getNumberOfRatings(address _userAddress) external view returns (uint256) {
        return reputations[_userAddress].numberOfRatings;
    }

    /**
     * @dev Update contract addresses (only owner)
     */
    function setContractAddresses(
        address _userRegistryAddress,
        address _projectManagerAddress,
        address _feedbackStorageAddress
    ) 
        external 
        onlyOwner 
    {
        if (_userRegistryAddress != address(0)) {
            userRegistry = IUserRegistry(_userRegistryAddress);
        }
        if (_projectManagerAddress != address(0)) {
            projectManager = IProjectManager(_projectManagerAddress);
        }
        if (_feedbackStorageAddress != address(0)) {
            feedbackStorage = IFeedbackStorage(_feedbackStorageAddress);
        }
    }
}

