package main

import (
	"fmt"
	"os"
)

var version = "0.57"

func printScript(label string, content []byte) {
	fmt.Println("### " + label + " ###")
	fmt.Println(string(content))
	fmt.Println("### end: " + label + " ###")
}

func exit(code int, err error) {
	if err != nil {
		fmt.Fprintln(os.Stderr, err.Error())
	}
	os.Exit(code)
}

func main() {
	args := os.Args[1:]

	if len(args) == 0 {
		fmt.Println("No arguments provided")
		return
	}

	if args[0] == "--version" {
		fmt.Println(version)
		return
	}

	if args[0] == "--help" {
		fmt.Println("Usage: program [options]")
		return
	}

	fmt.Printf("Processing: %v\n", args)
}