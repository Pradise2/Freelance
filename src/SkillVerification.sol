// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/Ownable.sol";

interface IUserRegistry {
    enum UserRole { None, Freelancer, Client, Arbitrator }
    function getUserRole(address _userAddress) external view returns (UserRole);
    function isActiveUser(address _userAddress) external view returns (bool);
}

/**
 * @title SkillVerification
 * @dev Manages skill verification and certification for freelancers
 * Allows for skill attestation and verification by authorized entities
 */
contract SkillVerification is Ownable {
    // Verification status
    enum VerificationStatus {
        Unverified,  // 0 - Not verified
        Pending,     // 1 - Verification in progress
        Verified,    // 2 - Successfully verified
        Rejected     // 3 - Verification rejected
    }

    // Skill verification structure
    struct SkillVerification {
        string skillName;
        address verifier;
        VerificationStatus status;
        string evidenceHash; // IPFS hash of verification evidence
        uint256 verificationTime;
        uint256 expiryTime;
    }

    // State variables
    mapping(address => mapping(string => SkillVerification)) public userSkills;
    mapping(address => string[]) public userSkillsList;
    mapping(address => bool) public authorizedVerifiers;
    
    uint256 public verificationValidityPeriod = 365 days; // 1 year validity

    IUserRegistry public userRegistry;

    // Events
    event SkillVerificationRequested(
        address indexed freelancer,
        string skillName,
        string evidenceHash,
        uint256 timestamp
    );

    event SkillVerified(
        address indexed freelancer,
        string skillName,
        address indexed verifier,
        uint256 timestamp,
        uint256 expiryTime
    );

    event SkillVerificationRejected(
        address indexed freelancer,
        string skillName,
        address indexed verifier,
        uint256 timestamp
    );

    event VerifierAuthorized(
        address indexed verifier,
        uint256 timestamp
    );

    event VerifierRevoked(
        address indexed verifier,
        uint256 timestamp
    );

    // Modifiers
    modifier onlyFreelancer() {
        require(
            userRegistry.getUserRole(msg.sender) == IUserRegistry.UserRole.Freelancer,
            "Only freelancers can perform this action"
        );
        require(userRegistry.isActiveUser(msg.sender), "User account is not active");
        _;
    }

    modifier onlyAuthorizedVerifier() {
        require(authorizedVerifiers[msg.sender], "Not an authorized verifier");
        _;
    }

    constructor(address _userRegistryAddress) Ownable(msg.sender) {
        require(_userRegistryAddress != address(0), "Invalid UserRegistry address");
        userRegistry = IUserRegistry(_userRegistryAddress);
    }

    /**
     * @dev Authorize a verifier
     * @param _verifier Address of the verifier to authorize
     */
    function authorizeVerifier(address _verifier) external onlyOwner {
        require(_verifier != address(0), "Invalid verifier address");
        authorizedVerifiers[_verifier] = true;
        emit VerifierAuthorized(_verifier, block.timestamp);
    }

    /**
     * @dev Revoke verifier authorization
     * @param _verifier Address of the verifier to revoke
     */
    function revokeVerifier(address _verifier) external onlyOwner {
        require(authorizedVerifiers[_verifier], "Verifier not authorized");
        authorizedVerifiers[_verifier] = false;
        emit VerifierRevoked(_verifier, block.timestamp);
    }

    /**
     * @dev Request skill verification
     * @param _skillName Name of the skill to verify
     * @param _evidenceHash IPFS hash of evidence supporting the skill claim
     */
    function requestSkillVerification(
        string calldata _skillName,
        string calldata _evidenceHash
    ) 
        external 
        onlyFreelancer 
    {
        require(bytes(_skillName).length > 0, "Skill name cannot be empty");
        require(bytes(_evidenceHash).length > 0, "Evidence hash cannot be empty");
        require(
            userSkills[msg.sender][_skillName].status == VerificationStatus.Unverified ||
            userSkills[msg.sender][_skillName].status == VerificationStatus.Rejected,
            "Skill verification already requested or verified"
        );

        // Add skill to user's skill list if not already present
        bool skillExists = false;
        for (uint256 i = 0; i < userSkillsList[msg.sender].length; i++) {
            if (keccak256(bytes(userSkillsList[msg.sender][i])) == keccak256(bytes(_skillName))) {
                skillExists = true;
                break;
            }
        }
        if (!skillExists) {
            userSkillsList[msg.sender].push(_skillName);
        }

        userSkills[msg.sender][_skillName] = SkillVerification({
            skillName: _skillName,
            verifier: address(0),
            status: VerificationStatus.Pending,
            evidenceHash: _evidenceHash,
            verificationTime: 0,
            expiryTime: 0
        });

        emit SkillVerificationRequested(msg.sender, _skillName, _evidenceHash, block.timestamp);
    }

    /**
     * @dev Verify a freelancer's skill
     * @param _freelancer Address of the freelancer
     * @param _skillName Name of the skill to verify
     */
    function verifySkill(address _freelancer, string calldata _skillName) 
        external 
        onlyAuthorizedVerifier 
    {
        require(_freelancer != address(0), "Invalid freelancer address");
        require(bytes(_skillName).length > 0, "Skill name cannot be empty");
        require(
            userSkills[_freelancer][_skillName].status == VerificationStatus.Pending,
            "Skill verification not pending"
        );

        uint256 expiryTime = block.timestamp + verificationValidityPeriod;

        userSkills[_freelancer][_skillName].verifier = msg.sender;
        userSkills[_freelancer][_skillName].status = VerificationStatus.Verified;
        userSkills[_freelancer][_skillName].verificationTime = block.timestamp;
        userSkills[_freelancer][_skillName].expiryTime = expiryTime;

        emit SkillVerified(_freelancer, _skillName, msg.sender, block.timestamp, expiryTime);
    }

    /**
     * @dev Reject a freelancer's skill verification
     * @param _freelancer Address of the freelancer
     * @param _skillName Name of the skill to reject
     */
    function rejectSkillVerification(address _freelancer, string calldata _skillName) 
        external 
        onlyAuthorizedVerifier 
    {
        require(_freelancer != address(0), "Invalid freelancer address");
        require(bytes(_skillName).length > 0, "Skill name cannot be empty");
        require(
            userSkills[_freelancer][_skillName].status == VerificationStatus.Pending,
            "Skill verification not pending"
        );

        userSkills[_freelancer][_skillName].verifier = msg.sender;
        userSkills[_freelancer][_skillName].status = VerificationStatus.Rejected;
        userSkills[_freelancer][_skillName].verificationTime = block.timestamp;

        emit SkillVerificationRejected(_freelancer, _skillName, msg.sender, block.timestamp);
    }

    /**
     * @dev Get skill verification details
     * @param _freelancer Address of the freelancer
     * @param _skillName Name of the skill
     * @return Skill verification details
     */
    function getSkillVerification(address _freelancer, string calldata _skillName) 
        external 
        view 
        returns (
            string memory skillName,
            address verifier,
            VerificationStatus status,
            string memory evidenceHash,
            uint256 verificationTime,
            uint256 expiryTime,
            bool isValid
        ) 
    {
        SkillVerification memory skill = userSkills[_freelancer][_skillName];
        bool valid = skill.status == VerificationStatus.Verified && 
                    block.timestamp <= skill.expiryTime;
        
        return (
            skill.skillName,
            skill.verifier,
            skill.status,
            skill.evidenceHash,
            skill.verificationTime,
            skill.expiryTime,
            valid
        );
    }

    /**
     * @dev Get all skills for a freelancer
     * @param _freelancer Address of the freelancer
     * @return Array of skill names
     */
    function getFreelancerSkills(address _freelancer) 
        external 
        view 
        returns (string[] memory) 
    {
        return userSkillsList[_freelancer];
    }

    /**
     * @dev Get verified skills for a freelancer
     * @param _freelancer Address of the freelancer
     * @return Array of verified skill names
     */
    function getVerifiedSkills(address _freelancer) 
        external 
        view 
        returns (string[] memory) 
    {
        string[] memory allSkills = userSkillsList[_freelancer];
        uint256 verifiedCount = 0;
        
        // Count verified skills
        for (uint256 i = 0; i < allSkills.length; i++) {
            SkillVerification memory skill = userSkills[_freelancer][allSkills[i]];
            if (skill.status == VerificationStatus.Verified && 
                block.timestamp <= skill.expiryTime) {
                verifiedCount++;
            }
        }
        
        // Create array of verified skills
        string[] memory verifiedSkills = new string[](verifiedCount);
        uint256 currentIndex = 0;
        
        for (uint256 i = 0; i < allSkills.length; i++) {
            SkillVerification memory skill = userSkills[_freelancer][allSkills[i]];
            if (skill.status == VerificationStatus.Verified && 
                block.timestamp <= skill.expiryTime) {
                verifiedSkills[currentIndex] = allSkills[i];
                currentIndex++;
            }
        }
        
        return verifiedSkills;
    }

    /**
     * @dev Set verification validity period (only owner)
     * @param _newPeriod New validity period in seconds
     */
    function setVerificationValidityPeriod(uint256 _newPeriod) external onlyOwner {
        require(_newPeriod > 0, "Validity period must be greater than zero");
        verificationValidityPeriod = _newPeriod;
    }

    /**
     * @dev Update UserRegistry address (only owner)
     * @param _userRegistryAddress New UserRegistry contract address
     */
    function setUserRegistryAddress(address _userRegistryAddress) external onlyOwner {
        require(_userRegistryAddress != address(0), "Invalid address");
        userRegistry = IUserRegistry(_userRegistryAddress);
    }
}

