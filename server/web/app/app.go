package app

import (
	"aave_web/config"
	"aave_web/logger/xzap"
	"aave_web/service"
	"context"
	"github.com/gin-gonic/gin"

	"go.uber.org/zap"
)

type Platform struct {
	config    *config.Config
	router    *gin.Engine
	serverCtx *service.ServerCtx
}

func NewPlatform(config *config.Config, router *gin.Engine, serverCtx *service.ServerCtx) (*Platform, error) {
	return &Platform{
		config:    config,
		router:    router,
		serverCtx: serverCtx,
	}, nil
}

func (p *Platform) Start() {
	xzap.WithContext(context.Background()).Info("Aave-End run", zap.String("port", p.config.Api.Port))
	if err := p.router.Run(p.config.Api.Port); err != nil {
		panic(err)
	}
}
