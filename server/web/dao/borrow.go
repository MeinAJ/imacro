package dao

import (
	v1 "aave_web/types/v1"
	"context"
)

// GetBorrowData 获取borrow数据（Utilization Rate、Borrowed，Borrowable,Interest(APY)）
func (d *Dao) GetBorrowData(ctx context.Context, collateralAsset int) (*v1.Collateral, error) {
	var newItem v1.Collateral
	borrowDb := d.DB.WithContext(ctx).
		Table(v1.GetCollateralTableName()).
		Select("utilization_rate, borrowed, borrowable, interest_rate, create_time, update_time, type, id, creator, updater").
		Where("type =?", collateralAsset).
		Order("id DESC").
		Limit(1)
	if err := borrowDb.Scan(&newItem).Error; err != nil {
		return &v1.Collateral{}, err
	}
	return &newItem, nil
}
