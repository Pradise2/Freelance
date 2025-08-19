// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title Governance
 * @dev Enables decentralized decision-making for the platform using token-based voting
 * Implements a DAO pattern for protocol upgrades and parameter changes
 */
contract Governance is Ownable {
    // Proposal status
    enum ProposalStatus {
        Pending,    // 0 - Proposal created, voting not started
        Active,     // 1 - Voting is active
        Succeeded,  // 2 - Proposal passed
        Defeated,   // 3 - Proposal failed
        Queued,     // 4 - Proposal queued for execution
        Executed,   // 5 - Proposal executed
        Cancelled   // 6 - Proposal cancelled
    }

    // Vote type
    enum VoteType {
        Against,    // 0 - Vote against
        For,        // 1 - Vote for
        Abstain     // 2 - Abstain from voting
    }

    // Proposal structure
    struct Proposal {
        uint256 id;
        address proposer;
        address[] targets;
        uint256[] values;
        bytes[] calldatas;
        string description;
        uint256 startBlock;
        uint256 endBlock;
        uint256 forVotes;
        uint256 againstVotes;
        uint256 abstainVotes;
        ProposalStatus status;
        mapping(address => bool) hasVoted;
        mapping(address => VoteType) votes;
    }

    // State variables
    mapping(uint256 => Proposal) public proposals;
    uint256 public nextProposalId = 1;

    IERC20 public governanceToken;
    
    uint256 public votingDelay = 1 days;      // Delay before voting starts (in blocks)
    uint256 public votingPeriod = 3 days;    // Duration of voting period (in blocks)
    uint256 public proposalThreshold = 1000 * 10**18; // Minimum tokens to create proposal
    uint256 public quorumVotes = 10000 * 10**18;      // Minimum votes for quorum

    // Events
    event ProposalCreated(
        uint256 indexed proposalId,
        address indexed proposer,
        address[] targets,
        uint256[] values,
        string description,
        uint256 startBlock,
        uint256 endBlock
    );

    event VoteCast(
        address indexed voter,
        uint256 indexed proposalId,
        VoteType support,
        uint256 votes
    );

    event ProposalQueued(
        uint256 indexed proposalId,
        uint256 eta
    );

    event ProposalExecuted(
        uint256 indexed proposalId
    );

    event ProposalCancelled(
        uint256 indexed proposalId
    );

    constructor(address _governanceTokenAddress) Ownable(msg.sender) {
        require(_governanceTokenAddress != address(0), "Invalid governance token address");
        governanceToken = IERC20(_governanceTokenAddress);
    }

    /**
     * @dev Create a new proposal
     * @param _targets Array of target contract addresses
     * @param _values Array of ETH values to send with calls
     * @param _calldatas Array of function call data
     * @param _description Description of the proposal
     */
    function propose(
        address[] calldata _targets,
        uint256[] calldata _values,
        bytes[] calldata _calldatas,
        string calldata _description
    ) external returns (uint256) {
        require(
            governanceToken.balanceOf(msg.sender) >= proposalThreshold,
            "Proposer votes below proposal threshold"
        );
        require(_targets.length > 0, "Must provide actions");
        require(_targets.length == _values.length, "Proposal function information arity mismatch");
        require(_targets.length == _calldatas.length, "Proposal function information arity mismatch");

        uint256 proposalId = nextProposalId++;
        uint256 startBlock = block.number + votingDelay;
        uint256 endBlock = startBlock + votingPeriod;

        proposals[proposalId] = Proposal({
            id: proposalId,
            proposer: msg.sender,
            targets: _targets,
            values: _values,
            calldatas: _calldatas,
            description: _description,
            startBlock: startBlock,
            endBlock: endBlock,
            forVotes: 0,
            againstVotes: 0,
            abstainVotes: 0,
            status: ProposalStatus.Pending
        });

        emit ProposalCreated(
            proposalId,
            msg.sender,
            _targets,
            _values,
            _description,
            startBlock,
            endBlock
        );

        return proposalId;
    }

    /**
     * @dev Cast a vote on a proposal
     * @param _proposalId ID of the proposal
     * @param _support Vote type (0=Against, 1=For, 2=Abstain)
     */
    function castVote(uint256 _proposalId, VoteType _support) external {
        require(proposals[_proposalId].id != 0, "Proposal does not exist");
        require(block.number >= proposals[_proposalId].startBlock, "Voting has not started");
        require(block.number <= proposals[_proposalId].endBlock, "Voting has ended");
        require(!proposals[_proposalId].hasVoted[msg.sender], "Voter has already voted");

        uint256 votes = governanceToken.balanceOf(msg.sender);
        require(votes > 0, "Voter has no voting power");

        proposals[_proposalId].hasVoted[msg.sender] = true;
        proposals[_proposalId].votes[msg.sender] = _support;

        if (_support == VoteType.Against) {
            proposals[_proposalId].againstVotes += votes;
        } else if (_support == VoteType.For) {
            proposals[_proposalId].forVotes += votes;
        } else {
            proposals[_proposalId].abstainVotes += votes;
        }

        emit VoteCast(msg.sender, _proposalId, _support, votes);
    }

    /**
     * @dev Queue a successful proposal for execution
     * @param _proposalId ID of the proposal
     */
    function queue(uint256 _proposalId) external {
        require(proposals[_proposalId].id != 0, "Proposal does not exist");
        require(block.number > proposals[_proposalId].endBlock, "Voting period not ended");
        require(proposals[_proposalId].status == ProposalStatus.Pending, "Proposal not in pending state");

        // Check if proposal succeeded
        uint256 totalVotes = proposals[_proposalId].forVotes + proposals[_proposalId].againstVotes + proposals[_proposalId].abstainVotes;
        bool quorumReached = totalVotes >= quorumVotes;
        bool majorityFor = proposals[_proposalId].forVotes > proposals[_proposalId].againstVotes;

        if (quorumReached && majorityFor) {
            proposals[_proposalId].status = ProposalStatus.Queued;
            emit ProposalQueued(_proposalId, block.timestamp + 2 days); // 2-day timelock
        } else {
            proposals[_proposalId].status = ProposalStatus.Defeated;
        }
    }

    /**
     * @dev Execute a queued proposal
     * @param _proposalId ID of the proposal
     */
    function execute(uint256 _proposalId) external payable {
        require(proposals[_proposalId].id != 0, "Proposal does not exist");
        require(proposals[_proposalId].status == ProposalStatus.Queued, "Proposal not queued");

        proposals[_proposalId].status = ProposalStatus.Executed;

        // Execute all actions in the proposal
        for (uint256 i = 0; i < proposals[_proposalId].targets.length; i++) {
            (bool success, ) = proposals[_proposalId].targets[i].call{
                value: proposals[_proposalId].values[i]
            }(proposals[_proposalId].calldatas[i]);
            require(success, "Transaction execution reverted");
        }

        emit ProposalExecuted(_proposalId);
    }

    /**
     * @dev Cancel a proposal (only proposer or owner)
     * @param _proposalId ID of the proposal
     */
    function cancel(uint256 _proposalId) external {
        require(proposals[_proposalId].id != 0, "Proposal does not exist");
        require(
            msg.sender == proposals[_proposalId].proposer || msg.sender == owner(),
            "Only proposer or owner can cancel"
        );
        require(
            proposals[_proposalId].status == ProposalStatus.Pending ||
            proposals[_proposalId].status == ProposalStatus.Active,
            "Cannot cancel executed proposal"
        );

        proposals[_proposalId].status = ProposalStatus.Cancelled;
        emit ProposalCancelled(_proposalId);
    }

    /**
     * @dev Get proposal details
     * @param _proposalId ID of the proposal
     * @return Proposal details
     */
    function getProposal(uint256 _proposalId) 
        external 
        view 
        returns (
            uint256 id,
            address proposer,
            address[] memory targets,
            uint256[] memory values,
            bytes[] memory calldatas,
            string memory description,
            uint256 startBlock,
            uint256 endBlock,
            uint256 forVotes,
            uint256 againstVotes,
            uint256 abstainVotes,
            ProposalStatus status
        ) 
    {
        require(proposals[_proposalId].id != 0, "Proposal does not exist");
        
        Proposal storage proposal = proposals[_proposalId];
        return (
            proposal.id,
            proposal.proposer,
            proposal.targets,
            proposal.values,
            proposal.calldatas,
            proposal.description,
            proposal.startBlock,
            proposal.endBlock,
            proposal.forVotes,
            proposal.againstVotes,
            proposal.abstainVotes,
            proposal.status
        );
    }

    /**
     * @dev Update governance parameters (only owner or through governance)
     */
    function setVotingDelay(uint256 _newVotingDelay) external onlyOwner {
        votingDelay = _newVotingDelay;
    }

    function setVotingPeriod(uint256 _newVotingPeriod) external onlyOwner {
        votingPeriod = _newVotingPeriod;
    }

    function setProposalThreshold(uint256 _newProposalThreshold) external onlyOwner {
        proposalThreshold = _newProposalThreshold;
    }

    function setQuorumVotes(uint256 _newQuorumVotes) external onlyOwner {
        quorumVotes = _newQuorumVotes;
    }
}

