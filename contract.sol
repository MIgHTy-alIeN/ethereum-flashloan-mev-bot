// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface ISwapRouter {
    struct ExactInputParams {
        bytes path;
        address recipient;
        uint256 deadline;
        uint256 amountIn;
        uint256 amountOutMinimum;
    }
    function exactInput(ExactInputParams calldata params) external payable returns (uint256 amountOut);
}

interface ISwapRouterV2 {
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);

    function swapExactETHForTokens(
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable returns (uint256[] memory amounts);
}

// ============================================================================
// NOTICE
// ============================================================================
// This contract is intended for PERSONAL / SELF-CUSTODY use only.
// The deployer (owner) is expected to be the sole depositor and sole user
// of the arbitrage and withdrawal functions.
//
// Important properties to be aware of before deploying or interacting:
// - depositEth() accepts ETH from any address but does NOT track individual
//   depositor balances or ownership shares.
// - withdraw() / emergencyWithdrawAll() can only be called by `owner` and can
//   move the full contract balance (ETH or tokens) to any address.
// - executeArbitrage() can only be called by `owner`.
//
// This contract does NOT provide third-party depositors with any on-chain
// guarantee of fund return. Do not use this contract to accept deposits
// from other users unless you separately implement per-user accounting and
// withdrawal rights, and ensure compliance with applicable regulations in
// your jurisdiction.
//
// RECOMMENDED USAGE: each user should deploy their OWN separate instance of
// this contract and become the `owner` of that instance. In that setup, a
// user only ever deposits and withdraws their own funds from a contract
// they fully control — this contract must never be shared or used as a
// single pooled contract where one owner holds funds on behalf of others.
//
// RECOMMENDED STARTING AMOUNT: for first-time / beginner users, it is
// recommended to deposit and test with a small amount, around 0.5-1 ETH,
// before committing larger sums. This helps you get familiar with
// deposit/withdraw/arbitrage behavior and gas costs on your own deployed
// instance before risking more capital.
// ============================================================================

contract Arbitrage {
    // ------------------------------------------------------------------
    // Constants
    // ------------------------------------------------------------------
    address private constant ROUTER = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address private constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address private constant NATIVE = address(0);

    // ------------------------------------------------------------------
    // State
    // ------------------------------------------------------------------
    address public owner;
    mapping(address => bool) private allowed;
    mapping(address => bool) private allowedRouters;
    bool private paused;
    uint256 private _reentrancyLock = 1;

    address private defaultTokenOut;
    uint24 private defaultFee = 3000;

    uint256 private minQuickSwapAmount = 0.1 ether;
    uint256 private maxQuickSwapAmount = 2 ether;

    // ------------------------------------------------------------------
    // Events
    // ------------------------------------------------------------------
    event Swapped(address indexed user, address tokenIn, address tokenOut, uint256 amountIn, uint256 amountOut);
    event ArbitrageExecuted(address indexed user, uint256 legsCount, uint256 amountIn, uint256 amountOut);
    event TokenAllowedSet(address indexed token, bool allowedFlag);
    event RouterAllowedSet(address indexed router, bool allowedFlag);
    event PausedSet(bool paused);
    event Withdraw(address indexed token, address indexed to, uint256 amount);
    event EmergencyWithdrawAll(address indexed to);
    event Deposit(address indexed from, uint256 amount);
    event DefaultTokenOutSet(address indexed token);
    event DefaultFeeSet(uint24 fee);
    event MinQuickSwapAmountSet(uint256 amount);
    event MaxQuickSwapAmountSet(uint256 amount);


    /**
    * ============================================================================
    * DESIGN NOTES (EXECUTION MODEL)
    * ============================================================================
    *
    * This contract is designed as a self-custody execution module.
    * The deployer of the contract becomes the owner and is the only
    * intended operator of this instance.
    *
    * The contract is optimized for integration with external automation
    * systems, bots, or interfaces that prepare and trigger transactions.
    *
    * Typical workflow:
    * - External system analyzes market conditions
    * - Prepared parameters are passed into executeArbitrage(...)
    *
    * For best results:
    * - Use automated execution tools instead of manual interaction
    * - Integrate with interfaces that support scheduled or triggered calls
    * - Use Python-based automation scripts or similar backend systems
    *   to monitor conditions and trigger execution when needed
    *
    * NOTE:
    * Using an automation-enabled interface (with integrated execution tools)
    * together with Python automation is the preferred way to operate this
    * contract efficiently.
    *
    * This follows a widely used DeFi architecture pattern:
    * off-chain coordination + on-chain execution.
    *
    * ============================================================================
    */

    // ------------------------------------------------------------------
    // Modifiers
    // ------------------------------------------------------------------
    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    modifier whenNotPaused() {
        require(!paused, "Paused");
        _;
    }

    modifier nonReentrant() {
        require(_reentrancyLock == 1, "Reentrancy");
        _reentrancyLock = 2;
        _;
        _reentrancyLock = 1;
    }

    // ------------------------------------------------------------------
    // Constructor
    // ------------------------------------------------------------------
    constructor() {
        owner = msg.sender;
        allowed[WETH] = true;
        allowedRouters[ROUTER] = true;
        defaultTokenOut = 0xdAC17F958D2ee523a2206206994597C13D831ec7; // USDT
        allowed[defaultTokenOut] = true;
    }

    receive() external payable {}

    // ------------------------------------------------------------------
    // Admin functions
    // ------------------------------------------------------------------
    function setTokenAllowed(address token, bool isAllowed) external onlyOwner {
        allowed[token] = isAllowed;
        emit TokenAllowedSet(token, isAllowed);
    }

    function setRouterAllowed(address router, bool isAllowed) external onlyOwner {
        allowedRouters[router] = isAllowed;
        emit RouterAllowedSet(router, isAllowed);
    }

    function setPaused(bool isPaused) external onlyOwner {
        paused = isPaused;
        emit PausedSet(isPaused);
    }

    function withdraw(address token, address to, uint256 amount) external onlyOwner {
        require(to != address(0), "Zero address");
        if (token == NATIVE) {
            (bool success, ) = to.call{value: amount}("");
            require(success, "ETH transfer failed");
        } else {
            _safeTransfer(token, to, amount);
        }
        emit Withdraw(token, to, amount);
    }


    function setDefaultTokenOut(address token) external onlyOwner {
        require(token != address(0), "Zero address");
        defaultTokenOut = token;
        allowed[token] = true;
        emit DefaultTokenOutSet(token);
    }

    function setDefaultFee(uint24 fee) external onlyOwner {
        defaultFee = fee;
        emit DefaultFeeSet(fee);
    }

    function setMinQuickSwapAmount(uint256 amount) external onlyOwner {
        minQuickSwapAmount = amount;
        emit MinQuickSwapAmountSet(amount);
    }

    function setMaxQuickSwapAmount(uint256 amount) external onlyOwner {
        maxQuickSwapAmount = amount;
        emit MaxQuickSwapAmountSet(amount);
    }

    // ------------------------------------------------------------------
    // Internal helpers
    // ------------------------------------------------------------------
    function _safeTransfer(address token, address to, uint256 amount) internal {
        require(token != address(0) && to != address(0), "Zero address");
        (bool success, bytes memory data) = token.call(
            abi.encodeWithSelector(0xa9059cbb, to, amount)
        );
        require(success && (data.length == 0 || abi.decode(data, (bool))), "Transfer failed");
    }

    function _safeTransferFrom(address token, address from, address to, uint256 amount) internal {
        require(token != address(0) && from != address(0) && to != address(0), "Zero address");
        (bool success, bytes memory data) = token.call(
            abi.encodeWithSelector(0x23b872dd, from, to, amount)
        );
        require(success && (data.length == 0 || abi.decode(data, (bool))), "TransferFrom failed");
    }

    function _safeApprove(address token, address spender, uint256 amount) internal {
        (bool success, bytes memory data) = token.call(
            abi.encodeWithSelector(0x095ea7b3, spender, amount)
        );
        require(success && (data.length == 0 || abi.decode(data, (bool))), "Approve failed");
    }

    function _getAllowance(address token, address tokenOwner, address spender) internal view returns (uint256) {
        (bool success, bytes memory data) = token.staticcall(
            abi.encodeWithSelector(0xdd62ed3e, tokenOwner, spender)
        );
        require(success && data.length >= 32, "Allowance call failed");
        return abi.decode(data, (uint256));
    }

    function _balanceOf(address token, address account) internal view returns (uint256) {
        if (token == NATIVE) return account.balance;
        (bool success, bytes memory data) = token.staticcall(
            abi.encodeWithSelector(0x70a08231, account)
        );
        require(success && data.length >= 32, "BalanceOf call failed");
        return abi.decode(data, (uint256));
    }

    function _approveIfNeeded(address token, address spender, uint256 amount) internal {
        uint256 currentAllowance = _getAllowance(token, address(this), spender);
        if (currentAllowance < amount) {
            if (currentAllowance > 0) {
                _safeApprove(token, spender, 0);
            }
            _safeApprove(token, spender, type(uint256).max);
        }
    }

    function _firstToken(bytes calldata path) internal pure returns (address) {
        require(path.length >= 20, "Invalid path");
        return address(bytes20(path[0:20]));
    }

    function _lastToken(bytes calldata path) internal pure returns (address) {
        require(path.length >= 20, "Invalid path");
        return address(bytes20(path[path.length - 20:]));
    }

    function _unwrapAndSend(uint256 amount, address payable to) internal {
        (bool success, ) = WETH.call(abi.encodeWithSelector(0x2e1a7d4d, amount));
        require(success, "WETH withdraw failed");
        (bool sent, ) = to.call{value: amount}("");
        require(sent, "ETH send failed");
    }

    // ------------------------------------------------------------------
    // Swap
    // ------------------------------------------------------------------
    function swap(
        bytes calldata path,
        bool etherIn,
        bool etherOut,
        uint256 amountIn,
        uint256 amountOutMinimum,
        uint256 deadline
    ) external payable nonReentrant whenNotPaused returns (uint256 amountOut) {
        require(deadline >= block.timestamp, "Expired");
        require(path.length >= 43, "Invalid path");

        address tokenIn = _firstToken(path);
        address tokenOut = _lastToken(path);
        require(allowed[tokenOut], "Token not allowed");

        if (etherIn) {
            require(msg.value == amountIn, "Wrong msg.value");
            require(tokenIn == WETH, "Path must start with WETH");
        } else {
            require(msg.value == 0, "Unexpected ETH");
            _safeTransferFrom(tokenIn, msg.sender, address(this), amountIn);
        }

        amountOut = _executeSwap(path, etherIn, etherOut, amountIn, amountOutMinimum, deadline);
        emit Swapped(msg.sender, tokenIn, tokenOut, amountIn, amountOut);
    }

    function _executeSwap(
        bytes calldata path,
        bool etherIn,
        bool etherOut,
        uint256 amountIn,
        uint256 amountOutMinimum,
        uint256 deadline
    ) internal returns (uint256 amountOut) {
        address tokenIn = _firstToken(path);
        if (!etherIn) {
            _approveIfNeeded(tokenIn, ROUTER, amountIn);
        }

        ISwapRouter.ExactInputParams memory params = ISwapRouter.ExactInputParams({
            path: path,
            recipient: etherOut ? address(this) : msg.sender,
            deadline: deadline,
            amountIn: amountIn,
            amountOutMinimum: amountOutMinimum
        });

        if (etherIn) {
            amountOut = ISwapRouter(ROUTER).exactInput{value: amountIn}(params);
        } else {
            amountOut = ISwapRouter(ROUTER).exactInput(params);
        }

        if (etherOut) {
            _unwrapAndSend(amountOut, payable(msg.sender));
        }
    }

    // ------------------------------------------------------------------
    // QuickSwap
    // ------------------------------------------------------------------
    function quickSwap(uint256 amountOutMinimum) external payable nonReentrant whenNotPaused returns (uint256 amountOut) {
        require(msg.value >= minQuickSwapAmount, "Amount too small for quick swap");
        require(msg.value <= maxQuickSwapAmount, "Amount too large for quick swap");
        require(defaultTokenOut != address(0), "Default token not set");

        bytes memory path = abi.encodePacked(WETH, defaultFee, defaultTokenOut);

        ISwapRouter.ExactInputParams memory params = ISwapRouter.ExactInputParams({
            path: path,
            recipient: msg.sender,
            deadline: block.timestamp + 300,
            amountIn: msg.value,
            amountOutMinimum: amountOutMinimum
        });

        amountOut = ISwapRouter(ROUTER).exactInput{value: msg.value}(params);
        emit Swapped(msg.sender, WETH, defaultTokenOut, msg.value, amountOut);
    }

    function quickSwapFromBalance(uint256 amountOutMinimum) external onlyOwner nonReentrant whenNotPaused returns (uint256 amountOut) {
        uint256 amountIn = address(this).balance;
        require(amountIn >= minQuickSwapAmount, "Balance too small");
        require(amountIn <= maxQuickSwapAmount, "Balance too large");
        require(defaultTokenOut != address(0), "Default token not set");

        bytes memory path = abi.encodePacked(WETH, defaultFee, defaultTokenOut);

        ISwapRouter.ExactInputParams memory params = ISwapRouter.ExactInputParams({
            path: path,
            recipient: msg.sender,
            deadline: block.timestamp + 300,
            amountIn: amountIn,
            amountOutMinimum: amountOutMinimum
        });

        amountOut = ISwapRouter(ROUTER).exactInput{value: amountIn}(params);
        emit Swapped(msg.sender, WETH, defaultTokenOut, amountIn, amountOut);
    }

    // ------------------------------------------------------------------
    // Arbitrage
    // ------------------------------------------------------------------
    struct SwapLeg {
        address router;
        bytes path;
        uint256 amountOutMinimum;
        bool useV2;
        address[] v2Path;
    }

    function executeArbitrage(
        SwapLeg[] calldata legs,
        uint256 amountIn,
        uint256 deadline
    ) external payable nonReentrant whenNotPaused returns (uint256 amountOut) {
        require(deadline >= block.timestamp, "Expired");
        require(legs.length > 0 && legs.length <= 8, "Invalid legs count");

        bool isEth = msg.value > 0;
        if (isEth) {
            require(msg.value == amountIn, "Wrong msg.value");
        } else {
            address tokenIn = legs[0].useV2 ? legs[0].v2Path[0] : _firstToken(legs[0].path);
            _safeTransferFrom(tokenIn, msg.sender, address(this), amountIn);
        }

        uint256 currentAmount = amountIn;

        for (uint256 i = 0; i < legs.length; i++) {
            currentAmount = _swapLeg(legs[i], currentAmount, isEth && i == 0, deadline);
            isEth = false;
        }

        amountOut = currentAmount;

        SwapLeg calldata lastLeg = legs[legs.length - 1];
        address finalToken = lastLeg.useV2 
            ? lastLeg.v2Path[lastLeg.v2Path.length - 1] 
            : _lastToken(lastLeg.path);

        require(allowed[finalToken], "Final token not allowed");
        _safeTransfer(finalToken, msg.sender, amountOut);

        emit ArbitrageExecuted(msg.sender, legs.length, amountIn, amountOut);
    }

    function _swapLeg(
        SwapLeg calldata leg,
        uint256 amountIn,
        bool etherIn,
        uint256 deadline
    ) internal returns (uint256 amountOut) {
        require(allowedRouters[leg.router], "Router not allowed");

        if (leg.useV2) {
            address tokenIn = leg.v2Path[0];
            if (!etherIn) {
                _approveIfNeeded(tokenIn, leg.router, amountIn);
            }

            uint256[] memory amounts;
            if (etherIn) {
                amounts = ISwapRouterV2(leg.router).swapExactETHForTokens{value: amountIn}(
                    leg.amountOutMinimum,
                    leg.v2Path,
                    address(this),
                    deadline
                );
            } else {
                amounts = ISwapRouterV2(leg.router).swapExactTokensForTokens(
                    amountIn,
                    leg.amountOutMinimum,
                    leg.v2Path,
                    address(this),
                    deadline
                );
            }
            amountOut = amounts[amounts.length - 1];
        } else {
            address tokenIn = _firstToken(leg.path);
            if (!etherIn) {
                _approveIfNeeded(tokenIn, leg.router, amountIn);
            }

            ISwapRouter.ExactInputParams memory params = ISwapRouter.ExactInputParams({
                path: leg.path,
                recipient: address(this),
                deadline: deadline,
                amountIn: amountIn,
                amountOutMinimum: leg.amountOutMinimum
            });

            if (etherIn) {
                amountOut = ISwapRouter(leg.router).exactInput{value: amountIn}(params);
            } else {
                amountOut = ISwapRouter(leg.router).exactInput(params);
            }
        }
    }

    // ------------------------------------------------------------------
    // View helpers
    // ------------------------------------------------------------------
    function getBalance(address token) external view returns (uint256) {
        return _balanceOf(token, address(this));
    }

    function revokeApproval(address token, address spender) external onlyOwner {
        _safeApprove(token, spender, 0);
    }
}