// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../src/ProjectManager.sol";
import "../src/UserRegistry.sol";
import "../src/JobBoard.sol";
import "../src/Escrow.sol";
import "../src/ArbitrationCourt.sol";
import "../src/FeeManager.sol";

contract ProjectManagerTest is Test {
    ProjectManager projectManager;
    UserRegistry userRegistry;
    JobBoard jobBoard;
    Escrow escrow;
    ArbitrationCourt arbitrationCourt;
    FeeManager feeManager;

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
        arbitrationCourt = new ArbitrationCourt(address(this), address(escrow), address(this)); // Mocking ProjectManager and ArbitratorRegistry for ArbitrationCourt

        projectManager = new ProjectManager(
            address(userRegistry),
            address(jobBoard),
            address(escrow),
            address(arbitrationCourt)
        );

        // Set owner of Escrow and ArbitrationCourt to deployer (this contract) for testing purposes
        escrow.transferOwnership(address(this));
        arbitrationCourt.transferOwnership(address(this));

        // Set ProjectManager and ArbitrationCourt addresses in Escrow and ArbitrationCourt
        escrow.setContractAddresses(address(projectManager), address(arbitrationCourt), address(feeManager));
        arbitrationCourt.setContractAddresses(address(projectManager), address(escrow), address(this)); // Mock ArbitratorRegistry

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

    function testStartProject() public {
        // Post a job first
        vm.startPrank(client1);
        string[] memory skills = new string[](1);
        skills[0] = "Solidity";
        jobBoard.postJob("Smart Contract Dev", "ipfs://jobdesc", 10 ether, block.timestamp + 30 days, skills);
        vm.stopPrank();

        uint256 jobId = 1;
        address client = client1;
        address freelancer = freelancer1;
        uint256 agreedBudget = 10 ether;
        uint256 agreedDeadline = block.timestamp + 20 days;
        string[] memory milestoneDescriptions = new string[](2);
        milestoneDescriptions[0] = "Milestone 1";
        milestoneDescriptions[1] = "Milestone 2";
        uint256[] memory milestoneAmounts = new uint256[](2);
        milestoneAmounts[0] = 5 ether;
        milestoneAmounts[1] = 5 ether;

        vm.startPrank(deployer); // Only owner (this contract) can call startProject
        projectManager.startProject(
            jobId,
            client,
            freelancer,
            agreedBudget,
            agreedDeadline,
            milestoneDescriptions,
            milestoneAmounts
        );
        vm.stopPrank();

        ProjectManager.Project memory project = projectManager.projects(1);
        assertEq(project.jobId, jobId);
        assertEq(project.client, client);
        assertEq(project.freelancer, freelancer);
        assertEq(project.agreedBudget, agreedBudget);
        assertEq(project.status, ProjectManager.ProjectStatus.Active);
        assertEq(project.totalMilestones, 2);
        assertEq(project.completedMilestones, 0);
        assertEq(project.approvedMilestones, 0);

        JobBoard.Job memory job = jobBoard.jobs(jobId);
        assertEq(job.status, JobBoard.JobStatus.InProgress);

        ProjectManager.Milestone memory m1 = projectManager.projectMilestones(1, 0);
        assertEq(m1.description, "Milestone 1");
        assertEq(m1.amount, 5 ether);
        assertFalse(m1.completed);

        ProjectManager.Milestone memory m2 = projectManager.projectMilestones(1, 1);
        assertEq(m2.description, "Milestone 2");
        assertEq(m2.amount, 5 ether);
        assertFalse(m2.completed);
    }

    function testMarkMilestoneCompleted() public {
        testStartProject();

        vm.startPrank(freelancer1);
        projectManager.markMilestoneCompleted(1, 0);
        vm.stopPrank();

        ProjectManager.Milestone memory m1 = projectManager.projectMilestones(1, 0);
        assertTrue(m1.completed);
        assertTrue(m1.completedTime > 0);
        assertEq(projectManager.projects(1).completedMilestones, 1);
    }

    function testApproveMilestone() public {
        testMarkMilestoneCompleted();

        // Fund escrow for the project
        vm.deal(client1, 10 ether);
        vm.startPrank(client1);
        escrow.fundProjectETH{value: 10 ether}(1);
        vm.stopPrank();

        uint256 initialFreelancerBalance = freelancer1.balance;

        vm.startPrank(client1);
        projectManager.approveMilestone(1, 0);
        vm.stopPrank();

        ProjectManager.Milestone memory m1 = projectManager.projectMilestones(1, 0);
        assertTrue(m1.approved);
        assertTrue(m1.approvedTime > 0);
        assertEq(projectManager.projects(1).approvedMilestones, 1);

        // Check if funds were released
        assertEq(freelancer1.balance, initialFreelancerBalance + 5 ether);
    }

    function testDisputeMilestone() public {
        testMarkMilestoneCompleted();

        vm.startPrank(client1);
        projectManager.disputeMilestone(1, 0, "ipfs://disputereason");
        vm.stopPrank();

        ProjectManager.Project memory project = projectManager.projects(1);
        assertEq(project.status, ProjectManager.ProjectStatus.Disputed);
    }

    function testResolveDisputeClientWins() public {
        testDisputeMilestone();

        // Simulate ArbitrationCourt resolving dispute in favor of client
        vm.startPrank(deployer); // ArbitrationCourt calls this as owner
        projectManager.resolveDispute(1, ProjectManager.ProjectStatus.Cancelled);
        vm.stopPrank();

        ProjectManager.Project memory project = projectManager.projects(1);
        assertEq(project.status, ProjectManager.ProjectStatus.Cancelled);
        assertEq(jobBoard.jobs(1).status, JobBoard.JobStatus.Cancelled);
    }

    function testResolveDisputeFreelancerWins() public {
        testDisputeMilestone();

        // Simulate ArbitrationCourt resolving dispute in favor of freelancer
        vm.startPrank(deployer); // ArbitrationCourt calls this as owner
        projectManager.resolveDispute(1, ProjectManager.ProjectStatus.Active);
        vm.stopPrank();

        ProjectManager.Project memory project = projectManager.projects(1);
        assertEq(project.status, ProjectManager.ProjectStatus.Active);
        assertEq(jobBoard.jobs(1).status, JobBoard.JobStatus.InProgress);
    }

    function testCompleteProject() public {
        testApproveMilestone(); // Approve first milestone

        // Mark and approve second milestone
        vm.startPrank(freelancer1);
        projectManager.markMilestoneCompleted(1, 1);
        vm.stopPrank();

        vm.startPrank(client1);
        projectManager.approveMilestone(1, 1);
        vm.stopPrank();

        ProjectManager.Project memory project = projectManager.projects(1);
        assertEq(project.status, ProjectManager.ProjectStatus.Completed);
        assertEq(jobBoard.jobs(1).status, JobBoard.JobStatus.Completed);
    }

    function testGetProjectDetails() public {
        testStartProject();

        (uint256 jobId, address client, address freelancer, uint256 agreedBudget, uint256 agreedDeadline, ProjectManager.ProjectStatus status, uint256 startTime, uint256 totalMilestones, uint256 completedMilestones, uint256 approvedMilestones) = projectManager.getProjectDetails(1);
        assertEq(jobId, 1);
        assertEq(client, client1);
        assertEq(freelancer, freelancer1);
        assertEq(agreedBudget, 10 ether);
        assertTrue(agreedDeadline > 0);
        assertEq(uint8(status), uint8(ProjectManager.ProjectStatus.Active));
        assertTrue(startTime > 0);
        assertEq(totalMilestones, 2);
        assertEq(completedMilestones, 0);
        assertEq(approvedMilestones, 0);
    }

    function testGetMilestoneDetails() public {
        testStartProject();

        (string memory description, uint256 amount, bool completed, bool approved, uint256 completedTime, uint256 approvedTime) = projectManager.getMilestoneDetails(1, 0);
        assertEq(description, "Milestone 1");
        assertEq(amount, 5 ether);
        assertFalse(completed);
        assertFalse(approved);
        assertEq(completedTime, 0);
        assertEq(approvedTime, 0);
    }

    function testSetContractAddresses() public {
        address newUserRegistry = makeAddr("newUserRegistry");
        address newJobBoard = makeAddr("newJobBoard");
        address newEscrow = makeAddr("newEscrow");
        address newArbitrationCourt = makeAddr("newArbitrationCourt");

        vm.startPrank(deployer);
        projectManager.setContractAddresses(newUserRegistry, newJobBoard, newEscrow, newArbitrationCourt);
        vm.stopPrank();

        assertEq(address(projectManager.userRegistry()), newUserRegistry);
        assertEq(address(projectManager.jobBoard()), newJobBoard);
        assertEq(address(projectManager.escrow()), newEscrow);
        assertEq(address(projectManager.arbitrationCourt()), newArbitrationCourt);
    }
}


