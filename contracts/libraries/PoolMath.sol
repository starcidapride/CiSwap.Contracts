// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.23;

import "@openzeppelin/contracts/utils/math/SafeCast.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "./ExtendMath.sol";

library PoolMath {
    using SafeCast for *;
    using Math for uint;
    using ExtendMath for uint;

    function _computeConstantA(
        uint basePriceAX96,
        uint maxPriceAX96,
        uint amountA
    ) private pure returns (uint) {
        uint priceRatioX96 = basePriceAX96.mulDiv(1 << 96, maxPriceAX96);

        uint sqrtPriceRatioX48 = priceRatioX96.sqrt();
        uint numerator = sqrtPriceRatioX48 * amountA;
        uint exponent = 1 << (96 / 2);
        (bool flag, uint denominator) = Math.trySub(
            exponent,
            sqrtPriceRatioX48
        );
        require(flag);
        return numerator / denominator;
    }

    function _computeConstantB(
        uint basePriceAX96,
        uint constantA,
        uint amountA,
        uint amountB
    ) private pure returns (uint) {
        uint denominator = 1 << 96;
        (bool flag, uint numerator) = Math.trySub(
            (amountA + constantA) * basePriceAX96,
            denominator * amountB
        );
        require(flag);
        return numerator / denominator;
    }

    function computeConstants(
        uint basePriceAX96,
        uint maxPriceAX96,
        uint amountA,
        uint amountB
    ) internal pure returns (uint constantA, uint constantB) {
        constantA = _computeConstantA(basePriceAX96, maxPriceAX96, amountA);
        constantB = _computeConstantB(
            basePriceAX96,
            constantA,
            amountA,
            amountB
        );
    }

    struct ComputeAmountOutParams {
        uint reserveIn;
        uint reserveOut;
        uint constantOut;
        uint amountIn;
        uint24 fee;
    }

    function computeAmountOut(
        ComputeAmountOutParams memory params
    ) internal pure returns (uint amountOut) {
        require(params.amountIn != 0);

        uint kLast = params.reserveIn * params.reserveOut;
        uint reserveInAdjusted = params.reserveIn + params.amountIn;
        uint reserveOutAdjusted = kLast / reserveInAdjusted;
        require(reserveOutAdjusted >= params.constantOut);
        uint amountOutGross = params.reserveOut - reserveOutAdjusted;
        amountOut = amountOutGross.computePercentageOf(10e4 - params.fee);
    }

    struct ComputeAmountInParams {
        uint reserveIn;
        uint reserveOut;
        uint constantOut;
        uint amountOut;
        uint24 fee;
    }

    function computeAmountIn(
        ComputeAmountInParams memory params
    ) internal pure returns (uint amountIn) {
        require(params.amountOut != 0);

        uint amountOutGross = params.amountOut.computePartOf(10e4 - params.fee);
        uint kLast = params.reserveIn * params.reserveOut;
        uint reserveOutAdjusted = params.reserveOut - amountOutGross;
        require(reserveOutAdjusted >= params.constantOut);
        uint reserveInAdjusted = kLast.divRoundingUp(reserveOutAdjusted);
        amountIn = reserveInAdjusted - params.reserveIn;
    }

    function computeLiquidity(
        uint reserve0,
        uint reserve1
    ) internal pure returns (uint) {
        return (reserve0 * reserve1).sqrt();
    }

    function computeAmountMint(
        uint totalSupply,
        uint reserve0,
        uint reserve1,
        uint adjusted0,
        uint adjusted1,
        uint24 fee
    ) internal pure returns (uint amount, uint feeToOwner) {
        uint liquidityBefore = PoolMath.computeLiquidity(reserve0, reserve1);
        uint liquidityAfter = PoolMath.computeLiquidity(adjusted0, adjusted1);
        require(liquidityAfter > liquidityBefore);
        uint amountGross = (liquidityAfter - liquidityBefore).mulDiv(
            totalSupply,
            liquidityBefore
        );
        amount = amountGross.computePercentageOf(10e4 - fee);
        feeToOwner = amountGross - amount;
    }

    function computeAmountsBurn(
        uint amount,
        uint totalSupply,
        uint reserve0,
        uint reserve1,
        uint balance0,
        uint balance1
    ) internal pure returns (uint amount0, uint amount1) {
        amount0 = reserve0.mulDiv(amount, totalSupply);
        amount1 = reserve1.mulDiv(amount, totalSupply);
        uint kLast = (reserve0 - amount0) * (reserve1 - amount1);

        if (amount0 > balance0) {
            amount0 = balance0;
            uint reserve1Adjusted = kLast / (reserve0 - amount0);
            amount1 = reserve1 - reserve1Adjusted;
        } else if (amount1 > balance1) {
            amount1 = balance1;
            uint reserve0Adjusted = kLast / (reserve1 - amount1);
            amount0 = reserve0 - reserve0Adjusted;
        }
    }

    function hasLiquidityGrownAfterFees(
        uint reserve0,
        uint reserve1,
        uint adjusted0,
        uint adjusted1,
        uint24 fee
    ) internal pure returns (bool){
        uint liquidityBefore = PoolMath.computeLiquidity(reserve0, reserve1);
        uint liquidityAfterGross = PoolMath.computeLiquidity(adjusted0, adjusted1);
        uint liquidityAfter = liquidityAfterGross.computePercentageOf(10e4 - fee);
        return liquidityAfter >= liquidityBefore;
    }
}
