// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../src/Governance.sol";
import "../src/Token.sol";

contract GovernanceTest is Test {
    Governance governance;
    Token token;

    address public deployer;
    address public voter1;
    address public voter2;
    address public voter3;
    address public nonVoter;

    function setUp() public {
        deployer = makeAddr("deployer");
        voter1 = makeAddr("voter1");
        voter2 = makeAddr("voter2");
        voter3 = makeAddr("voter3");
        nonVoter = makeAddr("nonVoter");

        vm.startPrank(deployer);
        token = new Token("GovernanceToken", "GOV");
        governance = new Governance(address(token));
        vm.stopPrank();

        // Mint tokens to voters
        vm.startPrank(deployer);
        token.mint(voter1, 100 * 10**18);
        token.mint(voter2, 150 * 10**18);
        token.mint(voter3, 200 * 10**18);
        vm.stopPrank();
    }

    function testCreateProposal() public {
        string memory description = "Increase platform fees by 1%";
        address[] memory targets = new address[](0);
        uint256[] memory values = new uint256[](0);
        bytes[] memory calldatas = new bytes[](0);

        vm.startPrank(voter1);
        governance.createProposal(description, targets, values, calldatas);
        vm.stopPrank();

        Governance.Proposal memory proposal = governance.proposals(1);
        assertEq(proposal.proposer, voter1);
        assertEq(proposal.description, description);
        assertEq(proposal.voteCountFor, 0);
        assertEq(proposal.voteCountAgainst, 0);
        assertEq(uint8(proposal.status), uint8(Governance.ProposalStatus.Pending));
        assertTrue(proposal.creationTime > 0);
        assertTrue(proposal.votingDeadline > proposal.creationTime);
        assertEq(governance.nextProposalId(), 2);
    }

    function testRevertCreateProposalNotEnoughTokens() public {
        string memory description = "Increase platform fees by 1%";
        address[] memory targets = new address[](0);
        uint256[] memory values = new uint256[](0);
        bytes[] memory calldatas = new bytes[](0);

        vm.startPrank(nonVoter);
        vm.expectRevert("Proposer must hold minimum tokens");
        governance.createProposal(description, targets, values, calldatas);
        vm.stopPrank();
    }

    function testVoteForProposal() public {
        testCreateProposal();

        vm.startPrank(voter1);
        governance.vote(1, true);
        vm.stopPrank();

        Governance.Proposal memory proposal = governance.proposals(1);
        assertEq(proposal.voteCountFor, 100 * 10**18);
        assertEq(proposal.voteCountAgainst, 0);
        assertTrue(governance.hasVoted(1, voter1));
    }

    function testVoteAgainstProposal() public {
        testCreateProposal();

        vm.startPrank(voter2);
        governance.vote(1, false);
        vm.stopPrank();

        Governance.Proposal memory proposal = governance.proposals(1);
        assertEq(proposal.voteCountFor, 0);
        assertEq(proposal.voteCountAgainst, 150 * 10**18);
        assertTrue(governance.hasVoted(1, voter2));
    }

    function testRevertVoteAlreadyVoted() public {
        testCreateProposal();

        vm.startPrank(voter1);
        governance.vote(1, true);
        vm.expectRevert("Already voted on this proposal");
        governance.vote(1, false);
        vm.stopPrank();
    }

    function testRevertVoteProposalNotActive() public {
        testCreateProposal();

        // Fast forward time to pass voting deadline
        vm.warp(block.timestamp + 7 days + 1);

        vm.startPrank(voter1);
        vm.expectRevert("Proposal not in active voting period");
        governance.vote(1, true);
        vm.stopPrank();
    }

    function testExecuteProposalSuccess() public {
        testCreateProposal();

        vm.startPrank(voter1);
        governance.vote(1, true);
        vm.stopPrank();

        vm.startPrank(voter2);
        governance.vote(1, true);
        vm.stopPrank();

        vm.startPrank(voter3);
        governance.vote(1, true);
        vm.stopPrank();

        // Fast forward time to pass voting deadline
        vm.warp(block.timestamp + 7 days + 1);

        vm.startPrank(deployer); // Anyone can execute
        governance.executeProposal(1);
        vm.stopPrank();

        Governance.Proposal memory proposal = governance.proposals(1);
        assertEq(uint8(proposal.status), uint8(Governance.ProposalStatus.Executed));
    }

    function testExecuteProposalFail() public {
        testCreateProposal();

        vm.startPrank(voter1);
        governance.vote(1, false);
        vm.stopPrank();

        vm.startPrank(voter2);
        governance.vote(1, false);
        vm.stopPrank();

        vm.startPrank(voter3);
        governance.vote(1, true);
        vm.stopPrank();

        // Fast forward time to pass voting deadline
        vm.warp(block.timestamp + 7 days + 1);

        vm.startPrank(deployer);
        vm.expectRevert("Proposal not passed or already executed");
        governance.executeProposal(1);
        vm.stopPrank();

        Governance.Proposal memory proposal = governance.proposals(1);
        assertEq(uint8(proposal.status), uint8(Governance.ProposalStatus.Defeated));
    }

    function testGetProposalDetails() public {
        testCreateProposal();

        (address proposer, string memory description, uint256 voteCountFor, uint256 voteCountAgainst, Governance.ProposalStatus status, uint256 creationTime, uint256 votingDeadline) = governance.getProposalDetails(1);
        assertEq(proposer, voter1);
        assertEq(description, "Increase platform fees by 1%");
        assertEq(voteCountFor, 0);
        assertEq(voteCountAgainst, 0);
        assertEq(uint8(status), uint8(Governance.ProposalStatus.Pending));
        assertTrue(creationTime > 0);
        assertTrue(votingDeadline > 0);
    }

    function testSetVotingPeriod() public {
        uint256 newPeriod = 10 days;
        vm.startPrank(deployer);
        governance.setVotingPeriod(newPeriod);
        vm.stopPrank();

        assertEq(governance.votingPeriod(), newPeriod);
    }

    function testSetMinTokensToPropose() public {
        uint256 newMinTokens = 200 * 10**18;
        vm.startPrank(deployer);
        governance.setMinTokensToPropose(newMinTokens);
        vm.stopPrank();

        assertEq(governance.minTokensToPropose(), newMinTokens);
    }

    function testSetQuorumPercentage() public {
        uint256 newQuorum = 6000; // 60%
        vm.startPrank(deployer);
        governance.setQuorumPercentage(newQuorum);
        vm.stopPrank();

        assertEq(governance.quorumPercentage(), newQuorum);
    }

    function testSetTokenAddress() public {
        address newToken = makeAddr("newToken");
        vm.startPrank(deployer);
        governance.setTokenAddress(newToken);
        vm.stopPrank();

        assertEq(address(governance.token()), newToken);
    }
}


