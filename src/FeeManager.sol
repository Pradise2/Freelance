// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title FeeManager
 * @dev Manages platform fees, their collection, and distribution
 */
contract FeeManager is Ownable {
    using SafeERC20 for IERC20;

    uint256 public feePercentage; // Stored as basis points (e.g., 100 for 1%)
    address public platformTreasury;

    // Events
    event FeePercentageUpdated(
        uint256 oldFeePercentage,
        uint256 newFeePercentage,
        uint256 timestamp
    );

    event FeeCollected(
        uint256 indexed projectId,
        address indexed tokenAddress,
        uint256 amount,
        uint256 timestamp
    );

    constructor(address _platformTreasury) Ownable(msg.sender) {
        require(_platformTreasury != address(0), "Invalid treasury address");
        platformTreasury = _platformTreasury;
        feePercentage = 0; // Initialize with 0% fee
    }

    /**
     * @dev Set the platform fee percentage
     * Only callable by the owner (or governance contract)
     * @param _newFeePercentage New fee percentage in basis points (e.g., 100 for 1%)
     */
    function setFeePercentage(uint256 _newFeePercentage) external onlyOwner {
        require(_newFeePercentage <= 10000, "Fee percentage cannot exceed 100%"); // Max 100% (10000 basis points)
        emit FeePercentageUpdated(feePercentage, _newFeePercentage, block.timestamp);
        feePercentage = _newFeePercentage;
    }

    /**
     * @dev Collect fee from a payment
     * Called by Escrow.sol before releasing funds to freelancer
     * @param _projectId ID of the project
     * @param _amount The amount from which fee is to be collected
     * @param _tokenAddress Address of the token (address(0) for ETH)
     */
    function collectFee(uint256 _projectId, uint256 _amount, address _tokenAddress) external returns (uint256 feeAmount) {
        // Only Escrow contract should call this
        // In a real system, we'd add a modifier to ensure msg.sender is the Escrow contract
        // For now, we'll assume proper integration.

        if (feePercentage == 0) {
            return 0; // No fee to collect
        }

        feeAmount = (_amount * feePercentage) / 10000;
        require(feeAmount <= _amount, "Calculated fee exceeds amount");

        if (feeAmount > 0) {
            if (_tokenAddress == address(0)) { // ETH
                // Transfer ETH directly to treasury
                payable(platformTreasury).transfer(feeAmount);
            } else { // ERC20
                // Transfer ERC20 tokens directly to treasury
                IERC20(_tokenAddress).safeTransfer(platformTreasury, feeAmount);
            }
            emit FeeCollected(_projectId, _tokenAddress, feeAmount, block.timestamp);
        }
    }

    /**
     * @dev Get the current platform treasury address
     * @return Address of the platform treasury
     */
    function getPlatformTreasury() external view returns (address) {
        return platformTreasury;
    }

    /**
     * @dev Update platform treasury address (only owner)
     * @param _newPlatformTreasury New address for the platform treasury
     */
    function setPlatformTreasury(address _newPlatformTreasury) external onlyOwner {
        require(_newPlatformTreasury != address(0), "Invalid treasury address");
        platformTreasury = _newPlatformTreasury;
    }
}

