#!/usr/bin/env go -run
// pingpong: two goroutines pass a ball over channels, a Go program. usage: pingpong [ROUNDS]
package main

import (
	"fmt"
	"os"
	"strconv"
)

func player(name string, in <-chan int, out chan<- int, done chan<- bool, rounds int) {
	for ball := range in {
		fmt.Println(name, ball)
		if ball >= rounds {
			done <- true
			return
		}
		out <- ball + 1
	}
}

func main() {
	rounds := 4
	if len(os.Args) > 1 {
		if n, err := strconv.Atoi(os.Args[1]); err == nil {
			rounds = n
		}
	}
	a, b := make(chan int), make(chan int)
	done := make(chan bool)
	go player("ping", a, b, done, rounds)
	go player("pong", b, a, done, rounds)
	a <- 1
	<-done
	fmt.Println("done")
}
