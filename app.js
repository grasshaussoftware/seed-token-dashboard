// Ensure the DOM is fully loaded
document.addEventListener('DOMContentLoaded', () => {
    const connectButton = document.getElementById('connectButton');
    const dashboard = document.getElementById('dashboard');
    const accountSpan = document.getElementById('account');
    const ethBalanceSpan = document.getElementById('ethBalance');
    const seedBalanceSpan = document.getElementById('seedBalance');
    const stakedBalanceSpan = document.getElementById('stakedBalance');
    const stakingRewardsSpan = document.getElementById('stakingRewards');
    const buyTokensButton = document.getElementById('buyTokensButton');
    const stakeTokensButton = document.getElementById('stakeTokensButton');
    const unstakeTokensButton = document.getElementById('unstakeTokensButton');
    const proposalsDiv = document.getElementById('proposals');

    let accounts;
    let seedContract;
    let provider;
    let signer;

    // SEED Token Contract Address and ABI
    const seedContractAddress = 'YOUR_SEED_TOKEN_CONTRACT_ADDRESS'; // Replace with your contract address
    const seedContractABI = [ /* Replace with your contract's ABI */ ];

    // Connect to MetaMask wallet
    connectButton.addEventListener('click', async () => {
        if (window.ethereum) {
            try {
                await window.ethereum.request({ method: 'eth_requestAccounts' });
                provider = new ethers.providers.Web3Provider(window.ethereum);
                signer = provider.getSigner();
                accounts = await provider.listAccounts();
                seedContract = new ethers.Contract(seedContractAddress, seedContractABI, signer);

                accountSpan.textContent = accounts[0];
                dashboard.classList.remove('hidden');
                connectButton.classList.add('hidden');

                // Fetch and display balances and proposals
                getBalances();
                loadProposals();
            } catch (error) {
                console.error('User rejected the request.', error);
            }
        } else {
            alert('Please install MetaMask!');
        }
    });

    // Function to get ETH and SEED balances
    async function getBalances() {
        // Get ETH balance
        const ethBalance = await provider.getBalance(accounts[0]);
        ethBalanceSpan.textContent = ethers.utils.formatEther(ethBalance);

        // Get SEED balance
        const seedBalance = await seedContract.balanceOf(accounts[0]);
        seedBalanceSpan.textContent = ethers.utils.formatUnits(seedBalance, 18);

        // Get staked SEED balance
        const stakeInfo = await seedContract.stakes(accounts[0]);
        const stakedAmount = stakeInfo.amount;
        stakedBalanceSpan.textContent = ethers.utils.formatUnits(stakedAmount, 18);

        // Calculate staking rewards
        const stakingRewards = await calculateStakingRewards(accounts[0]);
        stakingRewardsSpan.textContent = ethers.utils.formatUnits(stakingRewards, 18);
    }

    // Function to calculate staking rewards
    async function calculateStakingRewards(userAddress) {
        const stakeInfo = await seedContract.stakes(userAddress);
        const stakedAmount = stakeInfo.amount;
        const stakeTimestamp = stakeInfo.timestamp;

        if (stakedAmount.isZero()) {
            return ethers.BigNumber.from(0);
        }

        const currentTime = Math.floor(Date.now() / 1000);
        const stakingDuration = currentTime - stakeTimestamp;
        const annualRewardRate = await seedContract.REWARD_RATE();

        const reward = stakedAmount.mul(annualRewardRate).mul(stakingDuration).div(ethers.BigNumber.from(365 * 24 * 60 * 60)).div(100);
        return reward;
    }

    // Function to buy SEED tokens
    buyTokensButton.addEventListener('click', async () => {
        try {
            const amountInEther = prompt('Enter amount of ETH to spend:');
            if (!amountInEther || isNaN(amountInEther)) {
                alert('Invalid amount.');
                return;
            }
            const tx = await seedContract.buyTokens(ethers.constants.AddressZero, {
                value: ethers.utils.parseEther(amountInEther)
            });
            await tx.wait();
            alert('Tokens purchased successfully!');
            getBalances();
        } catch (error) {
            console.error(error);
            alert('Transaction failed.');
        }
    });

    // Function to stake SEED tokens
    stakeTokensButton.addEventListener('click', async () => {
        try {
            const amount = prompt('Enter amount of SEED to stake:');
            if (!amount || isNaN(amount)) {
                alert('Invalid amount.');
                return;
            }
            const amountInWei = ethers.utils.parseUnits(amount, 18);

            // Approve the contract to spend tokens
            const approveTx = await seedContract.approve(seedContractAddress, amountInWei);
            await approveTx.wait();

            // Stake tokens
            const stakeTx = await seedContract.stakeTokens(amountInWei);
            await stakeTx.wait();

            alert('Tokens staked successfully!');
            getBalances();
        } catch (error) {
            console.error(error);
            alert('Transaction failed.');
        }
    });

    // Function to unstake SEED tokens
    unstakeTokensButton.addEventListener('click', async () => {
        try {
            const tx = await seedContract.unstakeTokens();
            await tx.wait();
            alert('Tokens unstaked successfully!');
            getBalances();
        } catch (error) {
            console.error(error);
            alert('Transaction failed.');
        }
    });

    // Function to load governance proposals
    async function loadProposals() {
        const proposalCount = await seedContract.getProposalCount();
        proposalsDiv.innerHTML = '';

        for (let i = 0; i < proposalCount; i++) {
            const proposal = await seedContract.proposals(i);
            const hasVoted = await seedContract.hasVoted(i, accounts[0]);

            const proposalElement = document.createElement('div');
            proposalElement.classList.add('proposal');

            const title = document.createElement('h3');
            title.textContent = `Proposal #${i}: ${proposal.description}`;
            proposalElement.appendChild(title);

            const votesFor = document.createElement('p');
            votesFor.textContent = `Votes For: ${ethers.utils.formatUnits(proposal.votesFor, 18)} SEED`;
            proposalElement.appendChild(votesFor);

            const votesAgainst = document.createElement('p');
            votesAgainst.textContent = `Votes Against: ${ethers.utils.formatUnits(proposal.votesAgainst, 18)} SEED`;
            proposalElement.appendChild(votesAgainst);

            const endTime = new Date(proposal.endTime * 1000).toLocaleString();
            const endTimeP = document.createElement('p');
            endTimeP.textContent = `Voting Ends: ${endTime}`;
            proposalElement.appendChild(endTimeP);

            if (!hasVoted && Date.now() / 1000 < proposal.endTime) {
                const voteForButton = document.createElement('button');
                voteForButton.textContent = 'Vote For';
                voteForButton.onclick = async () => {
                    await voteOnProposal(i, true);
                };
                proposalElement.appendChild(voteForButton);

                const voteAgainstButton = document.createElement('button');
                voteAgainstButton.textContent = 'Vote Against';
                voteAgainstButton.onclick = async () => {
                    await voteOnProposal(i, false);
                };
                proposalElement.appendChild(voteAgainstButton);
            } else {
                const status = document.createElement('p');
                status.textContent = hasVoted ? 'You have voted on this proposal.' : 'Voting has ended.';
                proposalElement.appendChild(status);
            }

            proposalsDiv.appendChild(proposalElement);
        }
    }

    // Function to vote on a proposal
    async function voteOnProposal(proposalId, inFavor) {
        try {
            const tx = await seedContract.vote(proposalId, inFavor);
            await tx.wait();
            alert('Vote submitted successfully!');
            loadProposals();
        } catch (error) {
            console.error(error);
            alert('Voting failed.');
        }
    }
});
