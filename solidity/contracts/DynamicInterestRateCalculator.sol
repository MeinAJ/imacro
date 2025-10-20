// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

library DynamicInterestRateCalculator {
    uint256 public constant PRECISION = 1e18;
    uint256 public constant SECONDS_PER_DAY = 86400;
    uint256 public constant RATE_PRECISION = 1e6; // 6位精度，1000000 = 100%
    uint256 public constant DOLLAR_PRECISION = 1e2; // 美元精度2位

    // 双线动态利率模型参数
    uint256 public constant OPTIMAL_UTILIZATION_RATE = 800000; // 80% 最优利用率
    uint256 public constant BASE_BORROW_RATE = 20000; // 2% 基础利率
    uint256 public constant BASE_SUPPLY_RATE = 10000; // 1% 基础存款利率
    uint256 public constant SLOPE1 = 40000; // 4% 第一段斜率
    uint256 public constant SLOPE2 = 600000; // 60% 第二段斜率

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
        uint256 dailyRate = (_interestRate * PRECISION) / (365 * RATE_PRECISION);

        // 使用更高效的复利计算方法
        uint256 factor = PRECISION;
        uint256 tempDays = daysCount;
        uint256 tempRate = PRECISION + dailyRate;

        // 使用快速幂算法计算复利
        while (tempDays > 0) {
            if (tempDays & 1 == 1) {
                factor = (factor * tempRate) / PRECISION;
            }
            tempRate = (tempRate * tempRate) / PRECISION;
            tempDays >>= 1;
        }

        // 计算总金额：_amount * factor / PRECISION
        uint256 totalAmount = (_amount * factor) / PRECISION;

        // 返回利息部分
        return totalAmount - _amount;
    }

    /**
     * @dev 根据利用率计算动态借贷利率（双线模型）
     * @param _utilizationRate 利用率（6位精度）
     * @return 年化利率（6位精度）
     */
    function calculateBorrowRate(uint256 _utilizationRate) internal pure returns (uint256) {
        if (_utilizationRate <= OPTIMAL_UTILIZATION_RATE) {
            // 第一段：基础利率 + (利用率 / 最优利用率) * 第一段斜率
            return BASE_BORROW_RATE + (_utilizationRate * SLOPE1) / OPTIMAL_UTILIZATION_RATE;
        } else {
            // 第二段：基础利率 + 第一段斜率 + ((利用率 - 最优利用率) / (100% - 最优利用率)) * 第二段斜率
            uint256 excessUtilization = _utilizationRate - OPTIMAL_UTILIZATION_RATE;
            uint256 excessUtilizationRate = (excessUtilization * RATE_PRECISION) / (RATE_PRECISION - OPTIMAL_UTILIZATION_RATE);
            return BASE_BORROW_RATE + SLOPE1 + (excessUtilizationRate * SLOPE2) / RATE_PRECISION;
        }
    }

    /**
     * @dev 根据利用率计算动态存款利率
     * @param _utilizationRate 利用率（6位精度）
     * @param _borrowRate 借贷利率（6位精度）
     * @param _reserveFactor 储备金因子（6位精度，如10% = 100000）
     * @return 年化存款利率（6位精度）
     */
    function calculateSupplyRate(
        uint256 _utilizationRate,
        uint256 _borrowRate,
        uint256 _reserveFactor
    ) internal pure returns (uint256) {
        // 存款利率 = (借款利率 × 利用率) × (1 - 储备金因子)
        return ((_borrowRate * _utilizationRate) / RATE_PRECISION)
            * (RATE_PRECISION - _reserveFactor)
            / RATE_PRECISION;
    }

}
