// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title FreelanceCoin (FLC)
 * @dev ERC-20 token for the decentralized freelance platform
 * Can be used for platform fees, staking, or governance
 */
contract Token is ERC20, Ownable {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) Ownable(msg.sender) {
        // Mint initial supply to the deployer or a designated treasury
        _mint(msg.sender, 100000000 * (10 ** decimals())); // Example: 100 million tokens
    }

    /**
     * @dev Function to mint new tokens (only owner)
     * @param to The address that will receive the minted tokens.
     * @param amount The amount of tokens to mint.
     */
    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }

    /**
     * @dev Function to burn tokens (only owner)
     * @param amount The amount of tokens to burn.
     */
    function burn(uint256 amount) external onlyOwner {
        _burn(msg.sender, amount);
    }
}

