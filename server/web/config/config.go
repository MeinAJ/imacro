package config

import (
	logging "aave_web/logger"
	"aave_web/stores/gdb"
	"github.com/spf13/viper"
	"strings"
)

type Config struct {
	Api `toml:"api" json:"api"`
	Log logging.LogConf `toml:"log" json:"log"`
	DB  gdb.Config              `toml:"db" json:"db"`
	Kv  *KvConf         `toml:"kv" json:"kv"`
}

type Api struct {
	Port   string `toml:"port" json:"port"`
	MaxNum int64  `toml:"max_num" json:"max_num"`
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

func ParseConfig(configFilePath string) (*Config, error) {
	viper.SetConfigFile(configFilePath)
	viper.SetConfigType("toml")
	viper.AutomaticEnv()
	viper.SetEnvPrefix("CNFT")
	replacer := strings.NewReplacer(".", "_")
	viper.SetEnvKeyReplacer(replacer)

	if err := viper.ReadInConfig(); err != nil {
		return nil, err
	}
	config, err := DefaultConfig()
	if err != nil {
		return nil, err
	}

	if err := viper.Unmarshal(config); err != nil {
		return nil, err
	}
	return config, nil
}

func DefaultConfig() (*Config, error) {
	return &Config{}, nil
}
