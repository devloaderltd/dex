// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import "../interfaces/IPurDexFactory.sol";
import "../interfaces/IPurDexPair.sol";

/// @notice Helper math + reserve fetchers for the PurDex AMM.
library PurDexLibrary {
    error PurDexLibrary__IdenticalAddresses();
    error PurDexLibrary__ZeroAddress();
    error PurDexLibrary__InsufficientAmount();
    error PurDexLibrary__InsufficientLiquidity();

    // returns sorted token addresses, used to handle return values from pairs sorted in this order
    function sortTokens(address tokenA, address tokenB) internal pure returns (address token0, address token1) {
        if (tokenA == tokenB) revert PurDexLibrary__IdenticalAddresses();
        (token0, token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        if (token0 == address(0)) revert PurDexLibrary__ZeroAddress();
    }

    // fetches and sorts the reserves for a pair
    function getReserves(address factory, address tokenA, address tokenB)
        internal
        view
        returns (uint256 reserveA, uint256 reserveB)
    {
        (address token0, ) = sortTokens(tokenA, tokenB);
        address pair = IPurDexFactory(factory).getPair(tokenA, tokenB);
        require(pair != address(0), "PAIR_NOT_FOUND");
        (uint112 reserve0, uint112 reserve1, ) = IPurDexPair(pair).getReserves();
        (reserveA, reserveB) = tokenA == token0 ? (reserve0, reserve1) : (reserve1, reserve0);
    }

    // given some amount of an asset and pair reserves, returns an equivalent amount of the other asset
    function quote(uint256 amountA, uint256 reserveA, uint256 reserveB) internal pure returns (uint256 amountB) {
        if (amountA == 0) revert PurDexLibrary__InsufficientAmount();
        if (reserveA == 0 || reserveB == 0) revert PurDexLibrary__InsufficientLiquidity();
        amountB = (amountA * reserveB) / reserveA;
    }

    // given an input amount of an asset and pair reserves, returns the maximum output amount of the other asset
    function getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut)
        internal
        pure
        returns (uint256 amountOut)
    {
        if (amountIn == 0) revert PurDexLibrary__InsufficientAmount();
        if (reserveIn == 0 || reserveOut == 0) revert PurDexLibrary__InsufficientLiquidity();

        // 0.30% fee
        uint256 amountInWithFee = amountIn * 997;
        uint256 numerator = amountInWithFee * reserveOut;
        uint256 denominator = (reserveIn * 1000) + amountInWithFee;
        amountOut = numerator / denominator;
    }

    // given an output amount of an asset and pair reserves, returns a required input amount of the other asset
    function getAmountIn(uint256 amountOut, uint256 reserveIn, uint256 reserveOut)
        internal
        pure
        returns (uint256 amountIn)
    {
        if (amountOut == 0) revert PurDexLibrary__InsufficientAmount();
        if (reserveIn == 0 || reserveOut == 0) revert PurDexLibrary__InsufficientLiquidity();
        require(amountOut < reserveOut, "INSUFFICIENT_LIQUIDITY");

        // 0.30% fee
        uint256 numerator = reserveIn * amountOut * 1000;
        uint256 denominator = (reserveOut - amountOut) * 997;
        amountIn = (numerator / denominator) + 1;
    }

    // performs chained getAmountOut calculations on any number of pairs
    function getAmountsOut(address factory, uint256 amountIn, address[] memory path)
        internal
        view
        returns (uint256[] memory amounts)
    {
        uint256 length = path.length;
        require(length >= 2, "INVALID_PATH");
        amounts = new uint256[](length);
        amounts[0] = amountIn;
        // Gas Optimization: Cache array length
        for (uint256 i = 0; i < length - 1; i++) {
            (uint256 reserveIn, uint256 reserveOut) = getReserves(factory, path[i], path[i + 1]);
            amounts[i + 1] = getAmountOut(amounts[i], reserveIn, reserveOut);
        }
    }

    // performs chained getAmountIn calculations on any number of pairs
    function getAmountsIn(address factory, uint256 amountOut, address[] memory path)
        internal
        view
        returns (uint256[] memory amounts)
    {
        uint256 length = path.length;
        require(length >= 2, "INVALID_PATH");
        amounts = new uint256[](length);
        amounts[length - 1] = amountOut;
        // Gas Optimization: Cache array length
        for (uint256 i = length - 1; i > 0; i--) {
            (uint256 reserveIn, uint256 reserveOut) = getReserves(factory, path[i - 1], path[i]);
            amounts[i - 1] = getAmountIn(amounts[i], reserveIn, reserveOut);
        }
    }
}
