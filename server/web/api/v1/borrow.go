package v1

import (
	"aave_web/errcode"
	"aave_web/service"
	v1 "aave_web/service/v1"
	"aave_web/xhttp"
	"github.com/gin-gonic/gin"
	"strconv"
)

// GetBorrowDataHandler 获取borrow数据（Utilization Rate、Borrowed，Borrowable,Interest(APY)）
func GetBorrowDataHandler(serverCtx *service.ServerCtx) gin.HandlerFunc {
	return func(c *gin.Context) {
		// string c.Param("collateralAsset") 转uint64
		collateralAssetString, _ := c.GetQuery("collateralAsset")
		collateralAsset, err := strconv.Atoi(collateralAssetString)
		if err != nil {
			return
		}
		borrowData, err := v1.GetBorrowData(c, serverCtx, collateralAsset)
		if err != nil {
			xhttp.Error(c, errcode.NewCustomErr("Get borrow data failed."))
			return
		}
		xhttp.OkJson(c, borrowData)
	}

}
