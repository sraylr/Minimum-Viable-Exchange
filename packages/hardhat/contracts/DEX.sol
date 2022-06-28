// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";


contract DEX {

    IERC20 token;
    uint256 public totalLiquidity;
    mapping (address => uint256) public liquidity;
    

    /**
     * @notice Emitted when ethToToken() swap transacted
     */
    event EthToTokenSwap(address user, string txDetails, uint256 ethInput, uint256 tokenOutput);

    /**
     * @notice Emitted when tokenToEth() swap transacted
     */
    event TokenToEthSwap(address user, string txDetails, uint256 tokenInput, uint256 ethOutput);

    /**
     * @notice Emitted when liquidity provided to DEX and mints LPTs.
     */
    event LiquidityProvided(address user, uint256 liquidityMinted, uint256 ethInput, uint256 tokenInput);

    /**
     * @notice Emitted when liquidity removed from DEX and decreases LPT count within DEX.
     */
    event LiquidityRemoved(address user, uint256 liquidityRemoved, uint256 ethOutput, uint256 tokenOutput);

    constructor(address token_addr) public {
        token = IERC20(token_addr); //specifies the token address that will hook into the interface and be used through the variable 'token'
    }

    /**
     * @notice initializes amount of tokens that will be transferred to the DEX itself from the erc20 contract mintee (and only them based on how Balloons.sol is written). Loads contract up with both ETH and Balloons.
     */
    function init(uint256 tokens) public payable returns (uint256) {
        require(totalLiquidity == 0, "init() - already has liquidity");
        totalLiquidity = address(this).balance;
        liquidity[msg.sender] = totalLiquidity;
        require(token.transferFrom(msg.sender, address(this), tokens), "init() - failed to transfer tokens");
        return totalLiquidity;
    }

    /**
     * @notice returns yOutput, or yDelta for xInput (or xDelta)
     */
    function price(
        uint256 xInput,
        uint256 xReserves,
        uint256 yReserves
    ) public view returns (uint256 yOutput) {
        uint256 xInputWithFee = xInput * 997;
        uint256 numerator = xInputWithFee * yReserves;
        uint256 denominator = (xReserves * 1000) + xInputWithFee;
        return (numerator / denominator);
    }

    /**
     * @notice returns liquidity for a user. Note this is not needed typically due to the `liquidity()` mapping variable being public and having a getter as a result. This is left though as it is used within the front end code (App.jsx).
     */
    function getLiquidity(address lp) public view returns (uint256) {
        return liquidity[lp];
    }

    /**
     * @notice sends Ether to DEX in exchange for $BAL
     */
    function ethToToken() public payable returns (uint256) {
        require(msg.value > 0, "ethToToken() - input amount must be greater than 0");
        uint256 ethReserve = address(this).balance - msg.value;
        uint256 tokenReserve = token.balanceOf(address(this));
        uint256 tokenOutput = price(msg.value, ethReserve, tokenReserve);
        require(token.transfer(msg.sender, tokenOutput), "ethToToken() - failed to transfer tokens");
        emit EthToTokenSwap(msg.sender, "Ether to Balloons", msg.value, tokenOutput);
        return tokenOutput;

    }

    /**
     * @notice sends $BAL tokens to DEX in exchange for Ether
     */
    function tokenToEth(uint256 tokenInput) public returns (uint256) {
        require(tokenInput > 0, "tokenToEth() - input amount must be greater than 0");
        uint256 ethReserve = address(this).balance;
        uint256 tokenReserve = token.balanceOf(address(this));
        uint256 ethOutput = price(tokenInput, tokenReserve, ethReserve);
        require(token.transferFrom(msg.sender, address(this), tokenInput), "tokenToEth() - failed to transfer tokens");
        (bool sent, ) = payable(msg.sender).call{ value: ethOutput }("");
        require(sent, "tokenToEth() - failed to send ether");
        emit TokenToEthSwap(msg.sender, "Balloons to Ether", tokenInput, ethOutput);
        return ethOutput;
    }

    /**
     * @notice allows deposits of $BAL and $ETH to liquidity pool
     */
    function deposit() public payable returns (uint256 tokensDeposited) {
        uint256 ethReserve = address(this).balance - msg.value;
        uint256 tokenReserve = token.balanceOf(address(this));
        uint256 tokenDeposit = ((msg.value * tokenReserve) / ethReserve) + 1;
        uint256 liquidityMinted = (msg.value * totalLiquidity) / ethReserve;
        liquidity[msg.sender] += liquidityMinted;
        totalLiquidity += liquidityMinted;
        require(token.transferFrom(msg.sender, address(this), tokenDeposit), "deposit() - failed to transfer tokens");
        emit LiquidityProvided(msg.sender, liquidityMinted, msg.value, tokenDeposit);
        return liquidityMinted;
    }

    /**
     * @notice allows withdrawal of $BAL and $ETH from liquidity pool
     */
    function withdraw(uint256 amount) public returns (uint256 ethWithdrawn, uint256 tokensWithdrawn) {
        require(liquidity[msg.sender] >= amount, "withdraw() - not enough liquidity");
        uint256 ethReserve = address(this).balance;
        uint256 tokenReserve = token.balanceOf(address(this));
        uint256 ethAmount = (amount * ethReserve) / totalLiquidity;
        uint256 tokenAmount = (amount * tokenReserve) / totalLiquidity;
        liquidity[msg.sender] -= ethAmount;
        totalLiquidity -= ethAmount;
        (bool sent, ) = payable(msg.sender).call{value: ethAmount}("");
        require(sent, "withdraw() - failed to withdraw ether");
        require(token.transfer(msg.sender, tokenAmount), "withdraw() - failed to transfer tokens");
        emit LiquidityRemoved(msg.sender, amount, ethAmount, tokenAmount);
        return (ethAmount, tokenAmount);
    }
}