// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

interface IProjectManager {
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

interface IArbitrationCourt {
    // Function to be called by ArbitrationCourt to release or refund funds
    // This interface is for clarity, actual call will be direct or via a helper
}

/**
 * @title Escrow
 * @dev Securely holds funds for projects until conditions are met
 * Facilitates trustless transactions between clients and freelancers
 */
contract Escrow is Ownable {
    using SafeERC20 for IERC20;

    // Project balances: projectId => tokenAddress => amount
    mapping(uint256 => mapping(address => uint256)) public projectBalances;
    // Project token type: projectId => tokenAddress (to track which token is used for a project)
    mapping(uint256 => address) public projectToken;

    IProjectManager public projectManager;
    address public arbitrationCourtAddress;
    address public feeManagerAddress;

    // Events
    event ProjectFunded(
        uint256 indexed projectId,
        address indexed client,
        address indexed tokenAddress,
        uint256 amount,
        uint256 timestamp
    );

    event FundsReleased(
        uint256 indexed projectId,
        address indexed freelancer,
        address indexed tokenAddress,
        uint256 amount,
        uint256 timestamp
    );

    event FundsRefunded(
        uint256 indexed projectId,
        address indexed client,
        address indexed tokenAddress,
        uint256 amount,
        uint256 timestamp
    );

    // Modifiers
    modifier onlyProjectManager() {
        require(msg.sender == address(projectManager), "Only ProjectManager can call this function");
        _;
    }

    modifier onlyArbitrationCourt() {
        require(msg.sender == arbitrationCourtAddress, "Only ArbitrationCourt can call this function");
        _;
    }

    constructor(
        address _projectManagerAddress,
        address _arbitrationCourtAddress,
        address _feeManagerAddress
    ) Ownable(msg.sender) {
        require(_projectManagerAddress != address(0), "Invalid ProjectManager address");
        require(_arbitrationCourtAddress != address(0), "Invalid ArbitrationCourt address");
        require(_feeManagerAddress != address(0), "Invalid FeeManager address");
        projectManager = IProjectManager(_projectManagerAddress);
        arbitrationCourtAddress = _arbitrationCourtAddress;
        feeManagerAddress = _feeManagerAddress;
    }

    /**
     * @dev Deposit funds for a project (ETH)
     * @param _projectId ID of the project to fund
     */
    function fundProjectETH(uint256 _projectId) external payable {
        require(msg.value > 0, "Amount must be greater than zero");
        
        (, address client,, uint256 agreedBudget,,,,) = projectManager.getProjectDetails(_projectId);
        require(msg.sender == client, "Only project client can fund");
        require(projectToken[_projectId] == address(0) || projectToken[_projectId] == address(0x0), "Project already funded with a different token");

        projectBalances[_projectId][address(0)] += msg.value;
        projectToken[_projectId] = address(0); // Mark as ETH funded

        emit ProjectFunded(_projectId, msg.sender, address(0), msg.value, block.timestamp);
    }

    /**
     * @dev Deposit funds for a project (ERC20)
     * @param _projectId ID of the project to fund
     * @param _tokenAddress Address of the ERC20 token
     * @param _amount Amount of ERC20 tokens to deposit
     */
    function fundProjectERC20(uint256 _projectId, address _tokenAddress, uint256 _amount) external {
        require(_tokenAddress != address(0), "Invalid token address");
        require(_amount > 0, "Amount must be greater than zero");

        (, address client,, uint256 agreedBudget,,,,) = projectManager.getProjectDetails(_projectId);
        require(msg.sender == client, "Only project client can fund");
        require(projectToken[_projectId] == address(0) || projectToken[_projectId] == _tokenAddress, "Project already funded with a different token");

        IERC20(_tokenAddress).safeTransferFrom(msg.sender, address(this), _amount);
        projectBalances[_projectId][_tokenAddress] += _amount;
        projectToken[_projectId] = _tokenAddress;

        emit ProjectFunded(_projectId, msg.sender, _tokenAddress, _amount, block.timestamp);
    }

    /**
     * @dev Release funds to freelancer (called by ProjectManager or ArbitrationCourt)
     * @param _projectId ID of the project
     * @param _freelancer Address of the freelancer
     * @param _amount Amount to release
     */
    function releaseFunds(uint256 _projectId, address _freelancer, uint256 _amount) 
        external 
        onlyProjectManager 
    {
        require(_freelancer != address(0), "Invalid freelancer address");
        require(_amount > 0, "Amount must be greater than zero");

        address tokenAddress = projectToken[_projectId];
        require(projectBalances[_projectId][tokenAddress] >= _amount, "Insufficient funds in escrow");

        projectBalances[_projectId][tokenAddress] -= _amount;

        // Collect fee before transferring to freelancer
        if (feeManagerAddress != address(0)) {
            IFeeManager(feeManagerAddress).collectFee(_projectId, _amount, tokenAddress);
        }

        if (tokenAddress == address(0)) { // ETH
            payable(_freelancer).transfer(_amount);
        } else { // ERC20
            IERC20(tokenAddress).safeTransfer(_freelancer, _amount);
        }

        emit FundsReleased(_projectId, _freelancer, tokenAddress, _amount, block.timestamp);
    }

    /**
     * @dev Refund funds to client (called by ArbitrationCourt)
     * @param _projectId ID of the project
     * @param _client Address of the client
     * @param _amount Amount to refund
     */
    function refundFunds(uint256 _projectId, address _client, uint256 _amount) 
        external 
        onlyArbitrationCourt 
    {
        require(_client != address(0), "Invalid client address");
        require(_amount > 0, "Amount must be greater than zero");

        address tokenAddress = projectToken[_projectId];
        require(projectBalances[_projectId][tokenAddress] >= _amount, "Insufficient funds in escrow");

        projectBalances[_projectId][tokenAddress] -= _amount;

        if (tokenAddress == address(0)) { // ETH
            payable(_client).transfer(_amount);
        } else { // ERC20
            IERC20(tokenAddress).safeTransfer(_client, _amount);
        }

        emit FundsRefunded(_projectId, _client, tokenAddress, _amount, block.timestamp);
    }

    /**
     * @dev Get current balance for a project in a specific token
     * @param _projectId ID of the project
     * @param _tokenAddress Address of the token (address(0) for ETH)
     * @return Current balance
     */
    function getEscrowBalance(uint256 _projectId, address _tokenAddress) 
        external 
        view 
        returns (uint256) 
    {
        return projectBalances[_projectId][_tokenAddress];
    }

    /**
     * @dev Get the token address used for a project
     * @param _projectId ID of the project
     * @return Token address (address(0) for ETH)
     */
    function getProjectToken(uint256 _projectId) 
        external 
        view 
        returns (address) 
    {
        return projectToken[_projectId];
    }

    /**
     * @dev Update contract addresses (only owner)
     */
    function setContractAddresses(
        address _projectManagerAddress,
        address _arbitrationCourtAddress,
        address _feeManagerAddress
    ) 
        external 
        onlyOwner 
    {
        if (_projectManagerAddress != address(0)) {
            projectManager = IProjectManager(_projectManagerAddress);
        }
        if (_arbitrationCourtAddress != address(0)) {
            arbitrationCourtAddress = _arbitrationCourtAddress;
        }
        if (_feeManagerAddress != address(0)) {
            feeManagerAddress = _feeManagerAddress;
        }
    }
}

interface IFeeManager {
    function collectFee(uint256 _projectId, uint256 _amount, address _tokenAddress) external;
}

