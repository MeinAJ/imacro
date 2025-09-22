package service

import (
	"aave_web/config"
	"aave_web/dao"
	"aave_web/logger/xzap"
	"aave_web/stores/gdb"
	"aave_web/stores/xkv"
	"context"
	"github.com/zeromicro/go-zero/core/stores/cache"
	"github.com/zeromicro/go-zero/core/stores/kv"
	"github.com/zeromicro/go-zero/core/stores/redis"
	"gorm.io/gorm"
)

type ServerCtx struct {
	C  *config.Config
	DB *gorm.DB
	//ImageMgr image.ImageManager
	Dao     *dao.Dao
	KvStore *xkv.Store
}

func NewServiceContext(c *config.Config) (*ServerCtx, error) {
	var err error
	// Log
	_, err = xzap.SetUp(c.Log)
	if err != nil {
		return nil, err
	}
	// redis
	var kvConf kv.KvConf
	for _, con := range c.Kv.Redis {
		kvConf = append(kvConf, cache.NodeConf{
			RedisConf: redis.RedisConf{
				Host: con.Host,
				Type: con.Type,
				Pass: con.Pass,
			},
			Weight: 1,
		})
	}
	store := xkv.NewStore(kvConf)
	// db
	db, err := gdb.NewDB(&c.DB)
	if err != nil {
		return nil, err
	}
	d := dao.New(context.Background(), db, store)
	serverCtx := NewServerCtx(
		WithDB(db),
		WithKv(store),
		WithDao(d),
	)
	serverCtx.C = c
	return serverCtx, nil
}

type CtxConfig struct {
	db *gorm.DB
	//imageMgr image.ImageManager
	dao     *dao.Dao
	KvStore *xkv.Store
}

type CtxOption func(conf *CtxConfig)

func NewServerCtx(options ...CtxOption) *ServerCtx {
	c := &CtxConfig{}
	for _, opt := range options {
		opt(c)
	}
	return &ServerCtx{
		DB:      c.db,
		KvStore: c.KvStore,
		Dao:     c.dao,
	}
}

func WithKv(kv *xkv.Store) CtxOption {
	return func(conf *CtxConfig) {
		conf.KvStore = kv
	}
}

func WithDB(db *gorm.DB) CtxOption {
	return func(conf *CtxConfig) {
		conf.db = db
	}
}

func WithDao(dao *dao.Dao) CtxOption {
	return func(conf *CtxConfig) {
		conf.dao = dao
	}
}
