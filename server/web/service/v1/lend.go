package v1

import (
	"aave_web/service"
	v1 "aave_web/types/v1"
	"context"

	"github.com/pkg/errors"
)

func GetLendData(ctx context.Context, svcCtx *service.ServerCtx) (*v1.Lend, error) {
	lend, err := svcCtx.Dao.GetLendData(ctx)
	if err != nil {
		return nil, errors.Wrap(err, "failed on query lend data")
	}
	return lend, nil
}
