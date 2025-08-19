// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title FeedbackStorage
 * @dev Dedicated repository for storing IPFS hashes of detailed textual feedback
 */
contract FeedbackStorage is Ownable {
    // State variables
    // projectId => submitterAddress => targetUserAddress => feedbackHash
    mapping(uint256 => mapping(address => mapping(address => string))) public projectFeedbackHashes;
    
    address public reputationSystemAddress;

    // Events
    event FeedbackStored(
        uint256 indexed projectId,
        address indexed submitter,
        address indexed targetUser,
        string feedbackHash,
        uint256 timestamp
    );

    // Modifiers
    modifier onlyReputationSystem() {
        require(msg.sender == reputationSystemAddress, "Only ReputationSystem can call this function");
        _;
    }

    constructor(address _reputationSystemAddress) Ownable(msg.sender) {
        require(_reputationSystemAddress != address(0), "Invalid ReputationSystem address");
        reputationSystemAddress = _reputationSystemAddress;
    }

    /**
     * @dev Store the IPFS hash of a feedback entry
     * Only callable by the ReputationSystem contract
     * @param _projectId ID of the project
     * @param _submitter Address of the user who submitted the feedback
     * @param _targetUser Address of the user who received the feedback
     * @param _feedbackHash IPFS hash of the detailed textual feedback
     */
    function storeFeedback(
        uint256 _projectId,
        address _submitter,
        address _targetUser,
        string calldata _feedbackHash
    ) 
        external 
        onlyReputationSystem 
    {
        require(bytes(_feedbackHash).length > 0, "Feedback hash cannot be empty");
        
        projectFeedbackHashes[_projectId][_submitter][_targetUser] = _feedbackHash;
        
        emit FeedbackStored(_projectId, _submitter, _targetUser, _feedbackHash, block.timestamp);
    }

    /**
     * @dev Get the IPFS hash for a specific feedback entry
     * @param _projectId ID of the project
     * @param _submitter Address of the user who submitted the feedback
     * @param _targetUser Address of the user who received the feedback
     * @return IPFS hash of the feedback
     */
    function getFeedbackHash(
        uint256 _projectId,
        address _submitter,
        address _targetUser
    ) 
        external 
        view 
        returns (string memory) 
    {
        return projectFeedbackHashes[_projectId][_submitter][_targetUser];
    }

    /**
     * @dev Update ReputationSystem contract address (only owner)
     * @param _newReputationSystemAddress New ReputationSystem contract address
     */
    function setReputationSystemAddress(address _newReputationSystemAddress) 
        external 
        onlyOwner 
    {
        require(_newReputationSystemAddress != address(0), "Invalid address");
        reputationSystemAddress = _newReputationSystemAddress;
    }
}

