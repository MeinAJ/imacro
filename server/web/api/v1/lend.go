package v1

import (
	"aave_web/errcode"
	"aave_web/service"
	v1 "aave_web/service/v1"
	"aave_web/xhttp"
	"github.com/gin-gonic/gin"
)

// GetLendDataHandler 获取lend数据（Utilization Rate、Total Borrow，Total Deposits,Interest(APY)）
func GetLendDataHandler(serverCtx *service.ServerCtx) gin.HandlerFunc {
	return func(c *gin.Context) {
		lendData, err := v1.GetLendData(c, serverCtx)
		if err != nil {
			xhttp.Error(c, errcode.NewCustomErr("Get Lend Data failed."))
			return
		}
		xhttp.OkJson(c, lendData)
	}

}
