package dao

import (
	v1 "aave_web/types/v1"
	"context"
)

// GetLendData 获取lend数据（Utilization Rate、Total Borrow，Total Deposits,Interest(APY)）
func (d *Dao) GetLendData(ctx context.Context) (*v1.Lend, error) {
	var newItem v1.Lend
	lendDb := d.DB.WithContext(ctx).
		Table(v1.GetLendTableName()).
		Select("utilization_rate, total_borrow, total_deposits, interest_rate").
		Where("type =?", 0).
		Order("id DESC").
		Limit(1)
	if err := lendDb.Scan(&newItem).Error; err != nil {
		return &v1.Lend{}, err
	}
	return &newItem, nil
}
