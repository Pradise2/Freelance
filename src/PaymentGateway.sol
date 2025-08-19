// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

interface IEscrow {
    function fundProjectETH(uint256 _projectId) external payable;
    function fundProjectERC20(uint256 _projectId, address _tokenAddress, uint256 _amount) external;
}

interface IFeeManager {
    function getPlatformTreasury() external view returns (address);
}

/**
 * @title PaymentGateway
 * @dev Facilitates various cryptocurrency payments on the platform
 * Handles deposits of ETH and ERC20 tokens to the Escrow contract
 */
contract PaymentGateway is Ownable {
    using SafeERC20 for IERC20;

    IEscrow public escrow;
    IFeeManager public feeManager;

    // Events
    event ETHDeposited(
        address indexed client,
        uint256 indexed projectId,
        uint256 amount,
        uint256 timestamp
    );

    event ERC20Deposited(
        address indexed client,
        address indexed tokenAddress,
        uint256 indexed projectId,
        uint256 amount,
        uint256 timestamp
    );

    event ETHWithdrawn(
        address indexed to,
        uint256 amount,
        uint256 timestamp
    );

    event ERC20Withdrawn(
        address indexed tokenAddress,
        address indexed to,
        uint256 amount,
        uint256 timestamp
    );

    constructor(address _escrowAddress, address _feeManagerAddress) Ownable(msg.sender) {
        require(_escrowAddress != address(0), "Invalid Escrow address");
        require(_feeManagerAddress != address(0), "Invalid FeeManager address");
        escrow = IEscrow(_escrowAddress);
        feeManager = IFeeManager(_feeManagerAddress);
    }

    /**
     * @dev Deposit native blockchain currency (ETH) for a project
     * @param _projectId ID of the project to fund
     */
    function depositETH(uint256 _projectId) external payable {
        require(msg.value > 0, "Amount must be greater than zero");
        escrow.fundProjectETH{value: msg.value}(_projectId);
        emit ETHDeposited(msg.sender, _projectId, msg.value, block.timestamp);
    }

    /**
     * @dev Deposit ERC20 tokens for a project
     * @param _projectId ID of the project to fund
     * @param _tokenAddress Address of the ERC20 token
     * @param _amount Amount of ERC20 tokens to deposit
     */
    function depositERC20(uint256 _projectId, address _tokenAddress, uint256 _amount) external {
        require(_tokenAddress != address(0), "Invalid token address");
        require(_amount > 0, "Amount must be greater than zero");
        
        // The user must have approved this contract to spend their tokens beforehand
        IERC20(_tokenAddress).safeTransferFrom(msg.sender, address(escrow), _amount);
        escrow.fundProjectERC20(_projectId, _tokenAddress, _amount);
        emit ERC20Deposited(msg.sender, _tokenAddress, _projectId, _amount, block.timestamp);
    }

    /**
     * @dev Withdraw native currency (ETH) from this contract's balance
     * Only callable by owner or authorized contracts (e.g., FeeManager for treasury)
     * @param _to Address to send ETH to
     * @param _amount Amount of ETH to withdraw
     */
    function withdrawETH(address payable _to, uint256 _amount) external onlyOwner {
        require(_to != address(0), "Invalid recipient address");
        require(_amount > 0, "Amount must be greater than zero");
        require(address(this).balance >= _amount, "Insufficient ETH balance");
        
        _to.transfer(_amount);
        emit ETHWithdrawn(_to, _amount, block.timestamp);
    }

    /**
     * @dev Withdraw ERC20 tokens from this contract's balance
     * Only callable by owner or authorized contracts
     * @param _tokenAddress Address of the ERC20 token
     * @param _to Address to send tokens to
     * @param _amount Amount of tokens to withdraw
     */
    function withdrawERC20(address _tokenAddress, address _to, uint256 _amount) external onlyOwner {
        require(_tokenAddress != address(0), "Invalid token address");
        require(_to != address(0), "Invalid recipient address");
        require(_amount > 0, "Amount must be greater than zero");
        
        IERC20(_tokenAddress).safeTransfer(_to, _amount);
        emit ERC20Withdrawn(_tokenAddress, _to, _amount, block.timestamp);
    }

    /**
     * @dev Update contract addresses (only owner)
     */
    function setContractAddresses(
        address _escrowAddress,
        address _feeManagerAddress
    ) 
        external 
        onlyOwner 
    {
        if (_escrowAddress != address(0)) {
            escrow = IEscrow(_escrowAddress);
        }
        if (_feeManagerAddress != address(0)) {
            feeManager = IFeeManager(_feeManagerAddress);
        }
    }
}

