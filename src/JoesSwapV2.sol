// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import "../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

contract JoesSwapV2 {
    IERC20 public token0;
    IERC20 public token1;

    uint256 public reserve0;
    uint256 public reserve1;

    uint256 public liquidity;

    uint256 immutable PRECISION = 1e18;

    constructor(address _token0, address _token1) {
        token0 = IERC20(_token0);
        token1 = IERC20(_token1);
    }

    function addLiquidity(uint256 amount0, uint256 amount1) public {
        reserve0 += amount0;
        reserve1 += amount1;

        uint256 amount0Scaled = amount0 * PRECISION;
        uint256 amount1Scaled = amount1 * PRECISION;

        uint256 newLiquidity = sqrt(amount0Scaled * amount1Scaled);

        liquidity += newLiquidity;

        token0.transferFrom(msg.sender, address(this), amount0);
        token1.transferFrom(msg.sender, address(this), amount1);
    }

    function removeLiquidity(uint256 liquidityToRemove) public {
        uint256 amount0 = (reserve0 * liquidityToRemove) / liquidity;
        uint256 amount1 = (reserve1 * liquidityToRemove) / liquidity;

        reserve0 -= amount0;
        reserve1 -= amount1;

        liquidity -= liquidityToRemove;
        token0.transfer(msg.sender, amount0);
        token1.transfer(msg.sender, amount1);
    }

    function roundUpToNearestWhole(
        uint256 value
    ) public pure returns (uint256) {
        // Add half of 1e18 for rounding, then divide and multiply to get the rounded value
        return ((value + 5e17) / 1e18) * 1e18;
    }

    function roundDownToNearestWhole(
        uint256 value
    ) public pure returns (uint256) {
        // Divide and multiply to get the rounded down value
        return (value / 1e18) * 1e18;
    }

    function swap(uint256 amountIn) public {
        uint256 scaledAmountIn = amountIn * PRECISION;

        uint256 amountOutScaled = getAmountOut(scaledAmountIn);
        if (amountOutScaled < 1e18) revert("Amount out too small");
        uint256 amountOutRounded = roundUpToNearestWhole(amountOutScaled);
        uint256 amountOut = amountOutRounded / PRECISION;

        uint256 amountInCorrect = getAmountIn(amountOutRounded);
        uint256 amountInRouded = roundDownToNearestWhole(amountInCorrect);
        uint256 amountInSlippageFree = amountInRouded / PRECISION;
        reserve0 += scaledAmountIn / PRECISION;
        reserve1 -= amountOut;

        if (amountOut <= 0) revert("Invalid output amount");

        token0.transferFrom(msg.sender, address(this), amountInSlippageFree);
        token1.transfer(msg.sender, amountOut);
    }

    function swap2(uint256 amountOut, uint256 amountInMax) public {
        uint256 scaledAmountOut = amountOut * PRECISION;
        uint256 amountInScaled = getAmountIn(scaledAmountOut);
        uint256 amountInRounded = roundDownToNearestWhole(amountInScaled);
        uint256 amountIn = amountInScaled / PRECISION;
        if (amountIn > amountInMax) {
            revert("AmountIn is bigger than amountInMax");
        }

        uint256 amountOutCorrect = getAmountOut(amountInRounded);
        uint256 amountOutRounded = roundUpToNearestWhole(amountOutCorrect);
        uint256 amountOutSlippageFree = amountOutRounded / PRECISION;
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
