package main

import (
	"os"

	"use-practice/internal/cli"
)

func main() {
	app := cli.NewApp()
	os.Exit(app.Run(os.Args[1:]))
}
