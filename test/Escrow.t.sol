// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../src/Escrow.sol";
import "../src/Token.sol";
import "../src/FeeManager.sol";

interface IProjectManagerMock {
    function getProjectDetails(uint256 _projectId) external view returns (
        uint256 jobId,
        address client,
        address freelancer,
        uint256 agreedBudget,
        uint256 agreedDeadline,
        uint8 status,
        uint256 startTime,
        uint256 totalMilestones,
        uint256 completedMilestones,
        uint256 approvedMilestones
    );
}

contract EscrowTest is Test {
    Escrow escrow;
    Token testToken;
    FeeManager feeManager;
    IProjectManagerMock projectManagerMock;

    address public deployer;
    address public client1;
    address public freelancer1;
    address public arbitrationCourtMock;
    address public platformTreasury;

    function setUp() public {
        deployer = makeAddr("deployer");
        client1 = makeAddr("client1");
        freelancer1 = makeAddr("freelancer1");
        arbitrationCourtMock = makeAddr("arbitrationCourtMock");
        platformTreasury = makeAddr("platformTreasury");

        vm.startPrank(deployer);
        testToken = new Token("TestToken", "TST");
        feeManager = new FeeManager(platformTreasury);
        // Deploy Escrow with mock addresses for ProjectManager and ArbitrationCourt
        escrow = new Escrow(address(this), arbitrationCourtMock, address(feeManager));
        vm.stopPrank();

        // Mock ProjectManager behavior
        projectManagerMock = IProjectManagerMock(address(this));

        // Transfer ownership of Escrow to deployer for testing release/refund functions
        vm.startPrank(deployer);
        escrow.transferOwnership(deployer);
        vm.stopPrank();
    }

    // Mock function for IProjectManagerMock
    function getProjectDetails(uint256 _projectId) external view returns (
        uint256 jobId,
        address client,
        address freelancer,
        uint256 agreedBudget,
        uint256 agreedDeadline,
        uint8 status,
        uint256 startTime,
        uint256 totalMilestones,
        uint256 completedMilestones,
        uint256 approvedMilestones
    ) {
        if (_projectId == 1) {
            return (1, client1, freelancer1, 10 ether, block.timestamp + 10 days, 0, block.timestamp, 2, 0, 0);
        } else if (_projectId == 2) {
            return (2, client1, freelancer1, 100 * 10**18, block.timestamp + 10 days, 0, block.timestamp, 2, 0, 0);
        }
        revert("Project does not exist");
    }

    function testFundProjectETH() public {
        uint256 projectId = 1;
        uint256 amount = 5 ether;

        vm.deal(client1, amount);
        vm.startPrank(client1);
        escrow.fundProjectETH{value: amount}(projectId);
        vm.stopPrank();

        assertEq(escrow.projectBalances(projectId, address(0)), amount);
        assertEq(escrow.getEscrowBalance(projectId, address(0)), amount);
        assertEq(escrow.getProjectToken(projectId), address(0));
    }

    function testRevertFundProjectETHZeroAmount() public {
        uint256 projectId = 1;

        vm.deal(client1, 0);
        vm.startPrank(client1);
        vm.expectRevert("Amount must be greater than zero");
        escrow.fundProjectETH{value: 0}(projectId);
        vm.stopPrank();
    }

    function testRevertFundProjectETHNotClient() public {
        uint256 projectId = 1;
        uint256 amount = 5 ether;

        vm.deal(freelancer1, amount);
        vm.startPrank(freelancer1);
        vm.expectRevert("Only project client can fund");
        escrow.fundProjectETH{value: amount}(projectId);
        vm.stopPrank();
    }

    function testFundProjectERC20() public {
        uint256 projectId = 2;
        uint256 amount = 50 * 10**18; // 50 TST

        // Mint tokens to client1 and approve Escrow
        vm.startPrank(deployer);
        testToken.mint(client1, amount);
        vm.stopPrank();

        vm.startPrank(client1);
        testToken.approve(address(escrow), amount);
        escrow.fundProjectERC20(projectId, address(testToken), amount);
        vm.stopPrank();

        assertEq(escrow.projectBalances(projectId, address(testToken)), amount);
        assertEq(escrow.getEscrowBalance(projectId, address(testToken)), amount);
        assertEq(escrow.getProjectToken(projectId), address(testToken));
    }

    function testRevertFundProjectERC20ZeroAmount() public {
        uint256 projectId = 2;

        vm.startPrank(client1);
        vm.expectRevert("Amount must be greater than zero");
        escrow.fundProjectERC20(projectId, address(testToken), 0);
        vm.stopPrank();
    }

    function testRevertFundProjectERC20NotClient() public {
        uint256 projectId = 2;
        uint256 amount = 50 * 10**18;

        vm.startPrank(freelancer1);
        vm.expectRevert("Only project client can fund");
        escrow.fundProjectERC20(projectId, address(testToken), amount);
        vm.stopPrank();
    }

    function testReleaseFundsETH() public {
        testFundProjectETH();

        uint256 projectId = 1;
        uint256 amountToRelease = 2 ether;
        uint256 initialFreelancerBalance = freelancer1.balance;

        vm.startPrank(deployer); // Called by ProjectManager
        escrow.releaseFunds(projectId, freelancer1, amountToRelease);
        vm.stopPrank();

        assertEq(escrow.projectBalances(projectId, address(0)), 3 ether); // 5 - 2 = 3
        assertEq(freelancer1.balance, initialFreelancerBalance + amountToRelease);
    }

    function testReleaseFundsERC20() public {
        testFundProjectERC20();

        uint256 projectId = 2;
        uint256 amountToRelease = 20 * 10**18;
        uint256 initialFreelancerBalance = testToken.balanceOf(freelancer1);

        vm.startPrank(deployer); // Called by ProjectManager
        escrow.releaseFunds(projectId, freelancer1, amountToRelease);
        vm.stopPrank();

        assertEq(escrow.projectBalances(projectId, address(testToken)), 30 * 10**18); // 50 - 20 = 30
        assertEq(testToken.balanceOf(freelancer1), initialFreelancerBalance + amountToRelease);
    }

    function testRevertReleaseFundsInsufficient() public {
        testFundProjectETH();

        uint256 projectId = 1;
        uint256 amountToRelease = 6 ether;

        vm.startPrank(deployer);
        vm.expectRevert("Insufficient funds in escrow");
        escrow.releaseFunds(projectId, freelancer1, amountToRelease);
        vm.stopPrank();
    }

    function testRevertReleaseFundsNotProjectManager() public {
        testFundProjectETH();

        uint256 projectId = 1;
        uint256 amountToRelease = 2 ether;

        vm.startPrank(client1);
        vm.expectRevert("Only ProjectManager can call this function");
        escrow.releaseFunds(projectId, freelancer1, amountToRelease);
        vm.stopPrank();
    }

    function testRefundFundsETH() public {
        testFundProjectETH();

        uint256 projectId = 1;
        uint256 amountToRefund = 3 ether;
        uint256 initialClientBalance = client1.balance;

        vm.startPrank(arbitrationCourtMock); // Called by ArbitrationCourt
        escrow.refundFunds(projectId, client1, amountToRefund);
        vm.stopPrank();

        assertEq(escrow.projectBalances(projectId, address(0)), 2 ether); // 5 - 3 = 2
        assertEq(client1.balance, initialClientBalance + amountToRefund);
    }

    function testRefundFundsERC20() public {
        testFundProjectERC20();

        uint256 projectId = 2;
        uint256 amountToRefund = 30 * 10**18;
        uint256 initialClientBalance = testToken.balanceOf(client1);

        vm.startPrank(arbitrationCourtMock); // Called by ArbitrationCourt
        escrow.refundFunds(projectId, client1, amountToRefund);
        vm.stopPrank();

        assertEq(escrow.projectBalances(projectId, address(testToken)), 20 * 10**18); // 50 - 30 = 20
        assertEq(testToken.balanceOf(client1), initialClientBalance + amountToRefund);
    }

    function testRevertRefundFundsInsufficient() public {
        testFundProjectETH();

        uint256 projectId = 1;
        uint256 amountToRefund = 6 ether;

        vm.startPrank(arbitrationCourtMock);
        vm.expectRevert("Insufficient funds in escrow");
        escrow.refundFunds(projectId, client1, amountToRefund);
        vm.stopPrank();
    }

    function testRevertRefundFundsNotArbitrationCourt() public {
        testFundProjectETH();

        uint256 projectId = 1;
        uint256 amountToRefund = 2 ether;

        vm.startPrank(client1);
        vm.expectRevert("Only ArbitrationCourt can call this function");
        escrow.refundFunds(projectId, client1, amountToRefund);
        vm.stopPrank();
    }

    function testSetContractAddresses() public {
        address newProjectManager = makeAddr("newProjectManager");
        address newArbitrationCourt = makeAddr("newArbitrationCourt");
        address newFeeManager = makeAddr("newFeeManager");

        vm.startPrank(deployer);
        escrow.setContractAddresses(newProjectManager, newArbitrationCourt, newFeeManager);
        vm.stopPrank();

        assertEq(address(escrow.projectManager()), newProjectManager);
        assertEq(escrow.arbitrationCourtAddress(), newArbitrationCourt);
        assertEq(escrow.feeManagerAddress(), newFeeManager);
    }
}


