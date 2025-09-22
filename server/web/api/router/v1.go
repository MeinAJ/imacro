package router

import (
	v1 "aave_web/api/v1"
	"aave_web/service"
	v2 "aave_web/service/v1"
	"github.com/gin-gonic/gin"
)

func loadV1(r *gin.Engine, svcCtx *service.ServerCtx) {
	apiV1 := r.Group("/api/v1")

	lend := apiV1.Group("/lend")
	{
		lend.GET("/detail", v1.GetLendDataHandler(svcCtx)) // 获取lend详情
	}

	borrow := apiV1.Group("/borrow")
	{
		borrow.GET("/detail", v1.GetBorrowDataHandler(svcCtx)) // 获取borrow详情
	}

	// 添加WebSocket路由
	ws := apiV1.Group("/ws")
	{
		// websocket
		wsServer := v2.NewWSServer(svcCtx)
		// 创建推送广播
		v2.PushEvent(wsServer, svcCtx)
		ws.GET("", v2.HandleWebSocket(wsServer))
	}

}
