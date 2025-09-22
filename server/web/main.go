package main

import (
	"aave_web/api/router"
	"aave_web/app"
	"aave_web/config"
	"aave_web/service"
	"flag"
)

func main() {
	// parse config file
	conf := flag.String("conf", "./config/config.toml", "conf file path")
	flag.Parse()
	c, err := config.ParseConfig(*conf)
	if err != nil {
		panic(err)
	}
	// create service context
	serverCtx, err := service.NewServiceContext(c)
	if err != nil {
		panic(err)
	}
	// Initialize router
	r := router.NewRouter(serverCtx)
	platform, err := app.NewPlatform(c, r, serverCtx)
	if err != nil {
		panic(err)
	}
	platform.Start()
}
