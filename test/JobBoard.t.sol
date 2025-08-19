// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../src/JobBoard.sol";
import "../src/UserRegistry.sol";

contract JobBoardTest is Test {
    JobBoard jobBoard;
    UserRegistry userRegistry;

    address public deployer;
    address public client1;
    address public freelancer1;

    function setUp() public {
        deployer = makeAddr("deployer");
        client1 = makeAddr("client1");
        freelancer1 = makeAddr("freelancer1");

        vm.startPrank(deployer);
        userRegistry = new UserRegistry();
        jobBoard = new JobBoard(address(userRegistry));
        vm.stopPrank();

        // Register client1 as a client
        vm.startPrank(client1);
        userRegistry.registerUser(UserRegistry.UserRole.Client);
        vm.stopPrank();

        // Register freelancer1 as a freelancer
        vm.startPrank(freelancer1);
        userRegistry.registerUser(UserRegistry.UserRole.Freelancer);
        vm.stopPrank();
    }

    function testPostJob() public {
        string memory title = 


"Web Design Project";
        string memory descriptionHash = "ipfs://QmJobDesc1";
        uint256 budget = 1 ether;
        uint256 deadline = block.timestamp + 7 days;
        string[] memory skills = new string[](2);
        skills[0] = "HTML";
        skills[1] = "CSS";

        vm.startPrank(client1);
        jobBoard.postJob(title, descriptionHash, budget, deadline, skills);
        vm.stopPrank();

        JobBoard.Job memory job = jobBoard.jobs(1);
        assertEq(job.client, client1);
        assertEq(job.jobTitle, title);
        assertEq(job.jobDescriptionHash, descriptionHash);
        assertEq(job.budget, budget);
        assertEq(job.deadline, deadline);
        assertEq(job.status, JobBoard.JobStatus.Open);
        assertEq(jobBoard.totalJobs(), 1);
        assertEq(jobBoard.activeJobs(), 1);

        uint256[] memory clientJobs = jobBoard.getJobsByClient(client1);
        assertEq(clientJobs.length, 1);
        assertEq(clientJobs[0], 1);

        uint256[] memory activeJobs = jobBoard.getAllActiveJobs();
        assertEq(activeJobs.length, 1);
        assertEq(activeJobs[0], 1);
    }

    function testRevertPostJobNotClient() public {
        string memory title = "Web Design Project";
        string memory descriptionHash = "ipfs://QmJobDesc1";
        uint256 budget = 1 ether;
        uint256 deadline = block.timestamp + 7 days;
        string[] memory skills = new string[](2);
        skills[0] = "HTML";
        skills[1] = "CSS";

        vm.startPrank(freelancer1);
        vm.expectRevert("Only clients can perform this action");
        jobBoard.postJob(title, descriptionHash, budget, deadline, skills);
        vm.stopPrank();
    }

    function testRevertPostJobInvalidBudget() public {
        string memory title = "Web Design Project";
        string memory descriptionHash = "ipfs://QmJobDesc1";
        uint256 budget = 0;
        uint256 deadline = block.timestamp + 7 days;
        string[] memory skills = new string[](2);
        skills[0] = "HTML";
        skills[1] = "CSS";

        vm.startPrank(client1);
        vm.expectRevert("Budget must be greater than zero");
        jobBoard.postJob(title, descriptionHash, budget, deadline, skills);
        vm.stopPrank();
    }

    function testRevertPostJobInvalidDeadline() public {
        string memory title = "Web Design Project";
        string memory descriptionHash = "ipfs://QmJobDesc1";
        uint256 budget = 1 ether;
        uint256 deadline = block.timestamp - 1 days;
        string[] memory skills = new string[](2);
        skills[0] = "HTML";
        skills[1] = "CSS";

        vm.startPrank(client1);
        vm.expectRevert("Deadline must be in the future");
        jobBoard.postJob(title, descriptionHash, budget, deadline, skills);
        vm.stopPrank();
    }

    function testUpdateJob() public {
        testPostJob(); // Post a job first

        string memory newTitle = "Updated Web Design Project";
        string memory newDescriptionHash = "ipfs://QmNewJobDesc";
        uint256 newBudget = 2 ether;
        uint256 newDeadline = block.timestamp + 14 days;
        string[] memory newSkills = new string[](1);
        newSkills[0] = "React";

        vm.startPrank(client1);
        jobBoard.updateJob(1, newTitle, newDescriptionHash, newBudget, newDeadline, newSkills);
        vm.stopPrank();

        JobBoard.Job memory job = jobBoard.jobs(1);
        assertEq(job.jobTitle, newTitle);
        assertEq(job.jobDescriptionHash, newDescriptionHash);
        assertEq(job.budget, newBudget);
        assertEq(job.deadline, newDeadline);
        assertEq(job.requiredSkills[0], newSkills[0]);
    }

    function testRevertUpdateJobNotOwner() public {
        testPostJob();

        string memory newTitle = "Updated Web Design Project";
        string memory newDescriptionHash = "ipfs://QmNewJobDesc";
        uint256 newBudget = 2 ether;
        uint256 newDeadline = block.timestamp + 14 days;
        string[] memory newSkills = new string[](1);
        newSkills[0] = "React";

        vm.startPrank(freelancer1);
        vm.expectRevert("Not the job owner");
        jobBoard.updateJob(1, newTitle, newDescriptionHash, newBudget, newDeadline, newSkills);
        vm.stopPrank();
    }

    function testCancelJob() public {
        testPostJob();

        vm.startPrank(client1);
        jobBoard.cancelJob(1);
        vm.stopPrank();

        JobBoard.Job memory job = jobBoard.jobs(1);
        assertEq(job.status, JobBoard.JobStatus.Cancelled);
        assertEq(jobBoard.activeJobs(), 0);

        uint256[] memory activeJobs = jobBoard.getAllActiveJobs();
        assertEq(activeJobs.length, 0);
    }

    function testRevertCancelJobNotOpen() public {
        testPostJob();

        // Simulate job being in progress (e.g., by ProjectManager)
        vm.startPrank(deployer);
        jobBoard.changeJobStatus(1, JobBoard.JobStatus.InProgress);
        vm.stopPrank();

        vm.startPrank(client1);
        vm.expectRevert("Job is not open");
        jobBoard.cancelJob(1);
        vm.stopPrank();
    }

    function testChangeJobStatus() public {
        testPostJob();

        vm.startPrank(deployer);
        jobBoard.changeJobStatus(1, JobBoard.JobStatus.InProgress);
        vm.stopPrank();

        JobBoard.Job memory job = jobBoard.jobs(1);
        assertEq(job.status, JobBoard.JobStatus.InProgress);
        assertEq(jobBoard.activeJobs(), 0);

        vm.startPrank(deployer);
        jobBoard.changeJobStatus(1, JobBoard.JobStatus.Completed);
        vm.stopPrank();

        job = jobBoard.jobs(1);
        assertEq(job.status, JobBoard.JobStatus.Completed);
    }

    function testRevertChangeJobStatusNotOwner() public {
        testPostJob();

        vm.startPrank(client1);
        vm.expectRevert("Ownable: caller is not the owner");
        jobBoard.changeJobStatus(1, JobBoard.JobStatus.InProgress);
        vm.stopPrank();
    }

    function testGetJobDetails() public {
        testPostJob();

        (address client, string memory title, string memory descHash, uint256 budget, uint256 deadline, string[] memory skills, JobBoard.JobStatus status, uint256 creationTime, uint256 lastUpdated) = jobBoard.getJobDetails(1);
        assertEq(client, client1);
        assertEq(title, "Web Design Project");
        assertEq(descHash, "ipfs://QmJobDesc1");
        assertEq(budget, 1 ether);
        assertTrue(deadline > 0);
        assertEq(skills.length, 2);
        assertEq(skills[0], "HTML");
        assertEq(skills[1], "CSS");
        assertEq(uint8(status), uint8(JobBoard.JobStatus.Open));
        assertTrue(creationTime > 0);
        assertTrue(lastUpdated > 0);
    }

    function testSetUserRegistryAddress() public {
        address newUserRegistry = makeAddr("newUserRegistry");
        vm.startPrank(deployer);
        jobBoard.setUserRegistryAddress(newUserRegistry);
        vm.stopPrank();

        assertEq(address(jobBoard.userRegistry()), newUserRegistry);
    }
}


