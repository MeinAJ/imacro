package config

import (
	logging "aave_schedule/logger"
	"aave_schedule/stores/gdb"
	"github.com/spf13/viper"
)

type AnkrCfg struct {
	ApiKey       string `toml:"api_key" mapstructure:"api_key" json:"api_key"`
	HttpsUrl     string `toml:"https_url" mapstructure:"https_url" json:"https_url"`
	WebsocketUrl string `toml:"websocket_url" mapstructure:"websocket_url" json:"websocket_url"`
	EnableWss    bool   `toml:"enable_wss" mapstructure:"enable_wss" json:"enable_wss"`
}

type ChainCfg struct {
	Name string `toml:"name" mapstructure:"name" json:"name"`
	ID   int64  `toml:"id" mapstructure:"id" json:"id"`
}

type Monitor struct {
	PprofEnable bool  `toml:"pprof_enable" mapstructure:"pprof_enable" json:"pprof_enable"`
	PprofPort   int64 `toml:"pprof_port" mapstructure:"pprof_port" json:"pprof_port"`
}

type Config struct {
	Monitor     *Monitor        `toml:"monitor" mapstructure:"monitor" json:"monitor"`
	Log         logging.LogConf `toml:"log" json:"log"`
	DB          gdb.Config      `toml:"db" json:"db"`
	Kv          *KvConf         `toml:"kv" json:"kv"`
	AnkrCfg     AnkrCfg         `toml:"ankr_cfg" mapstructure:"ankr_cfg" json:"ankr_cfg"`
	ChainCfg    ChainCfg        `toml:"chain_cfg" mapstructure:"chain_cfg" json:"chain_cfg"`
	ContractCfg ContractCfg     `toml:"contract_cfg" mapstructure:"contract_cfg" json:"contract_cfg"`
}

type ContractCfg struct {
	AavePoolAddress            string `toml:"aave_pool_address" mapstructure:"aave_pool_address" json:"aave_pool_address"`
	TokenAddressMap            string `toml:"token_address_map" mapstructure:"token_address_map" json:"token_address_map"`
	AbiJson                    string `toml:"abijson" mapstructure:"abijson" json:"abijson"`
	DepositLendTopic           string `toml:"deposit_lend_topic" mapstructure:"deposit_lend_topic" json:"deposit_lend_topic"`
	DepositLendWithdrawTopic   string `toml:"deposit_lend_withdraw_topic" mapstructure:"deposit_lend_withdraw_topic" json:"deposit_lend_withdraw_topic"`
	DepositBorrowTopic         string `toml:"deposit_borrow_topic" mapstructure:"deposit_borrow_topic" json:"deposit_borrow_topic"`
	DepositBorrowWithdrawTopic string `toml:"deposit_borrow_withdraw_topic" mapstructure:"deposit_borrow_withdraw_topic" json:"deposit_borrow_withdraw_topic"`
	LiquidateTopic             string `toml:"liquidate_topic" mapstructure:"liquidate_topic" json:"liquidate_topic"`
	CalculateBorrowableTopic   string `toml:"calculate_borrowable_topic" mapstructure:"calculate_borrowable_topic" json:"calculate_borrowable_topic"`
	StatusChangedTopic         string `toml:"status_changed_topic" mapstructure:"status_changed_topic" json:"status_changed_topic"`
	CollateralChangedTopic     string `toml:"collateral_changed_topic" mapstructure:"collateral_changed_topic" json:"collateral_changed_topic"`
}

type KvConf struct {
	Redis []*Redis `toml:"redis" mapstructure:"redis" json:"redis"`
}

type Redis struct {
	MasterName string `toml:"master_name" mapstructure:"master_name" json:"master_name"`
	Host       string `toml:"host" json:"host"`
	Type       string `toml:"type" json:"type"`
	Pass       string `toml:"pass" json:"pass"`
}

// UnmarshalCmdConfig unmarshal conifg file
func UnmarshalCmdConfig() (*Config, error) {
	if err := viper.ReadInConfig(); err != nil {
		return nil, err
	}
	var c Config
	if err := viper.Unmarshal(&c); err != nil {
		return nil, err
	}
	return &c, nil
}

func DefaultConfig() (*Config, error) {
	return &Config{}, nil
}
