// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../src/UserRegistry.sol";

contract UserRegistryTest is Test {
    UserRegistry userRegistry;

    address public deployer;
    address public user1;
    address public user2;
    address public user3;

    function setUp() public {
        deployer = makeAddr("deployer");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        user3 = makeAddr("user3");

        vm.startPrank(deployer);
        userRegistry = new UserRegistry();
        vm.stopPrank();
    }

    function testRegisterUserFreelancer() public {
        vm.startPrank(user1);
        userRegistry.registerUser(UserRegistry.UserRole.Freelancer);
        vm.stopPrank();

        UserRegistry.UserProfile memory profile = userRegistry.users(user1);
        assertEq(uint8(profile.role), uint8(UserRegistry.UserRole.Freelancer));
        assertTrue(userRegistry.isRegistered(user1));
        assertTrue(profile.isActive);
        assertEq(userRegistry.totalUsers(), 1);

        assertEq(uint8(userRegistry.getUserRole(user1)), uint8(UserRegistry.UserRole.Freelancer));
        assertTrue(userRegistry.isActiveUser(user1));
    }

    function testRegisterUserClient() public {
        vm.startPrank(user2);
        userRegistry.registerUser(UserRegistry.UserRole.Client);
        vm.stopPrank();

        UserRegistry.UserProfile memory profile = userRegistry.users(user2);
        assertEq(uint8(profile.role), uint8(UserRegistry.UserRole.Client));
        assertTrue(userRegistry.isRegistered(user2));
        assertTrue(profile.isActive);
        assertEq(userRegistry.totalUsers(), 1);
    }

    function testRegisterUserArbitrator() public {
        vm.startPrank(user3);
        userRegistry.registerUser(UserRegistry.UserRole.Arbitrator);
        vm.stopPrank();

        UserRegistry.UserProfile memory profile = userRegistry.users(user3);
        assertEq(uint8(profile.role), uint8(UserRegistry.UserRole.Arbitrator));
        assertTrue(userRegistry.isRegistered(user3));
        assertTrue(profile.isActive);
        assertEq(userRegistry.totalUsers(), 1);
    }

    function testRevertRegisterExistingUser() public {
        vm.startPrank(user1);
        userRegistry.registerUser(UserRegistry.UserRole.Freelancer);
        vm.expectRevert("User already registered");
        userRegistry.registerUser(UserRegistry.UserRole.Client);
        vm.stopPrank();
    }

    function testRevertRegisterInvalidRole() public {
        vm.startPrank(user1);
        vm.expectRevert("Invalid role");
        userRegistry.registerUser(UserRegistry.UserRole.None);
        vm.stopPrank();
    }

    function testUpdateRole() public {
        vm.startPrank(user1);
        userRegistry.registerUser(UserRegistry.UserRole.Freelancer);
        userRegistry.updateRole(UserRegistry.UserRole.Client);
        vm.stopPrank();

        UserRegistry.UserProfile memory profile = userRegistry.users(user1);
        assertEq(uint8(profile.role), uint8(UserRegistry.UserRole.Client));
    }

    function testRevertUpdateRoleSameRole() public {
        vm.startPrank(user1);
        userRegistry.registerUser(UserRegistry.UserRole.Freelancer);
        vm.expectRevert("Role is already set to this value");
        userRegistry.updateRole(UserRegistry.UserRole.Freelancer);
        vm.stopPrank();
    }

    function testRevertUpdateRoleInvalidRole() public {
        vm.startPrank(user1);
        userRegistry.registerUser(UserRegistry.UserRole.Freelancer);
        vm.expectRevert("Invalid role");
        userRegistry.updateRole(UserRegistry.UserRole.None);
        vm.stopPrank();
    }

    function testSetProfileHash() public {
        vm.startPrank(user1);
        userRegistry.registerUser(UserRegistry.UserRole.Freelancer);
        string memory profileHash = "ipfs://Qma123";
        userRegistry.setProfileHash(profileHash);
        vm.stopPrank();

        UserRegistry.UserProfile memory profile = userRegistry.users(user1);
        assertEq(profile.profileHash, profileHash);
        assertEq(userRegistry.getProfileHash(user1), profileHash);
    }

    function testRevertSetProfileHashEmpty() public {
        vm.startPrank(user1);
        userRegistry.registerUser(UserRegistry.UserRole.Freelancer);
        vm.expectRevert("Profile hash cannot be empty");
        userRegistry.setProfileHash("");
        vm.stopPrank();
    }

    function testDeactivateAccount() public {
        vm.startPrank(user1);
        userRegistry.registerUser(UserRegistry.UserRole.Freelancer);
        userRegistry.deactivateAccount();
        vm.stopPrank();

        UserRegistry.UserProfile memory profile = userRegistry.users(user1);
        assertFalse(profile.isActive);
        assertFalse(userRegistry.isActiveUser(user1));
    }

    function testReactivateAccount() public {
        vm.startPrank(user1);
        userRegistry.registerUser(UserRegistry.UserRole.Freelancer);
        userRegistry.deactivateAccount();
        userRegistry.reactivateAccount();
        vm.stopPrank();

        UserRegistry.UserProfile memory profile = userRegistry.users(user1);
        assertTrue(profile.isActive);
        assertTrue(userRegistry.isActiveUser(user1));
    }

    function testRevertReactivateActiveAccount() public {
        vm.startPrank(user1);
        userRegistry.registerUser(UserRegistry.UserRole.Freelancer);
        vm.expectRevert("Account is already active");
        userRegistry.reactivateAccount();
        vm.stopPrank();
    }

    function testGetUserProfile() public {
        vm.startPrank(user1);
        userRegistry.registerUser(UserRegistry.UserRole.Freelancer);
        string memory profileHash = "ipfs://Qma123";
        userRegistry.setProfileHash(profileHash);
        vm.stopPrank();

        (UserRegistry.UserRole role, string memory pHash, bool active, uint256 regTime) = userRegistry.getUserProfile(user1);
        assertEq(uint8(role), uint8(UserRegistry.UserRole.Freelancer));
        assertEq(pHash, profileHash);
        assertTrue(active);
        assertTrue(regTime > 0);
    }

    function testSetProfileStorageAddress() public {
        address newAddress = makeAddr("newProfileStorage");
        vm.startPrank(deployer);
        userRegistry.setProfileStorageAddress(newAddress);
        vm.stopPrank();

        assertEq(userRegistry.profileStorageAddress(), newAddress);
    }

    function testRevertSetProfileStorageAddressNotOwner() public {
        address newAddress = makeAddr("newProfileStorage");
        vm.startPrank(user1);
        vm.expectRevert("Ownable: caller is not the owner");
        userRegistry.setProfileStorageAddress(newAddress);
        vm.stopPrank();
    }

    function testRevertSetProfileStorageAddressInvalid() public {
        vm.startPrank(deployer);
        vm.expectRevert("Invalid address");
        userRegistry.setProfileStorageAddress(address(0));
        vm.stopPrank();
    }
}


