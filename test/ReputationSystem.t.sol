// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../src/ReputationSystem.sol";
import "../src/UserRegistry.sol";
import "../src/ProjectManager.sol";
import "../src/FeedbackStorage.sol";

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
}

contract ReputationSystemTest is Test {
    ReputationSystem reputationSystem;
    UserRegistry userRegistry;
    FeedbackStorage feedbackStorage;
    IProjectManagerMock projectManagerMock;

    address public deployer;
    address public client1;
    address public freelancer1;
    address public client2;
    address public freelancer2;

    function setUp() public {
        deployer = makeAddr("deployer");
        client1 = makeAddr("client1");
        freelancer1 = makeAddr("freelancer1");
        client2 = makeAddr("client2");
        freelancer2 = makeAddr("freelancer2");

        vm.startPrank(deployer);
        userRegistry = new UserRegistry();
        feedbackStorage = new FeedbackStorage(address(this)); // Mock ReputationSystem
        reputationSystem = new ReputationSystem(
            address(userRegistry),
            address(this), // Mock ProjectManager
            address(feedbackStorage)
        );

        // Set ReputationSystem address in FeedbackStorage
        feedbackStorage.setReputationSystemAddress(address(reputationSystem));

        vm.stopPrank();

        // Register users
        vm.startPrank(client1);
        userRegistry.registerUser(UserRegistry.UserRole.Client);
        vm.stopPrank();

        vm.startPrank(freelancer1);
        userRegistry.registerUser(UserRegistry.UserRole.Freelancer);
        vm.stopPrank();

        vm.startPrank(client2);
        userRegistry.registerUser(UserRegistry.UserRole.Client);
        vm.stopPrank();

        vm.startPrank(freelancer2);
        userRegistry.registerUser(UserRegistry.UserRole.Freelancer);
        vm.stopPrank();
    }

    // Mock function for IProjectManagerMock
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
            return (1, client1, freelancer1, 10 ether, block.timestamp + 10 days, IProjectManagerMock.ProjectStatus.Completed, block.timestamp, 2, 2, 2);
        } else if (_projectId == 2) {
            return (2, freelancer1, client1, 5 ether, block.timestamp + 5 days, IProjectManagerMock.ProjectStatus.Completed, block.timestamp, 1, 1, 1);
        }
        revert("Project does not exist");
    }

    function testSubmitFeedback() public {
        uint256 projectId = 1;
        uint8 rating = 5;
        string memory feedbackHash = "ipfs://feedback1";

        vm.startPrank(client1);
        reputationSystem.submitFeedback(projectId, freelancer1, rating, feedbackHash);
        vm.stopPrank();

        ReputationSystem.UserReputation memory rep = reputationSystem.reputations(freelancer1);
        assertEq(rep.score, 5);
        assertEq(rep.totalRatingSum, 5);
        assertEq(rep.numberOfRatings, 1);

        assertEq(reputationSystem.getReputation(freelancer1), 5);
        assertEq(reputationSystem.getAverageRating(freelancer1), 5);
        assertEq(reputationSystem.getNumberOfRatings(freelancer1), 1);

        assertEq(feedbackStorage.getFeedbackHash(projectId, client1, freelancer1), feedbackHash);
    }

    function testSubmitMultipleFeedback() public {
        testSubmitFeedback(); // Freelancer1 gets 5 from Client1

        uint256 projectId2 = 2;
        uint8 rating2 = 4;
        string memory feedbackHash2 = "ipfs://feedback2";

        // Client1 gives feedback to Freelancer2 (mock project 2)
        vm.startPrank(client1);
        reputationSystem.submitFeedback(projectId2, freelancer2, rating2, feedbackHash2);
        vm.stopPrank();

        ReputationSystem.UserReputation memory rep1 = reputationSystem.reputations(freelancer1);
        assertEq(rep1.score, 5);

        ReputationSystem.UserReputation memory rep2 = reputationSystem.reputations(freelancer2);
        assertEq(rep2.score, 4);
        assertEq(rep2.totalRatingSum, 4);
        assertEq(rep2.numberOfRatings, 1);

        // Freelancer1 gives feedback to Client1 (mock project 2)
        vm.startPrank(freelancer1);
        reputationSystem.submitFeedback(projectId2, client1, 3, "ipfs://feedback3");
        vm.stopPrank();

        ReputationSystem.UserReputation memory repClient1 = reputationSystem.reputations(client1);
        assertEq(repClient1.score, 3);
        assertEq(repClient1.totalRatingSum, 3);
        assertEq(repClient1.numberOfRatings, 1);
    }

    function testRevertSubmitFeedbackNotRegistered() public {
        uint256 projectId = 1;
        uint8 rating = 5;
        string memory feedbackHash = "ipfs://feedback1";

        vm.startPrank(makeAddr("unregistered"));
        vm.expectRevert("Sender not a registered active user");
        reputationSystem.submitFeedback(projectId, freelancer1, rating, feedbackHash);
        vm.stopPrank();
    }

    function testRevertSubmitFeedbackSelf() public {
        uint256 projectId = 1;
        uint8 rating = 5;
        string memory feedbackHash = "ipfs://feedback1";

        vm.startPrank(client1);
        vm.expectRevert("Cannot give feedback to yourself");
        reputationSystem.submitFeedback(projectId, client1, rating, feedbackHash);
        vm.stopPrank();
    }

    function testRevertSubmitFeedbackProjectNotCompleted() public {
        // Mock project 3 as active
        vm.mockCall(address(this), abi.encodeWithSelector(IProjectManagerMock.getProjectDetails.selector, 3),
            abi.encode(3, client1, freelancer1, 10 ether, block.timestamp + 10 days, IProjectManagerMock.ProjectStatus.Active, block.timestamp, 2, 0, 0));

        uint256 projectId = 3;
        uint8 rating = 5;
        string memory feedbackHash = "ipfs://feedback1";

        vm.startPrank(client1);
        vm.expectRevert("Project not completed");
        reputationSystem.submitFeedback(projectId, freelancer1, rating, feedbackHash);
        vm.stopPrank();
    }

    function testRevertSubmitFeedbackInvalidRating() public {
        uint256 projectId = 1;
        string memory feedbackHash = "ipfs://feedback1";

        vm.startPrank(client1);
        vm.expectRevert("Rating must be between 1 and 5");
        reputationSystem.submitFeedback(projectId, freelancer1, 0, feedbackHash);
        vm.stopPrank();

        vm.startPrank(client1);
        vm.expectRevert("Rating must be between 1 and 5");
        reputationSystem.submitFeedback(projectId, freelancer1, 6, feedbackHash);
        vm.stopPrank();
    }

    function testRevertSubmitFeedbackEmptyHash() public {
        uint256 projectId = 1;
        uint8 rating = 5;

        vm.startPrank(client1);
        vm.expectRevert("Feedback hash cannot be empty");
        reputationSystem.submitFeedback(projectId, freelancer1, rating, "");
        vm.stopPrank();
    }

    function testSetContractAddresses() public {
        address newUserRegistry = makeAddr("newUserRegistry");
        address newProjectManager = makeAddr("newProjectManager");
        address newFeedbackStorage = makeAddr("newFeedbackStorage");

        vm.startPrank(deployer);
        reputationSystem.setContractAddresses(newUserRegistry, newProjectManager, newFeedbackStorage);
        vm.stopPrank();

        assertEq(address(reputationSystem.userRegistry()), newUserRegistry);
        assertEq(address(reputationSystem.projectManager()), newProjectManager);
        assertEq(address(reputationSystem.feedbackStorage()), newFeedbackStorage);
    }
}


