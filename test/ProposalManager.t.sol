// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../src/ProposalManager.sol";
import "../src/UserRegistry.sol";
import "../src/JobBoard.sol";
import "../src/ProjectManager.sol";
import "../src/Escrow.sol";
import "../src/FeeManager.sol";
import "../src/ArbitrationCourt.sol";
import "../src/ArbitratorRegistry.sol";

contract ProposalManagerTest is Test {
    ProposalManager proposalManager;
    UserRegistry userRegistry;
    JobBoard jobBoard;
    ProjectManager projectManager;
    Escrow escrow;
    FeeManager feeManager;
    ArbitrationCourt arbitrationCourt;
    ArbitratorRegistry arbitratorRegistry;

    address public deployer;
    address public client1;
    address public freelancer1;
    address public arbitrator1;
    address public platformTreasury;

    function setUp() public {
        deployer = makeAddr("deployer");
        client1 = makeAddr("client1");
        freelancer1 = makeAddr("freelancer1");
        arbitrator1 = makeAddr("arbitrator1");
        platformTreasury = makeAddr("platformTreasury");

        vm.startPrank(deployer);
        userRegistry = new UserRegistry();
        jobBoard = new JobBoard(address(userRegistry));
        feeManager = new FeeManager(platformTreasury);
        escrow = new Escrow(address(this), address(this), address(feeManager)); // Mocking ProjectManager and ArbitrationCourt for Escrow
        arbitratorRegistry = new ArbitratorRegistry(address(userRegistry), makeAddr("reputationSystem"));
        arbitrationCourt = new ArbitrationCourt(address(this), address(escrow), address(arbitratorRegistry)); // Mocking ProjectManager for ArbitrationCourt

        projectManager = new ProjectManager(
            address(userRegistry),
            address(jobBoard),
            address(escrow),
            address(arbitrationCourt)
        );

        proposalManager = new ProposalManager(
            address(userRegistry),
            address(jobBoard),
            address(projectManager),
            address(escrow)
        );

        // Set owner of Escrow, ArbitrationCourt, ProjectManager to deployer (this contract) for testing purposes
        escrow.transferOwnership(address(this));
        arbitrationCourt.transferOwnership(address(this));
        projectManager.transferOwnership(address(this));

        // Set contract addresses in dependent contracts
        escrow.setContractAddresses(address(projectManager), address(arbitrationCourt), address(feeManager));
        arbitrationCourt.setContractAddresses(address(projectManager), address(escrow), address(arbitratorRegistry));
        projectManager.setContractAddresses(address(userRegistry), address(jobBoard), address(escrow), address(arbitrationCourt));

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
        vm.stopPrank();
    }

    function testSubmitProposal() public {
        // Post a job first
        vm.startPrank(client1);
        string[] memory skills = new string[](1);
        skills[0] = "Solidity";
        jobBoard.postJob("Smart Contract Dev", "ipfs://jobdesc", 10 ether, block.timestamp + 30 days, skills);
        vm.stopPrank();

        uint256 jobId = 1;
        uint256 proposedBudget = 9 ether;
        uint256 proposedDeadline = block.timestamp + 25 days;
        string memory proposalDetailsHash = "ipfs://proposalDetails";
        string[] memory milestoneDescriptions = new string[](2);
        milestoneDescriptions[0] = "Milestone A";
        milestoneDescriptions[1] = "Milestone B";
        uint256[] memory milestoneAmounts = new uint256[](2);
        milestoneAmounts[0] = 4 ether;
        milestoneAmounts[1] = 5 ether;

        vm.startPrank(freelancer1);
        proposalManager.submitProposal(
            jobId,
            proposedBudget,
            proposedDeadline,
            proposalDetailsHash,
            milestoneDescriptions,
            milestoneAmounts
        );
        vm.stopPrank();

        ProposalManager.Proposal memory proposal = proposalManager.proposals(jobId, freelancer1);
        assertEq(proposal.jobId, jobId);
        assertEq(proposal.freelancer, freelancer1);
        assertEq(proposal.proposedBudget, proposedBudget);
        assertEq(proposal.proposedDeadline, proposedDeadline);
        assertEq(proposal.proposalDetailsHash, proposalDetailsHash);
        assertEq(proposal.proposedMilestones.length, 2);
        assertEq(uint8(proposal.status), uint8(ProposalManager.ProposalStatus.Pending));
        assertEq(proposalManager.totalProposals(), 1);

        address[] memory jobProposals = proposalManager.getProposalsForJob(jobId);
        assertEq(jobProposals.length, 1);
        assertEq(jobProposals[0], freelancer1);
    }

    function testRevertSubmitProposalNotFreelancer() public {
        // Post a job first
        vm.startPrank(client1);
        string[] memory skills = new string[](1);
        skills[0] = "Solidity";
        jobBoard.postJob("Smart Contract Dev", "ipfs://jobdesc", 10 ether, block.timestamp + 30 days, skills);
        vm.stopPrank();

        uint256 jobId = 1;
        uint256 proposedBudget = 9 ether;
        uint256 proposedDeadline = block.timestamp + 25 days;
        string memory proposalDetailsHash = "ipfs://proposalDetails";
        string[] memory milestoneDescriptions = new string[](2);
        milestoneDescriptions[0] = "Milestone A";
        milestoneDescriptions[1] = "Milestone B";
        uint256[] memory milestoneAmounts = new uint256[](2);
        milestoneAmounts[0] = 4 ether;
        milestoneAmounts[1] = 5 ether;

        vm.startPrank(client1);
        vm.expectRevert("Only freelancers can perform this action");
        proposalManager.submitProposal(
            jobId,
            proposedBudget,
            proposedDeadline,
            proposalDetailsHash,
            milestoneDescriptions,
            milestoneAmounts
        );
        vm.stopPrank();
    }

    function testRevertSubmitProposalJobNotOpen() public {
        // Post a job first
        vm.startPrank(client1);
        string[] memory skills = new string[](1);
        skills[0] = "Solidity";
        jobBoard.postJob("Smart Contract Dev", "ipfs://jobdesc", 10 ether, block.timestamp + 30 days, skills);
        vm.stopPrank();

        // Change job status to InProgress
        vm.startPrank(deployer);
        jobBoard.changeJobStatus(1, JobBoard.JobStatus.InProgress);
        vm.stopPrank();

        uint256 jobId = 1;
        uint256 proposedBudget = 9 ether;
        uint256 proposedDeadline = block.timestamp + 25 days;
        string memory proposalDetailsHash = "ipfs://proposalDetails";
        string[] memory milestoneDescriptions = new string[](2);
        milestoneDescriptions[0] = "Milestone A";
        milestoneDescriptions[1] = "Milestone B";
        uint256[] memory milestoneAmounts = new uint256[](2);
        milestoneAmounts[0] = 4 ether;
        milestoneAmounts[1] = 5 ether;

        vm.startPrank(freelancer1);
        vm.expectRevert("Job is not open for proposals");
        proposalManager.submitProposal(
            jobId,
            proposedBudget,
            proposedDeadline,
            proposalDetailsHash,
            milestoneDescriptions,
            milestoneAmounts
        );
        vm.stopPrank();
    }

    function testAcceptProposal() public {
        testSubmitProposal(); // Submit a proposal first

        uint256 jobId = 1;

        vm.startPrank(client1);
        proposalManager.acceptProposal(jobId, freelancer1);
        vm.stopPrank();

        ProposalManager.Proposal memory proposal = proposalManager.proposals(jobId, freelancer1);
        assertEq(uint8(proposal.status), uint8(ProposalManager.ProposalStatus.Accepted));

        // Verify that projectManager.startProject was called (indirectly)
        // This is hard to test directly without mocking ProjectManager more deeply.
        // For now, we assume the call happens and focus on ProposalManager's state change.
    }

    function testRevertAcceptProposalNotClient() public {
        testSubmitProposal();

        uint256 jobId = 1;

        vm.startPrank(freelancer1);
        vm.expectRevert("Only clients can perform this action");
        proposalManager.acceptProposal(jobId, freelancer1);
        vm.stopPrank();
    }

    function testRejectProposal() public {
        testSubmitProposal(); // Submit a proposal first

        uint256 jobId = 1;

        vm.startPrank(client1);
        proposalManager.rejectProposal(jobId, freelancer1);
        vm.stopPrank();

        ProposalManager.Proposal memory proposal = proposalManager.proposals(jobId, freelancer1);
        assertEq(uint8(proposal.status), uint8(ProposalManager.ProposalStatus.Rejected));
    }

    function testGetProposalsForJob() public {
        testSubmitProposal();

        // Submit another proposal for the same job from a different freelancer
        address freelancer2 = makeAddr("freelancer2");
        vm.startPrank(freelancer2);
        userRegistry.registerUser(UserRegistry.UserRole.Freelancer);
        proposalManager.submitProposal(1, 8 ether, block.timestamp + 20 days, "ipfs://proposalDetails2", new string[](1), new uint256[](1));
        vm.stopPrank();

        address[] memory jobProposals = proposalManager.getProposalsForJob(1);
        assertEq(jobProposals.length, 2);
        assertTrue(jobProposals[0] == freelancer1 || jobProposals[1] == freelancer1);
        assertTrue(jobProposals[0] == freelancer2 || jobProposals[1] == freelancer2);
    }

    function testGetProposalDetails() public {
        testSubmitProposal();

        (uint256 jobId, address freelancer, uint256 proposedBudget, uint256 proposedDeadline, string memory proposalDetailsHash, ProposalManager.Milestone[] memory proposedMilestones, ProposalManager.ProposalStatus status, uint256 submissionTime, uint256 lastUpdated) = proposalManager.getProposalDetails(1, freelancer1);
        assertEq(jobId, 1);
        assertEq(freelancer, freelancer1);
        assertEq(proposedBudget, 9 ether);
        assertTrue(proposedDeadline > 0);
        assertEq(proposalDetailsHash, "ipfs://proposalDetails");
        assertEq(proposedMilestones.length, 2);
        assertEq(uint8(status), uint8(ProposalManager.ProposalStatus.Pending));
        assertTrue(submissionTime > 0);
        assertTrue(lastUpdated > 0);
    }

    function testSetContractAddresses() public {
        address newUserRegistry = makeAddr("newUserRegistry");
        address newJobBoard = makeAddr("newJobBoard");
        address newProjectManager = makeAddr("newProjectManager");
        address newEscrow = makeAddr("newEscrow");

        vm.startPrank(deployer);
        proposalManager.setContractAddresses(newUserRegistry, newJobBoard, newProjectManager, newEscrow);
        vm.stopPrank();

        assertEq(address(proposalManager.userRegistry()), newUserRegistry);
        assertEq(address(proposalManager.jobBoard()), newJobBoard);
        assertEq(address(proposalManager.projectManager()), newProjectManager);
        assertEq(address(proposalManager.escrow()), newEscrow);
    }
}


