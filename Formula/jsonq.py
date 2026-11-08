#!/usr/bin/env python3
"""jsonq: read, filter and format JSON. A small jq.

  jsonq [-c] [-r] FILTER [FILE]     FILE or the piped text
  FILTER: .  .a.b  .a[0]  .[]  .a[]  keys  length  values  type  sort  sum  min  max  unique  first  last
          select(.a > 1)   map(.a)   FILTER | FILTER"""
import json
import sys


class JqError(Exception):
    pass


def split_top(text, sep):
    parts, depth, cur, quote = [], 0, "", None
    for ch in text:
        if quote:
            cur += ch
            if ch == quote:
                quote = None
            continue
        if ch == '"':
            quote = ch
        if ch in "([":
            depth += 1
        elif ch in ")]":
            depth -= 1
        if ch == sep and depth == 0:
            parts.append(cur)
            cur = ""
        else:
            cur += ch
    parts.append(cur)
    return parts


def path_step(values, step):
    out = []
    for v in values:
        if step == "":
            out.append(v)
        elif step == "[]":
            if isinstance(v, dict):
                out.extend(v.values())
            elif isinstance(v, list):
                out.extend(v)
            else:
                raise JqError("cannot iterate over %s" % type_name(v))
        elif step.startswith("["):
            index = int(step[1:-1])
            if not isinstance(v, list):
                raise JqError("cannot index %s with number" % type_name(v))
            out.append(v[index] if -len(v) <= index < len(v) else None)
        else:
            if v is None:
                out.append(None)
            elif not isinstance(v, dict):
                raise JqError("cannot index %s with \"%s\"" % (type_name(v), step))
            else:
                out.append(v.get(step))
    return out


def run_path(expr, values):
    i = 1
    if expr == ".":
        return values
    while i < len(expr) or i == 1:
        if i >= len(expr):
            break
        if expr[i] == "[":
            end = expr.index("]", i)
            values = path_step(values, expr[i:end + 1])
            i = end + 1
        else:
            if expr[i] == ".":
                i += 1
            start = i
            while i < len(expr) and expr[i] not in ".[":
                i += 1
            values = path_step(values, expr[start:i])
    return values


def type_name(v):
    if v is None:
        return "null"
    if isinstance(v, bool):
        return "boolean"
    if isinstance(v, (int, float)):
        return "number"
    if isinstance(v, str):
        return "string"
    if isinstance(v, list):
        return "array"
    return "object"


def literal(text):
    text = text.strip()
    if text.startswith("."):
        return None, text
    return json.loads(text), None


def compare(left, op, right):
    if op == "==":
        return left == right
    if op == "!=":
        return left != right
    if left is None or right is None:
        return False
    if op == ">":
        return left > right
    if op == "<":
        return left < right
    if op == ">=":
        return left >= right
    return left <= right


def condition(text, value):
    for op in ("==", "!=", ">=", "<=", ">", "<"):
        k = text.find(op)
        if k >= 0:
            lit, path = literal(text[k + len(op):])
            right = lit if path is None else run_path(path, [value])[0]
            left = run_filter(text[:k].strip(), [value])[0]
            return compare(left, op, right)
    r = run_filter(text.strip(), [value])
    return bool(r and r[0] not in (None, False))


def one(name, v):
    if name == "keys":
        if isinstance(v, dict):
            return sorted(v.keys())
        return list(range(len(v)))
    if name == "values":
        return list(v.values()) if isinstance(v, dict) else list(v)
    if name == "length":
        return 0 if v is None else len(v) if not isinstance(v, (int, float)) else abs(v)
    if name == "type":
        return type_name(v)
    if name == "sort":
        return sorted(v)
    if name == "reverse":
        return list(reversed(v))
    if name == "sum" or name == "add":
        if not v:
            return None
        total = v[0]
        for item in v[1:]:
            total = total + item
        return total
    if name == "min":
        return min(v) if v else None
    if name == "max":
        return max(v) if v else None
    if name == "unique":
        return sorted(set(v))
    if name == "first":
        return v[0] if v else None
    if name == "last":
        return v[-1] if v else None
    if name == "tostring":
        return v if isinstance(v, str) else json.dumps(v)
    if name == "tonumber":
        return float(v) if "." in str(v) else int(v)
    if name == "ascii_downcase":
        return v.lower()
    if name == "ascii_upcase":
        return v.upper()
    raise JqError("%s is not defined" % name)


def run_filter(expr, values):
    expr = expr.strip()
    parts = split_top(expr, "|")
    if len(parts) > 1:
        for part in parts:
            values = run_filter(part, values)
        return values
    if expr.startswith("."):
        return run_path(expr, values)
    if expr.startswith("select(") and expr.endswith(")"):
        return [v for v in values if condition(expr[7:-1], v)]
    if expr.startswith("map(") and expr.endswith(")"):
        inner = expr[4:-1]
        return [run_filter(inner, list(v.values()) if isinstance(v, dict) else v) for v in values]
    if expr[:1] in '"0123456789-' or expr in ("null", "true", "false"):
        return [json.loads(expr) for _ in values]
    return [one(expr, v) for v in values]


def show(v, compact, raw):
    if raw and isinstance(v, str):
        return v
    if compact:
        return json.dumps(v, separators=(",", ":"))
    return json.dumps(v, indent=2)


def main(argv):
    compact = raw = False
    words = []
    for a in argv:
        if a == "-c":
            compact = True
        elif a == "-r":
            raw = True
        elif a == "-cr" or a == "-rc":
            compact = raw = True
        elif a in ("-h", "--help"):
            print(__doc__)
            return 0
        else:
            words.append(a)
    if not words:
        print(__doc__)
        return 2
    expr = words[0]
    if len(words) > 1:
        try:
            with open(words[1]) as f:
                text = f.read()
        except OSError as e:
            print("jsonq: %s: %s" % (words[1], e.strerror), file=sys.stderr)
            return 2
    else:
        text = sys.stdin.read()
    try:
        data = json.loads(text)
    except ValueError as e:
        print("jsonq: not JSON: %s" % e, file=sys.stderr)
        return 2
    try:
        for v in run_filter(expr, [data]):
            print(show(v, compact, raw))
    except JqError as e:
        print("jsonq: error: %s" % e, file=sys.stderr)
        return 5
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
