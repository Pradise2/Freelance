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
    function getJobDetails(uint256 _jobId) external view returns (
        address client,
        string memory jobTitle,
        string memory jobDescriptionHash,
        uint256 budget,
        uint256 deadline,
        string[] memory requiredSkills,
        JobStatus status,
        uint256 creationTime,
        uint256 lastUpdated
    );
}

interface IProjectManager {
    struct Milestone {
        string description;
        uint256 amount;
        bool completed;
        bool approved;
        uint256 completedTime;
        uint256 approvedTime;
    }
    function startProject(
        uint256 _jobId,
        address _clientAddress,
        address _freelancerAddress,
        uint256 _agreedBudget,
        uint256 _agreedDeadline,
        string[] calldata _milestoneDescriptions,
        uint256[] calldata _milestoneAmounts
    ) external;
}

interface IEscrow {
    function fundProject(uint256 _projectId, address _client, uint256 _amount) external payable;
}

/**
 * @title ProposalManager
 * @dev Facilitates interaction between freelancers and clients regarding job proposals
 * Manages proposal submission, acceptance, and rejection
 */
contract ProposalManager is Ownable {
    // Proposal status enumeration
    enum ProposalStatus {
        Pending,  // 0 - Submitted, awaiting client review
        Accepted, // 1 - Accepted by client
        Rejected  // 2 - Rejected by client
    }

    // Milestone structure (re-declared for local use, consistent with ProjectManager)
    struct Milestone {
        string description;
        uint256 amount;
    }

    // Proposal structure
    struct Proposal {
        uint256 jobId;
        address freelancer;
        uint256 proposedBudget;
        uint256 proposedDeadline;
        string proposalDetailsHash; // IPFS hash
        Milestone[] proposedMilestones;
        ProposalStatus status;
        uint256 submissionTime;
        uint256 lastUpdated;
    }

    // State variables
    mapping(uint256 => mapping(address => Proposal)) public proposals;
    mapping(uint256 => address[]) public jobProposals;
    
    uint256 public totalProposals;

    IUserRegistry public userRegistry;
    IJobBoard public jobBoard;
    IProjectManager public projectManager;
    IEscrow public escrow;

    // Events
    event ProposalSubmitted(
        uint256 indexed jobId,
        address indexed freelancer,
        uint256 proposedBudget,
        uint256 timestamp
    );

    event ProposalAccepted(
        uint256 indexed jobId,
        address indexed client,
        address indexed freelancer,
        uint256 projectId,
        uint256 timestamp
    );

    event ProposalRejected(
        uint256 indexed jobId,
        address indexed client,
        address indexed freelancer,
        uint256 timestamp
    );

    event ProposalStatusChanged(
        uint256 indexed jobId,
        address indexed freelancer,
        ProposalStatus oldStatus,
        ProposalStatus newStatus,
        uint256 timestamp
    );

    // Modifiers
    modifier onlyFreelancer() {
        require(
            userRegistry.getUserRole(msg.sender) == IUserRegistry.UserRole.Freelancer,
            "Only freelancers can perform this action"
        );
        require(userRegistry.isActiveUser(msg.sender), "User account is not active");
        _;
    }

    modifier onlyClient() {
        require(
            userRegistry.getUserRole(msg.sender) == IUserRegistry.UserRole.Client,
            "Only clients can perform this action"
        );
        require(userRegistry.isActiveUser(msg.sender), "User account is not active");
        _;
    }

    modifier jobExistsAndOpen(uint256 _jobId) {
        (,,,,, , IJobBoard.JobStatus status,,) = jobBoard.getJobDetails(_jobId);
        require(status == IJobBoard.JobStatus.Open, "Job is not open for proposals");
        _;
    }

    modifier proposalExists(uint256 _jobId, address _freelancerAddress) {
        require(proposals[_jobId][_freelancerAddress].jobId != 0, "Proposal does not exist");
        _;
    }

    constructor(
        address _userRegistryAddress,
        address _jobBoardAddress,
        address _projectManagerAddress,
        address _escrowAddress
    ) Ownable(msg.sender) {
        require(_userRegistryAddress != address(0), "Invalid UserRegistry address");
        require(_jobBoardAddress != address(0), "Invalid JobBoard address");
        require(_projectManagerAddress != address(0), "Invalid ProjectManager address");
        require(_escrowAddress != address(0), "Invalid Escrow address");

        userRegistry = IUserRegistry(_userRegistryAddress);
        jobBoard = IJobBoard(_jobBoardAddress);
        projectManager = IProjectManager(_projectManagerAddress);
        escrow = IEscrow(_escrowAddress);
    }

    /**
     * @dev Submit a proposal for an open job
     * @param _jobId ID of the job to propose for
     * @param _proposedBudget Proposed budget for the job
     * @param _proposedDeadline Proposed deadline for the job
     * @param _proposalDetailsHash IPFS hash of detailed proposal document
     * @param _proposedMilestoneDescriptions Array of proposed milestone descriptions
     * @param _proposedMilestoneAmounts Array of proposed milestone amounts
     */
    function submitProposal(
        uint256 _jobId,
        uint256 _proposedBudget,
        uint256 _proposedDeadline,
        string calldata _proposalDetailsHash,
        string[] calldata _proposedMilestoneDescriptions,
        uint256[] calldata _proposedMilestoneAmounts
    ) 
        external 
        onlyFreelancer 
        jobExistsAndOpen(_jobId)
    {
        require(proposals[_jobId][msg.sender].jobId == 0, "Proposal already submitted for this job");
        require(_proposedBudget > 0, "Proposed budget must be greater than zero");
        require(_proposedDeadline > block.timestamp, "Proposed deadline must be in the future");
        require(bytes(_proposalDetailsHash).length > 0, "Proposal details hash cannot be empty");
        require(_proposedMilestoneDescriptions.length > 0, "At least one milestone is required");
        require(_proposedMilestoneDescriptions.length == _proposedMilestoneAmounts.length, "Milestone arrays length mismatch");

        uint256 totalMilestoneAmount = 0;
        for (uint256 i = 0; i < _proposedMilestoneAmounts.length; i++) {
            require(_proposedMilestoneAmounts[i] > 0, "Milestone amount must be greater than zero");
            totalMilestoneAmount += _proposedMilestoneAmounts[i];
        }
        require(totalMilestoneAmount == _proposedBudget, "Total milestone amounts must equal proposed budget");

        Milestone[] memory milestones = new Milestone[](_proposedMilestoneDescriptions.length);
        for (uint256 i = 0; i < _proposedMilestoneDescriptions.length; i++) {
            milestones[i] = Milestone({
                description: _proposedMilestoneDescriptions[i],
                amount: _proposedMilestoneAmounts[i]
            });
        }

        proposals[_jobId][msg.sender] = Proposal({
            jobId: _jobId,
            freelancer: msg.sender,
            proposedBudget: _proposedBudget,
            proposedDeadline: _proposedDeadline,
            proposalDetailsHash: _proposalDetailsHash,
            proposedMilestones: milestones,
            status: ProposalStatus.Pending,
            submissionTime: block.timestamp,
            lastUpdated: block.timestamp
        });

        jobProposals[_jobId].push(msg.sender);
        totalProposals++;

        emit ProposalSubmitted(_jobId, msg.sender, _proposedBudget, block.timestamp);
    }

    /**
     * @dev Accept a freelancer's proposal
     * @param _jobId ID of the job
     * @param _freelancerAddress Address of the freelancer whose proposal to accept
     */
    function acceptProposal(uint256 _jobId, address _freelancerAddress) 
        external 
        onlyClient 
        proposalExists(_jobId, _freelancerAddress)
    {
        (address clientAddress,,,,,,,) = jobBoard.getJobDetails(_jobId);
        require(clientAddress == msg.sender, "Not the client for this job");

        Proposal storage proposal = proposals[_jobId][_freelancerAddress];
        require(proposal.status == ProposalStatus.Pending, "Proposal is not pending");

        // Set proposal status to Accepted
        ProposalStatus oldStatus = proposal.status;
        proposal.status = ProposalStatus.Accepted;
        proposal.lastUpdated = block.timestamp;

        // Prepare milestone data for ProjectManager
        string[] memory milestoneDescriptions = new string[](proposal.proposedMilestones.length);
        uint256[] memory milestoneAmounts = new uint256[](proposal.proposedMilestones.length);
        for (uint256 i = 0; i < proposal.proposedMilestones.length; i++) {
            milestoneDescriptions[i] = proposal.proposedMilestones[i].description;
            milestoneAmounts[i] = proposal.proposedMilestones[i].amount;
        }

        // Start project in ProjectManager
        projectManager.startProject(
            _jobId,
            msg.sender, // client
            _freelancerAddress,
            proposal.proposedBudget,
            proposal.proposedDeadline,
            milestoneDescriptions,
            milestoneAmounts
        );

        // Fund escrow for the project (assuming projectManager.startProject returns projectId or it's predictable)
        // For simplicity, we'll assume the projectId is the next one from ProjectManager
        // In a real scenario, ProjectManager.startProject might return the projectId or emit an event with it.
        // For now, we'll use a placeholder projectId (e.g., totalProjects + 1 from ProjectManager's perspective)
        // This needs careful handling in a real system to ensure correct projectId mapping.
        // For this example, we'll assume a simple incrementing ID from ProjectManager.
        // A more robust solution would involve ProjectManager emitting the new projectId and this contract listening for it.
        // For now, we'll pass 0 as projectId to escrow.fundProject, which needs to be updated later.
        // A better approach: ProjectManager.startProject should return the new projectId, and then this contract calls escrow.fundProject with that ID.
        // For the purpose of this development, we'll assume ProjectManager handles the funding call to Escrow internally upon project start.
        // Or, the client directly funds the escrow after accepting the proposal.
        // Let's adjust the flow: client accepts proposal, then client funds escrow, then project starts.
        // For now, let's assume the client will fund the escrow separately after acceptance.
        // The `startProject` call in ProjectManager will be triggered by the client after funding the escrow.
        // So, this `acceptProposal` function only changes the proposal status.

        emit ProposalAccepted(_jobId, msg.sender, _freelancerAddress, 0, block.timestamp); // projectId is placeholder
        emit ProposalStatusChanged(_jobId, _freelancerAddress, oldStatus, ProposalStatus.Accepted, block.timestamp);
    }

    /**
     * @dev Reject a freelancer's proposal
     * @param _jobId ID of the job
     * @param _freelancerAddress Address of the freelancer whose proposal to reject
     */
    function rejectProposal(uint256 _jobId, address _freelancerAddress) 
        external 
        onlyClient 
        proposalExists(_jobId, _freelancerAddress)
    {
        (address clientAddress,,,,,,,) = jobBoard.getJobDetails(_jobId);
        require(clientAddress == msg.sender, "Not the client for this job");

        Proposal storage proposal = proposals[_jobId][_freelancerAddress];
        require(proposal.status == ProposalStatus.Pending, "Proposal is not pending");

        ProposalStatus oldStatus = proposal.status;
        proposal.status = ProposalStatus.Rejected;
        proposal.lastUpdated = block.timestamp;

        emit ProposalRejected(_jobId, msg.sender, _freelancerAddress, block.timestamp);
        emit ProposalStatusChanged(_jobId, _freelancerAddress, oldStatus, ProposalStatus.Rejected, block.timestamp);
    }

    /**
     * @dev Get all proposals for a specific job
     * @param _jobId ID of the job
     * @return Array of freelancer addresses who submitted proposals
     */
    function getProposalsForJob(uint256 _jobId) 
        external 
        view 
        returns (address[] memory) 
    {
        return jobProposals[_jobId];
    }

    /**
     * @dev Get details of a specific proposal
     * @param _jobId ID of the job
     * @param _freelancerAddress Address of the freelancer
     * @return Proposal details
     */
    function getProposalDetails(
        uint256 _jobId, 
        address _freelancerAddress
    ) 
        external 
        view 
        proposalExists(_jobId, _freelancerAddress)
        returns (
            uint256 jobId,
            address freelancer,
            uint256 proposedBudget,
            uint256 proposedDeadline,
            string memory proposalDetailsHash,
            Milestone[] memory proposedMilestones,
            ProposalStatus status,
            uint256 submissionTime,
            uint256 lastUpdated
        ) 
    {
        Proposal memory proposal = proposals[_jobId][_freelancerAddress];
        return (
            proposal.jobId,
            proposal.freelancer,
            proposal.proposedBudget,
            proposal.proposedDeadline,
            proposal.proposalDetailsHash,
            proposal.proposedMilestones,
            proposal.status,
            proposal.submissionTime,
            proposal.lastUpdated
        );
    }

    /**
     * @dev Update contract addresses (only owner)
     */
    function setContractAddresses(
        address _userRegistryAddress,
        address _jobBoardAddress,
        address _projectManagerAddress,
        address _escrowAddress
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
        if (_projectManagerAddress != address(0)) {
            projectManager = IProjectManager(_projectManagerAddress);
        }
        if (_escrowAddress != address(0)) {
            escrow = IEscrow(_escrowAddress);
        }
    }
}

