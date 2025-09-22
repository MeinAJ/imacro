create table aave.lend
(
    id               bigint auto_increment primary key not null comment '主键ID,自增',
    type             int8                              not null default 0 comment '贷款类型；0:USDC',
    total_borrow     decimal(32, 2)                    not null default 0 comment '总借出金额，usdc换算成的dollar，保留两小数',
    total_deposits   decimal(32, 2)                    not null default 0 comment '总存入金额，usdc换算成的dollar，保留两小数',
    utilization_rate decimal(4, 2)                     not null default 0 comment '利用率，保留两位小数，百分比，例子：10.02%',
    apy_interest     decimal(4, 2)                     not null comment '动态年化利率，保留两位小数，百分比，例子：10.02%',
    create_time      timestamp                         not null comment '创建时间',
    update_time      timestamp                         not null comment '更新时间',
    creator          char(42)                          not null comment '创建人',
    updater          char(42)                          not null comment '更新人'
);


create table aave.collateral
(
    id               bigint auto_increment primary key not null comment '主键ID,自增',
    type             int8                              not null default 0 comment '抵押代币类型；0:TOSHI，1:DEGEN',
    borrowed         decimal(32, 2)                    not null default 0 comment '总借出金额，usdc换算成的dollar，保留两小数',
    borrowable       decimal(32, 2)                    not null default 0 comment '总可借金额，usdc换算成的dollar，保留两小数',
    utilization_rate decimal(4, 2)                     not null default 0 comment '利用率，保留两位小数，百分比，例子：10.02%',
    apy_interest     decimal(4, 2)                     not null comment '动态年化利率',
    create_time      timestamp                         not null comment '创建时间',
    update_time      timestamp                         not null comment '更新时间',
    creator          char(42)                          not null comment '创建人',
    updater          char(42)                          not null comment '更新人'
)