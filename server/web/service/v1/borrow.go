package v1

import (
	"aave_web/service"
	v1 "aave_web/types/v1"
	"context"

	"github.com/pkg/errors"
)

func GetBorrowData(ctx context.Context, svcCtx *service.ServerCtx, collateralAsset int) (*v1.Collateral, error) {
	borrow, err := svcCtx.Dao.GetBorrowData(ctx, collateralAsset)
	if err != nil {
		return nil, errors.Wrap(err, "failed on query borrow data")
	}
	return borrow, nil
}
