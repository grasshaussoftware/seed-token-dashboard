// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Import OpenZeppelin Contracts for ERC20 standard and security
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/**
 * @title Seed Token Contract
 * @dev Implements a fundraising token with multiple features such as
 * fundraising stages, staking, governance, team vesting, anti-whale measures,
 * and more.
 */
contract Seed is ERC20, Ownable, ReentrancyGuard {
    // ==============================
    // Constants and Immutable Variables
    // ==============================

    // Total supply of tokens (100 million SEED)
    uint256 public constant TOTAL_SUPPLY = 100_000_000 * 10**18;

    // Token price per SEED in wei (0.001 ETH)
    uint256 public constant TOKEN_PRICE = 0.001 ether;

    // Soft cap and hard cap for fundraising
    uint256 public constant SOFT_CAP = 100_000 * 10**18; // 100,000 SEED
    uint256 public constant HARD_CAP = 500_000 * 10**18; // 500,000 SEED

    // Maximum purchase limit per address (Anti-Whale Measure)
    uint256 public constant MAX_PURCHASE_LIMIT = 5_000 * 10**18; // 5,000 SEED

    // Reward rate for staking (10% annual)
    uint256 public constant REWARD_RATE = 10; // 10%

    // Duration for team vesting (6 months)
    uint256 public constant TEAM_VESTING_DURATION = 180 days;

    // Duration for voting on proposals (7 days)
    uint256 public constant VOTING_DURATION = 7 days;

    // ==============================
    // Enums and Structs
    // ==============================

    // Sale stages enumeration
    enum SaleStage { PrivateSale, PreSale, PublicSale, Ended }
    SaleStage public currentStage;

    // Stake information
    struct StakeInfo {
        uint256 amount;
        uint256 timestamp;
    }

    // Governance proposal structure
    struct Proposal {
        string description;
        uint256 votesFor;
        uint256 votesAgainst;
        bool executed;
        uint256 endTime;
    }

    // ==============================
    // State Variables
    // ==============================

    // Token allocations
    uint256 public teamTokens = TOTAL_SUPPLY * 20 / 100; // 20% for team
    uint256 public saleTokens = TOTAL_SUPPLY * 50 / 100; // 50% for sale
    uint256 public ecosystemTokens = TOTAL_SUPPLY * 20 / 100; // 20% for ecosystem
    uint256 public liquidityTokens = TOTAL_SUPPLY * 10 / 100; // 10% for liquidity

    // Team vesting
    uint256 public teamUnlockTime;
    address public teamWallet;
    bool public teamTokensClaimed;

    // Fundraising tracking
    uint256 public totalFundsRaised;
    bool public softCapReached;
    mapping(address => uint256) public contributions;

    // Staking
    mapping(address => StakeInfo) public stakes;

    // Governance
    Proposal[] public proposals;
    mapping(uint256 => mapping(address => bool)) public hasVoted;

    // Liquidity Pool
    address public liquidityPoolAddress;
    bool public liquidityLocked;

    // Referral Program
    mapping(address => address) public referrers; // User => Referrer
    uint256 public constant REFERRAL_BONUS = 5; // 5% bonus

    // ==============================
    // Events
    // ==============================

    event TokensPurchased(address indexed buyer, uint256 amount);
    event RefundIssued(address indexed recipient, uint256 amount);
    event SoftCapReached();
    event TeamTokensClaimed();
    event Staked(address indexed staker, uint256 amount);
    event Unstaked(address indexed staker, uint256 amount, uint256 reward);
    event ProposalCreated(uint256 indexed proposalId, string description);
    event Voted(uint256 indexed proposalId, address indexed voter, bool inFavor);
    event LiquidityLocked(address liquidityPoolAddress);
    event TokensBurned(address indexed burner, uint256 amount);
    event ReferralSet(address indexed user, address indexed referrer);

    // ==============================
    // Constructor
    // ==============================

    /**
     * @dev Initializes the contract, mints tokens to the contract address, and sets up team vesting.
     * @param _teamWallet Address of the team's wallet.
     */
    constructor(address _teamWallet)
        ERC20("Seed Token", "SEED")
        Ownable(msg.sender) // Pass the owner address to the Ownable constructor
    {
        require(_teamWallet != address(0), "Team wallet cannot be zero address");
        teamWallet = _teamWallet;
        teamUnlockTime = block.timestamp + TEAM_VESTING_DURATION;

        // Mint tokens to contract for sale, ecosystem, and liquidity
        _mint(address(this), saleTokens + ecosystemTokens + liquidityTokens);

        // Set initial sale stage
        currentStage = SaleStage.PrivateSale;
    }

    // ==============================
    // Fundraising Functions
    // ==============================

    /**
     * @dev Allows users to buy tokens during the fundraising stages.
     * @param referrer Address of the referrer (optional).
     */
    function buyTokens(address referrer) external payable nonReentrant {
        require(currentStage != SaleStage.Ended, "Sale has ended");
        require(msg.value > 0, "Must send ETH to buy tokens");

        // Calculate number of tokens to buy
        uint256 tokensToBuy = (msg.value * 10**18) / TOKEN_PRICE;

        // Apply referral bonus if applicable
        if (referrer != address(0) && referrer != msg.sender) {
            uint256 bonusTokens = (tokensToBuy * REFERRAL_BONUS) / 100;
            tokensToBuy += bonusTokens;

            // Record the referrer
            referrers[msg.sender] = referrer;
            emit ReferralSet(msg.sender, referrer);
        }

        // Anti-Whale: Check purchase limits
        require(
            balanceOf(msg.sender) + tokensToBuy <= MAX_PURCHASE_LIMIT,
            "Exceeds max purchase limit"
        );

        // Check hard cap
        require(totalSupply() + tokensToBuy <= saleTokens + ecosystemTokens + liquidityTokens, "Exceeds token allocation");

        // Update contributions and total funds raised
        contributions[msg.sender] += msg.value;
        totalFundsRaised += msg.value;

        // Transfer tokens to buyer
        _transfer(address(this), msg.sender, tokensToBuy);
        emit TokensPurchased(msg.sender, tokensToBuy);

        // Check if soft cap is reached
        if (totalFundsRaised >= (SOFT_CAP * TOKEN_PRICE / 10**18) && !softCapReached) {
            softCapReached = true;
            emit SoftCapReached();
        }
    }

    /**
     * @dev Allows the owner to withdraw funds after soft cap is reached.
     */
    function withdrawFunds() external onlyOwner {
        require(softCapReached, "Soft cap not reached");
        payable(owner()).transfer(address(this).balance);
    }

    /**
     * @dev Allows contributors to get a refund if soft cap is not met.
     */
    function refund() external nonReentrant {
        require(!softCapReached, "Soft cap reached, refunds not available");
        uint256 contributedAmount = contributions[msg.sender];
        require(contributedAmount > 0, "No contributions to refund");

        // Reset contribution
        contributions[msg.sender] = 0;

        // Transfer tokens back to contract
        uint256 tokenBalance = balanceOf(msg.sender);
        _transfer(msg.sender, address(this), tokenBalance);

        // Refund ETH
        payable(msg.sender).transfer(contributedAmount);
        emit RefundIssued(msg.sender, contributedAmount);
    }

    /**
     * @dev Allows the owner to end the sale.
     */
    function endSale() external onlyOwner {
        currentStage = SaleStage.Ended;
    }

    // ==============================
    // Team Vesting Functions
    // ==============================

    /**
     * @dev Allows the team to claim their vested tokens after the vesting period.
     */
    function claimTeamTokens() external {
        require(block.timestamp >= teamUnlockTime, "Team tokens are still locked");
        require(msg.sender == teamWallet, "Only team wallet can claim team tokens");
        require(!teamTokensClaimed, "Team tokens already claimed");

        // Mint team tokens to team wallet
        _mint(teamWallet, teamTokens);
        teamTokensClaimed = true;
        emit TeamTokensClaimed();
    }

    // ==============================
    // Staking Functions
    // ==============================

    /**
     * @dev Allows users to stake tokens and earn rewards.
     * @param amount Amount of tokens to stake.
     */
    function stakeTokens(uint256 amount) external nonReentrant {
        require(amount > 0, "Cannot stake zero tokens");
        require(balanceOf(msg.sender) >= amount, "Not enough tokens to stake");

        // Transfer tokens to contract for staking
        _transfer(msg.sender, address(this), amount);

        // Update staking information
        stakes[msg.sender].amount += amount;
        stakes[msg.sender].timestamp = block.timestamp;

        emit Staked(msg.sender, amount);
    }

    /**
     * @dev Allows users to unstake tokens and claim rewards.
     */
    function unstakeTokens() external nonReentrant {
        StakeInfo storage userStake = stakes[msg.sender];
        require(userStake.amount > 0, "No staked tokens to unstake");

        uint256 stakedAmount = userStake.amount;

        // Calculate staking duration and rewards
        uint256 stakingDuration = block.timestamp - userStake.timestamp;
        uint256 reward = (stakedAmount * REWARD_RATE * stakingDuration) / (365 days * 100);

        // Reset staking information
        userStake.amount = 0;
        userStake.timestamp = 0;

        // Transfer staked tokens and rewards back to user
        _transfer(address(this), msg.sender, stakedAmount + reward);
        emit Unstaked(msg.sender, stakedAmount, reward);
    }

    // ==============================
    // Governance Functions
    // ==============================

    /**
     * @dev Allows the owner to create a new proposal.
     * @param description Description of the proposal.
     */
    function createProposal(string memory description) external onlyOwner {
        proposals.push(
            Proposal({
                description: description,
                votesFor: 0,
                votesAgainst: 0,
                executed: false,
                endTime: block.timestamp + VOTING_DURATION
            })
        );
        emit ProposalCreated(proposals.length - 1, description);
    }

    /**
     * @dev Allows token holders to vote on proposals.
     * @param proposalId ID of the proposal.
     * @param inFavor True to vote for, false to vote against.
     */
    function vote(uint256 proposalId, bool inFavor) external {
        require(proposalId < proposals.length, "Proposal does not exist");
        Proposal storage proposal = proposals[proposalId];
        require(block.timestamp < proposal.endTime, "Voting period has ended");
        require(!hasVoted[proposalId][msg.sender], "Already voted on this proposal");

        uint256 voterBalance = balanceOf(msg.sender);
        require(voterBalance > 0, "Must own tokens to vote");

        // Record vote
        hasVoted[proposalId][msg.sender] = true;

        // Tally votes
        if (inFavor) {
            proposal.votesFor += voterBalance;
        } else {
            proposal.votesAgainst += voterBalance;
        }

        emit Voted(proposalId, msg.sender, inFavor);
    }

    /**
     * @dev Allows the owner to execute a proposal after the voting period.
     * @param proposalId ID of the proposal.
     */
    function executeProposal(uint256 proposalId) external onlyOwner {
        require(proposalId < proposals.length, "Proposal does not exist");
        Proposal storage proposal = proposals[proposalId];
        require(block.timestamp >= proposal.endTime, "Voting period not yet ended");
        require(!proposal.executed, "Proposal already executed");

        // Check if proposal passed
        if (proposal.votesFor > proposal.votesAgainst) {
            // Implement proposal execution logic here
            // For example, changing contract parameters or allocating funds
            // This requires custom implementation based on your project's needs
        }

        proposal.executed = true;
        // Add event or further actions as needed
    }

    // ==============================
    // Liquidity Functions
    // ==============================

    /**
     * @dev Locks liquidity tokens in a specified liquidity pool.
     * @param _liquidityPoolAddress Address of the liquidity pool (e.g., Uniswap pair).
     */
    function lockLiquidity(address _liquidityPoolAddress) external onlyOwner {
        require(!liquidityLocked, "Liquidity already locked");
        require(_liquidityPoolAddress != address(0), "Invalid liquidity pool address");

        liquidityPoolAddress = _liquidityPoolAddress;
        liquidityLocked = true;

        // Transfer liquidity tokens to liquidity pool address
        _transfer(address(this), liquidityPoolAddress, liquidityTokens);
        emit LiquidityLocked(liquidityPoolAddress);
    }

    // ==============================
    // Token Burn Function
    // ==============================

    /**
     * @dev Burns a specified amount of tokens from the caller's account.
     * @param amount Amount of tokens to burn.
     */
    function burn(uint256 amount) external {
        _burn(msg.sender, amount);
        emit TokensBurned(msg.sender, amount);
    }

    // ==============================
    // Admin Functions
    // ==============================

    /**
     * @dev Allows the owner to set the current sale stage.
     * @param _stage The new sale stage.
     */
    function setSaleStage(SaleStage _stage) external onlyOwner {
        currentStage = _stage;
    }

    /**
     * @dev Allows the owner to distribute ecosystem tokens.
     * @param recipient Address receiving the tokens.
     * @param amount Amount of tokens to distribute.
     */
    function distributeEcosystemTokens(address recipient, uint256 amount) external onlyOwner {
        require(ecosystemTokens >= amount, "Not enough ecosystem tokens");
        ecosystemTokens -= amount;
        _transfer(address(this), recipient, amount);
    }

    // ==============================
    // Fallback Function
    // ==============================

    /**
     * @dev Fallback function to accept ETH.
     */
    receive() external payable {}

    // ==============================
    // Helper Functions
    // ==============================

    /**
     * @dev Returns the number of proposals created.
     * @return Number of proposals.
     */
    function getProposalCount() external view returns (uint256) {
        return proposals.length;
    }
}














































































































































































































































































































































































