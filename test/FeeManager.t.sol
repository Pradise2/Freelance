// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../src/FeeManager.sol";
import "../src/Token.sol";

contract FeeManagerTest is Test {
    FeeManager feeManager;
    Token testToken;

    address public deployer;
    address public platformTreasury;
    address public projectManagerMock;

    function setUp() public {
        deployer = makeAddr("deployer");
        platformTreasury = makeAddr("platformTreasury");
        projectManagerMock = makeAddr("projectManagerMock");

        vm.startPrank(deployer);
        feeManager = new FeeManager(platformTreasury);
        testToken = new Token("TestToken", "TST");
        vm.stopPrank();
    }

    function testSetFeePercentage() public {
        uint256 newFee = 500; // 5%
        vm.startPrank(deployer);
        feeManager.setFeePercentage(newFee);
        vm.stopPrank();

        assertEq(feeManager.feePercentage(), newFee);
    }

    function testRevertSetFeePercentageNotOwner() public {
        uint256 newFee = 500;
        vm.startPrank(makeAddr("random"));
        vm.expectRevert("Ownable: caller is not the owner");
        feeManager.setFeePercentage(newFee);
        vm.stopPrank();
    }

    function testRevertSetFeePercentageTooHigh() public {
        uint256 newFee = 10001; // > 100%
        vm.startPrank(deployer);
        vm.expectRevert("Fee percentage cannot exceed 100%");
        feeManager.setFeePercentage(newFee);
        vm.stopPrank();
    }

    function testCollectFeeETH() public {
        uint256 projectId = 1;
        uint256 amount = 1 ether;
        uint256 feePercentage = 1000; // 10%
        uint256 expectedFee = (amount * feePercentage) / 10000;

        vm.startPrank(deployer);
        feeManager.setFeePercentage(feePercentage);
        vm.stopPrank();

        vm.deal(address(feeManager), amount); // Simulate Escrow sending funds to FeeManager
        uint256 initialTreasuryBalance = platformTreasury.balance;

        vm.startPrank(projectManagerMock); // Simulate Escrow calling collectFee
        feeManager.collectFee(projectId, amount, address(0));
        vm.stopPrank();

        assertEq(platformTreasury.balance, initialTreasuryBalance + expectedFee);
    }

    function testCollectFeeERC20() public {
        uint256 projectId = 1;
        uint256 amount = 100 * 10**18; // 100 TST
        uint256 feePercentage = 500; // 5%
        uint256 expectedFee = (amount * feePercentage) / 10000;

        vm.startPrank(deployer);
        feeManager.setFeePercentage(feePercentage);
        testToken.mint(address(feeManager), amount); // Simulate Escrow sending tokens to FeeManager
        vm.stopPrank();

        uint256 initialTreasuryBalance = testToken.balanceOf(platformTreasury);

        vm.startPrank(projectManagerMock); // Simulate Escrow calling collectFee
        feeManager.collectFee(projectId, amount, address(testToken));
        vm.stopPrank();

        assertEq(testToken.balanceOf(platformTreasury), initialTreasuryBalance + expectedFee);
    }

    function testCollectFeeZeroPercentage() public {
        uint256 projectId = 1;
        uint256 amount = 1 ether;

        vm.startPrank(deployer);
        feeManager.setFeePercentage(0);
        vm.stopPrank();

        vm.deal(address(feeManager), amount);
        uint256 initialTreasuryBalance = platformTreasury.balance;

        vm.startPrank(projectManagerMock);
        feeManager.collectFee(projectId, amount, address(0));
        vm.stopPrank();

        assertEq(platformTreasury.balance, initialTreasuryBalance); // No fee collected
    }

    function testGetPlatformTreasury() public {
        assertEq(feeManager.getPlatformTreasury(), platformTreasury);
    }

    function testSetPlatformTreasury() public {
        address newTreasury = makeAddr("newTreasury");
        vm.startPrank(deployer);
        feeManager.setPlatformTreasury(newTreasury);
        vm.stopPrank();

        assertEq(feeManager.platformTreasury(), newTreasury);
    }

    function testRevertSetPlatformTreasuryNotOwner() public {
        address newTreasury = makeAddr("newTreasury");
        vm.startPrank(makeAddr("random"));
        vm.expectRevert("Ownable: caller is not the owner");
        feeManager.setPlatformTreasury(newTreasury);
        vm.stopPrank();
    }

    function testRevertSetPlatformTreasuryInvalidAddress() public {
        vm.startPrank(deployer);
        vm.expectRevert("Invalid treasury address");
        feeManager.setPlatformTreasury(address(0));
        vm.stopPrank();
    }
}


