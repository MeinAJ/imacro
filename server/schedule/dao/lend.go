package dao

import (
	"aave_schedule/types"
	"context"
)

// GetLendData 获取lend数据（Utilization Rate、Total Borrow，Total Deposits,Interest(APY)）
func (d *Dao) GetLendData(ctx context.Context) (*types.Lend, error) {
	var newItem types.Lend
	lendDb := d.DB.WithContext(ctx).
		Table(types.GetLendTableName()).
		Select("utilization_rate, total_borrow, total_deposits, interest_rate").
		Where("type =?", 0).
		Order("create_time DESC").
		Limit(1)
	if err := lendDb.Scan(&newItem).Error; err != nil {
		return &types.Lend{}, err
	}
	return &newItem, nil
}
