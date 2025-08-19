// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/Ownable.sol";

interface IUserRegistry {
    enum UserRole { None, Freelancer, Client, Arbitrator }
    function getUserRole(address _userAddress) external view returns (UserRole);
    function isActiveUser(address _userAddress) external view returns (bool);
}

interface IJobBoard {
    enum JobStatus { Open, InProgress, Completed, Cancelled }
    function changeJobStatus(uint256 _jobId, JobStatus _newStatus) external;
}

interface IEscrow {
    function releaseFunds(uint256 _projectId, address _freelancer, uint256 _amount) external;
    function getEscrowBalance(uint256 _projectId) external view returns (uint256);
}

interface IArbitrationCourt {
    function startDispute(uint256 _projectId, uint256 _milestoneIndex, string calldata _reasonHash) external;
}

/**
 * @title ProjectManager
 * @dev Oversees the lifecycle of active projects from proposal acceptance to completion
 * Manages project milestones, tracks progress, and facilitates fund release
 */
contract ProjectManager is Ownable {
    // Project status enumeration
    enum ProjectStatus { 
        Active,     // 0 - Project is ongoing
        Disputed,   // 1 - Project has disputes
        Completed,  // 2 - All milestones completed
        Cancelled   // 3 - Project cancelled
    }

    // Milestone structure
    struct Milestone {
        string description;
        uint256 amount;
        bool completed;
        bool approved;
        uint256 completedTime;
        uint256 approvedTime;
    }

    // Project structure
    struct Project {
        uint256 jobId;
        address client;
        address freelancer;
        uint256 agreedBudget;
        uint256 agreedDeadline;
        ProjectStatus status;
        uint256 startTime;
        uint256 lastUpdated;
        uint256 totalMilestones;
        uint256 completedMilestones;
        uint256 approvedMilestones;
    }

    // State variables
    mapping(uint256 => Project) public projects;
    mapping(uint256 => mapping(uint256 => Milestone)) public projectMilestones;
    mapping(uint256 => bool) public projectExists;
    mapping(address => uint256[]) public clientProjects;
    mapping(address => uint256[]) public freelancerProjects;
    
    uint256 public nextProjectId = 1;
    uint256 public totalProjects;
    uint256 public activeProjects;
    
    IUserRegistry public userRegistry;
    IJobBoard public jobBoard;
    IEscrow public escrow;
    IArbitrationCourt public arbitrationCourt;

    // Events
    event ProjectStarted(
        uint256 indexed projectId,
        uint256 indexed jobId,
        address indexed client,
        address freelancer,
        uint256 agreedBudget,
        uint256 timestamp
    );

    event MilestoneCompleted(
        uint256 indexed projectId,
        uint256 indexed milestoneIndex,
        address indexed freelancer,
        uint256 timestamp
    );

    event MilestoneApproved(
        uint256 indexed projectId,
        uint256 indexed milestoneIndex,
        address indexed client,
        uint256 amount,
        uint256 timestamp
    );

    event MilestoneDisputed(
        uint256 indexed projectId,
        uint256 indexed milestoneIndex,
        address indexed disputer,
        uint256 timestamp
    );

    event ProjectCompleted(
        uint256 indexed projectId,
        uint256 indexed jobId,
        uint256 timestamp
    );

    event ProjectStatusChanged(
        uint256 indexed projectId,
        ProjectStatus oldStatus,
        ProjectStatus newStatus,
        uint256 timestamp
    );

    // Modifiers
    modifier projectExists_(uint256 _projectId) {
        require(projectExists[_projectId], "Project does not exist");
        _;
    }

    modifier onlyProjectClient(uint256 _projectId) {
        require(projects[_projectId].client == msg.sender, "Only project client can perform this action");
        _;
    }

    modifier onlyProjectFreelancer(uint256 _projectId) {
        require(projects[_projectId].freelancer == msg.sender, "Only project freelancer can perform this action");
        _;
    }

    modifier onlyProjectParticipant(uint256 _projectId) {
        require(
            projects[_projectId].client == msg.sender || 
            projects[_projectId].freelancer == msg.sender,
            "Only project participants can perform this action"
        );
        _;
    }

    modifier validMilestone(uint256 _projectId, uint256 _milestoneIndex) {
        require(_milestoneIndex < projects[_projectId].totalMilestones, "Invalid milestone index");
        _;
    }

    modifier projectActive(uint256 _projectId) {
        require(projects[_projectId].status == ProjectStatus.Active, "Project is not active");
        _;
    }

    constructor(
        address _userRegistryAddress,
        address _jobBoardAddress,
        address _escrowAddress,
        address _arbitrationCourtAddress
    ) Ownable(msg.sender) {
        require(_userRegistryAddress != address(0), "Invalid UserRegistry address");
        require(_jobBoardAddress != address(0), "Invalid JobBoard address");
        require(_escrowAddress != address(0), "Invalid Escrow address");
        require(_arbitrationCourtAddress != address(0), "Invalid ArbitrationCourt address");
        
        userRegistry = IUserRegistry(_userRegistryAddress);
        jobBoard = IJobBoard(_jobBoardAddress);
        escrow = IEscrow(_escrowAddress);
        arbitrationCourt = IArbitrationCourt(_arbitrationCourtAddress);
    }

    /**
     * @dev Start a new project
     * @param _jobId ID of the job this project is based on
     * @param _clientAddress Address of the client
     * @param _freelancerAddress Address of the freelancer
     * @param _agreedBudget Total agreed budget for the project
     * @param _agreedDeadline Agreed deadline for project completion
     * @param _milestoneDescriptions Array of milestone descriptions
     * @param _milestoneAmounts Array of milestone payment amounts
     */
    function startProject(
        uint256 _jobId,
        address _clientAddress,
        address _freelancerAddress,
        uint256 _agreedBudget,
        uint256 _agreedDeadline,
        string[] calldata _milestoneDescriptions,
        uint256[] calldata _milestoneAmounts
    ) 
        external 
        onlyOwner 
    {
        require(_clientAddress != address(0), "Invalid client address");
        require(_freelancerAddress != address(0), "Invalid freelancer address");
        require(_clientAddress != _freelancerAddress, "Client and freelancer cannot be the same");
        require(_agreedBudget > 0, "Budget must be greater than zero");
        require(_agreedDeadline > block.timestamp, "Deadline must be in the future");
        require(_milestoneDescriptions.length > 0, "At least one milestone is required");
        require(_milestoneDescriptions.length == _milestoneAmounts.length, "Milestone arrays length mismatch");

        // Verify total milestone amounts equal agreed budget
        uint256 totalMilestoneAmount = 0;
        for (uint256 i = 0; i < _milestoneAmounts.length; i++) {
            require(_milestoneAmounts[i] > 0, "Milestone amount must be greater than zero");
            totalMilestoneAmount += _milestoneAmounts[i];
        }
        require(totalMilestoneAmount == _agreedBudget, "Total milestone amounts must equal agreed budget");

        uint256 projectId = nextProjectId++;

        // Create project
        projects[projectId] = Project({
            jobId: _jobId,
            client: _clientAddress,
            freelancer: _freelancerAddress,
            agreedBudget: _agreedBudget,
            agreedDeadline: _agreedDeadline,
            status: ProjectStatus.Active,
            startTime: block.timestamp,
            lastUpdated: block.timestamp,
            totalMilestones: _milestoneDescriptions.length,
            completedMilestones: 0,
            approvedMilestones: 0
        });

        // Create milestones
        for (uint256 i = 0; i < _milestoneDescriptions.length; i++) {
            projectMilestones[projectId][i] = Milestone({
                description: _milestoneDescriptions[i],
                amount: _milestoneAmounts[i],
                completed: false,
                approved: false,
                completedTime: 0,
                approvedTime: 0
            });
        }

        projectExists[projectId] = true;
        clientProjects[_clientAddress].push(projectId);
        freelancerProjects[_freelancerAddress].push(projectId);
        totalProjects++;
        activeProjects++;

        // Update job status to InProgress
        jobBoard.changeJobStatus(_jobId, IJobBoard.JobStatus.InProgress);

        emit ProjectStarted(projectId, _jobId, _clientAddress, _freelancerAddress, _agreedBudget, block.timestamp);
    }

    /**
     * @dev Mark a milestone as completed by freelancer
     * @param _projectId ID of the project
     * @param _milestoneIndex Index of the milestone to mark as completed
     */
    function markMilestoneCompleted(uint256 _projectId, uint256 _milestoneIndex) 
        external 
        projectExists_(_projectId)
        onlyProjectFreelancer(_projectId)
        projectActive(_projectId)
        validMilestone(_projectId, _milestoneIndex)
    {
        Milestone storage milestone = projectMilestones[_projectId][_milestoneIndex];
        require(!milestone.completed, "Milestone already marked as completed");
        require(!milestone.approved, "Milestone already approved");

        milestone.completed = true;
        milestone.completedTime = block.timestamp;
        projects[_projectId].completedMilestones++;
        projects[_projectId].lastUpdated = block.timestamp;

        emit MilestoneCompleted(_projectId, _milestoneIndex, msg.sender, block.timestamp);
    }

    /**
     * @dev Approve a completed milestone and release funds
     * @param _projectId ID of the project
     * @param _milestoneIndex Index of the milestone to approve
     */
    function approveMilestone(uint256 _projectId, uint256 _milestoneIndex) 
        external 
        projectExists_(_projectId)
        onlyProjectClient(_projectId)
        projectActive(_projectId)
        validMilestone(_projectId, _milestoneIndex)
    {
        Milestone storage milestone = projectMilestones[_projectId][_milestoneIndex];
        require(milestone.completed, "Milestone not marked as completed");
        require(!milestone.approved, "Milestone already approved");

        milestone.approved = true;
        milestone.approvedTime = block.timestamp;
        projects[_projectId].approvedMilestones++;
        projects[_projectId].lastUpdated = block.timestamp;

        // Release funds from escrow
        escrow.releaseFunds(_projectId, projects[_projectId].freelancer, milestone.amount);

        emit MilestoneApproved(_projectId, _milestoneIndex, msg.sender, milestone.amount, block.timestamp);

        // Check if all milestones are approved
        if (projects[_projectId].approvedMilestones == projects[_projectId].totalMilestones) {
            _completeProject(_projectId);
        }
    }

    /**
     * @dev Dispute a milestone
     * @param _projectId ID of the project
     * @param _milestoneIndex Index of the milestone to dispute
     * @param _reasonHash IPFS hash of the dispute reason
     */
    function disputeMilestone(
        uint256 _projectId, 
        uint256 _milestoneIndex, 
        string calldata _reasonHash
    ) 
        external 
        projectExists_(_projectId)
        onlyProjectParticipant(_projectId)
        projectActive(_projectId)
        validMilestone(_projectId, _milestoneIndex)
    {
        require(bytes(_reasonHash).length > 0, "Reason hash cannot be empty");
        
        Milestone storage milestone = projectMilestones[_projectId][_milestoneIndex];
        require(milestone.completed, "Can only dispute completed milestones");
        require(!milestone.approved, "Cannot dispute approved milestones");

        // Change project status to disputed
        ProjectStatus oldStatus = projects[_projectId].status;
        projects[_projectId].status = ProjectStatus.Disputed;
        projects[_projectId].lastUpdated = block.timestamp;

        // Start arbitration process
        arbitrationCourt.startDispute(_projectId, _milestoneIndex, _reasonHash);

        emit MilestoneDisputed(_projectId, _milestoneIndex, msg.sender, block.timestamp);
        emit ProjectStatusChanged(_projectId, oldStatus, ProjectStatus.Disputed, block.timestamp);
    }

    /**
     * @dev Complete a project (internal function)
     * @param _projectId ID of the project to complete
     */
    function _completeProject(uint256 _projectId) internal {
        ProjectStatus oldStatus = projects[_projectId].status;
        projects[_projectId].status = ProjectStatus.Completed;
        projects[_projectId].lastUpdated = block.timestamp;
        activeProjects--;

        // Update job status to completed
        jobBoard.changeJobStatus(projects[_projectId].jobId, IJobBoard.JobStatus.Completed);

        emit ProjectCompleted(_projectId, projects[_projectId].jobId, block.timestamp);
        emit ProjectStatusChanged(_projectId, oldStatus, ProjectStatus.Completed, block.timestamp);
    }

    /**
     * @dev Resolve dispute and update project status (only owner - called by ArbitrationCourt)
     * @param _projectId ID of the project
     * @param _newStatus New status after dispute resolution
     */
    function resolveDispute(uint256 _projectId, ProjectStatus _newStatus) 
        external 
        onlyOwner 
        projectExists_(_projectId)
    {
        require(projects[_projectId].status == ProjectStatus.Disputed, "Project is not disputed");
        
        ProjectStatus oldStatus = projects[_projectId].status;
        projects[_projectId].status = _newStatus;
        projects[_projectId].lastUpdated = block.timestamp;

        if (_newStatus == ProjectStatus.Completed) {
            activeProjects--;
            jobBoard.changeJobStatus(projects[_projectId].jobId, IJobBoard.JobStatus.Completed);
        } else if (_newStatus == ProjectStatus.Cancelled) {
            activeProjects--;
            jobBoard.changeJobStatus(projects[_projectId].jobId, IJobBoard.JobStatus.Cancelled);
        }

        emit ProjectStatusChanged(_projectId, oldStatus, _newStatus, block.timestamp);
    }

    /**
     * @dev Get project details
     * @param _projectId ID of the project
     * @return Project details
     */
    function getProjectDetails(uint256 _projectId) 
        external 
        view 
        projectExists_(_projectId)
        returns (
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
        ) 
    {
        Project memory project = projects[_projectId];
        return (
            project.jobId,
            project.client,
            project.freelancer,
            project.agreedBudget,
            project.agreedDeadline,
            project.status,
            project.startTime,
            project.totalMilestones,
            project.completedMilestones,
            project.approvedMilestones
        );
    }

    /**
     * @dev Get milestone details
     * @param _projectId ID of the project
     * @param _milestoneIndex Index of the milestone
     * @return Milestone details
     */
    function getMilestoneDetails(uint256 _projectId, uint256 _milestoneIndex) 
        external 
        view 
        projectExists_(_projectId)
        validMilestone(_projectId, _milestoneIndex)
        returns (
            string memory description,
            uint256 amount,
            bool completed,
            bool approved,
            uint256 completedTime,
            uint256 approvedTime
        ) 
    {
        Milestone memory milestone = projectMilestones[_projectId][_milestoneIndex];
        return (
            milestone.description,
            milestone.amount,
            milestone.completed,
            milestone.approved,
            milestone.completedTime,
            milestone.approvedTime
        );
    }

    /**
     * @dev Get projects by client
     * @param _clientAddress Address of the client
     * @return Array of project IDs
     */
    function getProjectsByClient(address _clientAddress) 
        external 
        view 
        returns (uint256[] memory) 
    {
        return clientProjects[_clientAddress];
    }

    /**
     * @dev Get projects by freelancer
     * @param _freelancerAddress Address of the freelancer
     * @return Array of project IDs
     */
    function getProjectsByFreelancer(address _freelancerAddress) 
        external 
        view 
        returns (uint256[] memory) 
    {
        return freelancerProjects[_freelancerAddress];
    }

    /**
     * @dev Update contract addresses (only owner)
     */
    function setContractAddresses(
        address _userRegistryAddress,
        address _jobBoardAddress,
        address _escrowAddress,
        address _arbitrationCourtAddress
    ) 
        external 
        onlyOwner 
    {
        if (_userRegistryAddress != address(0)) {
            userRegistry = IUserRegistry(_userRegistryAddress);
        }
        if (_jobBoardAddress != address(0)) {
            jobBoard = IJobBoard(_jobBoardAddress);
        }
        if (_escrowAddress != address(0)) {
            escrow = IEscrow(_escrowAddress);
        }
        if (_arbitrationCourtAddress != address(0)) {
            arbitrationCourt = IArbitrationCourt(_arbitrationCourtAddress);
        }
    }
}

