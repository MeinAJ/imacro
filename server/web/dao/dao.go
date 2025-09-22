package dao

import (
	"aave_web/stores/xkv"
	"context"
	"gorm.io/gorm"
)

// Dao is show dao.
type Dao struct {
	ctx     context.Context
	DB      *gorm.DB
	KvStore *xkv.Store
}

func New(ctx context.Context, db *gorm.DB, kvStore *xkv.Store) *Dao {
	return &Dao{
		ctx:     ctx,
		DB:      db,
		KvStore: kvStore,
	}
}
