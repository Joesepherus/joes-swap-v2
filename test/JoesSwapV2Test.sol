// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {JoesSwapV2} from "../src/JoesSwapV2.sol";
import "../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {ERC20Mock} from "./ERC20Mock.sol";

contract JoesSwapV2Test is Test {
    JoesSwapV2 joesSwap2;
    IERC20 token0;
    IERC20 token1;

    uint256 immutable PRECISION = 1e18;

    function setUp() public {
        token0 = new ERC20Mock("token0", "T0");
        token0 = new ERC20Mock("token1", "T1");
        joesSwap2 = new JoesSwapV2(address(token0), address(token1));
    }

    function test_addLiquidity() public {
        uint256 amount0 = 500;
        uint256 amount1 = 100;

        joesSwap2.addLiquidity(amount0, amount1);

        assertEq(joesSwap2.reserve0(), amount0);
        assertEq(joesSwap2.reserve1(), amount1);
        assertEq(joesSwap2.liquidity(), sqrt(amount0 * amount1 * PRECISION * PRECISION));
    }

    function test_removeLiquidity() public {
        uint256 amount0 = 1000;
        uint256 amount1 = 100;
        joesSwap2.addLiquidity(amount0, amount1);

        uint256 removeLiquidityAmount = 100 * PRECISION;
        uint256 liquidityBefore = joesSwap2.liquidity();

        joesSwap2.removeLiquidity(removeLiquidityAmount);

        assertEq(joesSwap2.liquidity(), liquidityBefore - removeLiquidityAmount );
        assertEq(joesSwap2.reserve0(), 684);
        assertEq(joesSwap2.reserve1(), 69);
    }

    function test_removeLiquidityAll() public {
        uint256 amount0 = 1000;
        uint256 amount1 = 100;
        joesSwap2.addLiquidity(amount0, amount1);
        uint256 liquidityBefore = joesSwap2.liquidity();
        joesSwap2.removeLiquidity(liquidityBefore);

        assertEq(joesSwap2.liquidity(), 0);
        assertEq(joesSwap2.reserve0(), 0);
        assertEq(joesSwap2.reserve1(), 0);
    }

    function test_swap() public {
        uint256 amount0 = 520;
        uint256 amount1 = 90;
        joesSwap2.addLiquidity(amount0, amount1);

        uint256 swapAmount = 100;
        uint256 liquidityBefore = joesSwap2.liquidity();
        uint256 reserve0Before = joesSwap2.reserve0();
        uint256 reserve1Before = joesSwap2.reserve1();

        joesSwap2.swap(100);

        uint256 reserve1AfterExpected = (reserve0Before * reserve1Before) /
            (reserve0Before + swapAmount);

        assertEq(joesSwap2.liquidity(), liquidityBefore);
        assertEq(joesSwap2.reserve0(), reserve0Before + swapAmount);
        assertEq(joesSwap2.reserve1(), reserve1AfterExpected);
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

