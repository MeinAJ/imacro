// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

library DynamicInterestRateCalculator {
    uint256 public constant PRECISION = 1e18;
    uint256 public constant SECONDS_PER_DAY = 86400;
    uint256 public constant RATE_PRECISION = 1e6; // 6位精度，1000000 = 100%
    uint256 public constant DOLLAR_PRECISION = 1e2; // 美元精度2位

    // 双线动态利率模型参数
    uint256 public constant OPTIMAL_UTILIZATION_RATE = 800000; // 80% 最优利用率
    uint256 public constant BASE_RATE = 20000; // 2% 基础利率
    uint256 public constant SLOPE1 = 40000; // 4% 第一段斜率
    uint256 public constant SLOPE2 = 600000; // 60% 第二段斜率

    /**
     * @dev 根据利用率计算动态借贷利率（双线模型）
     * @param _utilizationRate 利用率（6位精度）
     * @return 年化利率（6位精度）
     */
    function calculateBorrowRate(uint256 _utilizationRate) internal pure returns (uint256) {
        if (_utilizationRate <= OPTIMAL_UTILIZATION_RATE) {
            // 第一段：基础利率 + (利用率 / 最优利用率) * 第一段斜率
            return BASE_RATE + (_utilizationRate * SLOPE1) / OPTIMAL_UTILIZATION_RATE;
        } else {
            // 第二段：基础利率 + 第一段斜率 + ((利用率 - 最优利用率) / (100% - 最优利用率)) * 第二段斜率
            uint256 excessUtilization = _utilizationRate - OPTIMAL_UTILIZATION_RATE;
            uint256 excessUtilizationRate = (excessUtilization * RATE_PRECISION) / (RATE_PRECISION - OPTIMAL_UTILIZATION_RATE);
            return BASE_RATE + SLOPE1 + (excessUtilizationRate * SLOPE2) / RATE_PRECISION;
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
        // 存款利率 = 利用率 * 借贷利率 * (1 - 储备金因子)
        uint256 rateToPool = (_borrowRate * (RATE_PRECISION - _reserveFactor)) / RATE_PRECISION;
        return (_utilizationRate * rateToPool) / RATE_PRECISION;
    }

}
