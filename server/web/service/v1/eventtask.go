package v1

import (
	"aave_web/logger/xzap"
	"aave_web/service"
	"context"
	"encoding/json"
	"go.uber.org/zap"
	"time"
)

type Event struct {
	Type string `json:"type"`
}

func getNotifyQueue() string {
	return "aave:event:CollateralChanged"
}

func PushEvent(wsServer *WSServer, svcCtx *service.ServerCtx) {
	go func() {
		key := getNotifyQueue()
		for {
			ctx := context.Background()
			result, err := svcCtx.KvStore.Lpop(key)
			if err != nil || result == "" {
				time.Sleep(5 * time.Second)
				xzap.WithContext(ctx).Info("no event in redis queue, wait 5s")
				continue
			}
			xzap.WithContext(ctx).Info("get event from redis queue", zap.String("result", result))
			// 从数据库查询相关信息，推送给websocket
			lendData, err := svcCtx.Dao.GetLendData(ctx)
			if err != nil {
				xzap.WithContext(ctx).Warn("failed on GetLendData", zap.Error(err))
				continue
			}
			if lendData != nil {
				// json序列化
				lendDataJson, err := json.Marshal(lendData)
				if err != nil {
					xzap.WithContext(ctx).Warn("failed on json.Marshal lendData", zap.Error(err))
				} else {
					// 广播
					xzap.WithContext(ctx).Info("broadcast lendData to websocket", zap.String("lendDataJson", string(lendDataJson)))
					wsServer.broadcast <- lendDataJson
				}
			}
		}
	}()
}
