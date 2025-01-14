// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import "../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import "../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import "../lib/openzeppelin-contracts/contracts/access/Ownable.sol";

/** 
 * @author Joesepherus   
 * @title JoesSwapV2
 * @dev Decentralized token swapping contract with liquidity provision and fee management.
 */
contract JoesSwapV2 is ReentrancyGuard, Ownable {
    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/
    IERC20 public token0;
    IERC20 public token1;
    uint256 public reserve0;
    uint256 public reserve1;
    uint256 public liquidity;
    uint256 public accumulatedFeePerLiquidityUnit;
    bool public poolInitialized = false;

    mapping(address => uint256) public lpBalances;
    mapping(address => uint256) public userEntryFeePerLiquidityUnit;

    /*//////////////////////////////////////////////////////////////
                                CONSTANTS 
    //////////////////////////////////////////////////////////////*/
    uint256 immutable PRECISION = 1e18;

    uint256 immutable FEE = 3;

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/
    event PoolInitialized(address sender, uint256 amount0, uint256 amount1);
    event AddLiquidity(address sender, uint256 amount0, uint256 amount1);
    event RemoveLiquidity(address sender, uint256 liquidityToRemove, uint256 amount0, uint256 amount1);
    event Swap(address sender, uint256 amount0, uint256 amount1);
    event WithdrawFees(address sender, uint256 feeAmount);

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/
    error InsufficentFeesBalance();
    error InsufficentLiquidity();
    error PoolAlreadyInitialized();

    constructor(address _token0, address _token1) Ownable(msg.sender) {
        token0 = IERC20(_token0);
        token1 = IERC20(_token1);
    }

    /*//////////////////////////////////////////////////////////////
                               FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Initializes the pool with the provided liquidity amounts of token0 and token1.
     * @dev This function can only be called once and by the owner. 
     *      It transfers the specified amounts of token0 and token1 from the caller to the contract,
     *      calculates the new liquidity, updates reserves, and records the user's entry per liquidity unit.
     *      Emits a `PoolInitialized` event upon successful execution.
     * @param amount0 The amount of token0 to add to the pool.
     * @param amount1 The amount of token1 to add to the pool.
     * @custom:modifier onlyOwner Can only be called by the contract owner.
     * @custom:revert PoolAlreadyInitialized if the pool has already been initialized.
     */
    function initializePoolLiquidity(
        uint256 amount0,
        uint256 amount1
    ) public onlyOwner {
        if(poolInitialized) revert PoolAlreadyInitialized(); 
        uint256 amount0Scaled = amount0 * PRECISION;
        uint256 amount1Scaled = amount1 * PRECISION;
        uint256 newLiquidity = sqrt(amount0Scaled * amount1Scaled);

        token0.transferFrom(msg.sender, address(this), amount0);
        token1.transferFrom(msg.sender, address(this), amount1);

        reserve0 += amount0;
        reserve1 += amount1;

        uint256 currentFeePerUnit = accumulatedFeePerLiquidityUnit;
        userEntryFeePerLiquidityUnit[msg.sender] = currentFeePerUnit;
        liquidity += newLiquidity;
        lpBalances[msg.sender] += newLiquidity;
        poolInitialized = true;

        emit PoolInitialized(msg.sender, amount0, amount1);
    }

    /**
     * @notice Adds liquidity to the pool with the provided amount of token0 and token1 is then calculated.
     * @dev The function scales up the amount of token0 by PRECISION.
     *      It calls getAmountOut to get the correct amount of token1 in proportion to token0.
     *      Calculates the liquidity, updates reserves, handles transfers from user to the pool.
     *      Sets up liquidity balance and entry point for the caller.
     *      Emits a `AddLiquidity` event upon successful execution.
     * @param amount0 The amount of token0 to add to the pool.
     * @custom:modifier nonReentrant Function cannot be re-entered
     */
    function addLiquidity(uint256 amount0) public nonReentrant {
        uint256 amount0Scaled = amount0 * PRECISION;

        uint256 amount1Scaled = getAmountOut(amount0Scaled);
        uint256 amount1 = amount1Scaled / PRECISION;

        uint256 newLiquidity = sqrt(amount0Scaled * amount1Scaled);

        token0.transferFrom(msg.sender, address(this), amount0);
        token1.transferFrom(msg.sender, address(this), amount1);

        reserve0 += amount0;
        reserve1 += amount1;

        uint256 currentFeePerUnit = accumulatedFeePerLiquidityUnit;
        userEntryFeePerLiquidityUnit[msg.sender] = currentFeePerUnit;
        liquidity += newLiquidity;
        lpBalances[msg.sender] += newLiquidity;

        emit AddLiquidity(msg.sender, amount0, amount1);
    }

    /**
     * @notice Removes all liquidity the caller has in the pool.
     * @dev The functions gets the correct amount of token0 and token1 to send to the user.
     *      Handles transfers from the pool to the caller.
     *      Updates reserves, liquidity of the pool.
     *      Updates lp balance of the caller.
     *      Emits a `RemoveLiquidity` event upon successful execution.
     * @custom:modifier nonReentrant Function cannot be re-entered.
     * @custom:revert InsufficentLiquidity if the caller has no liquidity in the pool.
     */
    function removeLiquidity() public nonReentrant {
        uint256 liquidityToRemove = lpBalances[msg.sender];
        if (liquidityToRemove <= 0) {
            revert InsufficentLiquidity();
        }
        uint256 amount0 = (reserve0 * liquidityToRemove) / liquidity;
        uint256 amount1 = (reserve1 * liquidityToRemove) / liquidity;

        token0.transfer(msg.sender, amount0);
        token1.transfer(msg.sender, amount1);

        reserve0 -= amount0;
        reserve1 -= amount1;

        liquidity -= liquidityToRemove;
        lpBalances[msg.sender] -= liquidityToRemove;

        emit RemoveLiquidity(msg.sender, liquidityToRemove, amount0, amount1);
    }

    /**
     * @notice Swaps amount of token0 for an amount of token1
     * @dev The function calculates the proper amount of token1 and swaps it with
     *      the caller for his provided amount of token0.
     *      It calls getAmountOut to get the correct amount of token1 in proportion to token0.
     *      Rounds this result down and calculates the correct amout of token0 to be traded for the amount.
     *      This way the swap is fair and there is minimal slippage.
     *      Calculates the fee amount and updates the fee pool.
     *      Transfers amount token0 to the pool and transfers amount token1 to the caller.
     *      Updates reserves of the pool.
     *      Emits a `Swap` event upon successful execution.
     * @param amountIn The amount of token0 to add to the pool.
     * @custom:modifier nonReentrant Function cannot be re-entered
     * @custom:revert "Invalid output amount" if the calculated amount of token1 is less than 0
     */
    function swapToken0Amount(uint256 amountIn) public nonReentrant {
        uint256 scaledAmountIn = amountIn * PRECISION;

        uint256 amountOutScaled = getAmountOut(scaledAmountIn);
        if (amountOutScaled < 1e18) revert("Amount out too small");
        uint256 amountOutRounded = roundDownToNearestWhole(amountOutScaled);
        uint256 amountOut = amountOutRounded / PRECISION;

        uint256 amountInCorrect = getAmountIn(amountOutRounded);

        uint256 feeAmount = (amountInCorrect * FEE) / 100;
        uint256 amountInAfterFee = amountInCorrect + feeAmount;

        uint256 amountInRouded = roundUpToNearestWhole(amountInAfterFee);
        uint256 amountInSlippageFree = amountInRouded / PRECISION;

        if (amountOut <= 0) revert("Invalid output amount");

        token0.transferFrom(msg.sender, address(this), amountInSlippageFree);
        token1.transfer(msg.sender, amountOut);

        accumulatedFeePerLiquidityUnit += (feeAmount * PRECISION) / liquidity;

        reserve0 += scaledAmountIn / PRECISION;
        reserve1 -= amountOut;
        emit Swap(msg.sender, amountInSlippageFree, amountOut);
    }

    /**
     * @notice Swaps amount of token1 for an amount of token0
     * @dev The function calculates the proper amount of token0 and swaps it with
     *      the caller for his provided amount of token1.
     *      It calls getAmountIn to get the correct amount of token0 in proportion to token1.
     *      Rounds this result down and calculates the correct amout of token1 to be traded for the amount.
     *      This way the swap is fair and there is minimal slippage.
     *      Calculates the fee amount and updates the fee pool.
     *      Transfers amount token1 to the pool and transfers amount token0 to the caller.
     *      Updates reserves of the pool.
     *      Emits a `Swap` event upon successful execution.
     * @param amountOut The amount of token0 to add to the pool.
     * @custom:modifier nonReentrant Function cannot be re-entered
     * @custom:revert "Invalid output amount" if the calculated amount of token1 is less than 0
     */
    function swapToken1Amount(uint256 amountOut, uint256 amountInMax) public nonReentrant {
        uint256 scaledAmountOut = amountOut * PRECISION;

        uint256 amountInScaledBefore = getAmountIn(scaledAmountOut);
        uint256 feeAmount = (scaledAmountOut * FEE) / 100;
        uint256 amountOutAfterFee = scaledAmountOut + feeAmount;

        uint256 amountInScaled = getAmountIn(amountOutAfterFee);
        uint256 amountInRounded = roundUpToNearestWhole(amountInScaled);
        uint256 amountIn = amountInRounded / PRECISION;

        if (amountIn > amountInMax) revert("AmountIn too high");

        uint256 amountOutCorrect = getAmountOut(amountInRounded);

        uint256 amountOutRounded = roundDownToNearestWhole(amountOutAfterFee);
        uint256 amountOutSlippageFree = amountOutRounded / PRECISION;

        token0.transferFrom(msg.sender, address(this), amountIn);
        token1.transfer(msg.sender, amountOutSlippageFree);

        accumulatedFeePerLiquidityUnit += (feeAmount * PRECISION) / liquidity;
        reserve0 += roundUpToNearestWhole(amountInScaledBefore) / PRECISION;
        reserve1 -= amountOut;

        emit Swap(msg.sender, amountIn, amountOutSlippageFree);
    }

    /**
     * @notice Withdraws collected fees of the caller
     * @dev The function calculates the callers share of the fee pool and 
     *      transfers the fees from the pool to the caller.
     *      Updates the liquidity entry point for the the caller so he can't double spend.
     *      Emits a `WithdrawFees` event upon successful execution.
     * @custom:modifier nonReentrant Function cannot be re-entered
     * @custom:revert InsufficentFeesBalance if the calculated fee share is less than 0
     */
    function withdrawFees() public nonReentrant {
        uint256 liquidityToRemove = lpBalances[msg.sender];

        uint256 feeShareScaled = ((accumulatedFeePerLiquidityUnit -
            userEntryFeePerLiquidityUnit[msg.sender]) * liquidityToRemove) /
            PRECISION;
        uint256 feeShare = feeShareScaled / PRECISION;
        if (feeShare <= 0) {
            revert InsufficentFeesBalance();
        }
        token0.transfer(msg.sender, feeShare);
        userEntryFeePerLiquidityUnit[msg.sender] = accumulatedFeePerLiquidityUnit;
        emit WithdrawFees(msg.sender, feeShare);
    }

    /**
     * @notice Gets amount of token1 compared to amount token0
     * @param amountIn The amount of token0
     * @dev The function calculates and returns the token1 compared to token0 amount 
     */
    function getAmountOut(uint256 amountIn) internal view returns (uint256) {
        uint k = reserve0 * PRECISION * reserve1 * PRECISION;
        uint256 newReserve0 = reserve0 * PRECISION + amountIn;
        uint256 newReserve1 = k / newReserve0;

        return reserve1 * PRECISION - newReserve1;
    }

    /**
     * @notice Gets amount of token0 compared to amount token1
     * @dev The function calculates and returns the token0 compared to token1 amount 
     * @param amountOut The amount of token1 
     */
    function getAmountIn(uint256 amountOut) internal view returns (uint256) {
        uint k = reserve0 * PRECISION * reserve1 * PRECISION;
        uint256 newReserve1 = reserve1 * PRECISION - amountOut;
        uint256 newReserve0 = k / newReserve1;

        return newReserve0 - reserve0 * PRECISION;
    }

    /**
     * @notice Helper function for rounding up numbers
     * @dev The function rounds up the provided number and returns it
     * @param value The amount of token0 
    */
    function roundUpToNearestWhole(
        uint256 value
    ) internal pure returns (uint256) {
        // If there's any remainder when dividing by 1e18, round up
        if (value % 1e18 != 0) {
            return ((value / 1e18) + 1) * 1e18;
        }
        return value;
    }

    /**
     * @notice Helper function for rounding up numbers
     * @dev The function rounds down the provided number and returns it
     * @param value The amount of token0 
    */
    function roundDownToNearestWhole(
        uint256 value
    ) internal pure returns (uint256) {
        // Divide and multiply to get the rounded down value
        return (value / 1e18) * 1e18;
    }

    /**
     * @notice Helper function for calculating the square root of a number
     * @dev The function rounds up the provided number and returns it
     * @param x The number to calculate the square root for
    */
    function sqrt(uint256 x) internal pure returns (uint256 y) {
        y = x;
        uint256 z = (x + 1) / 2;
        while (z < y) {
            y = z;
            z = (x / z + z) / 2;
        }
    }
}
