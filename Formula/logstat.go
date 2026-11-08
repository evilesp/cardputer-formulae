// logstat: reads a log file and shows what is in it: the lines per level, per hour and the most frequent messages.
//   logstat [-n TOP] [-level WORD] FILE    or a pipe
package main

import (
	"bufio"
	"flag"
	"fmt"
	"os"
	"regexp"
	"sort"
	"strings"
)

type counter struct {
	name  string
	count int
}

func sorted(m map[string]int) []counter {
	out := make([]counter, 0, len(m))
	for k, v := range m {
		out = append(out, counter{k, v})
	}
	sort.Slice(out, func(i, j int) bool {
		if out[i].count != out[j].count {
			return out[i].count > out[j].count
		}
		return out[i].name < out[j].name
	})
	return out
}

func levelOf(line string) string {
	up := strings.ToUpper(line)
	for _, l := range []string{"FATAL", "ERROR", "WARN", "INFO", "DEBUG"} {
		if strings.Contains(up, l) {
			return l
		}
	}
	return "OTHER"
}

func bar(n, most int) string {
	if most == 0 {
		return ""
	}
	return strings.Repeat("#", n*20/most)
}

func main() {
	top := flag.Int("n", 5, "how many messages to show")
	only := flag.String("level", "", "only this level")
	flag.Parse()
	var in *os.File = os.Stdin
	if flag.NArg() > 0 {
		f, err := os.Open(flag.Arg(0))
		if err != nil {
			fmt.Fprintln(os.Stderr, "logstat:", err)
			os.Exit(1)
		}
		defer f.Close()
		in = f
	}
	digits := regexp.MustCompile(`[0-9]+`)
	hour := regexp.MustCompile(`[ T]([0-9][0-9]):[0-9][0-9]`)
	levels := map[string]int{}
	hours := map[string]int{}
	messages := map[string]int{}
	total := 0
	sc := bufio.NewScanner(in)
	for sc.Scan() {
		line := sc.Text()
		if strings.TrimSpace(line) == "" {
			continue
		}
		lv := levelOf(line)
		if *only != "" && lv != strings.ToUpper(*only) {
			continue
		}
		total++
		levels[lv]++
		if m := hour.FindStringSubmatch(line); m != nil {
			hours[m[1]]++
		}
		i := strings.Index(strings.ToUpper(line), lv)
		text := line
		if i >= 0 && lv != "OTHER" {
			text = line[i+len(lv):]
		}
		text = strings.Trim(text, " :]-")
		messages[digits.ReplaceAllString(text, "N")]++
	}
	fmt.Printf("%d lines\n", total)
	fmt.Println("levels")
	ls := sorted(levels)
	for _, c := range ls {
		fmt.Printf("  %-6s %6d %s\n", c.name, c.count, bar(c.count, ls[0].count))
	}
	if len(hours) > 0 {
		fmt.Println("hours")
		keys := make([]string, 0, len(hours))
		most := 0
		for k, v := range hours {
			keys = append(keys, k)
			if v > most {
				most = v
			}
		}
		sort.Strings(keys)
		for _, k := range keys {
			fmt.Printf("  %s:00 %6d %s\n", k, hours[k], bar(hours[k], most))
		}
	}
	fmt.Println("most frequent")
	for i, c := range sorted(messages) {
		if i >= *top {
			break
		}
		fmt.Printf("  %5d  %s\n", c.count, c.name)
	}
}
