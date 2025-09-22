package types

/**
create table aave.indexed_status
(
    id                 bigint auto_increment primary key not null comment '主键ID,自增',
    chain_id           bigint  default 1                 not null comment '链id (1:以太坊, 56: BSC)',
    last_indexed_block bigint  default 0                 null comment '区块号',
    last_indexed_time  bigint                            null comment '最后同步时间戳',
    index_type         tinyint default 0                 not null comment '0:activity',
    create_time        bigint                            null comment '创建时间戳',
    update_time        bigint                            null comment '更新时间戳'
);
*/

// IndexedStatus 根据上面的表结构，我们可以定义一个IndexedStatus结构体
type IndexedStatus struct {
	ID               int64  `json:"id"`
	ChainID          int64  `json:"chain_id"`
	LastIndexedBlock int64  `json:"last_indexed_block"`
	LastIndexedTime  int64  `json:"last_indexed_time"`
	IndexType        int8   `json:"index_type"`
	CreateTime       int64  `json:"create_time"`
	UpdateTime       int64  `json:"update_time"`
	Creator          string `json:"creator"`
	Updater          string `json:"updater"`
}

func GetIndexedStatusTableName() string {
	return "indexed_status"
}
