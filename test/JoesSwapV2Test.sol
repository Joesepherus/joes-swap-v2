// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {JoesSwapV2} from "../src/JoesSwapV2.sol";
import "../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {ERC20Mock} from "./ERC20Mock.sol";

contract JoesSwapV2Test is Test {
    JoesSwapV2 joesSwap2;
    ERC20Mock token0;
    ERC20Mock token1;

    uint256 immutable PRECISION = 1e18;

    address owner = address(0x4eFF9F6DBb11A3D9a18E92E35BD4D54ac4E1533a);

    function setUp() public {
        token0 = new ERC20Mock("Token0", "T0");
        token1 = new ERC20Mock("Token1", "T1");
        joesSwap2 = new JoesSwapV2(address(token0), address(token1));

        uint256 STARTING_AMOUNT = 1_000_000;

        vm.deal(owner, STARTING_AMOUNT);

        token0.mint(owner, STARTING_AMOUNT);
        token1.mint(owner, STARTING_AMOUNT);

        vm.startPrank(owner);
        token0.approve(address(joesSwap2), STARTING_AMOUNT);
        token1.approve(address(joesSwap2), STARTING_AMOUNT);
        vm.stopPrank();
        uint256 token0Balance = token0.balanceOf(address(joesSwap2));
        uint256 token1Balance = token1.balanceOf(address(joesSwap2));
        console.log("token0Balance", token0Balance);
        console.log("token1Balance", token1Balance);
        uint256 token0Owner = token0.balanceOf(owner);
        uint256 token1Owner = token1.balanceOf(owner);
        console.log("token0Owner", token0Owner);
        console.log("token1Owner", token1Owner);
    }

    function test_addLiquidity() public {
        uint256 amount0 = 500;
        uint256 amount1 = 100;
        vm.prank(owner);
        joesSwap2.addLiquidity(amount0, amount1);

        assertEq(joesSwap2.reserve0(), amount0);
        assertEq(joesSwap2.reserve1(), amount1);
        assertEq(
            joesSwap2.liquidity(),
            sqrt(amount0 * amount1 * PRECISION * PRECISION)
        );
    }

    function test_removeLiquidity() public {
        uint256 amount0 = 1000;
        uint256 amount1 = 100;
        vm.prank(owner);
        joesSwap2.addLiquidity(amount0, amount1);

        uint256 removeLiquidityAmount = 100 * PRECISION;
        uint256 liquidityBefore = joesSwap2.liquidity();

        joesSwap2.removeLiquidity();

        assertEq(
            joesSwap2.liquidity(),
            liquidityBefore - removeLiquidityAmount
        );
        assertEq(joesSwap2.reserve0(), 684);
        assertEq(joesSwap2.reserve1(), 69);
    }

    function test_removeLiquidityAll() public {
        uint256 amount0 = 1000;
        uint256 amount1 = 100;
        vm.prank(owner);
        joesSwap2.addLiquidity(amount0, amount1);
        uint256 liquidityBefore = joesSwap2.liquidity();
        joesSwap2.removeLiquidity();

        assertEq(joesSwap2.liquidity(), 0);
        assertEq(joesSwap2.reserve0(), 0);
        assertEq(joesSwap2.reserve1(), 0);
    }

    function test_swap1_1() public {
        uint256 amount0 = 1000;
        uint256 amount1 = 100;
        vm.prank(owner);
        joesSwap2.addLiquidity(amount0, amount1);

        uint256 swapAmount = 100;
        uint256 liquidityBefore = joesSwap2.liquidity();
        uint256 reserve0Before = joesSwap2.reserve0();
        uint256 reserve1Before = joesSwap2.reserve1();

        vm.prank(owner);
        joesSwap2.swap(swapAmount);

        uint256 reserve1AfterExpected = (reserve0Before * reserve1Before) /
            (reserve0Before + swapAmount);

//        assertEq(joesSwap2.liquidity(), liquidityBefore);
//        assertEq(joesSwap2.reserve0(), reserve0Before + swapAmount);
//        assertEq(joesSwap2.reserve1(), reserve1AfterExpected);

        vm.prank(owner);
        joesSwap2.removeLiquidity();

        console.log("pool token0 balance", token0.balanceOf(address(joesSwap2)));
        console.log("pool token1 balance", token1.balanceOf(address(joesSwap2)));
    }

    function test_swap2_1() public {
        uint256 amount0 = 1000;
        uint256 amount1 = 100;
        vm.prank(owner);
        joesSwap2.addLiquidity(amount0, amount1);

        uint256 swapAmount = 10;
        uint256 liquidityBefore = joesSwap2.liquidity();
        uint256 reserve0Before = joesSwap2.reserve0();
        uint256 reserve1Before = joesSwap2.reserve1();

        vm.prank(owner);
        joesSwap2.swap2(swapAmount, 123);

        uint256 reserve1AfterExpected = (reserve0Before * reserve1Before) /
            (reserve0Before + swapAmount);

        //        assertEq(joesSwap2.liquidity(), liquidityBefore);
        //        assertEq(joesSwap2.reserve0(), reserve0Before + swapAmount);
        //        assertEq(joesSwap2.reserve1(), reserve1AfterExpected);

        uint256 liquidity = joesSwap2.liquidity();
        vm.prank(owner);
        joesSwap2.removeLiquidity();
    }


    function test_swap2_2() public {
        uint256 amount0 = 1000;
        uint256 amount1 = 100;
        vm.prank(owner);
        joesSwap2.addLiquidity(amount0, amount1);

        uint256 swapAmount = 10;
        uint256 liquidityBefore = joesSwap2.liquidity();
        uint256 reserve0Before = joesSwap2.reserve0();
        uint256 reserve1Before = joesSwap2.reserve1();

        vm.prank(owner);
        joesSwap2.swap2(swapAmount, 123);

        uint256 reserve1AfterExpected = (reserve0Before * reserve1Before) /
            (reserve0Before + swapAmount);

        //        assertEq(joesSwap2.liquidity(), liquidityBefore);
        //        assertEq(joesSwap2.reserve0(), reserve0Before + swapAmount);
        //        assertEq(joesSwap2.reserve1(), reserve1AfterExpected);

        uint256 liquidity = joesSwap2.liquidity();
        vm.prank(owner);
        joesSwap2.removeLiquidity();
        vm.prank(owner);
        joesSwap2.withdrawFees();
    }

    function test_withdrawFeesBeforeSwap() public {
        vm.prank(owner);
        joesSwap2.withdrawFees();
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
