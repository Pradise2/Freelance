// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/Ownable.sol";

interface IUserRegistry {
    enum UserRole { None, Freelancer, Client, Arbitrator }
    function getUserRole(address _userAddress) external view returns (UserRole);
    function isActiveUser(address _userAddress) external view returns (bool);
}

/**
 * @title JobBoard
 * @dev Enables clients to post job listings and freelancers to discover projects
 * Manages the lifecycle of job postings from creation to closure
 */
contract JobBoard is Ownable {
    // Job status enumeration
    enum JobStatus { 
        Open,       // 0 - Available for proposals
        InProgress, // 1 - Proposal accepted, project started
        Completed,  // 2 - Project completed
        Cancelled   // 3 - Job cancelled by client
    }

    // Job structure
    struct Job {
        address client;
        string jobTitle;
        string jobDescriptionHash; // IPFS hash
        uint256 budget;
        uint256 deadline;
        string[] requiredSkills;
        JobStatus status;
        uint256 creationTime;
        uint256 lastUpdated;
    }

    // State variables
    mapping(uint256 => Job) public jobs;
    mapping(address => uint256[]) public clientJobs;
    mapping(uint256 => bool) public jobExists;
    
    uint256 public nextJobId = 1;
    uint256 public totalJobs;
    uint256 public activeJobs;
    
    IUserRegistry public userRegistry;

    // Events
    event JobPosted(
        uint256 indexed jobId,
        address indexed client,
        string jobTitle,
        uint256 budget,
        uint256 deadline,
        uint256 timestamp
    );

    event JobUpdated(
        uint256 indexed jobId,
        address indexed client,
        uint256 timestamp
    );

    event JobCancelled(
        uint256 indexed jobId,
        address indexed client,
        uint256 timestamp
    );

    event JobStatusChanged(
        uint256 indexed jobId,
        JobStatus oldStatus,
        JobStatus newStatus,
        uint256 timestamp
    );

    // Modifiers
    modifier onlyClient() {
        require(
            userRegistry.getUserRole(msg.sender) == IUserRegistry.UserRole.Client,
            "Only clients can perform this action"
        );
        require(userRegistry.isActiveUser(msg.sender), "User account is not active");
        _;
    }

    modifier jobExistsAndOpen(uint256 _jobId) {
        require(jobExists[_jobId], "Job does not exist");
        require(jobs[_jobId].status == JobStatus.Open, "Job is not open");
        _;
    }

    modifier onlyJobOwner(uint256 _jobId) {
        require(jobs[_jobId].client == msg.sender, "Not the job owner");
        _;
    }

    modifier validBudget(uint256 _budget) {
        require(_budget > 0, "Budget must be greater than zero");
        _;
    }

    modifier validDeadline(uint256 _deadline) {
        require(_deadline > block.timestamp, "Deadline must be in the future");
        _;
    }

    constructor(address _userRegistryAddress) Ownable(msg.sender) {
        require(_userRegistryAddress != address(0), "Invalid UserRegistry address");
        userRegistry = IUserRegistry(_userRegistryAddress);
    }

    /**
     * @dev Post a new job listing
     * @param _jobTitle Title of the job
     * @param _jobDescriptionHash IPFS hash of detailed job description
     * @param _budget Budget for the job in wei
     * @param _deadline Unix timestamp deadline for the job
     * @param _requiredSkills Array of required skills
     */
    function postJob(
        string calldata _jobTitle,
        string calldata _jobDescriptionHash,
        uint256 _budget,
        uint256 _deadline,
        string[] calldata _requiredSkills
    ) 
        external 
        onlyClient 
        validBudget(_budget)
        validDeadline(_deadline)
    {
        require(bytes(_jobTitle).length > 0, "Job title cannot be empty");
        require(bytes(_jobDescriptionHash).length > 0, "Job description hash cannot be empty");
        require(_requiredSkills.length > 0, "At least one skill is required");

        uint256 jobId = nextJobId++;
        
        jobs[jobId] = Job({
            client: msg.sender,
            jobTitle: _jobTitle,
            jobDescriptionHash: _jobDescriptionHash,
            budget: _budget,
            deadline: _deadline,
            requiredSkills: _requiredSkills,
            status: JobStatus.Open,
            creationTime: block.timestamp,
            lastUpdated: block.timestamp
        });

        jobExists[jobId] = true;
        clientJobs[msg.sender].push(jobId);
        totalJobs++;
        activeJobs++;

        emit JobPosted(jobId, msg.sender, _jobTitle, _budget, _deadline, block.timestamp);
    }

    /**
     * @dev Update job details (only before proposal acceptance)
     * @param _jobId ID of the job to update
     * @param _newJobTitle New job title
     * @param _newJobDescriptionHash New IPFS hash for job description
     * @param _newBudget New budget
     * @param _newDeadline New deadline
     * @param _newRequiredSkills New required skills array
     */
    function updateJob(
        uint256 _jobId,
        string calldata _newJobTitle,
        string calldata _newJobDescriptionHash,
        uint256 _newBudget,
        uint256 _newDeadline,
        string[] calldata _newRequiredSkills
    ) 
        external 
        jobExistsAndOpen(_jobId)
        onlyJobOwner(_jobId)
        validBudget(_newBudget)
        validDeadline(_newDeadline)
    {
        require(bytes(_newJobTitle).length > 0, "Job title cannot be empty");
        require(bytes(_newJobDescriptionHash).length > 0, "Job description hash cannot be empty");
        require(_newRequiredSkills.length > 0, "At least one skill is required");

        Job storage job = jobs[_jobId];
        job.jobTitle = _newJobTitle;
        job.jobDescriptionHash = _newJobDescriptionHash;
        job.budget = _newBudget;
        job.deadline = _newDeadline;
        job.requiredSkills = _newRequiredSkills;
        job.lastUpdated = block.timestamp;

        emit JobUpdated(_jobId, msg.sender, block.timestamp);
    }

    /**
     * @dev Cancel a job posting
     * @param _jobId ID of the job to cancel
     */
    function cancelJob(uint256 _jobId) 
        external 
        jobExistsAndOpen(_jobId)
        onlyJobOwner(_jobId)
    {
        JobStatus oldStatus = jobs[_jobId].status;
        jobs[_jobId].status = JobStatus.Cancelled;
        jobs[_jobId].lastUpdated = block.timestamp;
        activeJobs--;

        emit JobCancelled(_jobId, msg.sender, block.timestamp);
        emit JobStatusChanged(_jobId, oldStatus, JobStatus.Cancelled, block.timestamp);
    }

    /**
     * @dev Change job status (internal function for other contracts)
     * @param _jobId ID of the job
     * @param _newStatus New status to set
     */
    function changeJobStatus(uint256 _jobId, JobStatus _newStatus) 
        external 
        onlyOwner 
    {
        require(jobExists[_jobId], "Job does not exist");
        
        JobStatus oldStatus = jobs[_jobId].status;
        require(oldStatus != _newStatus, "Status is already set to this value");
        
        jobs[_jobId].status = _newStatus;
        jobs[_jobId].lastUpdated = block.timestamp;

        // Update active jobs counter
        if (oldStatus == JobStatus.Open && _newStatus != JobStatus.Open) {
            activeJobs--;
        } else if (oldStatus != JobStatus.Open && _newStatus == JobStatus.Open) {
            activeJobs++;
        }

        emit JobStatusChanged(_jobId, oldStatus, _newStatus, block.timestamp);
    }

    /**
     * @dev Get job details
     * @param _jobId ID of the job
     * @return Job details
     */
    function getJobDetails(uint256 _jobId) 
        external 
        view 
        returns (
            address client,
            string memory jobTitle,
            string memory jobDescriptionHash,
            uint256 budget,
            uint256 deadline,
            string[] memory requiredSkills,
            JobStatus status,
            uint256 creationTime,
            uint256 lastUpdated
        ) 
    {
        require(jobExists[_jobId], "Job does not exist");
        
        Job memory job = jobs[_jobId];
        return (
            job.client,
            job.jobTitle,
            job.jobDescriptionHash,
            job.budget,
            job.deadline,
            job.requiredSkills,
            job.status,
            job.creationTime,
            job.lastUpdated
        );
    }

    /**
     * @dev Get jobs posted by a specific client
     * @param _clientAddress Address of the client
     * @return Array of job IDs
     */
    function getJobsByClient(address _clientAddress) 
        external 
        view 
        returns (uint256[] memory) 
    {
        return clientJobs[_clientAddress];
    }

    /**
     * @dev Get all active (open) jobs
     * @return Array of job IDs that are currently open
     */
    function getAllActiveJobs() 
        external 
        view 
        returns (uint256[] memory) 
    {
        uint256[] memory activeJobIds = new uint256[](activeJobs);
        uint256 currentIndex = 0;
        
        for (uint256 i = 1; i < nextJobId; i++) {
            if (jobExists[i] && jobs[i].status == JobStatus.Open) {
                activeJobIds[currentIndex] = i;
                currentIndex++;
            }
        }
        
        return activeJobIds;
    }

    /**
     * @dev Get jobs by status
     * @param _status Status to filter by
     * @return Array of job IDs with the specified status
     */
    function getJobsByStatus(JobStatus _status) 
        external 
        view 
        returns (uint256[] memory) 
    {
        // First, count jobs with the specified status
        uint256 count = 0;
        for (uint256 i = 1; i < nextJobId; i++) {
            if (jobExists[i] && jobs[i].status == _status) {
                count++;
            }
        }
        
        // Create array and populate it
        uint256[] memory jobIds = new uint256[](count);
        uint256 currentIndex = 0;
        
        for (uint256 i = 1; i < nextJobId; i++) {
            if (jobExists[i] && jobs[i].status == _status) {
                jobIds[currentIndex] = i;
                currentIndex++;
            }
        }
        
        return jobIds;
    }

    /**
     * @dev Update UserRegistry address (only owner)
     * @param _userRegistryAddress New UserRegistry contract address
     */
    function setUserRegistryAddress(address _userRegistryAddress) 
        external 
        onlyOwner 
    {
        require(_userRegistryAddress != address(0), "Invalid address");
        userRegistry = IUserRegistry(_userRegistryAddress);
    }
}

