// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../src/Token.sol";

contract TokenTest is Test {
    Token token;

    address public deployer;
    address public user1;
    address public user2;

    function setUp() public {
        deployer = makeAddr("deployer");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");

        vm.startPrank(deployer);
        token = new Token("FreelanceToken", "FLT");
        vm.stopPrank();
    }

    function testNameAndSymbol() public {
        assertEq(token.name(), "FreelanceToken");
        assertEq(token.symbol(), "FLT");
    }

    function testDecimals() public {
        assertEq(token.decimals(), 18);
    }

    function testTotalSupply() public {
        assertEq(token.totalSupply(), 0);
    }

    function testMint() public {
        uint256 amount = 100 * 10**18;
        vm.startPrank(deployer);
        token.mint(user1, amount);
        vm.stopPrank();

        assertEq(token.balanceOf(user1), amount);
        assertEq(token.totalSupply(), amount);
    }

    function testRevertMintNotOwner() public {
        uint256 amount = 100 * 10**18;
        vm.startPrank(user1);
        vm.expectRevert("Ownable: caller is not the owner");
        token.mint(user1, amount);
        vm.stopPrank();
    }

    function testBurn() public {
        uint256 amount = 100 * 10**18;
        vm.startPrank(deployer);
        token.mint(user1, amount);
        vm.stopPrank();

        vm.startPrank(user1);
        token.burn(amount);
        vm.stopPrank();

        assertEq(token.balanceOf(user1), 0);
        assertEq(token.totalSupply(), 0);
    }

    function testRevertBurnInsufficientBalance() public {
        uint256 amount = 100 * 10**18;
        vm.startPrank(user1);
        vm.expectRevert("ERC20: burn amount exceeds balance");
        token.burn(amount);
        vm.stopPrank();
    }

    function testTransfer() public {
        uint256 amount = 100 * 10**18;
        vm.startPrank(deployer);
        token.mint(user1, amount);
        vm.stopPrank();

        vm.startPrank(user1);
        token.transfer(user2, 50 * 10**18);
        vm.stopPrank();

        assertEq(token.balanceOf(user1), 50 * 10**18);
        assertEq(token.balanceOf(user2), 50 * 10**18);
    }

    function testApproveAndTransferFrom() public {
        uint256 amount = 100 * 10**18;
        vm.startPrank(deployer);
        token.mint(user1, amount);
        vm.stopPrank();

        vm.startPrank(user1);
        token.approve(user2, 50 * 10**18);
        vm.stopPrank();

        assertEq(token.allowance(user1, user2), 50 * 10**18);

        vm.startPrank(user2);
        token.transferFrom(user1, deployer, 30 * 10**18);
        vm.stopPrank();

        assertEq(token.balanceOf(user1), 70 * 10**18);
        assertEq(token.balanceOf(deployer), 30 * 10**18);
        assertEq(token.allowance(user1, user2), 20 * 10**18);
    }
}


