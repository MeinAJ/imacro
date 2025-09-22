package service

import (
	"aave_schedule/chain"
	"aave_schedule/chain/chainclient"
	"aave_schedule/config"
	"aave_schedule/model"
	"aave_schedule/service/event"
	"aave_schedule/stores/xkv"
	"context"
	"fmt"
	"sync"

	"github.com/pkg/errors"
	"github.com/zeromicro/go-zero/core/stores/cache"
	"github.com/zeromicro/go-zero/core/stores/kv"
	"github.com/zeromicro/go-zero/core/stores/redis"
	"gorm.io/gorm"
)

type Service struct {
	ctx          context.Context
	config       *config.Config
	kvStore      *xkv.Store
	db           *gorm.DB
	wg           *sync.WaitGroup
	eventService *event.Service
}

func New(ctx context.Context, cfg *config.Config) (*Service, error) {
	var kvConf kv.KvConf
	for _, con := range cfg.Kv.Redis {
		kvConf = append(kvConf, cache.NodeConf{
			RedisConf: redis.RedisConf{
				Host: con.Host,
				Type: con.Type,
				Pass: con.Pass,
			},
			Weight: 2,
		})
	}

	kvStore := xkv.NewStore(kvConf)

	var err error
	db := model.NewDB(&cfg.DB)
	var eventService *event.Service
	var chainClient chainclient.ChainClient
	fmt.Println("chainClient url:" + cfg.AnkrCfg.HttpsUrl + cfg.AnkrCfg.ApiKey)

	chainClient, err = chainclient.New(int(cfg.ChainCfg.ID), cfg.AnkrCfg.HttpsUrl+cfg.AnkrCfg.ApiKey)
	if err != nil {
		return nil, errors.Wrap(err, "failed on create evm client")
	}

	switch cfg.ChainCfg.ID {
	case chain.EthChainID, chain.OptimismChainID, chain.SepoliaChainID:
		eventService = event.New(ctx, cfg, db, kvStore, chainClient, cfg.ChainCfg.ID, cfg.ChainCfg.Name)
	}

	serviceContext := Service{
		ctx:          ctx,
		config:       cfg,
		db:           db,
		kvStore:      kvStore,
		eventService: eventService,
		wg:           &sync.WaitGroup{},
	}
	return &serviceContext, nil
}

func (s *Service) Start() error {
	// event activities
	s.eventService.Start()
	return nil
}
