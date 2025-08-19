// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/Ownable.sol";

interface IProjectManager {
    enum ProjectStatus { Active, Disputed, Completed, Cancelled }
    function resolveDispute(uint256 _projectId, ProjectStatus _newStatus) external;
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

interface IEscrow {
    function releaseFunds(uint256 _projectId, address _freelancer, uint256 _amount) external;
    function refundFunds(uint256 _projectId, address _client, uint256 _amount) external;
    function getEscrowBalance(uint256 _projectId, address _tokenAddress) external view returns (uint256);
    function getProjectToken(uint256 _projectId) external view returns (address);
}

interface IArbitratorRegistry {
    function selectArbitrators(uint256 _numberOfArbitrators) external view returns (address[] memory);
    function isArbitrator(address _userAddress) external view returns (bool);
}

/**
 * @title ArbitrationCourt
 * @dev Manages the decentralized dispute resolution system
 * Oversees dispute initiation, evidence submission, voting, and finalization
 */
contract ArbitrationCourt is Ownable {
    // Dispute status enumeration
    enum DisputeStatus {
        Open,               // 0 - Dispute initiated, awaiting arbitrator selection
        EvidenceCollection, // 1 - Parties can submit evidence
        Voting,             // 2 - Arbitrators are voting
        Finalized           // 3 - Dispute resolved
    }

    // Dispute structure
    struct Dispute {
        uint256 projectId;
        uint256 milestoneIndex;
        address client;
        address freelancer;
        address[] arbitrators; // Selected arbitrators for this dispute
        mapping(address => bool) hasVoted; // Arbitrator => voted
        uint256 clientVotes; // Votes for client
        uint256 freelancerVotes; // Votes for freelancer
        mapping(address => string) evidenceHashes; // User => IPFS hash of evidence
        DisputeStatus status;
        uint256 startTime;
        uint256 evidenceDeadline;
        uint256 votingDeadline;
        uint256 totalArbitrators;
    }

    // State variables
    mapping(uint256 => Dispute) public disputes;
    uint256 public nextDisputeId = 1;
    uint256 public evidencePeriod = 3 days; // Time for evidence submission
    uint256 public votingPeriod = 3 days;   // Time for arbitrator voting
    uint256 public requiredArbitrators = 3; // Number of arbitrators for a dispute

    IProjectManager public projectManager;
    IEscrow public escrow;
    IArbitratorRegistry public arbitratorRegistry;

    // Events
    event DisputeStarted(
        uint256 indexed disputeId,
        uint256 indexed projectId,
        uint256 indexed milestoneIndex,
        address indexed disputer,
        address[] arbitrators,
        uint256 timestamp
    );

    event EvidenceSubmitted(
        uint256 indexed disputeId,
        address indexed submitter,
        string evidenceHash,
        uint256 timestamp
    );

    event ArbitratorVoted(
        uint256 indexed disputeId,
        address indexed arbitrator,
        bool clientWins,
        uint256 timestamp
    );

    event DisputeFinalized(
        uint256 indexed disputeId,
        uint256 indexed projectId,
        bool clientWon,
        uint256 fundsReleasedToFreelancer,
        uint256 fundsRefundedToClient,
        uint256 timestamp
    );

    event DisputeStatusChanged(
        uint256 indexed disputeId,
        DisputeStatus oldStatus,
        DisputeStatus newStatus,
        uint256 timestamp
    );

    // Modifiers
    modifier disputeExists(uint256 _disputeId) {
        require(disputes[_disputeId].projectId != 0, "Dispute does not exist");
        _;
    }

    modifier onlyDisputeParticipant(uint256 _disputeId) {
        require(
            msg.sender == disputes[_disputeId].client || 
            msg.sender == disputes[_disputeId].freelancer,
            "Not a participant in this dispute"
        );
        _;
    }

    modifier onlyArbitrator(uint256 _disputeId) {
        bool isArbitratorForThisDispute = false;
        for (uint256 i = 0; i < disputes[_disputeId].arbitrators.length; i++) {
            if (disputes[_disputeId].arbitrators[i] == msg.sender) {
                isArbitratorForThisDispute = true;
                break;
            }
        }
        require(isArbitratorForThisDispute, "Not an arbitrator for this dispute");
        _;
    }

    constructor(
        address _projectManagerAddress,
        address _escrowAddress,
        address _arbitratorRegistryAddress
    ) Ownable(msg.sender) {
        require(_projectManagerAddress != address(0), "Invalid ProjectManager address");
        require(_escrowAddress != address(0), "Invalid Escrow address");
        require(_arbitratorRegistryAddress != address(0), "Invalid ArbitratorRegistry address");
        projectManager = IProjectManager(_projectManagerAddress);
        escrow = IEscrow(_escrowAddress);
        arbitratorRegistry = IArbitratorRegistry(_arbitratorRegistryAddress);
    }

    /**
     * @dev Start a new dispute for a project milestone
     * Only callable by ProjectManager
     * @param _projectId ID of the project
     * @param _milestoneIndex Index of the milestone being disputed
     * @param _reasonHash IPFS hash of the reason for dispute
     */
    function startDispute(
        uint256 _projectId,
        uint256 _milestoneIndex,
        string calldata _reasonHash
    ) 
        external 
        onlyOwner // Only ProjectManager (owner of this contract) can call this
    {
        // Verify project details
        (,, address client, address freelancer,,,,,) = projectManager.getProjectDetails(_projectId);
        require(client != address(0), "Project does not exist");
        require(bytes(_reasonHash).length > 0, "Reason hash cannot be empty");

        // Select arbitrators
        address[] memory selectedArbitrators = arbitratorRegistry.selectArbitrators(requiredArbitrators);
        require(selectedArbitrators.length == requiredArbitrators, "Not enough arbitrators available");

        uint256 disputeId = nextDisputeId++;

        disputes[disputeId] = Dispute({
            projectId: _projectId,
            milestoneIndex: _milestoneIndex,
            client: client,
            freelancer: freelancer,
            arbitrators: selectedArbitrators,
            clientVotes: 0,
            freelancerVotes: 0,
            status: DisputeStatus.EvidenceCollection,
            startTime: block.timestamp,
            evidenceDeadline: block.timestamp + evidencePeriod,
            votingDeadline: 0, // Set later
            totalArbitrators: requiredArbitrators
        });

        // Initialize hasVoted mapping for arbitrators
        for (uint256 i = 0; i < selectedArbitrators.length; i++) {
            disputes[disputeId].hasVoted[selectedArbitrators[i]] = false;
        }

        emit DisputeStarted(
            disputeId,
            _projectId,
            _milestoneIndex,
            msg.sender, // The one who initiated the dispute (ProjectManager)
            selectedArbitrators,
            block.timestamp
        );
        emit DisputeStatusChanged(disputeId, DisputeStatus.Open, DisputeStatus.EvidenceCollection, block.timestamp);
    }

    /**
     * @dev Submit evidence for a dispute
     * @param _disputeId ID of the dispute
     * @param _evidenceHash IPFS hash of the evidence
     */
    function submitEvidence(uint256 _disputeId, string calldata _evidenceHash) 
        external 
        disputeExists(_disputeId)
        onlyDisputeParticipant(_disputeId)
    {
        require(disputes[_disputeId].status == DisputeStatus.EvidenceCollection, "Not in evidence collection phase");
        require(block.timestamp <= disputes[_disputeId].evidenceDeadline, "Evidence submission period has ended");
        require(bytes(_evidenceHash).length > 0, "Evidence hash cannot be empty");

        disputes[_disputeId].evidenceHashes[msg.sender] = _evidenceHash;

        emit EvidenceSubmitted(_disputeId, msg.sender, _evidenceHash, block.timestamp);
    }

    /**
     * @dev Move dispute to voting phase (only owner)
     * @param _disputeId ID of the dispute
     */
    function startVoting(uint256 _disputeId) external onlyOwner disputeExists(_disputeId) {
        require(disputes[_disputeId].status == DisputeStatus.EvidenceCollection, "Dispute not in evidence collection phase");
        require(block.timestamp > disputes[_disputeId].evidenceDeadline, "Evidence submission period not ended");

        disputes[_disputeId].status = DisputeStatus.Voting;
        disputes[_disputeId].votingDeadline = block.timestamp + votingPeriod;

        emit DisputeStatusChanged(_disputeId, DisputeStatus.EvidenceCollection, DisputeStatus.Voting, block.timestamp);
    }

    /**
     * @dev Arbitrator casts a vote on a dispute
     * @param _disputeId ID of the dispute
     * @param _clientWins True if voting for client, false for freelancer
     */
    function voteOnDispute(uint256 _disputeId, bool _clientWins) 
        external 
        disputeExists(_disputeId)
        onlyArbitrator(_disputeId)
    {
        require(disputes[_disputeId].status == DisputeStatus.Voting, "Not in voting phase");
        require(block.timestamp <= disputes[_disputeId].votingDeadline, "Voting period has ended");
        require(!disputes[_disputeId].hasVoted[msg.sender], "Arbitrator has already voted");

        disputes[_disputeId].hasVoted[msg.sender] = true;
        if (_clientWins) {
            disputes[_disputeId].clientVotes++;
        } else {
            disputes[_disputeId].freelancerVotes++;
        }

        emit ArbitratorVoted(_disputeId, msg.sender, _clientWins, block.timestamp);

        // Check if all arbitrators have voted or majority reached
        if (disputes[_disputeId].clientVotes + disputes[_disputeId].freelancerVotes == disputes[_disputeId].totalArbitrators) {
            finalizeDispute(_disputeId);
        }
    }

    /**
     * @dev Finalize a dispute and execute outcome
     * Can be called by anyone after voting period ends or all arbitrators have voted
     * @param _disputeId ID of the dispute
     */
    function finalizeDispute(uint256 _disputeId) 
        public 
        disputeExists(_disputeId)
    {
        require(disputes[_disputeId].status == DisputeStatus.Voting, "Dispute not in voting phase");
        require(
            block.timestamp > disputes[_disputeId].votingDeadline || 
            (disputes[_disputeId].clientVotes + disputes[_disputeId].freelancerVotes == disputes[_disputeId].totalArbitrators),
            "Voting period not ended or not all arbitrators voted yet"
        );

        Dispute storage dispute = disputes[_disputeId];
        
        bool clientWon = dispute.clientVotes > dispute.freelancerVotes;
        uint256 fundsReleasedToFreelancer = 0;
        uint256 fundsRefundedToClient = 0;

        // Get the total amount in escrow for this milestone
        (, , , , , , , , , uint256 totalMilestones, ,) = projectManager.getProjectDetails(dispute.projectId);
        uint256 milestoneAmount = projectManager.getMilestoneDetails(dispute.projectId, dispute.milestoneIndex).amount;
        address tokenAddress = escrow.getProjectToken(dispute.projectId);

        if (clientWon) {
            // Client wins: refund funds to client
            fundsRefundedToClient = milestoneAmount;
            escrow.refundFunds(dispute.projectId, dispute.client, fundsRefundedToClient);
            projectManager.resolveDispute(dispute.projectId, IProjectManager.ProjectStatus.Cancelled); // Project cancelled
        } else { // Freelancer wins or tie (default to freelancer)
            // Freelancer wins: release funds to freelancer
            fundsReleasedToFreelancer = milestoneAmount;
            escrow.releaseFunds(dispute.projectId, dispute.freelancer, fundsReleasedToFreelancer);
            projectManager.resolveDispute(dispute.projectId, IProjectManager.ProjectStatus.Active); // Project continues
        }

        dispute.status = DisputeStatus.Finalized;

        emit DisputeFinalized(
            _disputeId,
            dispute.projectId,
            clientWon,
            fundsReleasedToFreelancer,
            fundsRefundedToClient,
            block.timestamp
        );
        emit DisputeStatusChanged(_disputeId, DisputeStatus.Voting, DisputeStatus.Finalized, block.timestamp);
    }

    /**
     * @dev Get dispute details
     * @param _disputeId ID of the dispute
     * @return Dispute details
     */
    function getDisputeDetails(uint256 _disputeId) 
        external 
        view 
        disputeExists(_disputeId)
        returns (
            uint256 projectId,
            uint256 milestoneIndex,
            address client,
            address freelancer,
            address[] memory arbitrators,
            uint256 clientVotes,
            uint256 freelancerVotes,
            DisputeStatus status,
            uint256 startTime,
            uint256 evidenceDeadline,
            uint256 votingDeadline,
            uint256 totalArbitrators
        ) 
    {
        Dispute memory dispute = disputes[_disputeId];
        return (
            dispute.projectId,
            dispute.milestoneIndex,
            dispute.client,
            dispute.freelancer,
            dispute.arbitrators,
            dispute.clientVotes,
            dispute.freelancerVotes,
            dispute.status,
            dispute.startTime,
            dispute.evidenceDeadline,
            dispute.votingDeadline,
            dispute.totalArbitrators
        );
    }

    /**
     * @dev Get evidence hash for a participant in a dispute
     * @param _disputeId ID of the dispute
     * @param _participant Address of the participant
     * @return IPFS hash of the evidence
     */
    function getEvidenceHash(uint256 _disputeId, address _participant) 
        external 
        view 
        disputeExists(_disputeId)
        returns (string memory) 
    {
        return disputes[_disputeId].evidenceHashes[_participant];
    }

    /**
     * @dev Update contract addresses (only owner)
     */
    function setContractAddresses(
        address _projectManagerAddress,
        address _escrowAddress,
        address _arbitratorRegistryAddress
    ) 
        external 
        onlyOwner 
    {
        if (_projectManagerAddress != address(0)) {
            projectManager = IProjectManager(_projectManagerAddress);
        }
        if (_escrowAddress != address(0)) {
            escrow = IEscrow(_escrowAddress);
        }
        if (_arbitratorRegistryAddress != address(0)) {
            arbitratorRegistry = IArbitratorRegistry(_arbitratorRegistryAddress);
        }
    }

    /**
     * @dev Set dispute parameters (only owner)
     * @param _evidencePeriod New evidence submission period in seconds
     * @param _votingPeriod New voting period in seconds
     * @param _requiredArbitrators New number of required arbitrators
     */
    function setDisputeParameters(
        uint256 _evidencePeriod,
        uint256 _votingPeriod,
        uint256 _requiredArbitrators
    ) 
        external 
        onlyOwner 
    {
        require(_evidencePeriod > 0, "Evidence period must be greater than zero");
        require(_votingPeriod > 0, "Voting period must be greater than zero");
        require(_requiredArbitrators > 0, "Required arbitrators must be greater than zero");
        
        evidencePeriod = _evidencePeriod;
        votingPeriod = _votingPeriod;
        requiredArbitrators = _requiredArbitrators;
    }
}

