// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title OracleInterface
 * @dev Provides external data feeds for the freelance platform
 * Integrates with price oracles, reputation data, and other external information
 */
contract OracleInterface is Ownable {
    // Oracle data structure
    struct OracleData {
        uint256 value;
        uint256 timestamp;
        bool isValid;
    }

    // State variables
    mapping(string => OracleData) public dataFeeds;
    mapping(address => bool) public authorizedOracles;
    
    uint256 public dataValidityPeriod = 1 hours; // Data is valid for 1 hour

    // Events
    event DataUpdated(
        string indexed feedName,
        uint256 value,
        uint256 timestamp,
        address indexed oracle
    );

    event OracleAuthorized(
        address indexed oracle,
        uint256 timestamp
    );

    event OracleRevoked(
        address indexed oracle,
        uint256 timestamp
    );

    // Modifiers
    modifier onlyAuthorizedOracle() {
        require(authorizedOracles[msg.sender], "Not an authorized oracle");
        _;
    }

    constructor() Ownable(msg.sender) {}

    /**
     * @dev Authorize an oracle address
     * @param _oracle Address of the oracle to authorize
     */
    function authorizeOracle(address _oracle) external onlyOwner {
        require(_oracle != address(0), "Invalid oracle address");
        authorizedOracles[_oracle] = true;
        emit OracleAuthorized(_oracle, block.timestamp);
    }

    /**
     * @dev Revoke oracle authorization
     * @param _oracle Address of the oracle to revoke
     */
    function revokeOracle(address _oracle) external onlyOwner {
        require(authorizedOracles[_oracle], "Oracle not authorized");
        authorizedOracles[_oracle] = false;
        emit OracleRevoked(_oracle, block.timestamp);
    }

    /**
     * @dev Update data feed (only authorized oracles)
     * @param _feedName Name of the data feed
     * @param _value New value for the feed
     */
    function updateDataFeed(string calldata _feedName, uint256 _value) 
        external 
        onlyAuthorizedOracle 
    {
        require(bytes(_feedName).length > 0, "Feed name cannot be empty");
        
        dataFeeds[_feedName] = OracleData({
            value: _value,
            timestamp: block.timestamp,
            isValid: true
        });

        emit DataUpdated(_feedName, _value, block.timestamp, msg.sender);
    }

    /**
     * @dev Get data from a feed
     * @param _feedName Name of the data feed
     * @return value Current value
     * @return timestamp When the data was last updated
     * @return isValid Whether the data is still valid
     */
    function getDataFeed(string calldata _feedName) 
        external 
        view 
        returns (uint256 value, uint256 timestamp, bool isValid) 
    {
        OracleData memory data = dataFeeds[_feedName];
        bool stillValid = data.isValid && (block.timestamp - data.timestamp <= dataValidityPeriod);
        
        return (data.value, data.timestamp, stillValid);
    }

    /**
     * @dev Get latest valid price for ETH/USD (example feed)
     * @return price Latest ETH price in USD (with 8 decimals)
     */
    function getETHUSDPrice() external view returns (uint256 price) {
        (uint256 value, , bool isValid) = this.getDataFeed("ETH/USD");
        require(isValid, "ETH/USD price data is stale or invalid");
        return value;
    }

    /**
     * @dev Set data validity period (only owner)
     * @param _newPeriod New validity period in seconds
     */
    function setDataValidityPeriod(uint256 _newPeriod) external onlyOwner {
        require(_newPeriod > 0, "Validity period must be greater than zero");
        dataValidityPeriod = _newPeriod;
    }

    /**
     * @dev Batch update multiple data feeds (only authorized oracles)
     * @param _feedNames Array of feed names
     * @param _values Array of corresponding values
     */
    function batchUpdateDataFeeds(
        string[] calldata _feedNames,
        uint256[] calldata _values
    ) 
        external 
        onlyAuthorizedOracle 
    {
        require(_feedNames.length == _values.length, "Arrays length mismatch");
        require(_feedNames.length > 0, "Empty arrays");

        for (uint256 i = 0; i < _feedNames.length; i++) {
            require(bytes(_feedNames[i]).length > 0, "Feed name cannot be empty");
            
            dataFeeds[_feedNames[i]] = OracleData({
                value: _values[i],
                timestamp: block.timestamp,
                isValid: true
            });

            emit DataUpdated(_feedNames[i], _values[i], block.timestamp, msg.sender);
        }
    }
}

