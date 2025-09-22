package v1

/**
-- auto-generated definition
create table collateral
(
    id                     bigint auto_increment comment '主键ID,自增'
        primary key,
    token_address          varchar(100)             not null,
    type                   int          default 0   not null comment '抵押代币类型；0:TOSHI，1:DEGEN',
    borrowed               varchar(100) default '0' not null comment '总借出金额，usdc换算成的dollar，保留两小数',
    borrowable             varchar(100) default '0' not null comment '总可借金额，usdc换算成的dollar，保留两小数',
    utilization_rate       int          default 0   not null comment '利用率，保留两位小数，百分比，例子：10.02%',
    interest_rate          int          default 0   not null comment '动态年化利率',
    liquidation_threshold  int          default 0   not null,
    collateralization_rate int          default 0   not null,
    create_time            int                      not null comment '创建时间',
    update_time            int                      not null comment '更新时间',
    creator                char(42)                 not null comment '创建人',
    updater                char(42)                 not null comment '更新人'
);
*/

// Collateral 根据上面的表结构，我们可以定义一个Collateral结构体
type Collateral struct {
	ID                    int64  `gorm:"column:id;primaryKey;autoIncrement" json:"id"`
	TokenAddress          string `gorm:"column:token_address;not null" json:"token_address"`
	Type                  int    `gorm:"column:type;default:0;not null" json:"type"`
	Borrowed              string `gorm:"column:borrowed;default:'0';not null" json:"borrowed"`
	Borrowable            string `gorm:"column:borrowable;default:'0';not null" json:"borrowable"`
	UtilizationRate       int    `gorm:"column:utilization_rate;default:0;not null" json:"utilization_rate"`
	InterestRate          int    `gorm:"column:interest_rate;not null" json:"interest_rate"`
	HealthFactor          int    `gorm:"column:health_factor;default:0;not null" json:"health_factor"`
	LiquidationThreshold  int    `gorm:"column:liquidation_threshold;default:0;not null" json:"liquidation_threshold"`
	CollateralizationRate int    `gorm:"column:collateralization_rate;not null" json:"collateralization_rate"`
	CreateTime            int    `gorm:"column:create_time;not null" json:"create_time"`
	UpdateTime            int    `gorm:"column:update_time;not null" json:"update_time"`
	Creator               string `gorm:"column:creator;not null" json:"creator"`
	Updater               string `gorm:"column:updater;not null" json:"updater"`
}

func GetCollateralTableName() string {
	return "collateral"
}
