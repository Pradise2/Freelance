// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../src/SkillVerification.sol";
import "../src/UserRegistry.sol";

contract SkillVerificationTest is Test {
    SkillVerification skillVerification;
    UserRegistry userRegistry;

    address public deployer;
    address public freelancer1;
    address public client1;
    address public verifier1;
    address public verifier2;

    function setUp() public {
        deployer = makeAddr("deployer");
        freelancer1 = makeAddr("freelancer1");
        client1 = makeAddr("client1");
        verifier1 = makeAddr("verifier1");
        verifier2 = makeAddr("verifier2");

        vm.startPrank(deployer);
        userRegistry = new UserRegistry();
        skillVerification = new SkillVerification(address(userRegistry));
        skillVerification.authorizeVerifier(verifier1);
        vm.stopPrank();

        // Register users
        vm.startPrank(freelancer1);
        userRegistry.registerUser(UserRegistry.UserRole.Freelancer);
        vm.stopPrank();

        vm.startPrank(client1);
        userRegistry.registerUser(UserRegistry.UserRole.Client);
        vm.stopPrank();
    }

    function testAuthorizeVerifier() public {
        vm.startPrank(deployer);
        skillVerification.authorizeVerifier(verifier2);
        vm.stopPrank();

        assertTrue(skillVerification.authorizedVerifiers(verifier2));
    }

    function testRevertAuthorizeVerifierNotOwner() public {
        vm.startPrank(client1);
        vm.expectRevert("Ownable: caller is not the owner");
        skillVerification.authorizeVerifier(verifier2);
        vm.stopPrank();
    }

    function testRevertAuthorizeVerifierInvalidAddress() public {
        vm.startPrank(deployer);
        vm.expectRevert("Invalid verifier address");
        skillVerification.authorizeVerifier(address(0));
        vm.stopPrank();
    }

    function testRevokeVerifier() public {
        vm.startPrank(deployer);
        skillVerification.revokeVerifier(verifier1);
        vm.stopPrank();

        assertFalse(skillVerification.authorizedVerifiers(verifier1));
    }

    function testRevertRevokeVerifierNotOwner() public {
        vm.startPrank(client1);
        vm.expectRevert("Ownable: caller is not the owner");
        skillVerification.revokeVerifier(verifier1);
        vm.stopPrank();
    }

    function testRevertRevokeVerifierNotAuthorized() public {
        vm.startPrank(deployer);
        vm.expectRevert("Verifier not authorized");
        skillVerification.revokeVerifier(verifier2);
        vm.stopPrank();
    }

    function testRequestSkillVerification() public {
        string memory skillName = "Solidity";
        string memory evidenceHash = "ipfs://QmEvidence1";

        vm.startPrank(freelancer1);
        skillVerification.requestSkillVerification(skillName, evidenceHash);
        vm.stopPrank();

        SkillVerification.SkillVerification memory skill = skillVerification.userSkills(freelancer1, skillName);
        assertEq(skill.skillName, skillName);
        assertEq(skill.evidenceHash, evidenceHash);
        assertEq(uint8(skill.status), uint8(SkillVerification.VerificationStatus.Pending));
        assertEq(skillVerification.getFreelancerSkills(freelancer1).length, 1);
        assertEq(skillVerification.getFreelancerSkills(freelancer1)[0], skillName);
    }

    function testRevertRequestSkillVerificationNotFreelancer() public {
        string memory skillName = "Solidity";
        string memory evidenceHash = "ipfs://QmEvidence1";

        vm.startPrank(client1);
        vm.expectRevert("Only freelancers can perform this action");
        skillVerification.requestSkillVerification(skillName, evidenceHash);
        vm.stopPrank();
    }

    function testRevertRequestSkillVerificationEmptySkillName() public {
        string memory evidenceHash = "ipfs://QmEvidence1";

        vm.startPrank(freelancer1);
        vm.expectRevert("Skill name cannot be empty");
        skillVerification.requestSkillVerification("", evidenceHash);
        vm.stopPrank();
    }

    function testRevertRequestSkillVerificationEmptyEvidenceHash() public {
        string memory skillName = "Solidity";

        vm.startPrank(freelancer1);
        vm.expectRevert("Evidence hash cannot be empty");
        skillVerification.requestSkillVerification(skillName, "");
        vm.stopPrank();
    }

    function testVerifySkill() public {
        testRequestSkillVerification();

        string memory skillName = "Solidity";

        vm.startPrank(verifier1);
        skillVerification.verifySkill(freelancer1, skillName);
        vm.stopPrank();

        SkillVerification.SkillVerification memory skill = skillVerification.userSkills(freelancer1, skillName);
        assertEq(uint8(skill.status), uint8(SkillVerification.VerificationStatus.Verified));
        assertEq(skill.verifier, verifier1);
        assertTrue(skill.verificationTime > 0);
        assertTrue(skill.expiryTime > 0);

        (string memory sName, address verifier, SkillVerification.VerificationStatus status, string memory eHash, uint256 vTime, uint256 eTime, bool isValid) = skillVerification.getSkillVerification(freelancer1, skillName);
        assertEq(sName, skillName);
        assertEq(verifier, verifier1);
        assertEq(uint8(status), uint8(SkillVerification.VerificationStatus.Verified));
        assertTrue(isValid);

        assertEq(skillVerification.getVerifiedSkills(freelancer1).length, 1);
        assertEq(skillVerification.getVerifiedSkills(freelancer1)[0], skillName);
    }

    function testRevertVerifySkillNotAuthorized() public {
        testRequestSkillVerification();

        string memory skillName = "Solidity";

        vm.startPrank(client1);
        vm.expectRevert("Not an authorized verifier");
        skillVerification.verifySkill(freelancer1, skillName);
        vm.stopPrank();
    }

    function testRevertVerifySkillNotPending() public {
        testRequestSkillVerification();

        string memory skillName = "Solidity";

        vm.startPrank(verifier1);
        skillVerification.verifySkill(freelancer1, skillName); // Verify once
        vm.expectRevert("Skill verification not pending");
        skillVerification.verifySkill(freelancer1, skillName); // Try to verify again
        vm.stopPrank();
    }

    function testRejectSkillVerification() public {
        testRequestSkillVerification();

        string memory skillName = "Solidity";

        vm.startPrank(verifier1);
        skillVerification.rejectSkillVerification(freelancer1, skillName);
        vm.stopPrank();

        SkillVerification.SkillVerification memory skill = skillVerification.userSkills(freelancer1, skillName);
        assertEq(uint8(skill.status), uint8(SkillVerification.VerificationStatus.Rejected));
        assertEq(skill.verifier, verifier1);
        assertTrue(skill.verificationTime > 0);
    }

    function testRevertRejectSkillVerificationNotAuthorized() public {
        testRequestSkillVerification();

        string memory skillName = "Solidity";

        vm.startPrank(client1);
        vm.expectRevert("Not an authorized verifier");
        skillVerification.rejectSkillVerification(freelancer1, skillName);
        vm.stopPrank();
    }

    function testGetSkillVerificationExpired() public {
        testVerifySkill();

        string memory skillName = "Solidity";

        // Fast forward time to make verification expired
        vm.warp(block.timestamp + 365 days + 1);

        (string memory sName, address verifier, SkillVerification.VerificationStatus status, string memory eHash, uint256 vTime, uint256 eTime, bool isValid) = skillVerification.getSkillVerification(freelancer1, skillName);
        assertEq(sName, skillName);
        assertEq(verifier, verifier1);
        assertEq(uint8(status), uint8(SkillVerification.VerificationStatus.Verified));
        assertFalse(isValid);
    }

    function testSetVerificationValidityPeriod() public {
        uint256 newPeriod = 180 days;
        vm.startPrank(deployer);
        skillVerification.setVerificationValidityPeriod(newPeriod);
        vm.stopPrank();

        assertEq(skillVerification.verificationValidityPeriod(), newPeriod);
    }

    function testSetUserRegistryAddress() public {
        address newUserRegistry = makeAddr("newUserRegistry");
        vm.startPrank(deployer);
        skillVerification.setUserRegistryAddress(newUserRegistry);
        vm.stopPrank();

        assertEq(address(skillVerification.userRegistry()), newUserRegistry);
    }
}


