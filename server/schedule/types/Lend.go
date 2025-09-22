package types

/**
-- auto-generated definition
create table lend
(
    id               bigint auto_increment comment '主键ID,自增'
        primary key,
    type             int default 0 not null comment '贷款类型；0:USDC',
    total_borrow     varchar(100)  not null comment '总借出金额，usdc换算成的dollar，保留两小数',
    total_deposits   varchar(100)  not null comment '总存入金额，usdc换算成的dollar，保留两小数',
    utilization_rate int default 0 not null comment '利用率，保留两位小数，百分比，例子：10.02%',
    interest_rate    int default 0 not null comment '动态年化利率，保留两位小数，百分比，例子：10.02%',
    create_time      int           not null comment '创建时间',
    update_time      int           not null comment '更新时间',
    creator          char(42)      not null comment '创建人',
    updater          char(42)      not null comment '更新人'
);
*/

// Lend 根据上面的表结构，我们可以定义一个Lend结构体
type Lend struct {
	ID              int64  `gorm:"column:id;primaryKey;autoIncrement" json:"id"`
	Type            int    `gorm:"column:type;not null;default:0" json:"type"`
	TotalBorrow     string `gorm:"column:total_borrow;not null;default:0" json:"total_borrow"`
	TotalDeposits   string `gorm:"column:total_deposits;not null;default:0" json:"total_deposits"`
	UtilizationRate int    `gorm:"column:utilization_rate;not null;default:0" json:"utilization_rate"`
	InterestRate    int    `gorm:"column:interest_rate;not null" json:"interest_rate"`
	CreateTime      int    `gorm:"column:create_time;not null" json:"create_time"`
	UpdateTime      int    `gorm:"column:update_time;not null" json:"update_time"`
	Creator         string `gorm:"column:creator;not null;default:''" json:"creator"`
	Updater         string `gorm:"column:updater;not null;default:''" json:"updater"`
}

func GetLendTableName() string {
	return "lend"
}
