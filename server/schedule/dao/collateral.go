package dao

import (
	"aave_schedule/types"
	"context"
)

// GetCollateralData 获取borrow数据（Utilization Rate、Borrowed，Borrowable,Interest(APY)）
func (d *Dao) GetCollateralData(ctx context.Context, collateralAsset int) (*types.Collateral, error) {
	var newItem types.Collateral
	borrowDb := d.DB.WithContext(ctx).
		Table(types.GetCollateralTableName()).
		Select("utilization_rate, borrowed, borrowable, interest_rate, create_time, update_time, type, id, creator, updater").
		Where("type =?", collateralAsset).
		Order("create_time DESC").
		Limit(1)
	if err := borrowDb.Scan(&newItem).Error; err != nil {
		return &types.Collateral{}, err
	}
	return &newItem, nil
}
