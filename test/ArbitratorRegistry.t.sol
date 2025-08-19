// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../src/ArbitratorRegistry.sol";
import "../src/UserRegistry.sol";
import "../src/ReputationSystem.sol";
import "../src/FeedbackStorage.sol";

interface IReputationSystemMock {
    function getReputation(address _userAddress) external view returns (uint256);
}

contract ArbitratorRegistryTest is Test {
    ArbitratorRegistry arbitratorRegistry;
    UserRegistry userRegistry;
    ReputationSystem reputationSystem;
    FeedbackStorage feedbackStorage;

    address public deployer;
    address public arbitrator1;
    address public arbitrator2;
    address public client1;

    function setUp() public {
        deployer = makeAddr("deployer");
        arbitrator1 = makeAddr("arbitrator1");
        arbitrator2 = makeAddr("arbitrator2");
        client1 = makeAddr("client1");

        vm.startPrank(deployer);
        userRegistry = new UserRegistry();
        feedbackStorage = new FeedbackStorage(address(this)); // Mock ReputationSystem
        reputationSystem = new ReputationSystem(address(userRegistry), makeAddr("projectManager"), address(feedbackStorage));
        arbitratorRegistry = new ArbitratorRegistry(address(userRegistry), address(reputationSystem));

        // Set ReputationSystem address in FeedbackStorage
        feedbackStorage.setReputationSystemAddress(address(reputationSystem));

        vm.stopPrank();

        // Register users
        vm.startPrank(arbitrator1);
        userRegistry.registerUser(UserRegistry.UserRole.Arbitrator);
        vm.stopPrank();

        vm.startPrank(arbitrator2);
        userRegistry.registerUser(UserRegistry.UserRole.Arbitrator);
        vm.stopPrank();

        vm.startPrank(client1);
        userRegistry.registerUser(UserRegistry.UserRole.Client);
        vm.stopPrank();

        // Give reputation to arbitrators for testing
        vm.startPrank(makeAddr("random")); // Simulate feedback from a random address
        reputationSystem.submitFeedback(1, arbitrator1, 5, "ipfs://feedback1");
        reputationSystem.submitFeedback(2, arbitrator2, 5, "ipfs://feedback2");
        vm.stopPrank();
    }

    function testRegisterArbitrator() public {
        string memory profileHash = "ipfs://QmArbitrator1";

        vm.startPrank(arbitrator1);
        arbitratorRegistry.registerArbitrator(profileHash);
        vm.stopPrank();

        ArbitratorRegistry.ArbitratorProfile memory profile = arbitratorRegistry.arbitrators(arbitrator1);
        assertEq(profile.profileHash, profileHash);
        assertEq(uint8(profile.status), uint8(ArbitratorRegistry.ArbitratorStatus.Active));
        assertTrue(arbitratorRegistry.isArbitratorActive(arbitrator1));
        assertEq(arbitratorRegistry.activeArbitratorAddresses(0), arbitrator1);
    }

    function testRevertRegisterArbitratorNotArbitratorRole() public {
        string memory profileHash = "ipfs://QmClientProfile";

        vm.startPrank(client1);
        vm.expectRevert("User is not an Arbitrator role");
        arbitratorRegistry.registerArbitrator(profileHash);
        vm.stopPrank();
    }

    function testRevertRegisterArbitratorInsufficientReputation() public {
        address lowRepArbitrator = makeAddr("lowRepArbitrator");
        vm.startPrank(lowRepArbitrator);
        userRegistry.registerUser(UserRegistry.UserRole.Arbitrator);
        vm.stopPrank();

        string memory profileHash = "ipfs://QmLowRep";
        vm.startPrank(lowRepArbitrator);
        vm.expectRevert("Insufficient reputation to register");
        arbitratorRegistry.registerArbitrator(profileHash);
        vm.stopPrank();
    }

    function testDeregisterArbitrator() public {
        testRegisterArbitrator(); // Register arbitrator1 first

        vm.startPrank(arbitrator1);
        arbitratorRegistry.deregisterArbitrator();
        vm.stopPrank();

        ArbitratorRegistry.ArbitratorProfile memory profile = arbitratorRegistry.arbitrators(arbitrator1);
        assertEq(uint8(profile.status), uint8(ArbitratorRegistry.ArbitratorStatus.Inactive));
        assertFalse(arbitratorRegistry.isArbitratorActive(arbitrator1));
        assertEq(arbitratorRegistry.activeArbitratorAddresses.length, 0);
    }

    function testRevertDeregisterArbitratorNotActive() public {
        vm.startPrank(arbitrator1);
        vm.expectRevert("Not an active arbitrator");
        arbitratorRegistry.deregisterArbitrator();
        vm.stopPrank();
    }

    function testSelectArbitrators() public {
        testRegisterArbitrator(); // Register arbitrator1

        string memory profileHash2 = "ipfs://QmArbitrator2";
        vm.startPrank(arbitrator2);
        arbitratorRegistry.registerArbitrator(profileHash2);
        vm.stopPrank();

        vm.startPrank(deployer); // Only owner (ArbitrationCourt) can call
        address[] memory selected = arbitratorRegistry.selectArbitrators(2);
        vm.stopPrank();

        assertEq(selected.length, 2);
        assertTrue(selected[0] == arbitrator1 || selected[0] == arbitrator2);
        assertTrue(selected[1] == arbitrator1 || selected[1] == arbitrator2);
        assertNotEq(selected[0], selected[1]);
    }

    function testRevertSelectArbitratorsNotEnough() public {
        testRegisterArbitrator(); // Only one arbitrator registered

        vm.startPrank(deployer);
        vm.expectRevert("Not enough active arbitrators available");
        arbitratorRegistry.selectArbitrators(2);
        vm.stopPrank();
    }

    function testIsArbitrator() public {
        testRegisterArbitrator();

        assertTrue(arbitratorRegistry.isArbitrator(arbitrator1));
        assertFalse(arbitratorRegistry.isArbitrator(client1));
    }

    function testGetArbitratorProfile() public {
        testRegisterArbitrator();

        (string memory pHash, ArbitratorRegistry.ArbitratorStatus status, uint256 regTime) = arbitratorRegistry.getArbitratorProfile(arbitrator1);
        assertEq(pHash, "ipfs://QmArbitrator1");
        assertEq(uint8(status), uint8(ArbitratorRegistry.ArbitratorStatus.Active));
        assertTrue(regTime > 0);
    }

    function testSetMinReputationToRegister() public {
        uint256 newMinRep = 200;
        vm.startPrank(deployer);
        arbitratorRegistry.setMinReputationToRegister(newMinRep);
        vm.stopPrank();

        assertEq(arbitratorRegistry.minReputationToRegister(), newMinRep);
    }

    function testSetMinStakeAmount() public {
        uint256 newMinStake = 1 ether;
        vm.startPrank(deployer);
        arbitratorRegistry.setMinStakeAmount(newMinStake);
        vm.stopPrank();

        assertEq(arbitratorRegistry.minStakeAmount(), newMinStake);
    }

    function testSetContractAddresses() public {
        address newUserRegistry = makeAddr("newUserRegistry");
        address newReputationSystem = makeAddr("newReputationSystem");

        vm.startPrank(deployer);
        arbitratorRegistry.setContractAddresses(newUserRegistry, newReputationSystem);
        vm.stopPrank();

        assertEq(address(arbitratorRegistry.userRegistry()), newUserRegistry);
        assertEq(address(arbitratorRegistry.reputationSystem()), newReputationSystem);
    }
}


