// Deployment script for Decentralized Freelance Collaboration Platform
// This script deploys all contracts in the correct order with proper dependencies

const { ethers } = require("hardhat");

async function main() {
    console.log("Starting deployment of Decentralized Freelance Collaboration Platform...");
    
    const [deployer] = await ethers.getSigners();
    console.log("Deploying contracts with account:", deployer.address);
    console.log("Account balance:", (await deployer.getBalance()).toString());

    // Contract deployment order is important due to dependencies
    const deployedContracts = {};

    // 1. Deploy UserRegistry (no dependencies)
    console.log("\n1. Deploying UserRegistry...");
    const UserRegistry = await ethers.getContractFactory("UserRegistry");
    const userRegistry = await UserRegistry.deploy();
    await userRegistry.deployed();
    deployedContracts.UserRegistry = userRegistry.address;
    console.log("UserRegistry deployed to:", userRegistry.address);

    // 2. Deploy ProfileStorage (depends on UserRegistry)
    console.log("\n2. Deploying ProfileStorage...");
    const ProfileStorage = await ethers.getContractFactory("ProfileStorage");
    const profileStorage = await ProfileStorage.deploy(userRegistry.address);
    await profileStorage.deployed();
    deployedContracts.ProfileStorage = profileStorage.address;
    console.log("ProfileStorage deployed to:", profileStorage.address);

    // Set ProfileStorage address in UserRegistry
    await userRegistry.setProfileStorageAddress(profileStorage.address);
    console.log("ProfileStorage address set in UserRegistry");

    // 3. Deploy JobBoard (depends on UserRegistry)
    console.log("\n3. Deploying JobBoard...");
    const JobBoard = await ethers.getContractFactory("JobBoard");
    const jobBoard = await JobBoard.deploy(userRegistry.address);
    await jobBoard.deployed();
    deployedContracts.JobBoard = jobBoard.address;
    console.log("JobBoard deployed to:", jobBoard.address);

    // 4. Deploy FeeManager (no dependencies)
    console.log("\n4. Deploying FeeManager...");
    const FeeManager = await ethers.getContractFactory("FeeManager");
    const platformTreasury = deployer.address; // Using deployer as treasury for demo
    const feeManager = await FeeManager.deploy(platformTreasury);
    await feeManager.deployed();
    deployedContracts.FeeManager = feeManager.address;
    console.log("FeeManager deployed to:", feeManager.address);

    // 5. Deploy Escrow (temporary addresses, will be updated later)
    console.log("\n5. Deploying Escrow...");
    const Escrow = await ethers.getContractFactory("Escrow");
    const escrow = await Escrow.deploy(
        deployer.address, // Temporary ProjectManager address
        deployer.address, // Temporary ArbitrationCourt address
        feeManager.address
    );
    await escrow.deployed();
    deployedContracts.Escrow = escrow.address;
    console.log("Escrow deployed to:", escrow.address);

    // 6. Deploy FeedbackStorage (temporary address, will be updated later)
    console.log("\n6. Deploying FeedbackStorage...");
    const FeedbackStorage = await ethers.getContractFactory("FeedbackStorage");
    const feedbackStorage = await FeedbackStorage.deploy(deployer.address); // Temporary ReputationSystem address
    await feedbackStorage.deployed();
    deployedContracts.FeedbackStorage = feedbackStorage.address;
    console.log("FeedbackStorage deployed to:", feedbackStorage.address);

    // 7. Deploy ReputationSystem (depends on UserRegistry and FeedbackStorage)
    console.log("\n7. Deploying ReputationSystem...");
    const ReputationSystem = await ethers.getContractFactory("ReputationSystem");
    const reputationSystem = await ReputationSystem.deploy(
        userRegistry.address,
        deployer.address, // Temporary ProjectManager address
        feedbackStorage.address
    );
    await reputationSystem.deployed();
    deployedContracts.ReputationSystem = reputationSystem.address;
    console.log("ReputationSystem deployed to:", reputationSystem.address);

    // Update FeedbackStorage with correct ReputationSystem address
    await feedbackStorage.setReputationSystemAddress(reputationSystem.address);
    console.log("ReputationSystem address set in FeedbackStorage");

    // 8. Deploy ArbitratorRegistry (depends on UserRegistry and ReputationSystem)
    console.log("\n8. Deploying ArbitratorRegistry...");
    const ArbitratorRegistry = await ethers.getContractFactory("ArbitratorRegistry");
    const arbitratorRegistry = await ArbitratorRegistry.deploy(
        userRegistry.address,
        reputationSystem.address
    );
    await arbitratorRegistry.deployed();
    deployedContracts.ArbitratorRegistry = arbitratorRegistry.address;
    console.log("ArbitratorRegistry deployed to:", arbitratorRegistry.address);

    // 9. Deploy ArbitrationCourt (depends on Escrow and ArbitratorRegistry)
    console.log("\n9. Deploying ArbitrationCourt...");
    const ArbitrationCourt = await ethers.getContractFactory("ArbitrationCourt");
    const arbitrationCourt = await ArbitrationCourt.deploy(
        deployer.address, // Temporary ProjectManager address
        escrow.address,
        arbitratorRegistry.address
    );
    await arbitrationCourt.deployed();
    deployedContracts.ArbitrationCourt = arbitrationCourt.address;
    console.log("ArbitrationCourt deployed to:", arbitrationCourt.address);

    // 10. Deploy ProjectManager (depends on UserRegistry, JobBoard, Escrow, ArbitrationCourt)
    console.log("\n10. Deploying ProjectManager...");
    const ProjectManager = await ethers.getContractFactory("ProjectManager");
    const projectManager = await ProjectManager.deploy(
        userRegistry.address,
        jobBoard.address,
        escrow.address,
        arbitrationCourt.address
    );
    await projectManager.deployed();
    deployedContracts.ProjectManager = projectManager.address;
    console.log("ProjectManager deployed to:", projectManager.address);

    // Update contract addresses with correct ProjectManager address
    await escrow.setContractAddresses(projectManager.address, arbitrationCourt.address, feeManager.address);
    await arbitrationCourt.setContractAddresses(projectManager.address, escrow.address, arbitratorRegistry.address);
    await reputationSystem.setContractAddresses(userRegistry.address, projectManager.address, feedbackStorage.address);
    console.log("Contract addresses updated with correct ProjectManager address");

    // 11. Deploy ProposalManager (depends on UserRegistry, JobBoard, ProjectManager, Escrow)
    console.log("\n11. Deploying ProposalManager...");
    const ProposalManager = await ethers.getContractFactory("ProposalManager");
    const proposalManager = await ProposalManager.deploy(
        userRegistry.address,
        jobBoard.address,
        projectManager.address,
        escrow.address
    );
    await proposalManager.deployed();
    deployedContracts.ProposalManager = proposalManager.address;
    console.log("ProposalManager deployed to:", proposalManager.address);

    // 12. Deploy PaymentGateway (depends on UserRegistry, Escrow, FeeManager)
    console.log("\n12. Deploying PaymentGateway...");
    const PaymentGateway = await ethers.getContractFactory("PaymentGateway");
    const paymentGateway = await PaymentGateway.deploy(
        userRegistry.address,
        escrow.address,
        feeManager.address
    );
    await paymentGateway.deployed();
    deployedContracts.PaymentGateway = paymentGateway.address;
    console.log("PaymentGateway deployed to:", paymentGateway.address);

    // 13. Deploy Token (ERC-20 platform token)
    console.log("\n13. Deploying Token...");
    const Token = await ethers.getContractFactory("Token");
    const token = await Token.deploy("FreelancePlatformToken", "FPT");
    await token.deployed();
    deployedContracts.Token = token.address;
    console.log("Token deployed to:", token.address);

    // 14. Deploy Governance (depends on Token)
    console.log("\n14. Deploying Governance...");
    const Governance = await ethers.getContractFactory("Governance");
    const governance = await Governance.deploy(token.address);
    await governance.deployed();
    deployedContracts.Governance = governance.address;
    console.log("Governance deployed to:", governance.address);

    // 15. Deploy OracleInterface (no dependencies)
    console.log("\n15. Deploying OracleInterface...");
    const OracleInterface = await ethers.getContractFactory("OracleInterface");
    const oracleInterface = await OracleInterface.deploy();
    await oracleInterface.deployed();
    deployedContracts.OracleInterface = oracleInterface.address;
    console.log("OracleInterface deployed to:", oracleInterface.address);

    // 16. Deploy SkillVerification (depends on UserRegistry)
    console.log("\n16. Deploying SkillVerification...");
    const SkillVerification = await ethers.getContractFactory("SkillVerification");
    const skillVerification = await SkillVerification.deploy(userRegistry.address);
    await skillVerification.deployed();
    deployedContracts.SkillVerification = skillVerification.address;
    console.log("SkillVerification deployed to:", skillVerification.address);

    // 17. Deploy MessageSystem (depends on UserRegistry)
    console.log("\n17. Deploying MessageSystem...");
    const MessageSystem = await ethers.getContractFactory("MessageSystem");
    const messageSystem = await MessageSystem.deploy(userRegistry.address);
    await messageSystem.deployed();
    deployedContracts.MessageSystem = messageSystem.address;
    console.log("MessageSystem deployed to:", messageSystem.address);

    // 18. Deploy NotificationManager (depends on UserRegistry)
    console.log("\n18. Deploying NotificationManager...");
    const NotificationManager = await ethers.getContractFactory("NotificationManager");
    const notificationManager = await NotificationManager.deploy(userRegistry.address);
    await notificationManager.deployed();
    deployedContracts.NotificationManager = notificationManager.address;
    console.log("NotificationManager deployed to:", notificationManager.address);

    // Print deployment summary
    console.log("\n=== DEPLOYMENT SUMMARY ===");
    console.log("All contracts deployed successfully!");
    console.log("\nContract Addresses:");
    for (const [name, address] of Object.entries(deployedContracts)) {
        console.log(`${name}: ${address}`);
    }

    // Save deployment addresses to file
    const fs = require('fs');
    const deploymentData = {
        network: "localhost", // Change this based on your deployment network
        deployer: deployer.address,
        timestamp: new Date().toISOString(),
        contracts: deployedContracts
    };

    fs.writeFileSync('deployment-addresses.json', JSON.stringify(deploymentData, null, 2));
    console.log("\nDeployment addresses saved to deployment-addresses.json");

    console.log("\n=== NEXT STEPS ===");
    console.log("1. Verify contracts on block explorer (if deploying to public network)");
    console.log("2. Set up initial configuration (fees, parameters, etc.)");
    console.log("3. Register initial arbitrators and oracles");
    console.log("4. Test the platform with sample data");
    console.log("5. Deploy frontend application");
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error("Deployment failed:", error);
        process.exit(1);
    });

