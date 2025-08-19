// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../src/ArbitrationCourt.sol";
import "../src/ProjectManager.sol"; // Keep this for ProjectManager contract instance
import "../src/Escrow.sol"; // Keep this for Escrow contract instance
import "../src/ArbitratorRegistry.sol"; // Keep this for ArbitratorRegistry contract instance
import "../src/FeeManager.sol"; // Keep this for FeeManager contract instance
import "../src/UserRegistry.sol"; // Keep this for UserRegistry contract instance
import "../src/ReputationSystem.sol"; // Keep this for ReputationSystem contract instance
import "../src/FeedbackStorage.sol"; // Keep this for FeedbackStorage contract instance

// Mock interfaces for external contracts that ArbitrationCourt interacts with
interface IProjectManagerMock {
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
    function getMilestoneDetails(uint256 _projectId, uint256 _milestoneIndex) external view returns (
        string memory description,
        uint256 amount,
        bool completed,
        bool approved,
        uint256 completedTime,
        uint256 approvedTime
    );
    function resolveDispute(uint256 _projectId, ProjectStatus _newStatus) external;
}

interface IEscrowMock {
    function releaseFunds(uint256 _projectId, address _freelancer, uint256 _amount) external;
    function refundFunds(uint256 _projectId, address _client, uint256 _amount) external;
    function getEscrowBalance(uint256 _projectId, address _tokenAddress) external view returns (uint256);
    function getProjectToken(uint256 _projectId) external view returns (address);
}

interface IArbitratorRegistryMock {
    function selectArbitrators(uint256 _numberOfArbitrators) external view returns (address[] memory);
    function isArbitrator(address _userAddress) external view returns (bool);
}

contract ArbitrationCourtTest is Test {
    ArbitrationCourt arbitrationCourt;
    ProjectManager projectManager;
    Escrow escrow;
    ArbitratorRegistry arbitratorRegistry;
    FeeManager feeManager;
    UserRegistry userRegistry;
    ReputationSystem reputationSystem;
    FeedbackStorage feedbackStorage;

    address public deployer;
    address public client1;
    address public freelancer1;
    address public arbitrator1;
    address public arbitrator2;
    address public arbitrator3;
    address public platformTreasury;

    function setUp() public {
        deployer = makeAddr("deployer");
        client1 = makeAddr("client1");
        freelancer1 = makeAddr("freelancer1");
        arbitrator1 = makeAddr("arbitrator1");
        arbitrator2 = makeAddr("arbitrator2");
        arbitrator3 = makeAddr("arbitrator3");
        platformTreasury = makeAddr("platformTreasury");

        vm.startPrank(deployer);
        userRegistry = new UserRegistry();
        feedbackStorage = new FeedbackStorage(address(this)); // Mock ReputationSystem
        reputationSystem = new ReputationSystem(address(userRegistry), address(this), address(feedbackStorage)); // Mock ProjectManager
        arbitratorRegistry = new ArbitratorRegistry(address(userRegistry), address(reputationSystem));
        feeManager = new FeeManager(platformTreasury);
        escrow = new Escrow(address(this), address(this), address(feeManager)); // Mocking ProjectManager and ArbitrationCourt for Escrow

        arbitrationCourt = new ArbitrationCourt(
            address(this), // Mock ProjectManager
            address(escrow),
            address(arbitratorRegistry)
        );

        // Set owner of Escrow to deployer (this contract) for testing release/refund functions
        escrow.transferOwnership(deployer);
        // Set ArbitrationCourt as owner of ProjectManager for testing resolveDispute
        projectManager = new ProjectManager(address(userRegistry), makeAddr("jobBoard"), address(escrow), address(arbitrationCourt));
        projectManager.transferOwnership(address(arbitrationCourt));

        // Set contract addresses in dependent contracts
        escrow.setContractAddresses(address(projectManager), address(arbitrationCourt), address(feeManager));
        arbitrationCourt.setContractAddresses(address(projectManager), address(escrow), address(arbitratorRegistry));
        reputationSystem.setContractAddresses(address(userRegistry), address(projectManager), address(feedbackStorage));
        feedbackStorage.setReputationSystemAddress(address(reputationSystem));

        vm.stopPrank();

        // Register users
        vm.startPrank(client1);
        userRegistry.registerUser(UserRegistry.UserRole.Client);
        vm.stopPrank();

        vm.startPrank(freelancer1);
        userRegistry.registerUser(UserRegistry.UserRole.Freelancer);
        vm.stopPrank();

        vm.startPrank(arbitrator1);
        userRegistry.registerUser(UserRegistry.UserRole.Arbitrator);
        reputationSystem.submitFeedback(1, arbitrator1, 5, "ipfs://feedback"); // Give some reputation
        arbitratorRegistry.registerArbitrator("ipfs://arbitrator1");
        vm.stopPrank();

        vm.startPrank(arbitrator2);
        userRegistry.registerUser(UserRegistry.UserRole.Arbitrator);
        reputationSystem.submitFeedback(2, arbitrator2, 5, "ipfs://feedback");
        arbitratorRegistry.registerArbitrator("ipfs://arbitrator2");
        vm.stopPrank();

        vm.startPrank(arbitrator3);
        userRegistry.registerUser(UserRegistry.UserRole.Arbitrator);
        reputationSystem.submitFeedback(3, arbitrator3, 5, "ipfs://feedback");
        arbitratorRegistry.registerArbitrator("ipfs://arbitrator3");
        vm.stopPrank();
    }

    // Mock functions for IProjectManagerMock
    function getProjectDetails(uint256 _projectId) external view returns (
        uint256 jobId,
        address client,
        address freelancer,
        uint256 agreedBudget,
        uint256 agreedDeadline,
        IProjectManagerMock.ProjectStatus status,
        uint256 startTime,
        uint256 totalMilestones,
        uint256 completedMilestones,
        uint256 approvedMilestones
    ) {
        if (_projectId == 1) {
            return (1, client1, freelancer1, 10 ether, block.timestamp + 10 days, IProjectManagerMock.ProjectStatus.Disputed, block.timestamp, 2, 1, 0);
        }
        revert("Project does not exist");
    }

    function getMilestoneDetails(uint256 _projectId, uint256 _milestoneIndex) external view returns (
        string memory description,
        uint256 amount,
        bool completed,
        bool approved,
        uint256 completedTime,
        uint256 approvedTime
    ) {
        if (_projectId == 1 && _milestoneIndex == 0) {
            return ("Milestone 1", 5 ether, true, false, block.timestamp - 1 days, 0);
        }
        revert("Milestone does not exist");
    }

    function resolveDispute(uint256 _projectId, IProjectManagerMock.ProjectStatus _newStatus) external {
        // This function is called by ArbitrationCourt, so we just log it for testing
        emit log_named_uint("ProjectManager.resolveDispute called for projectId", _projectId);
        emit log_named_uint("New status", uint8(_newStatus));
    }

    function testStartDispute() public {
        uint256 projectId = 1;
        uint256 milestoneIndex = 0;
        string memory reasonHash = "ipfs://disputeReason";

        vm.startPrank(deployer); // ProjectManager calls this as owner
        arbitrationCourt.startDispute(projectId, milestoneIndex, reasonHash);
        vm.stopPrank();

        ArbitrationCourt.Dispute memory dispute = arbitrationCourt.disputes(1);
        assertEq(dispute.projectId, projectId);
        assertEq(dispute.milestoneIndex, milestoneIndex);
        assertEq(dispute.client, client1);
        assertEq(dispute.freelancer, freelancer1);
        assertEq(dispute.arbitrators.length, 3);
        assertEq(uint8(dispute.status), uint8(ArbitrationCourt.DisputeStatus.EvidenceCollection));
        assertTrue(dispute.startTime > 0);
        assertTrue(dispute.evidenceDeadline > dispute.startTime);
    }

    function testSubmitEvidence() public {
        testStartDispute();

        uint256 disputeId = 1;
        string memory evidenceHash = "ipfs://clientEvidence";

        vm.startPrank(client1);
        arbitrationCourt.submitEvidence(disputeId, evidenceHash);
        vm.stopPrank();

        assertEq(arbitrationCourt.getEvidenceHash(disputeId, client1), evidenceHash);
    }

    function testStartVoting() public {
        testSubmitEvidence();

        uint256 disputeId = 1;

        // Fast forward time to pass evidence collection period
        vm.warp(block.timestamp + 3 days + 1);

        vm.startPrank(deployer); // Only owner can start voting
        arbitrationCourt.startVoting(disputeId);
        vm.stopPrank();

        ArbitrationCourt.Dispute memory dispute = arbitrationCourt.disputes(disputeId);
        assertEq(uint8(dispute.status), uint8(ArbitrationCourt.DisputeStatus.Voting));
        assertTrue(dispute.votingDeadline > block.timestamp);
    }

    function testVoteOnDispute() public {
        testStartVoting();

        uint256 disputeId = 1;

        vm.startPrank(arbitrator1);
        arbitrationCourt.voteOnDispute(disputeId, true); // Arbitrator 1 votes for client
        vm.stopPrank();

        vm.startPrank(arbitrator2);
        arbitrationCourt.voteOnDispute(disputeId, false); // Arbitrator 2 votes for freelancer
        vm.stopPrank();

        vm.startPrank(arbitrator3);
        arbitrationCourt.voteOnDispute(disputeId, true); // Arbitrator 3 votes for client
        vm.stopPrank();

        ArbitrationCourt.Dispute memory dispute = arbitrationCourt.disputes(disputeId);
        assertEq(dispute.clientVotes, 2);
        assertEq(dispute.freelancerVotes, 1);
        assertEq(uint8(dispute.status), uint8(ArbitrationCourt.DisputeStatus.Finalized)); // Should finalize automatically
    }

    function testFinalizeDisputeClientWins() public {
        testVoteOnDispute(); // Client wins 2-1

        uint256 disputeId = 1;
        uint256 initialClientBalance = client1.balance;
        uint256 initialEscrowBalance = escrow.getEscrowBalance(1, address(0));

        // Simulate funds in escrow
        vm.deal(address(escrow), 5 ether);

        // Finalize dispute (can be called by anyone after voting ends)
        vm.startPrank(makeAddr("anyone"));
        arbitrationCourt.finalizeDispute(disputeId);
        vm.stopPrank();

        ArbitrationCourt.Dispute memory dispute = arbitrationCourt.disputes(disputeId);
        assertEq(uint8(dispute.status), uint8(ArbitrationCourt.DisputeStatus.Finalized));
        assertEq(client1.balance, initialClientBalance + 5 ether); // Client gets refund
        assertEq(escrow.getEscrowBalance(1, address(0)), initialEscrowBalance - 5 ether);
    }

    function testFinalizeDisputeFreelancerWins() public {
        testStartVoting();

        uint256 disputeId = 1;

        vm.startPrank(arbitrator1);
        arbitrationCourt.voteOnDispute(disputeId, false); // Arbitrator 1 votes for freelancer
        vm.stopPrank();

        vm.startPrank(arbitrator2);
        arbitrationCourt.voteOnDispute(disputeId, true); // Arbitrator 2 votes for client
        vm.stopPrank();

        vm.startPrank(arbitrator3);
        arbitrationCourt.voteOnDispute(disputeId, false); // Arbitrator 3 votes for freelancer
        vm.stopPrank();

        // Freelancer wins 2-1
        uint256 initialFreelancerBalance = freelancer1.balance;
        uint256 initialEscrowBalance = escrow.getEscrowBalance(1, address(0));

        // Simulate funds in escrow
        vm.deal(address(escrow), 5 ether);

        vm.startPrank(makeAddr("anyone"));
        arbitrationCourt.finalizeDispute(disputeId);
        vm.stopPrank();

        ArbitrationCourt.Dispute memory dispute = arbitrationCourt.disputes(disputeId);
        assertEq(uint8(dispute.status), uint8(ArbitrationCourt.DisputeStatus.Finalized));
        assertEq(freelancer1.balance, initialFreelancerBalance + 5 ether); // Freelancer gets funds
        assertEq(escrow.getEscrowBalance(1, address(0)), initialEscrowBalance - 5 ether);
    }

    function testGetDisputeDetails() public {
        testStartDispute();

        (uint256 projectId, uint256 milestoneIndex, address client, address freelancer, address[] memory arbitrators, uint256 clientVotes, uint256 freelancerVotes, ArbitrationCourt.DisputeStatus status, uint256 startTime, uint256 evidenceDeadline, uint256 votingDeadline, uint256 totalArbitrators) = arbitrationCourt.getDisputeDetails(1);
        assertEq(projectId, 1);
        assertEq(milestoneIndex, 0);
        assertEq(client, client1);
        assertEq(freelancer, freelancer1);
        assertEq(arbitrators.length, 3);
        assertEq(clientVotes, 0);
        assertEq(freelancerVotes, 0);
        assertEq(uint8(status), uint8(ArbitrationCourt.DisputeStatus.EvidenceCollection));
        assertTrue(startTime > 0);
        assertTrue(evidenceDeadline > 0);
        assertEq(votingDeadline, 0);
        assertEq(totalArbitrators, 3);
    }

    function testSetDisputeParameters() public {
        uint256 newEvidencePeriod = 5 days;
        uint256 newVotingPeriod = 5 days;
        uint256 newRequiredArbitrators = 5;

        vm.startPrank(deployer);
        arbitrationCourt.setDisputeParameters(newEvidencePeriod, newVotingPeriod, newRequiredArbitrators);
        vm.stopPrank();

        assertEq(arbitrationCourt.evidencePeriod(), newEvidencePeriod);
        assertEq(arbitrationCourt.votingPeriod(), newVotingPeriod);
        assertEq(arbitrationCourt.requiredArbitrators(), newRequiredArbitrators);
    }

    function testSetContractAddresses() public {
        address newProjectManager = makeAddr("newProjectManager");
        address newEscrow = makeAddr("newEscrow");
        address newArbitratorRegistry = makeAddr("newArbitratorRegistry");

        vm.startPrank(deployer);
        arbitrationCourt.setContractAddresses(newProjectManager, newEscrow, newArbitratorRegistry);
        vm.stopPrank();

        assertEq(address(arbitrationCourt.projectManager()), newProjectManager);
        assertEq(address(arbitrationCourt.escrow()), newEscrow);
        assertEq(address(arbitrationCourt.arbitratorRegistry()), newArbitratorRegistry);
    }
}


