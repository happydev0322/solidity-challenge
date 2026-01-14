// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20 {
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

contract Staking {
    IERC20 public immutable token;
    address public immutable owner;
    
    // Mapping to track staked amounts per user
    mapping(address => uint256) public stakedBalance;
    
    // Mapping to track when user started staking (timestamp)
    mapping(address => uint256) public stakingStartTime;
    
    // Mapping to track if user has redeemed before claiming (forfeits interest)
    mapping(address => bool) public interestForfeited;
    
    // Constants for time calculations
    uint256 private constant ONE_DAY = 1 days;
    uint256 private constant ONE_WEEK = 7 days;
    
    // Reward rates (in basis points: 100 = 1%, 1000 = 10%)
    uint256 private constant RATE_ONE_DAY = 100; // 1%
    uint256 private constant RATE_ONE_WEEK = 1000; // 10%
    
    constructor(address _token) {
        require(_token != address(0), "Invalid token address");
        token = IERC20(_token);
        owner = msg.sender;
    }
    
    // allows users to stake tokens
    function stake(uint256 amount) public {
        require(amount > 0, "Amount must be greater than 0");
        
        address user = msg.sender;
        
        // If user already has a staked balance, transfer accumulated rewards and staked tokens first
        if (stakedBalance[user] > 0) {
            uint256 currentStake = stakedBalance[user];
            uint256 rewards = 0;
            
            // Only calculate rewards if interest hasn't been forfeited
            if (!interestForfeited[user]) {
                rewards = _calculateRewards(user);
            }
            
            // Reset staking state
            stakedBalance[user] = 0;
            stakingStartTime[user] = 0;
            interestForfeited[user] = false;
            
            // Transfer accumulated rewards if any
            if (rewards > 0) {
                require(token.transfer(user, rewards), "Reward transfer failed");
            }
            
            // Transfer staked tokens back
            require(token.transfer(user, currentStake), "Stake transfer failed");
        }
        
        // Transfer new tokens from user to contract
        require(token.transferFrom(user, address(this), amount), "Token transfer failed");
        
        // Update staking state
        stakedBalance[user] = amount;
        stakingStartTime[user] = block.timestamp;
        interestForfeited[user] = false;
    }
    
    // allows users to redeem staked tokens
    function redeem(uint256 amount) public {
        require(amount > 0, "Amount must be greater than 0");
        require(amount <= stakedBalance[msg.sender], "Amount exceeds staked balance");
        
        address user = msg.sender;
        
        // If user redeems before claiming interest, mark interest as forfeited
        if (!interestForfeited[user]) {
            interestForfeited[user] = true;
        }
        
        // Update staked balance
        stakedBalance[user] -= amount;
        
        // If all tokens are redeemed, reset staking timestamp
        if (stakedBalance[user] == 0) {
            stakingStartTime[user] = 0;
        }
        
        // Transfer tokens back to user
        require(token.transfer(user, amount), "Token transfer failed");
    }
    
    // transfers rewards to staker
    function claimInterest() public {
        address user = msg.sender;
        require(stakedBalance[user] > 0, "No staked balance");
        require(!interestForfeited[user], "Interest forfeited due to redemption");
        
        uint256 rewards = _calculateRewards(user);
        require(rewards > 0, "No interest due");
        
        // Reset staking timestamp after claiming (interest is paid, start fresh)
        stakingStartTime[user] = block.timestamp;
        
        // Transfer rewards
        require(token.transfer(user, rewards), "Reward transfer failed");
    }
    
    // returns the accrued interest
    function getAccruedInterest(address user) public view returns (uint256) {
        if (stakedBalance[user] == 0 || interestForfeited[user]) {
            return 0;
        }
        return _calculateRewards(user);
    }
    
    // allows owner to collect all the staked tokens
    function sweep() public {
        require(msg.sender == owner, "Only owner can sweep");
        uint256 balance = token.balanceOf(address(this));
        require(balance > 0, "No tokens to sweep");
        require(token.transfer(owner, balance), "Sweep transfer failed");
    }
    
    // Internal function to calculate rewards based on staking duration
    function _calculateRewards(address user) private view returns (uint256) {
        if (stakedBalance[user] == 0 || stakingStartTime[user] == 0) {
            return 0;
        }
        
        uint256 stakingDuration = block.timestamp - stakingStartTime[user];
        uint256 stakedAmount = stakedBalance[user];
        
        // Less than 1 day: no rewards
        if (stakingDuration < ONE_DAY) {
            return 0;
        }
        
        // More than a week: 10% rewards
        if (stakingDuration >= ONE_WEEK) {
            return (stakedAmount * RATE_ONE_WEEK) / 10000;
        }
        
        // More than 1 day but less than a week: 1% rewards
        return (stakedAmount * RATE_ONE_DAY) / 10000;
    }
}