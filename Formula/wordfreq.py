#!/usr/bin/env python3
# wordfreq: the most frequent words of a text file. A Python program, installed like any other. usage: wordfreq FILE [HOW_MANY]
import re, sys
from collections import Counter

if len(sys.argv) < 2:
    print("usage: wordfreq FILE [HOW_MANY]")
    sys.exit(1)
how_many = int(sys.argv[2]) if len(sys.argv) > 2 else 10
with open(sys.argv[1]) as f:
    words = re.findall(r"[a-z']+", f.read().lower())
for word, n in Counter(words).most_common(how_many):
    print(f"{n:6d} {word}")
