// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../src/ProfileStorage.sol";

contract ProfileStorageTest is Test {
    ProfileStorage profileStorage;

    address public deployer;
    address public user1;
    address public user2;
    address public userRegistryMock;

    function setUp() public {
        deployer = makeAddr("deployer");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        userRegistryMock = makeAddr("userRegistryMock");

        vm.startPrank(deployer);
        profileStorage = new ProfileStorage(userRegistryMock);
        vm.stopPrank();
    }

    function testSetProfileHash() public {
        string memory profileHash = "ipfs://QmTestHash1";
        vm.startPrank(userRegistryMock);
        profileStorage.setProfileHash(user1, profileHash);
        vm.stopPrank();

        assertEq(profileStorage.profiles(user1), profileHash);
        assertEq(profileStorage.getProfileHash(user1), profileHash);
        assertTrue(profileStorage.hasProfile(user1));
        assertEq(profileStorage.totalProfiles(), 1);

        (string memory pHash, uint256 lastUpdated) = profileStorage.getProfileDetails(user1);
        assertEq(pHash, profileHash);
        assertTrue(lastUpdated > 0);
    }

    function testUpdateProfileHash() public {
        string memory profileHash1 = "ipfs://QmTestHash1";
        string memory profileHash2 = "ipfs://QmTestHash2";

        vm.startPrank(userRegistryMock);
        profileStorage.setProfileHash(user1, profileHash1);
        profileStorage.setProfileHash(user1, profileHash2);
        vm.stopPrank();

        assertEq(profileStorage.profiles(user1), profileHash2);
        assertEq(profileStorage.totalProfiles(), 1); // Should still be 1, not incremented
    }

    function testRevertSetProfileHashEmpty() public {
        vm.startPrank(userRegistryMock);
        vm.expectRevert("Profile hash cannot be empty");
        profileStorage.setProfileHash(user1, "");
        vm.stopPrank();
    }

    function testRevertSetProfileHashTooLong() public {
        string memory longHash = new string(101); // 101 characters
        for (uint i = 0; i < 101; i++) {
            longHash = string.concat(longHash, "a");
        }
        vm.startPrank(userRegistryMock);
        vm.expectRevert("Profile hash too long");
        profileStorage.setProfileHash(user1, longHash);
        vm.stopPrank();
    }

    function testRevertSetProfileHashInvalidUser() public {
        vm.startPrank(userRegistryMock);
        vm.expectRevert("Invalid user address");
        profileStorage.setProfileHash(address(0), "ipfs://QmTestHash");
        vm.stopPrank();
    }

    function testRevertSetProfileHashUnauthorized() public {
        vm.startPrank(user1);
        vm.expectRevert("Not authorized to modify profiles");
        profileStorage.setProfileHash(user1, "ipfs://QmTestHash");
        vm.stopPrank();
    }

    function testDeleteProfile() public {
        string memory profileHash = "ipfs://QmTestHash1";
        vm.startPrank(userRegistryMock);
        profileStorage.setProfileHash(user1, profileHash);
        vm.stopPrank();

        assertTrue(profileStorage.hasProfile(user1));
        assertEq(profileStorage.totalProfiles(), 1);

        vm.startPrank(userRegistryMock);
        profileStorage.deleteProfile(user1);
        vm.stopPrank();

        assertFalse(profileStorage.hasProfile(user1));
        assertEq(profileStorage.totalProfiles(), 0);
        assertEq(profileStorage.profiles(user1), "");
    }

    function testRevertDeleteNonExistentProfile() public {
        vm.startPrank(userRegistryMock);
        vm.expectRevert("Profile does not exist");
        profileStorage.deleteProfile(user1);
        vm.stopPrank();
    }

    function testBatchUpdateProfiles() public {
        address[] memory users = new address[](2);
        users[0] = user1;
        users[1] = user2;

        string[] memory hashes = new string[](2);
        hashes[0] = "ipfs://QmHashA";
        hashes[1] = "ipfs://QmHashB";

        vm.startPrank(deployer);
        profileStorage.batchUpdateProfiles(users, hashes);
        vm.stopPrank();

        assertEq(profileStorage.profiles(user1), "ipfs://QmHashA");
        assertEq(profileStorage.profiles(user2), "ipfs://QmHashB");
        assertEq(profileStorage.totalProfiles(), 2);
    }

    function testRevertBatchUpdateProfilesMismatch() public {
        address[] memory users = new address[](1);
        users[0] = user1;

        string[] memory hashes = new string[](2);
        hashes[0] = "ipfs://QmHashA";
        hashes[1] = "ipfs://QmHashB";

        vm.startPrank(deployer);
        vm.expectRevert("Arrays length mismatch");
        profileStorage.batchUpdateProfiles(users, hashes);
        vm.stopPrank();
    }

    function testRevertBatchUpdateProfilesEmpty() public {
        address[] memory users = new address[](0);
        string[] memory hashes = new string[](0);

        vm.startPrank(deployer);
        vm.expectRevert("Empty arrays");
        profileStorage.batchUpdateProfiles(users, hashes);
        vm.stopPrank();
    }

    function testSetUserRegistryAddress() public {
        address newAddress = makeAddr("newUserRegistry");
        vm.startPrank(deployer);
        profileStorage.setUserRegistryAddress(newAddress);
        vm.stopPrank();

        assertEq(profileStorage.userRegistryAddress(), newAddress);
    }

    function testRevertSetUserRegistryAddressNotOwner() public {
        address newAddress = makeAddr("newUserRegistry");
        vm.startPrank(user1);
        vm.expectRevert("Ownable: caller is not the owner");
        profileStorage.setUserRegistryAddress(newAddress);
        vm.stopPrank();
    }

    function testRevertSetUserRegistryAddressInvalid() public {
        vm.startPrank(deployer);
        vm.expectRevert("Invalid address");
        profileStorage.setUserRegistryAddress(address(0));
        vm.stopPrank();
    }
}


