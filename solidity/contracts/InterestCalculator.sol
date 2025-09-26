// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

library InterestCalculator {
    uint256 public constant PRECISION = 1e18;
    uint256 public constant SECONDS_PER_DAY = 86400;
    uint256 public constant RATE_PRECISION = 1e6;

    /**
     * @dev 计算每日复利的利息
     * @param _amount 本金金额（18位精度）
     * @param _interestRate 年化利率（6位精度，如10% = 100000）
     * @param _elapsedTime 经过的时间（秒）
     * @return 利息金额（18位精度）
     */
    function calculateCompoundInterest(
        uint256 _amount,
        uint256 _interestRate,
        uint256 _elapsedTime
    ) internal pure returns (uint256) {
        if (_elapsedTime == 0 || _amount == 0 || _interestRate == 0) {
            return 0;
        }

        // 计算天数（向下取整）
        uint256 daysCount = _elapsedTime / SECONDS_PER_DAY;

        if (daysCount == 0) {
            return 0;
        }

        // 计算日利率（18位精度）
        // 100000 * 1e18 / 365 / 1e6
        uint256 dailyRate = (_interestRate * PRECISION) / (365 * RATE_PRECISION);

        // 计算复利因子 (1 + dailyRate/PRECISION)^daysCount
        uint256 factor = PRECISION;

        for (uint256 i = 0; i < daysCount; i++) {
            // 1e18 * (1e18 + (100000 * 1e18 / 365 / 1e6)) / 1e18
            factor = (factor * (PRECISION + dailyRate)) / PRECISION;
        }

        // 计算总金额：_amount * factor / PRECISION
        uint256 totalAmount = (_amount * factor) / PRECISION;

        // 返回利息部分
        return totalAmount - _amount;
    }
}