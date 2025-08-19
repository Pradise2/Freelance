// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../src/OracleInterface.sol";

contract OracleInterfaceTest is Test {
    OracleInterface oracleInterface;

    address public deployer;
    address public oracle1;
    address public oracle2;
    address public nonOracle;

    function setUp() public {
        deployer = makeAddr("deployer");
        oracle1 = makeAddr("oracle1");
        oracle2 = makeAddr("oracle2");
        nonOracle = makeAddr("nonOracle");

        vm.startPrank(deployer);
        oracleInterface = new OracleInterface();
        oracleInterface.authorizeOracle(oracle1);
        vm.stopPrank();
    }

    function testAuthorizeOracle() public {
        vm.startPrank(deployer);
        oracleInterface.authorizeOracle(oracle2);
        vm.stopPrank();

        assertTrue(oracleInterface.authorizedOracles(oracle2));
    }

    function testRevertAuthorizeOracleNotOwner() public {
        vm.startPrank(nonOracle);
        vm.expectRevert("Ownable: caller is not the owner");
        oracleInterface.authorizeOracle(oracle2);
        vm.stopPrank();
    }

    function testRevertAuthorizeOracleInvalidAddress() public {
        vm.startPrank(deployer);
        vm.expectRevert("Invalid oracle address");
        oracleInterface.authorizeOracle(address(0));
        vm.stopPrank();
    }

    function testRevokeOracle() public {
        vm.startPrank(deployer);
        oracleInterface.revokeOracle(oracle1);
        vm.stopPrank();

        assertFalse(oracleInterface.authorizedOracles(oracle1));
    }

    function testRevertRevokeOracleNotOwner() public {
        vm.startPrank(nonOracle);
        vm.expectRevert("Ownable: caller is not the owner");
        oracleInterface.revokeOracle(oracle1);
        vm.stopPrank();
    }

    function testRevertRevokeOracleNotAuthorized() public {
        vm.startPrank(deployer);
        vm.expectRevert("Oracle not authorized");
        oracleInterface.revokeOracle(nonOracle);
        vm.stopPrank();
    }

    function testUpdateDataFeed() public {
        string memory feedName = "ETH/USD";
        uint256 value = 3000 * 10**8; // 3000 USD with 8 decimals

        vm.startPrank(oracle1);
        oracleInterface.updateDataFeed(feedName, value);
        vm.stopPrank();

        (uint256 retrievedValue, uint256 timestamp, bool isValid) = oracleInterface.getDataFeed(feedName);
        assertEq(retrievedValue, value);
        assertTrue(timestamp > 0);
        assertTrue(isValid);
    }

    function testRevertUpdateDataFeedNotAuthorized() public {
        string memory feedName = "ETH/USD";
        uint256 value = 3000 * 10**8;

        vm.startPrank(nonOracle);
        vm.expectRevert("Not an authorized oracle");
        oracleInterface.updateDataFeed(feedName, value);
        vm.stopPrank();
    }

    function testRevertUpdateDataFeedEmptyName() public {
        uint256 value = 3000 * 10**8;

        vm.startPrank(oracle1);
        vm.expectRevert("Feed name cannot be empty");
        oracleInterface.updateDataFeed("", value);
        vm.stopPrank();
    }

    function testGetDataFeedStale() public {
        string memory feedName = "ETH/USD";
        uint256 value = 3000 * 10**8;

        vm.startPrank(oracle1);
        oracleInterface.updateDataFeed(feedName, value);
        vm.stopPrank();

        // Fast forward time to make data stale
        vm.warp(block.timestamp + 1 hours + 1);

        (uint256 retrievedValue, uint256 timestamp, bool isValid) = oracleInterface.getDataFeed(feedName);
        assertEq(retrievedValue, value);
        assertTrue(timestamp > 0);
        assertFalse(isValid);
    }

    function testGetETHUSDPrice() public {
        string memory feedName = "ETH/USD";
        uint256 value = 3000 * 10**8;

        vm.startPrank(oracle1);
        oracleInterface.updateDataFeed(feedName, value);
        vm.stopPrank();

        assertEq(oracleInterface.getETHUSDPrice(), value);
    }

    function testRevertGetETHUSDPriceStale() public {
        string memory feedName = "ETH/USD";
        uint256 value = 3000 * 10**8;

        vm.startPrank(oracle1);
        oracleInterface.updateDataFeed(feedName, value);
        vm.stopPrank();

        // Fast forward time to make data stale
        vm.warp(block.timestamp + 1 hours + 1);

        vm.expectRevert("ETH/USD price data is stale or invalid");
        oracleInterface.getETHUSDPrice();
    }

    function testSetDataValidityPeriod() public {
        uint256 newPeriod = 2 hours;
        vm.startPrank(deployer);
        oracleInterface.setDataValidityPeriod(newPeriod);
        vm.stopPrank();

        assertEq(oracleInterface.dataValidityPeriod(), newPeriod);
    }

    function testRevertSetDataValidityPeriodNotOwner() public {
        uint256 newPeriod = 2 hours;
        vm.startPrank(nonOracle);
        vm.expectRevert("Ownable: caller is not the owner");
        oracleInterface.setDataValidityPeriod(newPeriod);
        vm.stopPrank();
    }

    function testRevertSetDataValidityPeriodZero() public {
        vm.startPrank(deployer);
        vm.expectRevert("Validity period must be greater than zero");
        oracleInterface.setDataValidityPeriod(0);
        vm.stopPrank();
    }

    function testBatchUpdateDataFeeds() public {
        string[] memory feedNames = new string[](2);
        feedNames[0] = "BTC/USD";
        feedNames[1] = "LINK/USD";

        uint256[] memory values = new uint256[](2);
        values[0] = 60000 * 10**8;
        values[1] = 15 * 10**8;

        vm.startPrank(oracle1);
        oracleInterface.batchUpdateDataFeeds(feedNames, values);
        vm.stopPrank();

        (uint256 btcValue, , bool btcValid) = oracleInterface.getDataFeed("BTC/USD");
        assertEq(btcValue, 60000 * 10**8);
        assertTrue(btcValid);

        (uint256 linkValue, , bool linkValid) = oracleInterface.getDataFeed("LINK/USD");
        assertEq(linkValue, 15 * 10**8);
        assertTrue(linkValid);
    }

    function testRevertBatchUpdateDataFeedsMismatch() public {
        string[] memory feedNames = new string[](1);
        feedNames[0] = "BTC/USD";

        uint256[] memory values = new uint256[](2);
        values[0] = 60000 * 10**8;
        values[1] = 15 * 10**8;

        vm.startPrank(oracle1);
        vm.expectRevert("Arrays length mismatch");
        oracleInterface.batchUpdateDataFeeds(feedNames, values);
        vm.stopPrank();
    }

    function testRevertBatchUpdateDataFeedsEmpty() public {
        string[] memory feedNames = new string[](0);
        uint256[] memory values = new uint256[](0);

        vm.startPrank(oracle1);
        vm.expectRevert("Empty arrays");
        oracleInterface.batchUpdateDataFeeds(feedNames, values);
        vm.stopPrank();
    }
}


