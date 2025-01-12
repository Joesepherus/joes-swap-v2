// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import "../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import "../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";

contract JoesSwapV2 is ReentrancyGuard {
    IERC20 public token0;
    IERC20 public token1;

    uint256 public reserve0;
    uint256 public reserve1;

    uint256 public liquidity;

    uint256 immutable PRECISION = 1e18;

    uint256 immutable FEE = 3;

    mapping(address => uint256) public lpBalances;
    mapping(address => uint256) public feePool0;
    mapping(address => uint256) public feePool1;

    event AddLiquidity(address sender, uint256 amount0, uint256 amount1);
    event RemoveLiquidity(address sender, uint256 liquidityToRemove);
    event Swap(address sender, uint256 amount0, uint256 amount1);
    event Swap2(address sender, uint256 amount0, uint256 amount1);
    event WithdrawFees(address sender, uint256 feeAmount);

    constructor(address _token0, address _token1) {
        token0 = IERC20(_token0);
        token1 = IERC20(_token1);
    }

    function addLiquidity(
        uint256 amount0,
        uint256 amount1
    ) public nonReentrant {
        reserve0 += amount0;
        reserve1 += amount1;

        uint256 amount0Scaled = amount0 * PRECISION;
        uint256 amount1Scaled = amount1 * PRECISION;

        uint256 newLiquidity = sqrt(amount0Scaled * amount1Scaled);

        liquidity += newLiquidity;
        lpBalances[msg.sender] += newLiquidity;

        token0.transferFrom(msg.sender, address(this), amount0);
        token1.transferFrom(msg.sender, address(this), amount1);

        emit AddLiquidity(msg.sender, amount0, amount1);
    }

    function removeLiquidity() public nonReentrant {
        uint256 liquidityToRemove = lpBalances[msg.sender];
        uint256 amount0 = (reserve0 * liquidityToRemove) / liquidity;
        uint256 amount1 = (reserve1 * liquidityToRemove) / liquidity;

        reserve0 -= amount0;
        reserve1 -= amount1;

        uint256 lpShareOfFees = feePool0[msg.sender];
        feePool0[msg.sender] -= lpShareOfFees;

        liquidity -= liquidityToRemove;
        token0.transfer(msg.sender, amount0);
        token1.transfer(msg.sender, amount1);

        if (lpShareOfFees > 0) {
            token0.transfer(msg.sender, lpShareOfFees);
        }

        emit RemoveLiquidity(msg.sender, liquidityToRemove);
    }

    function roundUpToNearestWhole(
        uint256 value
    ) internal pure returns (uint256) {
        // If there's any remainder when dividing by 1e18, round up
        if (value % 1e18 != 0) {
            return ((value / 1e18) + 1) * 1e18;
        }
        return value;
    }

    function roundDownToNearestWhole(
        uint256 value
    ) internal pure returns (uint256) {
        // Divide and multiply to get the rounded down value
        return (value / 1e18) * 1e18;
    }

    function swap(uint256 amountIn) public nonReentrant {
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

        feePool0[msg.sender] =
            roundUpToNearestWhole(scaledAmountIn - amountInCorrect) /
            PRECISION;

        reserve0 += scaledAmountIn / PRECISION;
        reserve1 -= amountOut;

        if (amountOut <= 0) revert("Invalid output amount");

        token0.transferFrom(msg.sender, address(this), amountInSlippageFree);
        token1.transfer(msg.sender, amountOut);
        emit Swap(msg.sender, amountInSlippageFree, amountOut);
    }

    function swap2(uint256 amountOut, uint256 amountInMax) public nonReentrant {
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

        feePool0[msg.sender] =
            (amountInScaled - amountInScaledBefore) /
            PRECISION;

        reserve0 += roundUpToNearestWhole(amountInScaledBefore) / PRECISION;
        reserve1 -= amountOut;

        token0.transferFrom(msg.sender, address(this), amountIn);
        token1.transfer(msg.sender, amountOutSlippageFree);

        emit Swap2(msg.sender, amountIn, amountOutSlippageFree);
    }

    function withdrawFees() public nonReentrant {
        uint256 feeAmount = feePool0[msg.sender];
        token0.transfer(msg.sender, feeAmount);
    }

    function getAmountOut(uint256 amountIn) internal view returns (uint256) {
        uint k = reserve0 * PRECISION * reserve1 * PRECISION;
        uint256 newReserve0 = reserve0 * PRECISION + amountIn;
        uint256 newReserve1 = k / newReserve0;

        return reserve1 * PRECISION - newReserve1;
    }

    function getAmountIn(uint256 amountOut) internal view returns (uint256) {
        uint k = reserve0 * PRECISION * reserve1 * PRECISION;
        uint256 newReserve1 = reserve1 * PRECISION - amountOut;
        uint256 newReserve0 = k / newReserve1;

        return newReserve0 - reserve0 * PRECISION;
    }

    function sqrt(uint256 x) internal pure returns (uint256 y) {
        y = x;
        uint256 z = (x + 1) / 2;
        while (z < y) {
            y = z;
            z = (x / z + z) / 2;
        }
    }
}
