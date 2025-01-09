// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

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
    }

    function removeLiquidity(uint256 liquidityToRemove) public {
        uint256 amount0 = (reserve0* liquidityToRemove) / liquidity;
        uint256 amount1 = (reserve1* liquidityToRemove) / liquidity;

        reserve0 -= amount0;
        reserve1 -= amount1;

        liquidity -= liquidityToRemove;
    }

    function swap(uint256 amountIn) public {
        uint256 amountOut = getAmountOut(amountIn);

        reserve0 += amountIn;
        reserve1 -= amountOut;
    }

    function getAmountOut(uint256 amountIn) internal view returns (uint256) {
        uint k = reserve0 * reserve1;
        uint256 newReserve0 = reserve0 + amountIn;
        uint256 newReserve1 = k / newReserve0;

        return reserve1 - newReserve1;
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
