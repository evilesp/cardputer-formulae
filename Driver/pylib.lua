#!lua
-- pylib: the library of Python written in Python, for the programs of python3. Each module is translated when it is first imported (tools/linux2esp.py does it on the computer).
return {
["argparse"] = [==[
import sys, os

SUPPRESS = "==SUPPRESS=="
OPTIONAL = "?"
ZERO_OR_MORE = "*"
ONE_OR_MORE = "+"
REMAINDER = "..."

class ArgumentError(Exception):
    pass

class ArgumentTypeError(Exception):
    pass

class Namespace:
    def __init__(self, **kw):
        for k in kw:
            setattr(self, k, kw[k])
    def __repr__(self):
        return "Namespace(" + ", ".join("%s=%r" % (k, v) for k, v in sorted(self.__dict__.items())) + ")"
    def __contains__(self, k):
        return k in self.__dict__

class HelpFormatter:
    def __init__(self, prog=None, **kw):
        pass

RawDescriptionHelpFormatter = HelpFormatter
RawTextHelpFormatter = HelpFormatter
ArgumentDefaultsHelpFormatter = HelpFormatter
MetavarTypeHelpFormatter = HelpFormatter

class FileType:
    def __init__(self, mode="r", **kw):
        self.mode = mode
    def __call__(self, name):
        if name == "-":
            return sys.stdin if "r" in self.mode else sys.stdout
        return open(name, self.mode)

class _Action:
    def __init__(self, flags, dest, action, nargs, const, default, type, choices, required, help, metavar):
        self.flags = flags
        self.option_strings = flags
        self.dest = dest
        self.action = action
        self.nargs = nargs
        self.const = const
        self.default = default
        self.type = type
        self.choices = choices
        self.required = required
        self.help = help
        self.metavar = metavar

class Action:
    def __init__(self, option_strings, dest, nargs=None, const=None, default=None, type=None, choices=None, required=False, help=None, metavar=None):
        self.option_strings = option_strings
        self.dest = dest
        self.nargs = nargs
        self.const = const
        self.default = default
        self.type = type
        self.choices = choices
        self.required = required
        self.help = help
        self.metavar = metavar
    def __call__(self, parser, namespace, values, option_string=None):
        raise NotImplementedError("Action")

class _Group:
    def __init__(self, parser, title=None, description=None, required=False):
        self.parser = parser
        self.title = title
        self.description = description
        self.required = required
    def add_argument(self, *a, **k):
        return self.parser.add_argument(*a, **k)
    def add_argument_group(self, *a, **k):
        return self.parser.add_argument_group(*a, **k)
    def add_mutually_exclusive_group(self, **k):
        return _Group(self.parser)
    def set_defaults(self, **k):
        return self.parser.set_defaults(**k)

class _Sub:
    def __init__(self, parent, dest, required):
        self.parent = parent
        self.dest = dest
        self.required = required
        self.parsers = {}
        self.helps = {}
    def add_parser(self, name, **kw):
        h = kw.pop("help", None)
        kw.pop("aliases", None)
        kw["prog"] = self.parent.prog + " " + name
        p = ArgumentParser(**kw)
        self.parsers[name] = p
        self.helps[name] = h
        return p

class ArgumentParser:
    def __init__(self, prog=None, usage=None, description=None, epilog=None, parents=None, formatter_class=None, prefix_chars="-", fromfile_prefix_chars=None, argument_default=None, conflict_handler="error", add_help=True, allow_abbrev=True, exit_on_error=True):
        self.prog = prog or (os.path.basename(sys.argv[0]) if sys.argv else "program")
        self.usage = usage
        self.description = description
        self.epilog = epilog
        self.actions = []
        self.defaults = {}
        self.sub = None
        self.allow_abbrev = allow_abbrev
        if add_help:
            self.add_argument("-h", "--help", action="help", help="show this help message and exit")
        for p in parents or []:
            for a in p.actions:
                if a.action != "help":
                    self.actions.append(a)
            self.defaults.update(p.defaults)

    def add_argument(self, *flags, **kw):
        action = kw.get("action", "store")
        dest = kw.get("dest")
        options = [f for f in flags if f.startswith("-")]
        if not dest:
            if options:
                longs = [f for f in options if f.startswith("--")]
                dest = (longs[0] if longs else options[0]).lstrip("-").replace("-", "_")
            else:
                dest = flags[0]
        default = kw.get("default")
        const = kw.get("const")
        if action == "store_true":
            if "default" not in kw:
                default = False
            const = True
        elif action == "store_false":
            if "default" not in kw:
                default = True
            const = False
        elif action == "count" or action == "append" or action == "extend":
            pass
        required = kw.get("required", False)
        a = _Action(options, dest, action, kw.get("nargs"), const, default, kw.get("type"), kw.get("choices"), required, kw.get("help"), kw.get("metavar"))
        a.version = kw.get("version")
        self.actions.append(a)
        return a

    def add_argument_group(self, title=None, description=None):
        return _Group(self, title, description)

    def add_mutually_exclusive_group(self, required=False):
        return _Group(self, None, None, required)

    def add_subparsers(self, title=None, description=None, dest=None, required=False, help=None, metavar=None, **kw):
        self.sub = _Sub(self, dest, required)
        return self.sub

    def set_defaults(self, **kw):
        self.defaults.update(kw)

    def get_default(self, dest):
        for a in self.actions:
            if a.dest == dest and a.default is not None:
                return a.default
        return self.defaults.get(dest)

    def _metavar(self, a):
        if a.metavar:
            return a.metavar
        if a.choices:
            return "{" + ",".join(str(c) for c in a.choices) + "}"
        return a.dest.upper() if a.flags else a.dest

    def _argtext(self, a):
        m = self._metavar(a)
        if a.action in ("store_true", "store_false", "count", "help", "version", "store_const", "append_const"):
            return ""
        n = a.nargs
        if n == "?":
            return "[" + m + "]"
        if n == "*":
            return "[" + m + " ...]"
        if n == "+":
            return m + " [" + m + " ...]"
        if n == "...":
            return "..."
        if isinstance(n, int):
            return " ".join([m] * n)
        return m

    def format_usage(self):
        if self.usage:
            return "usage: " + self.usage.replace("%(prog)s", self.prog) + "\n"
        parts = ["usage: " + self.prog]
        for a in self.actions:
            if a.flags:
                t = self._argtext(a)
                s = a.flags[0] + (" " + t if t else "")
                parts.append(s if a.required else "[" + s + "]")
        for a in self.actions:
            if not a.flags:
                parts.append(self._argtext(a))
        if self.sub:
            parts.append("{" + ",".join(self.sub.parsers) + "} ...")
        return " ".join(parts) + "\n"

    def format_help(self):
        out = [self.format_usage()]
        if self.description:
            out.append("\n" + self.description.replace("%(prog)s", self.prog) + "\n")
        pos = [a for a in self.actions if not a.flags]
        opts = [a for a in self.actions if a.flags]
        def row(left, text):
            if text == SUPPRESS:
                return ""
            if text:
                text = text.replace("%(prog)s", self.prog)
            if not text:
                return "  " + left + "\n"
            if len(left) < 22:
                return "  " + left.ljust(22) + text + "\n"
            return "  " + left + "\n" + " " * 24 + text + "\n"
        if pos or self.sub:
            out.append("\npositional arguments:\n")
            for a in pos:
                out.append(row(self._metavar(a), a.help))
            if self.sub:
                for n in self.sub.parsers:
                    out.append(row(n, self.sub.helps.get(n)))
        if opts:
            out.append("\noptions:\n")
            for a in opts:
                t = self._argtext(a)
                out.append(row(", ".join(f + (" " + t if t else "") for f in a.flags), a.help))
        if self.epilog:
            out.append("\n" + self.epilog.replace("%(prog)s", self.prog) + "\n")
        return "".join(out)

    def print_usage(self, file=None):
        (file or sys.stdout).write(self.format_usage())

    def print_help(self, file=None):
        (file or sys.stdout).write(self.format_help())

    def exit(self, status=0, message=None):
        if message:
            sys.stderr.write(message)
        sys.exit(status)

    def error(self, message):
        self.print_usage(sys.stderr)
        self.exit(2, "%s: error: %s\n" % (self.prog, message))

    def _convert(self, a, v):
        if a.type:
            try:
                v = a.type(v)
            except ArgumentTypeError as e:
                self.error("argument %s: %s" % ("/".join(a.flags) or a.dest, e))
            except (ValueError, TypeError):
                name = getattr(a.type, "__name__", "value")
                self.error("argument %s: invalid %s value: %r" % ("/".join(a.flags) or a.dest, name, v))
        if a.choices is not None and v not in a.choices:
            self.error("argument %s: invalid choice: %r (choose from %s)" % ("/".join(a.flags) or a.dest, v, ", ".join(repr(c) for c in a.choices)))
        return v

    def _apply(self, ns, a, values, flag):
        act = a.action
        if isinstance(act, str):
            if act in ("store", "extend") or act == "store_const":
                pass
        else:
            obj = act(a.flags, a.dest, nargs=a.nargs, const=a.const, default=a.default, type=a.type, choices=a.choices, required=a.required, help=a.help, metavar=a.metavar)
            obj(self, ns, values, flag)
            return
        if act == "store":
            setattr(ns, a.dest, values)
        elif act == "store_true" or act == "store_false" or act == "store_const":
            setattr(ns, a.dest, a.const)
        elif act == "append":
            cur = getattr(ns, a.dest, None)
            setattr(ns, a.dest, (list(cur) if cur else []) + [values])
        elif act == "append_const":
            cur = getattr(ns, a.dest, None)
            setattr(ns, a.dest, (list(cur) if cur else []) + [a.const])
        elif act == "extend":
            cur = getattr(ns, a.dest, None)
            setattr(ns, a.dest, (list(cur) if cur else []) + list(values))
        elif act == "count":
            setattr(ns, a.dest, (getattr(ns, a.dest, None) or 0) + 1)
        elif act == "help":
            self.print_help()
            self.exit()
        elif act == "version":
            sys.stdout.write((a.version or "").replace("%(prog)s", self.prog) + "\n")
            self.exit()

    def _find(self, flag):
        for a in self.actions:
            if flag in a.flags:
                return a
        if self.allow_abbrev and flag.startswith("--"):
            hits = []
            for a in self.actions:
                for f in a.flags:
                    if f.startswith(flag):
                        hits.append(a)
            if len(hits) == 1:
                return hits[0]
        return None

    def parse_known_args(self, args=None, namespace=None):
        ns = namespace if namespace is not None else Namespace()
        args = list(sys.argv[1:] if args is None else args)
        for a in self.actions:
            if a.action in ("help", "version"):
                continue
            if not hasattr(ns, a.dest):
                setattr(ns, a.dest, a.default)
        for k in self.defaults:
            if not hasattr(ns, k) or getattr(ns, k) is None:
                setattr(ns, k, self.defaults[k])
        positionals = [a for a in self.actions if not a.flags]
        extras = []
        free = []
        seen = set()
        i = 0
        only_pos = False
        sub_at = None
        while i < len(args):
            w = args[i]
            i += 1
            if only_pos:
                free.append(w)
                continue
            if w == "--":
                only_pos = True
                continue
            if len(w) > 1 and w[0] == "-" and not self._looks_number(w):
                value = None
                flag = w
                if w.startswith("--") and "=" in w:
                    flag, value = w.split("=", 1)
                a = self._find(flag)
                if a is None and not w.startswith("--") and len(w) > 2:
                    # -abc, -n5
                    a = self._find(w[:2])
                    if a is not None:
                        flag = w[:2]
                        rest = w[2:]
                        if self._takes(a):
                            value = rest
                        else:
                            args[i:i] = ["-" + rest]
                if a is None:
                    extras.append(w)
                    continue
                seen.add(a.dest)
                if not self._takes(a):
                    self._apply(ns, a, None, flag)
                    continue
                n = a.nargs
                vals = []
                if value is not None:
                    vals.append(value)
                    if n is None or n == "?":
                        n = 0
                    elif isinstance(n, int):
                        n = n - 1
                if n is None:
                    if i >= len(args):
                        self.error("argument %s: expected one argument" % "/".join(a.flags))
                    vals.append(args[i])
                    i += 1
                elif n == "?":
                    if i < len(args) and not self._is_flag(args[i]):
                        vals.append(args[i])
                        i += 1
                elif n == "*" or n == "+" or n == "...":
                    while i < len(args) and (n == "..." or not self._is_flag(args[i])):
                        vals.append(args[i])
                        i += 1
                    if n == "+" and not vals:
                        self.error("argument %s: expected at least one argument" % "/".join(a.flags))
                elif n:
                    for _ in range(n):
                        if i >= len(args):
                            self.error("argument %s: expected %d arguments" % ("/".join(a.flags), a.nargs))
                        vals.append(args[i])
                        i += 1
                if a.nargs is None or (a.nargs == "?" and vals):
                    v = self._convert(a, vals[0])
                elif a.nargs == "?":
                    v = a.const
                else:
                    v = [self._convert(a, x) for x in vals]
                self._apply(ns, a, v, flag)
            else:
                if self.sub and len(free) >= self._needed(positionals):
                    if w in self.sub.parsers:
                        if self.sub.dest:
                            setattr(ns, self.sub.dest, w)
                        sub_ns, more = self.sub.parsers[w].parse_known_args(args[i:], ns)
                        extras.extend(more)
                        i = len(args)
                        sub_at = w
                        continue
                    self.error("argument command: invalid choice: %r (choose from %s)" % (w, ", ".join(repr(k) for k in self.sub.parsers)))
                free.append(w)
        # the positional arguments share the free words
        idx = 0
        for k in range(len(positionals)):
            a = positionals[k]
            need_after = self._needed(positionals[k + 1:])
            n = a.nargs
            if n is None:
                if idx < len(free):
                    self._apply(ns, a, self._convert(a, free[idx]), None)
                    idx += 1
                else:
                    self.error("the following arguments are required: " + a.dest)
            elif n == "?":
                if idx < len(free) - need_after:
                    self._apply(ns, a, self._convert(a, free[idx]), None)
                    idx += 1
                else:
                    setattr(ns, a.dest, a.default if a.default is not None else a.const)
            elif n == "*" or n == "+" or n == "...":
                take = max(0, len(free) - idx - need_after)
                if n == "+" and take == 0:
                    self.error("the following arguments are required: " + a.dest)
                vals = [self._convert(a, x) for x in free[idx:idx + take]]
                idx += take
                if vals or a.default is None:
                    self._apply(ns, a, vals, None)
            else:
                vals = free[idx:idx + n]
                if len(vals) < n:
                    self.error("the following arguments are required: " + a.dest)
                self._apply(ns, a, [self._convert(a, x) for x in vals], None)
                idx += n
        extras.extend(free[idx:])
        missing = [a for a in self.actions if a.flags and a.required and a.dest not in seen]
        if missing:
            self.error("the following arguments are required: " + ", ".join("/".join(a.flags) for a in missing))
        if self.sub and self.sub.required and not sub_at:
            self.error("the following arguments are required: " + (self.sub.dest or "command"))
        return ns, extras

    def parse_args(self, args=None, namespace=None):
        ns, extras = self.parse_known_args(args, namespace)
        if extras:
            self.error("unrecognized arguments: " + " ".join(extras))
        return ns

    def _takes(self, a):
        return a.action in ("store", "append", "extend") or not isinstance(a.action, str)

    def _is_flag(self, w):
        return len(w) > 1 and w[0] == "-" and not self._looks_number(w) and (w == "--" or self._find(w) is not None or self._find(w[:2]) is not None or w.startswith("--"))

    def _looks_number(self, w):
        try:
            float(w)
            return True
        except ValueError:
            return False

    def _needed(self, positionals):
        n = 0
        for a in positionals:
            if a.nargs is None or a.nargs == "+":
                n += 1
            elif isinstance(a.nargs, int):
                n += a.nargs
        return n
]==],
["optparse"] = [==[
import sys, os
SUPPRESS_HELP = "SUPPRESSHELP"
class OptParseError(Exception):
    pass
class OptionValueError(OptParseError):
    pass
class Values:
    def __init__(self, defaults=None):
        for k in (defaults or {}):
            setattr(self, k, defaults[k])
class Option:
    def __init__(self, flags, kw):
        self.flags = flags
        self.action = kw.get("action", "store")
        self.type = kw.get("type")
        longs = [f for f in flags if f.startswith("--")]
        self.dest = kw.get("dest") or (longs[0][2:].replace("-", "_") if longs else flags[0][1:])
        self.default = kw.get("default")
        self.help = kw.get("help")
        self.metavar = kw.get("metavar")
        self.const = kw.get("const")
        self.callback = kw.get("callback")
class OptionGroup:
    def __init__(self, parser, title, description=None):
        self.parser = parser
    def add_option(self, *a, **k):
        return self.parser.add_option(*a, **k)
class OptionParser:
    def __init__(self, usage=None, version=None, description=None, prog=None, add_help_option=True, epilog=None, **kw):
        self.prog = prog or os.path.basename(sys.argv[0])
        self.usage = usage
        self.version = version
        self.description = description
        self.epilog = epilog
        self.options = []
        self.defaults = {}
        if add_help_option:
            self.add_option("-h", "--help", action="help", help="show this help message and exit")
        if version:
            self.add_option("--version", action="version", help="show program's version number and exit")
    def add_option(self, *flags, **kw):
        o = Option(flags, kw)
        self.options.append(o)
        return o
    def add_option_group(self, g):
        return g
    def set_defaults(self, **kw):
        self.defaults.update(kw)
    def set_usage(self, u):
        self.usage = u
    def format_help(self):
        out = "Usage: " + (self.usage or "%prog [options]").replace("%prog", self.prog) + "\n"
        if self.description:
            out += "\n" + self.description + "\n"
        out += "\nOptions:\n"
        for o in self.options:
            if o.help != SUPPRESS_HELP:
                out += "  " + ", ".join(o.flags).ljust(22) + " " + (o.help or "") + "\n"
        return out
    def print_help(self, file=None):
        (file or sys.stdout).write(self.format_help())
    def error(self, msg):
        sys.stderr.write("Usage: " + (self.usage or "%prog [options]").replace("%prog", self.prog) + "\n\n" + self.prog + ": error: " + msg + "\n")
        sys.exit(2)
    def exit(self, status=0, msg=None):
        if msg:
            sys.stderr.write(msg)
        sys.exit(status)
    def parse_args(self, args=None, values=None):
        args = list(sys.argv[1:] if args is None else args)
        v = values or Values()
        for o in self.options:
            if not hasattr(v, o.dest) and o.action not in ("help", "version"):
                setattr(v, o.dest, self.defaults.get(o.dest, o.default))
        rest = []
        i = 0
        while i < len(args):
            w = args[i]
            i += 1
            if w == "--":
                rest.extend(args[i:])
                break
            if len(w) < 2 or w[0] != "-":
                rest.append(w)
                continue
            value = None
            flag = w
            if w.startswith("--") and "=" in w:
                flag, value = w.split("=", 1)
            o = None
            for x in self.options:
                if flag in x.flags:
                    o = x
            if o is None and not w.startswith("--"):
                for x in self.options:
                    if w[:2] in x.flags:
                        o = x
                        flag = w[:2]
                        if x.action in ("store", "append"):
                            value = w[2:]
                        else:
                            args[i:i] = ["-" + w[2:]]
            if o is None:
                self.error("no such option: " + w)
            if o.action == "help":
                self.print_help()
                sys.exit(0)
            if o.action == "version":
                sys.stdout.write(self.version.replace("%prog", self.prog) + "\n")
                sys.exit(0)
            if o.action == "store_true":
                setattr(v, o.dest, True)
            elif o.action == "store_false":
                setattr(v, o.dest, False)
            elif o.action == "store_const":
                setattr(v, o.dest, o.const)
            elif o.action == "count":
                setattr(v, o.dest, (getattr(v, o.dest) or 0) + 1)
            elif o.action == "callback":
                o.callback(o, flag, None, self)
            else:
                if value is None:
                    if i >= len(args):
                        self.error(flag + " option requires an argument")
                    value = args[i]
                    i += 1
                if o.type == "int":
                    value = int(value)
                elif o.type == "float":
                    value = float(value)
                if o.action == "append":
                    setattr(v, o.dest, (getattr(v, o.dest) or []) + [value])
                else:
                    setattr(v, o.dest, value)
        return v, rest
]==],
["getopt"] = [==[
class GetoptError(Exception):
    def __init__(self, msg, opt=""):
        self.msg = msg
        self.opt = opt
        Exception.__init__(self, msg)
error = GetoptError
def getopt(args, shortopts, longopts=[]):
    return _run(list(args), shortopts, longopts, False)
def gnu_getopt(args, shortopts, longopts=[]):
    return _run(list(args), shortopts, longopts, True)
def _run(args, shortopts, longopts, gnu):
    if isinstance(longopts, str):
        longopts = [longopts]
    opts = []
    rest = []
    while args:
        a = args.pop(0)
        if a == "--":
            rest.extend(args)
            break
        if a.startswith("--"):
            name, eq, val = a[2:].partition("=")
            hits = [o for o in longopts if o.rstrip("=").startswith(name)]
            exact = [o for o in hits if o.rstrip("=") == name]
            if exact:
                hits = exact
            if not hits:
                raise GetoptError("option --%s not recognized" % name, name)
            o = hits[0]
            if o.endswith("="):
                if not eq:
                    if not args:
                        raise GetoptError("option --%s requires argument" % name, name)
                    val = args.pop(0)
            elif eq:
                raise GetoptError("option --%s must not have an argument" % name, name)
            opts.append(("--" + o.rstrip("="), val))
        elif a.startswith("-") and a != "-":
            s = a[1:]
            while s:
                c = s[0]
                s = s[1:]
                k = shortopts.find(c)
                if k < 0 or c == ":":
                    raise GetoptError("option -%s not recognized" % c, c)
                if k + 1 < len(shortopts) and shortopts[k + 1] == ":":
                    if s:
                        val = s
                        s = ""
                    elif args:
                        val = args.pop(0)
                    else:
                        raise GetoptError("option -%s requires argument" % c, c)
                    opts.append(("-" + c, val))
                else:
                    opts.append(("-" + c, ""))
        else:
            if gnu:
                rest.append(a)
            else:
                rest.append(a)
                rest.extend(args)
                break
    return opts, rest
]==],
["errno"] = [==[
EPERM=1; ENOENT=2; ESRCH=3; EINTR=4; EIO=5; ENXIO=6; E2BIG=7; ENOEXEC=8; EBADF=9; ECHILD=10; EAGAIN=11; ENOMEM=12; EACCES=13; EFAULT=14; EBUSY=16; EEXIST=17; EXDEV=18; ENODEV=19; ENOTDIR=20; EISDIR=21; EINVAL=22; ENFILE=23; EMFILE=24; ENOTTY=25; EFBIG=27; ENOSPC=28; ESPIPE=29; EROFS=30; EMLINK=31; EPIPE=32; EDOM=33; ERANGE=34; ENOTEMPTY=39; ECONNREFUSED=111; ECONNRESET=104; ETIMEDOUT=110; EHOSTUNREACH=113
errorcode = {1:"EPERM",2:"ENOENT",4:"EINTR",5:"EIO",9:"EBADF",11:"EAGAIN",12:"ENOMEM",13:"EACCES",17:"EEXIST",20:"ENOTDIR",21:"EISDIR",22:"EINVAL",28:"ENOSPC",32:"EPIPE"}
]==],
["stat"] = [==[
S_IFMT_ = 61440; S_IFDIR = 16384; S_IFREG = 32768; S_IFLNK = 40960; S_IFCHR = 8192; S_IFBLK = 24576; S_IFIFO = 4096; S_IFSOCK = 49152
S_IRUSR=256; S_IWUSR=128; S_IXUSR=64; S_IRGRP=32; S_IWGRP=16; S_IXGRP=8; S_IROTH=4; S_IWOTH=2; S_IXOTH=1; S_ISUID=2048; S_ISGID=1024; S_ISVTX=512; S_IRWXU=448; S_IRWXG=56; S_IRWXO=7
ST_MODE=0; ST_SIZE=6; ST_MTIME=8
def S_IFMT(m): return m & 61440
def S_IMODE(m): return m & 4095
def S_ISDIR(m): return m & 61440 == 16384
def S_ISREG(m): return m & 61440 == 32768
def S_ISLNK(m): return m & 61440 == 40960
def S_ISCHR(m): return m & 61440 == 8192
def S_ISBLK(m): return m & 61440 == 24576
def S_ISFIFO(m): return m & 61440 == 4096
def S_ISSOCK(m): return m & 61440 == 49152
def filemode(m):
    t = "d" if S_ISDIR(m) else "l" if S_ISLNK(m) else "-"
    s = t
    for shift in (6, 3, 0):
        b = (m >> shift) & 7
        s += ("r" if b & 4 else "-") + ("w" if b & 2 else "-") + ("x" if b & 1 else "-")
    return s
]==],
["fnmatch"] = [==[
import re
def translate(pat):
    out = ""
    i = 0
    n = len(pat)
    while i < n:
        c = pat[i]
        i += 1
        if c == "*":
            out += ".*"
        elif c == "?":
            out += "."
        elif c == "[":
            j = i
            if j < n and pat[j] == "!":
                j += 1
            if j < n and pat[j] == "]":
                j += 1
            while j < n and pat[j] != "]":
                j += 1
            if j >= n:
                out += "\\["
            else:
                body = pat[i:j].replace("\\", "\\\\")
                i = j + 1
                if body[0] == "!":
                    body = "^" + body[1:]
                out += "[" + body + "]"
        else:
            out += re.escape(c)
    return "^" + out + "$"
def fnmatchcase(name, pat):
    return re.match(translate(pat), name) is not None
def fnmatch(name, pat):
    return fnmatchcase(name.lower(), pat.lower())
def filter(names, pat):
    return [n for n in names if fnmatch(n, pat)]
]==],
["glob"] = [==[
import os, fnmatch
def has_magic(s):
    return "*" in s or "?" in s or "[" in s
def escape(s):
    return s.replace("[", "[[]").replace("*", "[*]").replace("?", "[?]")
def _expand(base, parts, recursive):
    if not parts:
        return [base]
    head = parts[0]
    rest = parts[1:]
    found = []
    if head == "**" and recursive:
        found.extend(_expand(base, rest, recursive))
        d = base or "."
        try:
            names = sorted(os.listdir(d))
        except OSError:
            return found
        for n in names:
            full = os.path.join(base, n) if base else n
            if os.path.isdir(full) and not n.startswith("."):
                found.extend(_expand(full, parts, recursive))
        return found
    if has_magic(head):
        d = base or "."
        try:
            names = sorted(os.listdir(d))
        except OSError:
            return []
        for n in names:
            if n.startswith(".") and not head.startswith("."):
                continue
            if fnmatch.fnmatchcase(n, head):
                found.extend(_expand(os.path.join(base, n) if base else n, rest, recursive))
        return found
    next_ = os.path.join(base, head) if base else head
    if rest or os.path.exists(next_):
        return _expand(next_, rest, recursive)
    return []
def glob(pattern, recursive=False):
    if pattern.startswith("/"):
        return _expand("/", [p for p in pattern.split("/") if p], recursive)
    return _expand("", [p for p in pattern.split("/") if p], recursive)
def iglob(pattern, recursive=False):
    return iter(glob(pattern, recursive=recursive))
]==],
["shutil"] = [==[
import os, sys
class Error(OSError):
    pass
def copyfileobj(a, b, length=4096):
    while True:
        d = a.read(length)
        if not d:
            break
        b.write(d)
def copyfile(a, b, **kw):
    with open(a, "rb") as x:
        with open(b, "wb") as y:
            copyfileobj(x, y)
    return b
def copy(a, b, **kw):
    if os.path.isdir(b):
        b = os.path.join(b, os.path.basename(a))
    return copyfile(a, b)
copy2 = copy
def copymode(a, b, **kw):
    pass
def copystat(a, b, **kw):
    pass
def copytree(a, b, **kw):
    os.makedirs(b, exist_ok=kw.get("dirs_exist_ok", False))
    for n in os.listdir(a):
        x = os.path.join(a, n)
        y = os.path.join(b, n)
        if os.path.isdir(x):
            copytree(x, y, **kw)
        else:
            copyfile(x, y)
    return b
def rmtree(p, ignore_errors=False, onerror=None):
    try:
        for n in os.listdir(p):
            x = os.path.join(p, n)
            if os.path.isdir(x):
                rmtree(x)
            else:
                os.remove(x)
        os.rmdir(p)
    except OSError:
        if not ignore_errors:
            raise
def move(a, b, **kw):
    if os.path.isdir(b):
        b = os.path.join(b, os.path.basename(a))
    os.rename(a, b)
    return b
def which(cmd, mode=1, path=None):
    if "/" in cmd:
        return cmd if os.path.exists(cmd) else None
    for d in (path or os.environ.get("PATH", "/usr/bin")).split(":"):
        p = os.path.join(d, cmd)
        if os.path.exists(p):
            return p
    return None
class _Size:
    def __init__(self, c, l):
        self.columns = c
        self.lines = l
    def __iter__(self):
        return iter([self.columns, self.lines])
def get_terminal_size(fallback=(80, 24)):
    s = os.get_terminal_size()
    return _Size(s.columns, s.lines)
class _Usage:
    def __init__(self, t, u, f):
        self.total = t
        self.used = u
        self.free = f
    def __iter__(self):
        return iter([self.total, self.used, self.free])
def disk_usage(p):
    import _lua
    if _lua.fs and getattr(_lua.fs, "usage", None):
        t = _lua.fs.usage()
        return _Usage(t, 0, t)
    return _Usage(0, 0, 0)
]==],
["subprocess"] = [==[
import os, sys, _lua
PIPE = -1
STDOUT = -2
DEVNULL = -3
class SubprocessError(Exception):
    pass
class CalledProcessError(SubprocessError):
    def __init__(self, returncode, cmd, output=None, stderr=None):
        self.returncode = returncode
        self.cmd = cmd
        self.output = output
        self.stdout = output
        self.stderr = stderr
        Exception.__init__(self, "Command %r returned non-zero exit status %d." % (cmd, returncode))
class TimeoutExpired(SubprocessError):
    pass
class CompletedProcess:
    def __init__(self, args, returncode, stdout=None, stderr=None):
        self.args = args
        self.returncode = returncode
        self.stdout = stdout
        self.stderr = stderr
    def check_returncode(self):
        if self.returncode:
            raise CalledProcessError(self.returncode, self.args, self.stdout, self.stderr)
def _line(a):
    if isinstance(a, str):
        return a
    out = []
    for w in a:
        out.append("'" + str(w).replace("'", "'\\''") + "'")
    return " ".join(out)
def _status(line):
    h = _lua.io.popen(line + "; echo \"\n@@$?\"", "r")
    text = h.read("a")
    h.close()
    k = text.rfind("\n@@")
    code = int(text[k + 3:].strip() or "0")
    return text[:k].rstrip("\n") + ("\n" if text[:k].strip() else ""), code
def run(args, stdin=None, input=None, stdout=None, stderr=None, capture_output=False, shell=False, cwd=None, timeout=None, check=False, text=None, encoding=None, errors=None, env=None, universal_newlines=None, **kw):
    line = _line(args)
    if cwd:
        line = "cd " + cwd + " && " + line
    if input is not None:
        with open("/tmp/.py_in", "w") as f:
            f.write(input)
        line += " < /tmp/.py_in"
    if capture_output or stdout == PIPE:
        out, code = _status(line + (" 2>&1" if stderr == STDOUT else ""))
    elif stdout == DEVNULL:
        out, code = _status(line)
        out = None
    else:
        code = os.system(line)
        out = None
    r = CompletedProcess(args, code, out, "" if capture_output or stderr == PIPE else None)
    if check and code:
        raise CalledProcessError(code, args, out)
    return r
def call(args, **kw):
    return run(args, **kw).returncode
def check_call(args, **kw):
    return run(args, check=True, **kw).returncode
def check_output(args, **kw):
    kw["stdout"] = PIPE
    return run(args, check=True, **kw).stdout
def getoutput(cmd):
    return _status(cmd)[0].rstrip("\n")
def getstatusoutput(cmd):
    o, c = _status(cmd)
    return c, o.rstrip("\n")
class Popen:
    def __init__(self, args, stdin=None, stdout=None, stderr=None, shell=False, **kw):
        self.args = args
        self.input_ = stdin
        self.want = stdout
        self.err = stderr
        self.kw = kw
        self.returncode = None
        self.pid = 1
        self.stdout = None
        self.stderr = None
        self.stdin = None
        if stdin != PIPE:
            self._go(None)
    def _go(self, data):
        r = run(self.args, input=data, stdout=self.want, stderr=self.err)
        self.returncode = r.returncode
        self.out_ = r.stdout
        if self.want == PIPE:
            import io
            self.stdout = io.StringIO(r.stdout or "")
    def communicate(self, input=None, timeout=None):
        if self.returncode is None:
            self._go(input)
        return self.out_, ""
    def wait(self, timeout=None):
        return self.returncode or 0
    def poll(self):
        return self.returncode
    def kill(self):
        pass
    terminate = kill
    def __enter__(self):
        return self
    def __exit__(self, *a):
        return False
]==],
["io"] = [==[
SEEK_SET = 0
SEEK_CUR = 1
SEEK_END = 2
DEFAULT_BUFFER_SIZE = 8192
class IOBase:
    pass
class UnsupportedOperation(OSError):
    pass
class StringIO(IOBase):
    def __init__(self, initial=""):
        self.buf = initial or ""
        self.pos = 0
        self.closed = False
    def read(self, n=-1):
        if n is None or n < 0:
            r = self.buf[self.pos:]
        else:
            r = self.buf[self.pos:self.pos + n]
        self.pos += len(r)
        return r
    def readline(self, n=-1):
        k = self.buf.find("\n", self.pos)
        end = len(self.buf) if k < 0 else k + 1
        r = self.buf[self.pos:end]
        self.pos = end
        return r
    def readlines(self):
        o = []
        while True:
            l = self.readline()
            if not l:
                return o
            o.append(l)
    def write(self, s):
        if self.pos == len(self.buf):
            self.buf += s
        else:
            self.buf = self.buf[:self.pos] + s + self.buf[self.pos + len(s):]
        self.pos += len(s)
        return len(s)
    def writelines(self, it):
        for s in it:
            self.write(s)
    def getvalue(self):
        return self.buf
    def seek(self, p, w=0):
        if w == 1:
            p += self.pos
        elif w == 2:
            p += len(self.buf)
        self.pos = p
        return p
    def tell(self):
        return self.pos
    def flush(self):
        pass
    def close(self):
        self.closed = True
    def isatty(self):
        return False
    def truncate(self, n=None):
        self.buf = self.buf[:self.pos if n is None else n]
    def __iter__(self):
        return self
    def __next__(self):
        l = self.readline()
        if not l:
            raise StopIteration
        return l
    def __enter__(self):
        return self
    def __exit__(self, *a):
        return False
BytesIO = StringIO
TextIOBase = IOBase
BufferedIOBase = IOBase
RawIOBase = IOBase
TextIOWrapper = None
BufferedReader = None
BufferedWriter = None
def open(*a, **k):
    import builtins
    return builtins.open(*a, **k)
]==],
["builtins"] = [==[
import _lua
_b = _lua
def open(*a, **k):
    return __builtin_open(*a, **k)
]==],
["datetime"] = [==[
import time as _time
MINYEAR = 1
MAXYEAR = 9999
_DAYS = [0, 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
_MON = ["", "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
_MONTH = ["", "January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]
_DAY = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
_WEEK = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
def _leap(y):
    return y % 4 == 0 and (y % 100 != 0 or y % 400 == 0)
def _dim(y, m):
    return 29 if m == 2 and _leap(y) else _DAYS[m]
def _ord(y, m, d):
    # days since 0001-01-01, and 1 for that day
    y2 = y - 1
    n = y2 * 365 + y2 // 4 - y2 // 100 + y2 // 400
    for k in range(1, m):
        n += _dim(y, k)
    return n + d
def _fromord(n):
    n -= 1
    y = n // 146097 * 400
    n %= 146097
    k = min(n // 36524, 3)
    y += k * 100
    n -= k * 36524
    y += n // 1461 * 4
    n %= 1461
    k = min(n // 365, 3)
    y += k
    n -= k * 365
    y += 1
    m = 1
    while n >= _dim(y, m):
        n -= _dim(y, m)
        m += 1
    return y, m, n + 1
class timedelta:
    def __init__(self, days=0, seconds=0, microseconds=0, milliseconds=0, minutes=0, hours=0, weeks=0):
        total = (days + weeks * 7) * 86400 + seconds + minutes * 60 + hours * 3600
        us = round((total - int(total)) * 1000000) + microseconds + milliseconds * 1000
        total = int(total)
        total += us // 1000000
        us = us % 1000000
        self.days = total // 86400
        self.seconds = total % 86400
        self.microseconds = int(us)
    def total_seconds(self):
        return self.days * 86400.0 + self.seconds + self.microseconds / 1000000
    def __add__(self, o):
        return timedelta(self.days + o.days, self.seconds + o.seconds, self.microseconds + o.microseconds)
    def __sub__(self, o):
        return timedelta(self.days - o.days, self.seconds - o.seconds, self.microseconds - o.microseconds)
    def __neg__(self):
        return timedelta(-self.days, -self.seconds, -self.microseconds)
    def __mul__(self, k):
        return timedelta(seconds=self.total_seconds() * k)
    def __truediv__(self, k):
        if isinstance(k, timedelta):
            return self.total_seconds() / k.total_seconds()
        return timedelta(seconds=self.total_seconds() / k)
    def __eq__(self, o):
        return isinstance(o, timedelta) and self.total_seconds() == o.total_seconds()
    def __lt__(self, o):
        return self.total_seconds() < o.total_seconds()
    def __le__(self, o):
        return self.total_seconds() <= o.total_seconds()
    def __gt__(self, o):
        return self.total_seconds() > o.total_seconds()
    def __ge__(self, o):
        return self.total_seconds() >= o.total_seconds()
    def __hash__(self):
        return hash(self.total_seconds())
    def __bool__(self):
        return self.total_seconds() != 0
    def __str__(self):
        h = self.seconds // 3600
        m = self.seconds % 3600 // 60
        s = self.seconds % 60
        t = "%d:%02d:%02d" % (h, m, s)
        if self.days:
            t = "%d day%s, " % (self.days, "" if abs(self.days) == 1 else "s") + t
        if self.microseconds:
            t += ".%06d" % self.microseconds
        return t
    def __repr__(self):
        return "datetime.timedelta(days=%d, seconds=%d)" % (self.days, self.seconds)
class tzinfo:
    pass
class timezone(tzinfo):
    def __init__(self, offset, name=None):
        self.offset = offset
        self.name = name
    def utcoffset(self, dt):
        return self.offset
    def tzname(self, dt):
        return self.name or "UTC"
timezone.utc = timezone(timedelta(0), "UTC")
UTC = timezone.utc
class date:
    def __init__(self, year, month, day):
        if not 1 <= month <= 12:
            raise ValueError("month must be in 1..12")
        if not 1 <= day <= _dim(year, month):
            raise ValueError("day is out of range for month")
        self.year = year
        self.month = month
        self.day = day
    @classmethod
    def today(cls):
        t = _time.localtime()
        return cls(t[0], t[1], t[2])
    @classmethod
    def fromordinal(cls, n):
        y, m, d = _fromord(n)
        return cls(y, m, d)
    @classmethod
    def fromtimestamp(cls, s):
        t = _time.localtime(s)
        return cls(t[0], t[1], t[2])
    @classmethod
    def fromisoformat(cls, s):
        return cls(int(s[0:4]), int(s[5:7]), int(s[8:10]))
    def toordinal(self):
        return _ord(self.year, self.month, self.day)
    def weekday(self):
        return (self.toordinal() + 6) % 7
    def isoweekday(self):
        return self.weekday() + 1
    def isocalendar(self):
        wd = self.isoweekday()
        thu = self.toordinal() - wd + 4
        y = _fromord(thu)[0]
        return (y, (thu - _ord(y, 1, 1)) // 7 + 1, wd)
    def isoformat(self):
        return "%04d-%02d-%02d" % (self.year, self.month, self.day)
    def replace(self, year=None, month=None, day=None):
        return date(year or self.year, month or self.month, day or self.day)
    def timetuple(self):
        return (self.year, self.month, self.day, 0, 0, 0, self.weekday(), self.toordinal() - _ord(self.year, 1, 1) + 1, -1)
    def strftime(self, f):
        return _strftime(self, f)
    def __format__(self, f):
        return _strftime(self, f) if f else str(self)
    def __str__(self):
        return self.isoformat()
    def __repr__(self):
        return "datetime.date(%d, %d, %d)" % (self.year, self.month, self.day)
    def __add__(self, o):
        return date.fromordinal(self.toordinal() + o.days)
    def __sub__(self, o):
        if isinstance(o, date):
            return timedelta(self.toordinal() - o.toordinal())
        return date.fromordinal(self.toordinal() - o.days)
    def __eq__(self, o):
        return isinstance(o, date) and self.toordinal() == o.toordinal()
    def __lt__(self, o):
        return self.toordinal() < o.toordinal()
    def __le__(self, o):
        return self.toordinal() <= o.toordinal()
    def __gt__(self, o):
        return self.toordinal() > o.toordinal()
    def __ge__(self, o):
        return self.toordinal() >= o.toordinal()
    def __hash__(self):
        return self.toordinal()
class time:
    def __init__(self, hour=0, minute=0, second=0, microsecond=0, tzinfo=None):
        self.hour = hour
        self.minute = minute
        self.second = second
        self.microsecond = microsecond
        self.tzinfo = tzinfo
    def isoformat(self):
        return "%02d:%02d:%02d" % (self.hour, self.minute, self.second)
    def strftime(self, f):
        return _strftime(self, f)
    __str__ = isoformat
class datetime(date):
    def __init__(self, year, month, day, hour=0, minute=0, second=0, microsecond=0, tzinfo=None):
        date.__init__(self, year, month, day)
        self.hour = hour
        self.minute = minute
        self.second = second
        self.microsecond = microsecond
        self.tzinfo = tzinfo
    @classmethod
    def now(cls, tz=None):
        s = _time.time()
        t = _time.gmtime(s) if tz else _time.localtime(s)
        return cls(t[0], t[1], t[2], t[3], t[4], t[5], int((s - int(s)) * 1000000), tz)
    @classmethod
    def utcnow(cls):
        s = _time.time()
        t = _time.gmtime(s)
        return cls(t[0], t[1], t[2], t[3], t[4], t[5], 0)
    @classmethod
    def today(cls):
        return cls.now()
    @classmethod
    def fromtimestamp(cls, s, tz=None):
        t = _time.gmtime(s) if tz else _time.localtime(s)
        return cls(t[0], t[1], t[2], t[3], t[4], t[5], int((s - int(s)) * 1000000), tz)
    @classmethod
    def utcfromtimestamp(cls, s):
        t = _time.gmtime(s)
        return cls(t[0], t[1], t[2], t[3], t[4], t[5], int((s - int(s)) * 1000000))
    @classmethod
    def combine(cls, d, t):
        return cls(d.year, d.month, d.day, t.hour, t.minute, t.second, t.microsecond)
    @classmethod
    def fromisoformat(cls, s):
        y, m, d = int(s[0:4]), int(s[5:7]), int(s[8:10])
        h = mi = se = 0
        if len(s) > 11:
            h = int(s[11:13])
            mi = int(s[14:16]) if len(s) >= 16 else 0
            se = int(s[17:19]) if len(s) >= 19 else 0
        return cls(y, m, d, h, mi, se)
    @classmethod
    def strptime(cls, text, fmt):
        return _strptime(cls, text, fmt)
    def date(self):
        return date(self.year, self.month, self.day)
    def time(self):
        return time(self.hour, self.minute, self.second, self.microsecond)
    def _secs(self):
        return self.toordinal() * 86400 + self.hour * 3600 + self.minute * 60 + self.second
    def timestamp(self):
        if not self.tzinfo:
            return _time.mktime((self.year, self.month, self.day, self.hour, self.minute, self.second, 0, 0, -1)) + self.microsecond / 1000000
        return (self._secs() - _ord(1970, 1, 1) * 86400) + self.microsecond / 1000000 - self._off()
    def _off(self):
        if self.tzinfo:
            return self.tzinfo.offset.total_seconds()
        return 0
    def astimezone(self, tz=None):
        return datetime.fromtimestamp(self.timestamp(), tz)
    def utcoffset(self):
        return self.tzinfo.offset if self.tzinfo else None
    def replace(self, year=None, month=None, day=None, hour=None, minute=None, second=None, microsecond=None, tzinfo=None):
        return datetime(self.year if year is None else year, self.month if month is None else month, self.day if day is None else day, self.hour if hour is None else hour, self.minute if minute is None else minute, self.second if second is None else second, self.microsecond if microsecond is None else microsecond, self.tzinfo if tzinfo is None else tzinfo)
    def timetuple(self):
        return (self.year, self.month, self.day, self.hour, self.minute, self.second, self.weekday(), self.toordinal() - _ord(self.year, 1, 1) + 1, -1)
    def isoformat(self, sep="T", timespec=None):
        t = "%04d-%02d-%02d%s%02d:%02d:%02d" % (self.year, self.month, self.day, sep, self.hour, self.minute, self.second)
        if self.microsecond:
            t += ".%06d" % self.microsecond
        if self.tzinfo:
            o = int(self.tzinfo.offset.total_seconds())
            t += "%s%02d:%02d" % ("+" if o >= 0 else "-", abs(o) // 3600, abs(o) % 3600 // 60)
        return t
    def __str__(self):
        return self.isoformat(" ")
    def __repr__(self):
        return "datetime.datetime(%d, %d, %d, %d, %d, %d)" % (self.year, self.month, self.day, self.hour, self.minute, self.second)
    def __add__(self, o):
        return _fromsecs(self._secs() + o.days * 86400 + o.seconds, self.microsecond + o.microseconds, self.tzinfo)
    def __sub__(self, o):
        if isinstance(o, datetime):
            return timedelta(seconds=self._secs() - o._secs(), microseconds=self.microsecond - o.microsecond)
        return _fromsecs(self._secs() - o.days * 86400 - o.seconds, self.microsecond - o.microseconds, self.tzinfo)
    def __eq__(self, o):
        return isinstance(o, datetime) and self._secs() == o._secs() and self.microsecond == o.microsecond
    def __lt__(self, o):
        return (self._secs(), self.microsecond) < (o._secs(), o.microsecond)
    def __le__(self, o):
        return (self._secs(), self.microsecond) <= (o._secs(), o.microsecond)
    def __gt__(self, o):
        return (self._secs(), self.microsecond) > (o._secs(), o.microsecond)
    def __ge__(self, o):
        return (self._secs(), self.microsecond) >= (o._secs(), o.microsecond)
    def __hash__(self):
        return self._secs()
def _fromsecs(s, us, tz):
    s += us // 1000000
    us = us % 1000000
    y, m, d = _fromord(s // 86400)
    s = s % 86400
    return datetime(y, m, d, s // 3600, s % 3600 // 60, s % 60, us, tz)
def _strftime(d, f):
    out = ""
    i = 0
    while i < len(f):
        c = f[i]
        i += 1
        if c != "%" or i >= len(f):
            out += c
            continue
        k = f[i]
        i += 1
        h = getattr(d, "hour", 0)
        if k == "Y": out += "%04d" % d.year
        elif k == "y": out += "%02d" % (d.year % 100)
        elif k == "m": out += "%02d" % d.month
        elif k == "d": out += "%02d" % d.day
        elif k == "e": out += "%2d" % d.day
        elif k == "H": out += "%02d" % h
        elif k == "I": out += "%02d" % (h % 12 or 12)
        elif k == "M": out += "%02d" % getattr(d, "minute", 0)
        elif k == "S": out += "%02d" % getattr(d, "second", 0)
        elif k == "f": out += "%06d" % getattr(d, "microsecond", 0)
        elif k == "p": out += "AM" if h < 12 else "PM"
        elif k == "a": out += _DAY[d.weekday()]
        elif k == "A": out += _WEEK[d.weekday()]
        elif k == "b" or k == "h": out += _MON[d.month]
        elif k == "B": out += _MONTH[d.month]
        elif k == "j": out += "%03d" % (d.toordinal() - _ord(d.year, 1, 1) + 1)
        elif k == "w": out += str((d.weekday() + 1) % 7)
        elif k == "u": out += str(d.isoweekday())
        elif k == "F": out += "%04d-%02d-%02d" % (d.year, d.month, d.day)
        elif k == "D": out += "%02d/%02d/%02d" % (d.month, d.day, d.year % 100)
        elif k == "T": out += "%02d:%02d:%02d" % (h, getattr(d, "minute", 0), getattr(d, "second", 0))
        elif k == "R": out += "%02d:%02d" % (h, getattr(d, "minute", 0))
        elif k == "c": out += "%s %s %2d %02d:%02d:%02d %d" % (_DAY[d.weekday()], _MON[d.month], d.day, h, getattr(d, "minute", 0), getattr(d, "second", 0), d.year)
        elif k == "x": out += "%02d/%02d/%02d" % (d.month, d.day, d.year % 100)
        elif k == "X": out += "%02d:%02d:%02d" % (h, getattr(d, "minute", 0), getattr(d, "second", 0))
        elif k == "Z": out += d.tzinfo.tzname(d) if getattr(d, "tzinfo", None) else ""
        elif k == "z":
            if getattr(d, "tzinfo", None):
                o = int(d.tzinfo.offset.total_seconds())
                out += "%s%02d%02d" % ("+" if o >= 0 else "-", abs(o) // 3600, abs(o) % 3600 // 60)
        elif k == "%": out += "%"
        else: out += "%" + k
    return out
def _strptime(cls, text, fmt):
    y, mo, d, h, mi, s, us = 1900, 1, 1, 0, 0, 0, 0
    pm = None
    i = 0
    j = 0
    def num(maxlen):
        nonlocal i
        st = i
        while i < len(text) and i - st < maxlen and text[i].isdigit():
            i += 1
        if st == i:
            raise ValueError("time data %r does not match format %r" % (text, fmt))
        return int(text[st:i])
    while j < len(fmt):
        c = fmt[j]
        j += 1
        if c != "%":
            if i >= len(text) or text[i] != c:
                raise ValueError("time data %r does not match format %r" % (text, fmt))
            i += 1
            continue
        k = fmt[j]
        j += 1
        if k == "Y": y = num(4)
        elif k == "y":
            y = num(2)
            y += 2000 if y < 69 else 1900
        elif k == "m": mo = num(2)
        elif k == "d": d = num(2)
        elif k == "H" or k == "I": h = num(2)
        elif k == "M": mi = num(2)
        elif k == "S": s = num(2)
        elif k == "f": us = num(6)
        elif k == "p":
            pm = text[i:i + 2].upper() == "PM"
            i += 2
        elif k == "b" or k == "h":
            mo = _MON.index(text[i:i + 3].capitalize())
            i += 3
        elif k == "B":
            for n in range(1, 13):
                if text[i:].lower().startswith(_MONTH[n].lower()):
                    mo = n
                    i += len(_MONTH[n])
                    break
        elif k == "a":
            i += 3
        elif k == "A":
            for n in _WEEK:
                if text[i:].lower().startswith(n.lower()):
                    i += len(n)
                    break
        elif k == "%":
            i += 1
    if pm is not None:
        h = h % 12 + (12 if pm else 0)
    return cls(y, mo, d, h, mi, s, us)
]==],
["textwrap"] = [==[
def wrap(text, width=70, **kw):
    initial = kw.get("initial_indent", "")
    subsequent = kw.get("subsequent_indent", "")
    words = text.split()
    lines = []
    cur = initial
    empty = True
    for w in words:
        while len(w) > width - len(subsequent) and kw.get("break_long_words", True):
            room = width - len(cur) - (0 if empty else 1)
            if room <= 0:
                lines.append(cur)
                cur = subsequent
                empty = True
                room = width - len(cur)
            cur += ("" if empty else " ") + w[:room]
            w = w[room:]
            lines.append(cur)
            cur = subsequent
            empty = True
        if empty:
            cur += w
            empty = not w
        elif len(cur) + 1 + len(w) <= width:
            cur += " " + w
        else:
            lines.append(cur)
            cur = subsequent + w
    if not empty:
        lines.append(cur)
    return lines
def fill(text, width=70, **kw):
    return "\n".join(wrap(text, width, **kw))
def shorten(text, width, placeholder=" [...]", **kw):
    t = " ".join(text.split())
    if len(t) <= width:
        return t
    out = ""
    for w in t.split():
        if len(out) + len(w) + 1 + len(placeholder) > width:
            break
        out += (" " if out else "") + w
    return out + placeholder
def dedent(text):
    lines = text.split("\n")
    margin = None
    for l in lines:
        s = l.lstrip()
        if s:
            n = len(l) - len(s)
            margin = n if margin is None else min(margin, n)
    if not margin:
        return "\n".join(l if l.strip() else "" for l in lines)
    return "\n".join(l[margin:] if l.strip() else "" for l in lines)
def indent(text, prefix, predicate=None):
    out = ""
    for l in text.splitlines(True):
        if (predicate(l) if predicate else l.strip()):
            out += prefix + l
        else:
            out += l
    return out
class TextWrapper:
    def __init__(self, width=70, **kw):
        self.width = width
        self.kw = kw
    def wrap(self, text):
        return wrap(text, self.width, **self.kw)
    def fill(self, text):
        return fill(text, self.width, **self.kw)
]==],
["shlex"] = [==[
def split(s, comments=False, posix=True):
    out = []
    cur = None
    q = None
    i = 0
    while i < len(s):
        c = s[i]
        i += 1
        if q:
            if c == q:
                q = None
            elif c == "\\" and q == '"' and i < len(s) and s[i] in '"\\$`':
                cur += s[i]
                i += 1
            else:
                cur += c
        elif c == "'" or c == '"':
            q = c
            if cur is None:
                cur = ""
        elif c == "\\" and i < len(s):
            cur = (cur or "") + s[i]
            i += 1
        elif c in " \t\r\n":
            if cur is not None:
                out.append(cur)
                cur = None
        elif c == "#" and comments and cur is None:
            while i < len(s) and s[i] != "\n":
                i += 1
        else:
            cur = (cur or "") + c
    if q:
        raise ValueError("No closing quotation")
    if cur is not None:
        out.append(cur)
    return out
def quote(s):
    if s and all(c.isalnum() or c in "_@%+=:,./-" for c in s):
        return s
    return "'" + s.replace("'", "'\"'\"'") + "'"
def join(words):
    return " ".join(quote(w) for w in words)
]==],
["tempfile"] = [==[
import os, random
tempdir = None
def gettempdir():
    return tempdir or os.environ.get("TMPDIR", "/tmp")
def _name(suffix, prefix, d):
    while True:
        n = os.path.join(d or gettempdir(), (prefix or "tmp") + "%08x" % random.randint(0, 2147483647) + (suffix or ""))
        if not os.path.exists(n):
            return n
def mktemp(suffix="", prefix="tmp", dir=None):
    return _name(suffix, prefix, dir)
def mkstemp(suffix="", prefix="tmp", dir=None, text=False):
    n = _name(suffix, prefix, dir)
    open(n, "w").close()
    return (3, n)
def mkdtemp(suffix="", prefix="tmp", dir=None):
    n = _name(suffix, prefix, dir)
    os.makedirs(n)
    return n
class _Named:
    def __init__(self, mode, suffix, prefix, dir, delete):
        self.name = _name(suffix, prefix, dir)
        self.f = open(self.name, "w+" if "+" in mode or "w" in mode else mode)
        self.delete = delete
    def __getattr__(self, k):
        return getattr(self.f, k)
    def __enter__(self):
        return self
    def __exit__(self, *a):
        self.close()
        return False
    def write(self, s):
        return self.f.write(s)
    def read(self, *a):
        return self.f.read(*a)
    def seek(self, *a):
        return self.f.seek(*a)
    def flush(self):
        return self.f.flush()
    def close(self):
        self.f.close()
        if self.delete and os.path.exists(self.name):
            os.remove(self.name)
def NamedTemporaryFile(mode="w+b", suffix="", prefix="tmp", dir=None, delete=True, **kw):
    return _Named(mode, suffix, prefix, dir, delete)
TemporaryFile = NamedTemporaryFile
class TemporaryDirectory:
    def __init__(self, suffix="", prefix="tmp", dir=None):
        self.name = mkdtemp(suffix, prefix, dir)
    def __enter__(self):
        return self.name
    def __exit__(self, *a):
        self.cleanup()
        return False
    def cleanup(self):
        import shutil
        shutil.rmtree(self.name, True)
]==],
["logging"] = [==[
import sys, time
CRITICAL = 50; FATAL = 50; ERROR = 40; WARNING = 30; WARN = 30; INFO = 20; DEBUG = 10; NOTSET = 0
_names = {50: "CRITICAL", 40: "ERROR", 30: "WARNING", 20: "INFO", 10: "DEBUG", 0: "NOTSET"}
def getLevelName(n):
    return _names.get(n, "Level %s" % n)
class Formatter:
    def __init__(self, fmt=None, datefmt=None, **kw):
        self.fmt = fmt or "%(levelname)s:%(name)s:%(message)s"
        self.datefmt = datefmt
    def format(self, r):
        d = {"levelname": getLevelName(r.levelno), "name": r.name, "message": r.message, "asctime": time.strftime(self.datefmt or "%Y-%m-%d %H:%M:%S"), "levelno": r.levelno, "filename": "", "lineno": 0, "funcName": "", "module": "", "process": 1, "thread": 1}
        return self.fmt % d
class _Record:
    def __init__(self, name, levelno, message):
        self.name = name
        self.levelno = levelno
        self.message = message
class Handler:
    def __init__(self, level=NOTSET):
        self.level = level
        self.formatter = None
    def setLevel(self, l):
        self.level = l
    def setFormatter(self, f):
        self.formatter = f
    def handle(self, r):
        if r.levelno >= self.level:
            self.emit(r)
    def emit(self, r):
        pass
    def format(self, r):
        return (self.formatter or Formatter()).format(r)
    def flush(self):
        pass
    def close(self):
        pass
class NullHandler(Handler):
    pass
class StreamHandler(Handler):
    def __init__(self, stream=None):
        Handler.__init__(self)
        self.stream = stream or sys.stderr
    def emit(self, r):
        self.stream.write(self.format(r) + "\n")
class FileHandler(StreamHandler):
    def __init__(self, filename, mode="a", **kw):
        StreamHandler.__init__(self, open(filename, mode))
class Logger:
    def __init__(self, name, parent=None):
        self.name = name
        self.parent = parent
        self.level = NOTSET
        self.handlers = []
        self.propagate = True
        self.disabled = False
    def setLevel(self, l):
        self.level = l if isinstance(l, int) else globals().get(l, 0)
    def addHandler(self, h):
        self.handlers.append(h)
    def removeHandler(self, h):
        if h in self.handlers:
            self.handlers.remove(h)
    def hasHandlers(self):
        return bool(self.handlers)
    def getEffectiveLevel(self):
        l = self
        while l:
            if l.level:
                return l.level
            l = l.parent
        return WARNING
    def isEnabledFor(self, n):
        return n >= self.getEffectiveLevel()
    def log(self, level, msg, *args, **kw):
        if not self.isEnabledFor(level):
            return
        text = str(msg) % args if args else str(msg)
        r = _Record(self.name, level, text)
        l = self
        found = False
        while l:
            for h in l.handlers:
                h.handle(r)
                found = True
            l = l.parent if l.propagate else None
        if not found and level >= WARNING:
            sys.stderr.write(text + "\n")
    def debug(self, m, *a, **k): self.log(DEBUG, m, *a)
    def info(self, m, *a, **k): self.log(INFO, m, *a)
    def warning(self, m, *a, **k): self.log(WARNING, m, *a)
    warn = warning
    def error(self, m, *a, **k): self.log(ERROR, m, *a)
    def exception(self, m, *a, **k): self.log(ERROR, m, *a)
    def critical(self, m, *a, **k): self.log(CRITICAL, m, *a)
    fatal = critical
root = Logger("root")
root.level = WARNING
_loggers = {}
def getLogger(name=None):
    if not name:
        return root
    if name not in _loggers:
        _loggers[name] = Logger(name, root)
    return _loggers[name]
def basicConfig(**kw):
    if root.handlers and not kw.get("force"):
        return
    if kw.get("filename"):
        h = FileHandler(kw["filename"], kw.get("filemode", "a"))
    else:
        h = StreamHandler(kw.get("stream"))
    h.setFormatter(Formatter(kw.get("format"), kw.get("datefmt")))
    root.addHandler(h)
    if "level" in kw:
        root.setLevel(kw["level"])
def debug(m, *a, **k): root.debug(m, *a)
def info(m, *a, **k): root.info(m, *a)
def warning(m, *a, **k): root.warning(m, *a)
warn = warning
def error(m, *a, **k): root.error(m, *a)
def exception(m, *a, **k): root.error(m, *a)
def critical(m, *a, **k): root.critical(m, *a)
def log(l, m, *a, **k): root.log(l, m, *a)
def disable(level=CRITICAL): pass
def shutdown(): pass
def captureWarnings(c): pass
]==],
["pathlib"] = [==[
import os, fnmatch, glob as _glob
class PurePath:
    def __init__(self, *parts):
        p = ""
        for x in parts:
            x = str(x)
            if x.startswith("/") or not p:
                p = x
            else:
                p = p.rstrip("/") + "/" + x
        self._p = os.path.normpath(p) if p else "."
    def __fspath__(self):
        return self._p
    def __str__(self):
        return self._p
    def __repr__(self):
        return "PosixPath('%s')" % self._p
    def __eq__(self, o):
        return str(self) == str(o)
    def __lt__(self, o):
        return str(self) < str(o)
    def __hash__(self):
        return hash(self._p)
    def __truediv__(self, o):
        return self.__class__(self._p, str(o))
    def __rtruediv__(self, o):
        return self.__class__(str(o), self._p)
    @property
    def name(self):
        return os.path.basename(self._p)
    @property
    def suffix(self):
        return os.path.splitext(self.name)[1]
    @property
    def suffixes(self):
        return ["." + x for x in self.name.split(".")[1:]]
    @property
    def stem(self):
        return os.path.splitext(self.name)[0]
    @property
    def parent(self):
        d = os.path.dirname(self._p)
        return self.__class__(d or ".")
    @property
    def parents(self):
        o = []
        p = self.parent
        while str(p) != "." and str(p) != "/":
            o.append(p)
            p = p.parent
        o.append(p)
        return o
    @property
    def parts(self):
        t = [x for x in self._p.split("/") if x]
        return tuple((["/"] if self._p.startswith("/") else []) + t)
    @property
    def anchor(self):
        return "/" if self._p.startswith("/") else ""
    def as_posix(self):
        return self._p
    def is_absolute(self):
        return self._p.startswith("/")
    def joinpath(self, *o):
        return self.__class__(self._p, *o)
    def with_name(self, n):
        return self.parent / n
    def with_suffix(self, s):
        return self.parent / (self.stem + s)
    def with_stem(self, s):
        return self.parent / (s + self.suffix)
    def match(self, pat):
        return fnmatch.fnmatch(self.name, pat)
    def relative_to(self, o):
        o = str(o).rstrip("/")
        if self._p == o:
            return self.__class__(".")
        if not self._p.startswith(o + "/"):
            raise ValueError("%r is not in the subpath of %r" % (self._p, o))
        return self.__class__(self._p[len(o) + 1:])
class Path(PurePath):
    @classmethod
    def cwd(cls):
        return cls(os.getcwd())
    @classmethod
    def home(cls):
        return cls(os.path.expanduser("~"))
    def exists(self):
        return os.path.exists(self._p)
    def is_file(self):
        return os.path.isfile(self._p)
    def is_dir(self):
        return os.path.isdir(self._p)
    def is_symlink(self):
        return False
    def stat(self):
        return os.stat(self._p)
    def lstat(self):
        return os.stat(self._p)
    def resolve(self, strict=False):
        return self.__class__(os.path.abspath(self._p))
    absolute = resolve
    def expanduser(self):
        return self.__class__(os.path.expanduser(self._p))
    def open(self, mode="r", **kw):
        return open(self._p, mode)
    def read_text(self, **kw):
        with open(self._p) as f:
            return f.read()
    def read_bytes(self):
        with open(self._p, "rb") as f:
            return f.read()
    def write_text(self, s, **kw):
        with open(self._p, "w") as f:
            return f.write(s)
    def write_bytes(self, s):
        with open(self._p, "wb") as f:
            return f.write(s)
    def touch(self, **kw):
        open(self._p, "a").close()
    def unlink(self, missing_ok=False):
        if missing_ok and not self.exists():
            return
        os.remove(self._p)
    def rmdir(self):
        os.rmdir(self._p)
    def mkdir(self, mode=511, parents=False, exist_ok=False):
        if self.exists():
            if exist_ok:
                return
            raise FileExistsError(17, "File exists")
        if parents:
            os.makedirs(self._p, exist_ok=exist_ok)
        else:
            os.mkdir(self._p)
    def rename(self, t):
        os.rename(self._p, str(t))
        return self.__class__(str(t))
    replace = rename
    def chmod(self, m):
        pass
    def iterdir(self):
        return iter([self / n for n in sorted(os.listdir(self._p))])
    def glob(self, pat):
        return iter([self.__class__(x) for x in _glob.glob(os.path.join(self._p, pat), recursive=True)])
    def rglob(self, pat):
        return self.glob("**/" + pat)
PosixPath = Path
PurePosixPath = PurePath
]==],
["platform"] = [==[
def system(): return "Linux"
def node():
    import socket
    return socket.gethostname()
def release(): return "6.8.0-esp"
def version(): return "#1 SMP"
def machine(): return "riscv32"
def processor(): return "riscv32"
def platform(**k): return "Linux-6.8.0-esp-riscv32"
def architecture(**k): return ("32bit", "ELF")
def python_version(): return "3.12.0"
def python_version_tuple(): return ("3", "12", "0")
def python_implementation(): return "ESP"
def uname():
    import os
    return os.uname()
]==],
["signal"] = [==[
SIGHUP=1; SIGINT=2; SIGQUIT=3; SIGABRT=6; SIGKILL=9; SIGSEGV=11; SIGPIPE=13; SIGALRM=14; SIGTERM=15; SIGCHLD=17; SIGCONT=18; SIGSTOP=19; SIGTSTP=20; SIGWINCH=28; SIGUSR1=10; SIGUSR2=12
SIG_DFL = 0
SIG_IGN = 1
_h = {}
def signal(n, f):
    o = _h.get(n, SIG_DFL)
    _h[n] = f
    return o
def getsignal(n):
    return _h.get(n, SIG_DFL)
def alarm(n):
    return 0
def pause():
    pass
]==],
["traceback"] = [==[
import sys
def format_exc(*a, **k):
    return "Traceback (most recent call last):\n"
def print_exc(*a, **k):
    sys.stderr.write(format_exc())
def print_exception(*a, **k):
    sys.stderr.write(format_exc())
def format_exception(*a, **k):
    return [format_exc()]
def print_stack(*a, **k):
    pass
def format_stack(*a, **k):
    return []
def extract_tb(*a, **k):
    return []
]==],
["warnings"] = [==[
import sys
def warn(message, category=None, stacklevel=1, **k):
    sys.stderr.write("Warning: %s\n" % (message,))
def simplefilter(*a, **k): pass
def filterwarnings(*a, **k): pass
def resetwarnings(): pass
class catch_warnings:
    def __init__(self, **k): pass
    def __enter__(self): return []
    def __exit__(self, *a): return False
]==],
["atexit"] = [==[
_funcs = []
def register(f, *a, **k):
    _funcs.append((f, a, k))
    return f
def unregister(f):
    pass
]==],
["contextlib"] = [==[
class _Gen:
    def __init__(self, g):
        self.g = g
    def __enter__(self):
        return next(self.g)
    def __exit__(self, t, v, tb):
        try:
            next(self.g)
        except StopIteration:
            pass
        return False
    def __call__(self, f):
        return f
def contextmanager(f):
    def wrapper(*a, **k):
        return _Gen(f(*a, **k))
    return wrapper
class suppress:
    def __init__(self, *e):
        self.e = e
    def __enter__(self):
        return self
    def __exit__(self, t, v, tb):
        return t is not None and issubclass(t, self.e)
class redirect_stdout:
    def __init__(self, target):
        self.target = target
    def __enter__(self):
        import sys
        self.old = sys.stdout
        sys.stdout = self.target
        return self.target
    def __exit__(self, *a):
        import sys
        sys.stdout = self.old
        return False
redirect_stderr = redirect_stdout
class closing:
    def __init__(self, x):
        self.x = x
    def __enter__(self):
        return self.x
    def __exit__(self, *a):
        self.x.close()
        return False
class nullcontext:
    def __init__(self, r=None):
        self.r = r
    def __enter__(self):
        return self.r
    def __exit__(self, *a):
        return False
class AbstractContextManager:
    pass
]==],
["operator"] = [==[
def add(a, b): return a + b
def sub(a, b): return a - b
def mul(a, b): return a * b
def truediv(a, b): return a / b
def floordiv(a, b): return a // b
def mod(a, b): return a % b
def pow(a, b): return a ** b
def neg(a): return -a
def eq(a, b): return a == b
def ne(a, b): return a != b
def lt(a, b): return a < b
def le(a, b): return a <= b
def gt(a, b): return a > b
def ge(a, b): return a >= b
def not_(a): return not a
def contains(a, b): return b in a
def getitem(a, b): return a[b]
def setitem(a, b, c): a[b] = c
def and_(a, b): return a & b
def or_(a, b): return a | b
def xor(a, b): return a ^ b
def concat(a, b): return a + b
def itemgetter(*k):
    if len(k) == 1:
        i = k[0]
        return lambda o: o[i]
    return lambda o: tuple(o[i] for i in k)
def attrgetter(*k):
    if len(k) == 1:
        i = k[0]
        def g(o):
            for part in i.split("."):
                o = getattr(o, part)
            return o
        return g
    return lambda o: tuple(getattr(o, i) for i in k)
def methodcaller(n, *a, **kw):
    return lambda o: getattr(o, n)(*a, **kw)
]==],
["bisect"] = [==[
def bisect_right(a, x, lo=0, hi=None):
    hi = len(a) if hi is None else hi
    while lo < hi:
        m = (lo + hi) // 2
        if x < a[m]:
            hi = m
        else:
            lo = m + 1
    return lo
def bisect_left(a, x, lo=0, hi=None):
    hi = len(a) if hi is None else hi
    while lo < hi:
        m = (lo + hi) // 2
        if a[m] < x:
            lo = m + 1
        else:
            hi = m
    return lo
bisect = bisect_right
def insort_right(a, x, lo=0, hi=None):
    a.insert(bisect_right(a, x, lo, hi), x)
insort = insort_right
def insort_left(a, x, lo=0, hi=None):
    a.insert(bisect_left(a, x, lo, hi), x)
]==],
["heapq"] = [==[
def heappush(h, x):
    h.append(x)
    i = len(h) - 1
    while i > 0:
        p = (i - 1) // 2
        if h[i] < h[p]:
            h[i], h[p] = h[p], h[i]
            i = p
        else:
            break
def heappop(h):
    last = h.pop()
    if not h:
        return last
    top = h[0]
    h[0] = last
    i = 0
    n = len(h)
    while True:
        l = 2 * i + 1
        r = l + 1
        m = i
        if l < n and h[l] < h[m]:
            m = l
        if r < n and h[r] < h[m]:
            m = r
        if m == i:
            break
        h[i], h[m] = h[m], h[i]
        i = m
    return top
def heapify(h):
    items = list(h)
    del h[:]
    for x in items:
        heappush(h, x)
def heappushpop(h, x):
    heappush(h, x)
    return heappop(h)
def nsmallest(n, it, key=None):
    return sorted(it, key=key)[:n]
def nlargest(n, it, key=None):
    return sorted(it, key=key, reverse=True)[:n]
]==],
["statistics"] = [==[
import math
class StatisticsError(ValueError):
    pass
def mean(d):
    d = list(d)
    if not d:
        raise StatisticsError("mean requires at least one data point")
    r = sum(d) / len(d)
    return int(r) if r == int(r) and all(isinstance(x, int) for x in d) else r
def fmean(d):
    d = list(d)
    return sum(d) / len(d)
def median(d):
    d = sorted(d)
    n = len(d)
    if not n:
        raise StatisticsError("no median for empty data")
    if n % 2:
        return d[n // 2]
    return (d[n // 2 - 1] + d[n // 2]) / 2
def mode(d):
    c = {}
    for x in d:
        c[x] = c.get(x, 0) + 1
    return max(c, key=lambda k: c[k])
def pvariance(d):
    d = list(d)
    m = mean(d)
    return sum((x - m) ** 2 for x in d) / len(d)
def variance(d):
    d = list(d)
    m = mean(d)
    return sum((x - m) ** 2 for x in d) / (len(d) - 1)
def pstdev(d): return math.sqrt(pvariance(d))
def stdev(d): return math.sqrt(variance(d))
]==],
["base64"] = [==[
_A = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
def b64encode(s, altchars=None):
    if isinstance(s, str):
        s = s.encode()
    out = []
    data = [ord(c) for c in s]
    for i in range(0, len(data), 3):
        chunk = data[i:i + 3]
        n = len(chunk)
        v = (chunk[0] << 16) | ((chunk[1] if n > 1 else 0) << 8) | (chunk[2] if n > 2 else 0)
        out.append(_A[(v >> 18) & 63])
        out.append(_A[(v >> 12) & 63])
        out.append(_A[(v >> 6) & 63] if n > 1 else "=")
        out.append(_A[v & 63] if n > 2 else "=")
    return "".join(out)
def b64decode(s, altchars=None, validate=False):
    out = []
    bits = 0
    n = 0
    for c in s:
        k = _A.find(c)
        if k < 0:
            continue
        bits = (bits << 6) | k
        n += 6
        if n >= 8:
            n -= 8
            out.append(chr((bits >> n) & 255))
            bits &= (1 << n) - 1
    return "".join(out)
standard_b64encode = b64encode
standard_b64decode = b64decode
def urlsafe_b64encode(s):
    return b64encode(s).replace("+", "-").replace("/", "_")
def urlsafe_b64decode(s):
    return b64decode(s.replace("-", "+").replace("_", "/"))
encodebytes = b64encode
decodebytes = b64decode
def b16encode(s):
    return "".join("%02X" % ord(c) for c in s)
def b16decode(s, casefold=False):
    return "".join(chr(int(s[i:i + 2], 16)) for i in range(0, len(s), 2))
]==],
["hashlib"] = [==[
import _lua
def _rol(x, n):
    return ((x << n) | (x >> (32 - n))) & 4294967295
class _Hash:
    def __init__(self, data=""):
        self.data = data
    def update(self, d):
        self.data += d
    def digest(self):
        h = self.hexdigest()
        return "".join(chr(int(h[i:i + 2], 16)) for i in range(0, len(h), 2))
    def copy(self):
        o = self.__class__(self.data)
        return o
class sha256(_Hash):
    name = "sha256"
    digest_size = 32
    block_size = 64
    def hexdigest(self):
        import _lua
        K = [1116352408,1899447441,3049323471,3921009573,961987163,1508970993,2453635748,2870763221,3624381080,310598401,607225278,1426881987,1925078388,2162078206,2614888103,3248222580,3835390401,4022224774,264347078,604807628,770255983,1249150122,1555081692,1996064986,2554220882,2821834349,2952996808,3210313671,3336571891,3584528711,113926993,338241895,666307205,773529912,1294757372,1396182291,1695183700,1986661051,2177026350,2456956037,2730485921,2820302411,3259730800,3345764771,3516065817,3600352804,4094571909,275423344,430227734,506948616,659060556,883997877,958139571,1322822218,1537002063,1747873779,1955562222,2024104815,2227730452,2361852424,2428436474,2756734187,3204031479,3329325298]
        H = [1779033703,3144134277,1013904242,2773480762,1359893119,2600822924,528734635,1541459225]
        d = self.data
        n = len(d)
        d = d + chr(128) + chr(0) * ((55 - n) % 64)
        bits = n * 8
        d = d + "".join(chr((bits >> s) & 255) for s in (56, 48, 40, 32, 24, 16, 8, 0))
        def rr(x, c):
            return ((x >> c) | (x << (32 - c))) & 4294967295
        for off in range(0, len(d), 64):
            w = [0] * 64
            for t in range(16):
                p = off + t * 4
                w[t] = (ord(d[p]) << 24) | (ord(d[p + 1]) << 16) | (ord(d[p + 2]) << 8) | ord(d[p + 3])
            for t in range(16, 64):
                s0 = rr(w[t - 15], 7) ^ rr(w[t - 15], 18) ^ (w[t - 15] >> 3)
                s1 = rr(w[t - 2], 17) ^ rr(w[t - 2], 19) ^ (w[t - 2] >> 10)
                w[t] = (w[t - 16] + s0 + w[t - 7] + s1) & 4294967295
            a, b, c, e_, f, g, h, i = H[0], H[1], H[2], H[3], H[4], H[5], H[6], H[7]
            for t in range(64):
                S1 = rr(f, 6) ^ rr(f, 11) ^ rr(f, 25)
                ch = (f & g) ^ ((~f & 4294967295) & h)
                t1 = (i + S1 + ch + K[t] + w[t]) & 4294967295
                S0 = rr(a, 2) ^ rr(a, 13) ^ rr(a, 22)
                maj = (a & b) ^ (a & c) ^ (b & c)
                t2 = (S0 + maj) & 4294967295
                i = h; h = g; g = f
                f = (e_ + t1) & 4294967295
                e_ = c; c = b; b = a
                a = (t1 + t2) & 4294967295
            H = [(H[0] + a) & 4294967295, (H[1] + b) & 4294967295, (H[2] + c) & 4294967295, (H[3] + e_) & 4294967295, (H[4] + f) & 4294967295, (H[5] + g) & 4294967295, (H[6] + h) & 4294967295, (H[7] + i) & 4294967295]
        return "".join("%08x" % x for x in H)
class sha1(_Hash):
    name = "sha1"
    digest_size = 20
    block_size = 64
    def hexdigest(self):
        H = [1732584193, 4023233417, 2562383102, 271733878, 3285377520]
        d = self.data
        n = len(d)
        d = d + chr(128) + chr(0) * ((55 - n) % 64)
        bits = n * 8
        d = d + "".join(chr((bits >> s) & 255) for s in (56, 48, 40, 32, 24, 16, 8, 0))
        for off in range(0, len(d), 64):
            w = [0] * 80
            for t in range(16):
                p = off + t * 4
                w[t] = (ord(d[p]) << 24) | (ord(d[p + 1]) << 16) | (ord(d[p + 2]) << 8) | ord(d[p + 3])
            for t in range(16, 80):
                w[t] = _rol(w[t - 3] ^ w[t - 8] ^ w[t - 14] ^ w[t - 16], 1)
            a, b, c, e_, f = H[0], H[1], H[2], H[3], H[4]
            for t in range(80):
                if t < 20:
                    fn = (b & c) | ((~b & 4294967295) & e_)
                    k = 1518500249
                elif t < 40:
                    fn = b ^ c ^ e_
                    k = 1859775393
                elif t < 60:
                    fn = (b & c) | (b & e_) | (c & e_)
                    k = 2400959708
                else:
                    fn = b ^ c ^ e_
                    k = 3395469782
                x = (_rol(a, 5) + fn + f + k + w[t]) & 4294967295
                f = e_; e_ = c; c = _rol(b, 30); b = a; a = x
            H = [(H[0] + a) & 4294967295, (H[1] + b) & 4294967295, (H[2] + c) & 4294967295, (H[3] + e_) & 4294967295, (H[4] + f) & 4294967295]
        return "".join("%08x" % x for x in H)
class md5(_Hash):
    name = "md5"
    digest_size = 16
    block_size = 64
    def hexdigest(self):
        import math
        S = [7,12,17,22]*4 + [5,9,14,20]*4 + [4,11,16,23]*4 + [6,10,15,21]*4
        K = [int(abs(math.sin(i + 1)) * 4294967296) & 4294967295 for i in range(64)]
        a0, b0, c0, d0 = 1732584193, 4023233417, 2562383102, 271733878
        d = self.data
        n = len(d)
        d = d + chr(128) + chr(0) * ((55 - n) % 64)
        bits = n * 8
        d = d + "".join(chr((bits >> s) & 255) for s in (0, 8, 16, 24, 32, 40, 48, 56))
        for off in range(0, len(d), 64):
            M = []
            for t in range(16):
                p = off + t * 4
                M.append(ord(d[p]) | (ord(d[p + 1]) << 8) | (ord(d[p + 2]) << 16) | (ord(d[p + 3]) << 24))
            A, B, C, D = a0, b0, c0, d0
            for i in range(64):
                if i < 16:
                    F = (B & C) | ((~B & 4294967295) & D)
                    g = i
                elif i < 32:
                    F = (D & B) | ((~D & 4294967295) & C)
                    g = (5 * i + 1) % 16
                elif i < 48:
                    F = B ^ C ^ D
                    g = (3 * i + 5) % 16
                else:
                    F = C ^ (B | (~D & 4294967295))
                    g = (7 * i) % 16
                F = (F + A + K[i] + M[g]) & 4294967295
                A = D; D = C; C = B
                B = (B + _rol(F, S[i])) & 4294967295
            a0 = (a0 + A) & 4294967295; b0 = (b0 + B) & 4294967295; c0 = (c0 + C) & 4294967295; d0 = (d0 + D) & 4294967295
        out = ""
        for x in (a0, b0, c0, d0):
            out += "".join("%02x" % ((x >> s) & 255) for s in (0, 8, 16, 24))
        return out
def new(name, data=""):
    return {"md5": md5, "sha1": sha1, "sha256": sha256}[name](data)
algorithms_available = {"md5", "sha1", "sha256"}
algorithms_guaranteed = algorithms_available
]==],
["urllib"] = [==[
]==],
["urllib.parse"] = [==[
_SAFE = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_.-~"
def quote(s, safe="/", **k):
    if isinstance(s, (int, float)):
        s = str(s)
    return "".join(c if c in _SAFE or c in safe else "%%%02X" % ord(c) for c in s)
def quote_plus(s, safe="", **k):
    return quote(s, safe + " ").replace(" ", "+")
def unquote(s, **k):
    out = ""
    i = 0
    while i < len(s):
        if s[i] == "%" and i + 2 < len(s) + 0 and i + 2 <= len(s) - 1:
            try:
                out += chr(int(s[i + 1:i + 3], 16))
                i += 3
                continue
            except ValueError:
                pass
        out += s[i]
        i += 1
    return out
def unquote_plus(s, **k):
    return unquote(s.replace("+", " "))
def urlencode(q, doseq=False, **k):
    items = q.items() if hasattr(q, "items") else q
    parts = []
    for a, b in items:
        if doseq and isinstance(b, (list, tuple)):
            for v in b:
                parts.append(quote_plus(str(a)) + "=" + quote_plus(str(v)))
        else:
            parts.append(quote_plus(str(a)) + "=" + quote_plus(str(b)))
    return "&".join(parts)
class ParseResult:
    def __init__(self, scheme, netloc, path, params, query, fragment):
        self.scheme = scheme
        self.netloc = netloc
        self.path = path
        self.params = params
        self.query = query
        self.fragment = fragment
        host = netloc.rpartition("@")[2]
        self.hostname = host.split(":")[0] or None
        self.port = int(host.split(":")[1]) if ":" in host and host.split(":")[1] else None
        self.username = None
        self.password = None
    def geturl(self):
        return urlunparse(self)
    def __iter__(self):
        return iter([self.scheme, self.netloc, self.path, self.params, self.query, self.fragment])
    def __getitem__(self, i):
        return [self.scheme, self.netloc, self.path, self.params, self.query, self.fragment][i]
def urlparse(u, scheme="", allow_fragments=True):
    fragment = ""
    query = ""
    if "#" in u:
        u, fragment = u.split("#", 1)
    if "?" in u:
        u, query = u.split("?", 1)
    netloc = ""
    if "://" in u:
        scheme, u = u.split("://", 1)
        k = u.find("/")
        if k < 0:
            netloc, u = u, ""
        else:
            netloc, u = u[:k], u[k:]
    elif u.startswith("//"):
        u = u[2:]
        k = u.find("/")
        if k < 0:
            netloc, u = u, ""
        else:
            netloc, u = u[:k], u[k:]
    return ParseResult(scheme, netloc, u, "", query, fragment)
urlsplit = urlparse
def urlunparse(p):
    s = ""
    if p[0]:
        s += p[0] + "://"
    s += p[1] + p[2]
    if p[4]:
        s += "?" + p[4]
    if p[5]:
        s += "#" + p[5]
    return s
urlunsplit = urlunparse
def urljoin(base, url):
    if "://" in url:
        return url
    p = urlparse(base)
    if url.startswith("/"):
        return p.scheme + "://" + p.netloc + url
    d = p.path.rpartition("/")[0]
    return p.scheme + "://" + p.netloc + d + "/" + url
def parse_qsl(q, **k):
    o = []
    for part in q.split("&"):
        if part:
            a, _, b = part.partition("=")
            o.append((unquote_plus(a), unquote_plus(b)))
    return o
def parse_qs(q, **k):
    d = {}
    for a, b in parse_qsl(q):
        d.setdefault(a, []).append(b)
    return d
]==],
["urllib.error"] = [==[
class URLError(OSError):
    def __init__(self, reason):
        self.reason = reason
        OSError.__init__(self, "<urlopen error %s>" % (reason,))
class HTTPError(URLError):
    def __init__(self, url, code, msg, hdrs=None, fp=None):
        self.url = url
        self.code = code
        self.msg = msg
        self.headers = hdrs
        self.fp = fp
        OSError.__init__(self, "HTTP Error %d: %s" % (code, msg))
    def read(self):
        return self.fp or ""
]==],
["urllib.request"] = [==[
import _lua
from urllib.error import URLError, HTTPError
class Request:
    def __init__(self, url, data=None, headers=None, method=None, **k):
        self.full_url = url
        self.data = data
        self.headers = dict(headers or {})
        self.method = method
    def add_header(self, a, b):
        self.headers[a] = b
    def get_full_url(self):
        return self.full_url
class _Response:
    def __init__(self, url, status, body):
        self.url = url
        self.status = status
        self.code = status
        self.body = body
        self.pos = 0
        self.headers = {}
        self.reason = "OK"
    def read(self, n=-1):
        r = self.body[self.pos:] if n is None or n < 0 else self.body[self.pos:self.pos + n]
        self.pos += len(r)
        return r
    def readline(self):
        k = self.body.find("\n", self.pos)
        e = len(self.body) if k < 0 else k + 1
        r = self.body[self.pos:e]
        self.pos = e
        return r
    def readlines(self):
        return self.body[self.pos:].splitlines(True)
    def __iter__(self):
        return iter(self.readlines())
    def getcode(self):
        return self.status
    def geturl(self):
        return self.url
    def info(self):
        return self.headers
    def getheader(self, k, d=None):
        return d
    def close(self):
        pass
    def __enter__(self):
        return self
    def __exit__(self, *a):
        return False
def urlopen(req, data=None, timeout=None, **k):
    if isinstance(req, str):
        req = Request(req, data)
    t = _lua.dict_new() if False else None
    status, body = _lua.__pyhttp(req.full_url, req.method, req.headers, req.data if req.data is not None else data)
    if status is None:
        raise URLError(body)
    if status >= 400:
        raise HTTPError(req.full_url, status, "error", None, body)
    return _Response(req.full_url, status, body)
def urlretrieve(url, filename=None, **k):
    r = urlopen(url)
    with open(filename or "download", "w") as f:
        f.write(r.read())
    return filename, {}
def build_opener(*a):
    class O:
        addheaders = []
        def open(self, u, d=None, timeout=None):
            return urlopen(u, d)
    return O()
def install_opener(o):
    pass
]==],
["socket"] = [==[
import _lua
AF_INET = 2
AF_INET6 = 10
AF_UNSPEC = 0
SOCK_STREAM = 1
SOCK_DGRAM = 2
SOL_SOCKET = 1
SO_REUSEADDR = 2
SO_KEEPALIVE = 9
SO_BROADCAST = 6
IPPROTO_TCP = 6
TCP_NODELAY = 1
SHUT_RD = 0
SHUT_WR = 1
SHUT_RDWR = 2
error = OSError
class timeout(OSError):
    pass
class gaierror(OSError):
    pass
class herror(OSError):
    pass
_default = None
def setdefaulttimeout(t):
    global _default
    _default = t
def getdefaulttimeout():
    return _default
def gethostname():
    return _lua.sys.hostname()
def gethostbyname(n):
    ok, a = _lua.__pysock("toip", n)
    if not ok:
        raise gaierror(-2, "Name or service not known")
    return a
def getaddrinfo(host, port, family=0, type=0, proto=0, flags=0):
    return [(AF_INET, SOCK_STREAM, 6, "", (gethostbyname(host), port))]
def inet_aton(a):
    return "".join(chr(int(x)) for x in a.split("."))
def inet_ntoa(b):
    return ".".join(str(ord(c)) for c in b)
def _fail(e):
    if e == "timeout":
        return timeout("timed out")
    if e == "connection refused":
        return ConnectionRefusedError(111, "Connection refused")
    if e == "closed":
        return ConnectionResetError(104, "Connection reset by peer")
    return OSError(5, str(e))
class socket:
    def __init__(self, family=AF_INET, type=SOCK_STREAM, proto=0, fileno=None, handle=None):
        self.family = family
        self.type = type
        self.s = handle if handle is not None else _lua.__pysock("new", "udp" if type == SOCK_DGRAM else "tcp")
        self.t = _default
    def settimeout(self, t):
        self.t = t
        _lua.__pysock("timeout", self.s, t)
    def gettimeout(self):
        return self.t
    def setblocking(self, b):
        self.settimeout(None if b else 0)
    def setsockopt(self, level, opt, value):
        names = {SO_REUSEADDR: "reuseaddr", SO_KEEPALIVE: "keepalive", SO_BROADCAST: "broadcast"}
        if level == IPPROTO_TCP:
            _lua.__pysock("option", self.s, "tcp-nodelay", bool(value))
        elif opt in names:
            _lua.__pysock("option", self.s, names[opt], bool(value))
    def getsockopt(self, *a):
        return 0
    def connect(self, addr):
        ok, e = _lua.__pysock("connect", self.s, addr[0], addr[1])
        if not ok:
            raise _fail(e)
    def connect_ex(self, addr):
        ok, e = _lua.__pysock("connect", self.s, addr[0], addr[1])
        return 0 if ok else 111
    def bind(self, addr):
        ok, e = _lua.__pysock("bind", self.s, addr[0] or "*", addr[1])
        if not ok:
            raise _fail(e)
    def listen(self, n=8):
        _lua.__pysock("listen", self.s, n)
    def accept(self):
        ok, c = _lua.__pysock("accept", self.s)
        if not ok:
            raise _fail(c)
        cl = socket(self.family, self.type, handle=c)
        ok2, a, b = _lua.__pysock("peer", c)
        return cl, (a, b)
    def send(self, d):
        ok, e = _lua.__pysock("send", self.s, d)
        if not ok:
            raise _fail(e)
        return ok
    def sendall(self, d):
        self.send(d)
    def sendto(self, d, addr):
        ok, e = _lua.__pysock("sendto", self.s, d, addr[0], addr[1])
        if not ok:
            raise _fail(e)
        return len(d)
    def recv(self, n, flags=0):
        ok, d = _lua.__pysock("recv", self.s, n)
        if not ok:
            if d == "closed":
                return ""
            raise _fail(d)
        return d
    def recvfrom(self, n, flags=0):
        ok, d, a, p = _lua.__pysock("recvfrom", self.s)
        if not ok:
            raise _fail(d)
        return d, (a, p)
    def getsockname(self):
        ok, a, b = _lua.__pysock("name", self.s)
        return (a, b)
    def getpeername(self):
        ok, a, b = _lua.__pysock("peer", self.s)
        return (a, b)
    def fileno(self):
        return 3
    def shutdown(self, how=2):
        _lua.__pysock("shutdown", self.s)
    def close(self):
        if self.s is not None:
            _lua.__pysock("close", self.s)
            self.s = None
    def makefile(self, mode="r", **k):
        return _SockFile(self)
    def __enter__(self):
        return self
    def __exit__(self, *a):
        self.close()
        return False
class _SockFile:
    def __init__(self, s):
        self.s = s
        self.buf = ""
    def _more(self):
        d = self.s.recv(1024)
        self.buf += d
        return d
    def readline(self):
        while "\n" not in self.buf:
            if not self._more():
                break
        k = self.buf.find("\n")
        if k < 0:
            r = self.buf
            self.buf = ""
            return r
        r = self.buf[:k + 1]
        self.buf = self.buf[k + 1:]
        return r
    def read(self, n=-1):
        while n < 0 or len(self.buf) < n:
            if not self._more():
                break
        if n < 0:
            n = len(self.buf)
        r = self.buf[:n]
        self.buf = self.buf[n:]
        return r
    def write(self, d):
        self.s.send(d)
        return len(d)
    def flush(self):
        pass
    def close(self):
        pass
    def __iter__(self):
        return self
    def __next__(self):
        l = self.readline()
        if not l:
            raise StopIteration
        return l
def create_connection(addr, timeout=None, source_address=None):
    s = socket()
    if timeout:
        s.settimeout(timeout)
    s.connect(addr)
    return s
]==],
["queue"] = [==[
class Empty(Exception):
    pass
class Full(Exception):
    pass
class Queue:
    def __init__(self, maxsize=0):
        self.q = []
        self.maxsize = maxsize
    def put(self, x, block=True, timeout=None):
        if self.maxsize and len(self.q) >= self.maxsize:
            raise Full()
        self.q.append(x)
    put_nowait = put
    def get(self, block=True, timeout=None):
        if not self.q:
            raise Empty()
        return self.q.pop(0)
    get_nowait = get
    def empty(self):
        return not self.q
    def full(self):
        return self.maxsize and len(self.q) >= self.maxsize
    def qsize(self):
        return len(self.q)
    def task_done(self):
        pass
    def join(self):
        pass
class LifoQueue(Queue):
    def get(self, block=True, timeout=None):
        if not self.q:
            raise Empty()
        return self.q.pop()
class PriorityQueue(Queue):
    def get(self, block=True, timeout=None):
        if not self.q:
            raise Empty()
        self.q.sort()
        return self.q.pop(0)
]==],
["threading"] = [==[
# one task: a thread runs to its end when it is started
class Thread:
    def __init__(self, group=None, target=None, name=None, args=(), kwargs=None, daemon=None):
        self.target = target
        self.args = args
        self.kwargs = kwargs or {}
        self.name = name or "Thread"
        self.daemon = daemon
        self.alive = False
    def run(self):
        if self.target:
            self.target(*self.args, **self.kwargs)
    def start(self):
        self.alive = True
        self.run()
        self.alive = False
    def join(self, timeout=None):
        pass
    def is_alive(self):
        return self.alive
    def setDaemon(self, d):
        self.daemon = d
class Lock:
    def acquire(self, *a, **k):
        return True
    def release(self):
        pass
    def locked(self):
        return False
    def __enter__(self):
        return self
    def __exit__(self, *a):
        return False
RLock = Lock
Semaphore = Lock
BoundedSemaphore = Lock
class Event:
    def __init__(self):
        self.f = False
    def set(self):
        self.f = True
    def clear(self):
        self.f = False
    def is_set(self):
        return self.f
    def wait(self, t=None):
        return self.f
class Condition(Lock):
    def wait(self, t=None):
        return True
    def notify(self, n=1):
        pass
    def notify_all(self):
        pass
class Timer(Thread):
    def __init__(self, interval, function, args=None, kwargs=None):
        Thread.__init__(self, target=function, args=args or (), kwargs=kwargs)
    def cancel(self):
        self.target = None
class local:
    pass
_main = Thread(name="MainThread")
def current_thread():
    return _main
def main_thread():
    return _main
def active_count():
    return 1
def enumerate():
    return [_main]
]==],
["types"] = [==[
class SimpleNamespace:
    def __init__(self, **kw):
        for k in kw:
            setattr(self, k, kw[k])
    def __repr__(self):
        return "namespace(" + ", ".join("%s=%r" % x for x in self.__dict__.items()) + ")"
def _f(): pass
FunctionType = type(_f)
LambdaType = FunctionType
MethodType = FunctionType
ModuleType = object
GeneratorType = object
BuiltinFunctionType = FunctionType
TracebackType = object
FrameType = object
NoneType = type(None)
]==],
["keyword"] = [==[
kwlist = ["False","None","True","and","as","assert","async","await","break","class","continue","def","del","elif","else","except","finally","for","from","global","if","import","in","is","lambda","nonlocal","not","or","pass","raise","return","try","while","with","yield"]
def iskeyword(s):
    return s in kwlist
]==],
["locale"] = [==[
LC_ALL = 6; LC_CTYPE = 0; LC_NUMERIC = 1; LC_TIME = 2; LC_COLLATE = 3; LC_MONETARY = 4; LC_MESSAGES = 5; CODESET = 14
class Error(Exception):
    pass
def setlocale(c, l=None):
    return "C"
def getlocale(c=None):
    return ("C", "UTF-8")
def getdefaultlocale(*a):
    return ("C", "UTF-8")
def getpreferredencoding(*a):
    return "UTF-8"
def nl_langinfo(x):
    return "UTF-8"
def format_string(f, v, grouping=False):
    return f % v
]==],
["gettext"] = [==[
def gettext(s): return s
def ngettext(a, b, n): return a if n == 1 else b
def bindtextdomain(*a): return None
def textdomain(*a): return None
def install(*a, **k): pass
class NullTranslations:
    def gettext(self, s): return s
    def ngettext(self, a, b, n): return a if n == 1 else b
    def install(self, *a, **k): pass
def translation(*a, **k): return NullTranslations()
_ = gettext
]==],
["getpass"] = [==[
import os
def getuser():
    return os.environ.get("USER", "user")
def getpass(prompt="Password: ", stream=None):
    return input(prompt)
]==],
["codecs"] = [==[
def open(path, mode="r", encoding=None, errors=None, **k):
    import builtins
    return builtins.open(path, mode)
def encode(s, enc="utf-8", errors="strict"):
    return s
def decode(s, enc="utf-8", errors="strict"):
    return s
def lookup(n):
    return n
def getwriter(n):
    return lambda s: s
def getreader(n):
    return lambda s: s
BOM_UTF8 = chr(239) + chr(187) + chr(191)
]==],
["html"] = [==[
def escape(s, quote=True):
    s = s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
    if quote:
        s = s.replace('"', "&quot;").replace("'", "&#x27;")
    return s
def unescape(s):
    return s.replace("&lt;", "<").replace("&gt;", ">").replace("&quot;", '"').replace("&#x27;", "'").replace("&#39;", "'").replace("&nbsp;", " ").replace("&amp;", "&")
]==],
["secrets"] = [==[
import random, os
def token_bytes(n=32): return os.urandom(n)
def token_hex(n=32): return "".join("%02x" % random.randint(0, 255) for _ in range(n))
def token_urlsafe(n=32):
    a = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_"
    return "".join(random.choice(a) for _ in range(n))
def randbelow(n): return random.randrange(n)
def choice(s): return random.choice(s)
def randbits(k): return random.getrandbits(k)
]==],
["uuid"] = [==[
import random
class UUID:
    def __init__(self, hex=None, **k):
        self.hex = (hex or "").replace("-", "").lower()
    def __str__(self):
        h = self.hex
        return h[:8] + "-" + h[8:12] + "-" + h[12:16] + "-" + h[16:20] + "-" + h[20:]
    def __repr__(self):
        return "UUID('%s')" % self
    def __eq__(self, o):
        return str(self) == str(o)
    def __hash__(self):
        return hash(self.hex)
def uuid4():
    h = "".join("%02x" % random.randint(0, 255) for _ in range(16))
    return UUID(h[:12] + "4" + h[13:16] + "89ab"[random.randint(0, 3)] + h[17:])
uuid1 = uuid4
]==],
["pprint"] = [==[
import sys
def pformat(o, indent=1, width=80, **k):
    return repr(o)
def pprint(o, stream=None, **k):
    (stream or sys.stdout).write(pformat(o) + "\n")
pp = pprint
]==],
["csv"] = [==[
QUOTE_MINIMAL = 0
QUOTE_ALL = 1
QUOTE_NONNUMERIC = 2
QUOTE_NONE = 3
class Error(Exception):
    pass
class Dialect:
    delimiter = ","
    quotechar = '"'
    lineterminator = "\r\n"
excel = Dialect
def _split_rows(lines, d, q):
    for line in lines:
        row = []
        cur = ""
        inq = False
        i = 0
        line = line.rstrip("\r\n")
        while i < len(line):
            c = line[i]
            i += 1
            if inq:
                if c == q:
                    if i < len(line) and line[i] == q:
                        cur += q
                        i += 1
                    else:
                        inq = False
                else:
                    cur += c
            elif c == q:
                inq = True
            elif c == d:
                row.append(cur)
                cur = ""
            else:
                cur += c
        row.append(cur)
        yield row
def reader(f, dialect=None, delimiter=",", quotechar='"', **k):
    return _split_rows(f, delimiter, quotechar)
class _Writer:
    def __init__(self, f, delimiter, quotechar, lineterminator, quoting):
        self.f = f
        self.d = delimiter
        self.q = quotechar
        self.t = lineterminator
        self.quoting = quoting
    def writerow(self, row):
        parts = []
        for v in row:
            s = "" if v is None else str(v)
            if self.quoting == QUOTE_ALL or self.d in s or self.q in s or "\n" in s:
                s = self.q + s.replace(self.q, self.q + self.q) + self.q
            parts.append(s)
        self.f.write(self.d.join(parts) + self.t)
    def writerows(self, rows):
        for r in rows:
            self.writerow(r)
def writer(f, dialect=None, delimiter=",", quotechar='"', lineterminator="\r\n", quoting=0, **k):
    return _Writer(f, delimiter, quotechar, lineterminator, quoting)
class DictReader:
    def __init__(self, f, fieldnames=None, delimiter=",", quotechar='"', **k):
        self.r = _split_rows(f, delimiter, quotechar)
        self.fieldnames = fieldnames
    def __iter__(self):
        return self
    def __next__(self):
        if self.fieldnames is None:
            self.fieldnames = next(self.r)
        row = next(self.r)
        return dict(zip(self.fieldnames, row))
class DictWriter:
    def __init__(self, f, fieldnames, delimiter=",", lineterminator="\r\n", **k):
        self.w = _Writer(f, delimiter, '"', lineterminator, 0)
        self.fieldnames = fieldnames
    def writeheader(self):
        self.w.writerow(self.fieldnames)
    def writerow(self, d):
        self.w.writerow([d.get(k, "") for k in self.fieldnames])
    def writerows(self, rows):
        for r in rows:
            self.writerow(r)
]==],
["configparser"] = [==[
class Error(Exception):
    pass
class NoSectionError(Error):
    pass
class NoOptionError(Error):
    pass
class ParsingError(Error):
    pass
class ConfigParser:
    def __init__(self, *a, **k):
        self.data = {}
    def read(self, names, encoding=None):
        if isinstance(names, str):
            names = [names]
        ok = []
        for n in names:
            try:
                with open(n) as f:
                    self.read_file(f)
                ok.append(n)
            except OSError:
                pass
        return ok
    def read_file(self, f, source=None):
        sec = None
        for line in f:
            s = line.strip()
            if not s or s[0] in "#;":
                continue
            if s[0] == "[" and s[-1] == "]":
                sec = s[1:-1]
                self.data.setdefault(sec, {})
            elif sec is not None:
                for sep in "=:":
                    if sep in s:
                        a, b = s.split(sep, 1)
                        self.data[sec][a.strip().lower()] = b.strip()
                        break
    def read_string(self, s, source=None):
        self.read_file(s.splitlines())
    def sections(self):
        return list(self.data)
    def has_section(self, s):
        return s in self.data
    def has_option(self, s, o):
        return s in self.data and o.lower() in self.data[s]
    def options(self, s):
        return list(self.data[s])
    def items(self, s=None):
        return list(self.data[s].items()) if s else list(self.data.items())
    def add_section(self, s):
        self.data[s] = {}
    def set(self, s, o, v):
        self.data[s][o.lower()] = v
    def get(self, s, o, fallback=None, **k):
        if s in self.data and o.lower() in self.data[s]:
            return self.data[s][o.lower()]
        if fallback is not None:
            return fallback
        if s not in self.data:
            raise NoSectionError("No section: %r" % s)
        raise NoOptionError("No option %r in section: %r" % (o, s))
    def getint(self, s, o, **k):
        return int(self.get(s, o, **k))
    def getfloat(self, s, o, **k):
        return float(self.get(s, o, **k))
    def getboolean(self, s, o, **k):
        return str(self.get(s, o, **k)).lower() in ("1", "yes", "true", "on")
    def write(self, f):
        for s in self.data:
            f.write("[%s]\n" % s)
            for k in self.data[s]:
                f.write("%s = %s\n" % (k, self.data[s][k]))
            f.write("\n")
    def __contains__(self, s):
        return s in self.data
    def __getitem__(self, s):
        return self.data[s]
RawConfigParser = ConfigParser
SafeConfigParser = ConfigParser
]==],
["struct"] = [==[
error = ValueError
_SIZES = {"b":1,"B":1,"c":1,"?":1,"h":2,"H":2,"i":4,"I":4,"l":4,"L":4,"q":8,"Q":8,"f":4,"d":8,"s":1,"x":1}
def _parse(fmt):
    big = False
    if fmt and fmt[0] in "<>=!@":
        big = fmt[0] in ">!"
        fmt = fmt[1:]
    items = []
    n = ""
    for c in fmt:
        if c.isdigit():
            n += c
        else:
            items.append((c, int(n) if n else 1))
            n = ""
    return big, items
def calcsize(fmt):
    big, items = _parse(fmt)
    return sum(_SIZES[c] * k for c, k in items)
def pack(fmt, *vals):
    big, items = _parse(fmt)
    out = ""
    i = 0
    for c, k in items:
        if c == "x":
            out += chr(0) * k
        elif c == "s":
            s = vals[i]
            i += 1
            out += (s + chr(0) * k)[:k]
        else:
            for _ in range(k):
                v = vals[i]
                i += 1
                size = _SIZES[c]
                if c == "c":
                    out += v
                    continue
                v = int(v)
                b = [chr((v >> (8 * j)) & 255) for j in range(size)]
                if big:
                    b.reverse()
                out += "".join(b)
    return out
def unpack(fmt, data):
    big, items = _parse(fmt)
    out = []
    p = 0
    for c, k in items:
        if c == "x":
            p += k
        elif c == "s":
            out.append(data[p:p + k])
            p += k
        else:
            for _ in range(k):
                size = _SIZES[c]
                chunk = data[p:p + size]
                p += size
                if c == "c":
                    out.append(chunk)
                    continue
                v = 0
                seq = chunk if big else chunk[::-1]
                for ch in seq:
                    v = (v << 8) | ord(ch)
                if c in "bhilq" and v >= 1 << (size * 8 - 1):
                    v -= 1 << (size * 8)
                out.append(v)
    return tuple(out)
]==],
["select"] = [==[
def select(r, w, x, timeout=None):
    return r, w, []
]==],
["timeit"] = [==[
import time
default_timer = time.perf_counter
def timeit(stmt="pass", setup="pass", timer=None, number=1000000, globals=None):
    t = time.perf_counter()
    for _ in range(number):
        if callable(stmt):
            stmt()
    return time.perf_counter() - t
]==],
["posixpath"] = [==[
from os.path import *
import os
sep = "/"
]==],
["pwd"] = [==[
import os
class struct_passwd:
    def __init__(self):
        self.pw_name = os.environ.get("USER", "user")
        self.pw_dir = os.environ.get("HOME", "/home/user")
        self.pw_uid = 1000
        self.pw_gid = 1000
        self.pw_shell = "/bin/sh"
        self.pw_gecos = ""
def getpwuid(u): return struct_passwd()
def getpwnam(n): return struct_passwd()
def getpwall(): return [struct_passwd()]
]==],
["grp"] = [==[
class struct_group:
    gr_name = "user"
    gr_gid = 1000
    gr_mem = []
def getgrgid(g): return struct_group()
def getgrnam(n): return struct_group()
]==],
["typing_extensions"] = [==[
from typing import *
]==],
["http"] = [==[
class HTTPStatus:
    OK = 200
    NOT_FOUND = 404
]==],
["http.client"] = [==[
import urllib.request as _r
class HTTPException(Exception):
    pass
class HTTPConnection:
    scheme = "http"
    def __init__(self, host, port=None, timeout=None, **k):
        self.host = host if not port else "%s:%d" % (host, port)
        self.resp = None
    def request(self, method, url, body=None, headers=None):
        self.resp = _r.urlopen(_r.Request(self.scheme + "://" + self.host + url, body, headers or {}, method))
    def getresponse(self):
        return self.resp
    def close(self):
        pass
class HTTPSConnection(HTTPConnection):
    scheme = "https"
OK = 200
]==],
["ssl"] = [==[
class SSLError(OSError):
    pass
class SSLContext:
    def __init__(self, *a, **k):
        pass
def create_default_context(*a, **k):
    return SSLContext()
CERT_NONE = 0
PROTOCOL_TLS = 2
]==],
["cmd"] = [==[
import sys
class Cmd:
    prompt = "(Cmd) "
    intro = None
    def __init__(self, *a, **k):
        self.lastcmd = ""
    def cmdloop(self, intro=None):
        if intro or self.intro:
            print(intro or self.intro)
        self.preloop()
        stop = False
        while not stop:
            try:
                line = input(self.prompt)
            except EOFError:
                line = "EOF"
            line = self.precmd(line)
            stop = self.onecmd(line)
            stop = self.postcmd(stop, line)
        self.postloop()
    def onecmd(self, line):
        line = line.strip()
        if not line:
            return self.emptyline()
        name, _, arg = line.partition(" ")
        f = getattr(self, "do_" + name, None)
        if f:
            return f(arg)
        return self.default(line)
    def default(self, line):
        print("*** Unknown syntax: " + line)
    def emptyline(self):
        return False
    def preloop(self): pass
    def postloop(self): pass
    def precmd(self, l): return l
    def postcmd(self, s, l): return s
    def do_help(self, arg):
        print(" ".join(k[3:] for k in dir(self) if k.startswith("do_")))
]==],
["readline"] = [==[
def parse_and_bind(s): pass
def set_completer(f): pass
def add_history(s): pass
def read_history_file(p=None): pass
def write_history_file(p=None): pass
def set_history_length(n): pass
]==],
["tty"] = [==[
def setraw(*a): pass
def setcbreak(*a): pass
]==],
["termios"] = [==[
TCSANOW = 0
TCSADRAIN = 1
TCSAFLUSH = 2
def tcgetattr(fd): return []
def tcsetattr(fd, when, attrs): pass
class error(Exception):
    pass
]==],
["fcntl"] = [==[
def ioctl(*a): return 0
def fcntl(*a): return 0
def flock(*a): pass
LOCK_EX = 2
LOCK_UN = 8
LOCK_SH = 1
LOCK_NB = 4
]==],
["curses"] = [==[
import _lua
ERR = -1
OK = 0
A_NORMAL = 0
A_BOLD = 2097152
A_REVERSE = 65536
A_STANDOUT = 65536
A_UNDERLINE = 131072
A_DIM = 1048576
A_BLINK = 524288
COLOR_BLACK, COLOR_RED, COLOR_GREEN, COLOR_YELLOW, COLOR_BLUE, COLOR_MAGENTA, COLOR_CYAN, COLOR_WHITE = 0, 1, 2, 3, 4, 5, 6, 7
KEY_DOWN, KEY_UP, KEY_LEFT, KEY_RIGHT, KEY_HOME, KEY_BACKSPACE, KEY_DC, KEY_NPAGE, KEY_PPAGE, KEY_ENTER, KEY_END, KEY_RESIZE = 258, 259, 260, 261, 262, 263, 330, 338, 339, 343, 360, 410
error = Exception
_pairs = {}
_names = ["dim", "red", "green", "yellow", "blue", "magenta", "cyan", "white"]
LINES = 24
COLS = 80
def color_pair(n): return n << 8
def pair_number(a): return (a >> 8) & 255
def init_pair(n, f, b): _pairs[n] = _names[f] if 0 <= f < 8 else "text"
def start_color(): pass
def use_default_colors(): pass
def has_colors(): return True
def noecho(): pass
def echo(): pass
def cbreak(): pass
def nocbreak(): pass
def raw(): pass
def curs_set(n): return 1
def napms(n): _lua.sys.sleep(n)
def beep(): pass
def flash(): pass
def doupdate(): _lua.term.flush()
def flushinp(): pass
def endwin(): _lua.term.fullscreen(False)
def isendwin(): return False
def _color(a):
    c = _pairs.get((a >> 8) & 255, "text")
    if a & 65536:
        return "inverse" if c == "text" else "inverse-" + c
    if a & 2097152 and c == "text":
        return "white"
    return c
_KEYS = {"up": 259, "down": 258, "left": 260, "right": 261, "backspace": 263, "enter": 10, "tab": 9, "space": 32}
class _Window:
    def __init__(self, h, w, y=0, x=0):
        self.h = h
        self.w = w
        self.oy = y
        self.ox = x
        self.y = 0
        self.x = 0
        self.attr = 0
        self.delay = -1
    def getmaxyx(self): return (self.h, self.w)
    def getbegyx(self): return (self.oy, self.ox)
    def getyx(self): return (self.y, self.x)
    def keypad(self, f): pass
    def nodelay(self, f): self.delay = 0 if f else -1
    def timeout(self, t): self.delay = t
    def scrollok(self, f): pass
    def leaveok(self, f): pass
    def idlok(self, f): pass
    def clear(self):
        for y in range(self.h):
            _lua.term.text(self.ox, self.oy + y, " " * self.w)
        self.y = 0
        self.x = 0
    erase = clear
    def clrtoeol(self):
        _lua.term.text(self.ox + self.x, self.oy + self.y, " " * max(0, self.w - self.x))
    def clrtobot(self):
        self.clrtoeol()
        for y in range(self.y + 1, self.h):
            _lua.term.text(self.ox, self.oy + y, " " * self.w)
    def move(self, y, x):
        self.y = y
        self.x = x
    def attron(self, a): self.attr |= a
    def attroff(self, a): self.attr &= ~a
    def attrset(self, a): self.attr = a
    def bkgd(self, *a): pass
    def border(self, *a): self.box()
    def box(self, *a):
        _lua.term.text(self.ox, self.oy, "+" + "-" * (self.w - 2) + "+")
        _lua.term.text(self.ox, self.oy + self.h - 1, "+" + "-" * (self.w - 2) + "+")
        for y in range(1, self.h - 1):
            _lua.term.put(self.ox, self.oy + y, "|")
            _lua.term.put(self.ox + self.w - 1, self.oy + y, "|")
    def addstr(self, *a):
        if isinstance(a[0], int):
            self.y = a[0]
            self.x = a[1]
            a = a[2:]
        s = a[0]
        attr = (a[1] if len(a) > 1 else 0) | self.attr
        for line_i, part in enumerate(s.split("\n")):
            if line_i:
                self.y += 1
                self.x = 0
            room = self.w - self.x
            if part and room > 0 and 0 <= self.y < self.h:
                _lua.term.text(self.ox + self.x, self.oy + self.y, part[:room], _color(attr))
            self.x += len(part)
    addnstr = addstr
    insstr = addstr
    def addch(self, *a):
        if isinstance(a[0], int) and len(a) >= 3:
            self.y = a[0]
            self.x = a[1]
            a = a[2:]
        c = a[0]
        if isinstance(c, int):
            c = chr(c & 255)
        self.addstr(c, a[1] if len(a) > 1 else 0)
    def hline(self, *a): pass
    def vline(self, *a): pass
    def refresh(self): _lua.term.flush()
    def noutrefresh(self): pass
    def getch(self, *a):
        _lua.term.flush()
        start = _lua.sys.millis()
        while True:
            k = _lua.key.poll()
            if k is not None:
                if k in _KEYS:
                    return _KEYS[k]
                if len(k) == 1:
                    return ord(k)
                if k.startswith("ctrl-"):
                    return ord(k[5]) & 31
            if self.delay >= 0 and _lua.sys.millis() - start >= self.delay:
                return -1
            _lua.sys.sleep(5)
    def getkey(self, *a):
        c = self.getch()
        return chr(c) if c < 256 else "KEY"
    def getstr(self, *a):
        return input("")
    def subwin(self, *a):
        return _Window(a[0], a[1], a[2] if len(a) > 2 else 0, a[3] if len(a) > 3 else 0)
    derwin = subwin
    def resize(self, h, w):
        self.h = h
        self.w = w
def newwin(h, w, y=0, x=0):
    return _Window(h, w, y, x)
def initscr():
    global LINES, COLS
    w, h = _size()
    LINES = h
    COLS = w
    _lua.term.fullscreen(True)
    _lua.term.clear()
    return _Window(h, w)
def _size():
    import os
    s = os.get_terminal_size()
    return s.columns, s.lines
def wrapper(f, *a, **k):
    s = initscr()
    try:
        return f(s, *a, **k)
    finally:
        endwin()
]==],
["__future__"] = [==[
annotations = None
print_function = None
division = None
unicode_literals = None
absolute_import = None
generators = None
]==],
["fractions"] = [==[
import math
class Fraction:
    def __init__(self, n=0, d=1):
        g = math.gcd(n, d) or 1
        if d < 0:
            g = -g
        self.numerator = n // g
        self.denominator = d // g
    def __add__(self, o):
        o = _f(o)
        return Fraction(self.numerator * o.denominator + o.numerator * self.denominator, self.denominator * o.denominator)
    __radd__ = __add__
    def __sub__(self, o):
        o = _f(o)
        return Fraction(self.numerator * o.denominator - o.numerator * self.denominator, self.denominator * o.denominator)
    def __mul__(self, o):
        o = _f(o)
        return Fraction(self.numerator * o.numerator, self.denominator * o.denominator)
    __rmul__ = __mul__
    def __truediv__(self, o):
        o = _f(o)
        return Fraction(self.numerator * o.denominator, self.denominator * o.numerator)
    def __eq__(self, o):
        o = _f(o)
        return self.numerator == o.numerator and self.denominator == o.denominator
    def __lt__(self, o):
        o = _f(o)
        return self.numerator * o.denominator < o.numerator * self.denominator
    def __float__(self):
        return self.numerator / self.denominator
    def __str__(self):
        return str(self.numerator) if self.denominator == 1 else "%d/%d" % (self.numerator, self.denominator)
    def __repr__(self):
        return "Fraction(%d, %d)" % (self.numerator, self.denominator)
def _f(x):
    return x if isinstance(x, Fraction) else Fraction(x)
]==],
["inspect"] = [==[
def isfunction(o): return callable(o) and not isinstance(o, type)
def isclass(o): return isinstance(o, type)
def ismethod(o): return False
def ismodule(o): return False
def isgenerator(o): return False
def signature(o): return None
def getdoc(o): return getattr(o, "__doc__", None)
def getmembers(o, p=None):
    out = []
    for k in dir(o):
        v = getattr(o, k, None)
        if not p or p(v):
            out.append((k, v))
    return out
def stack(*a): return []
def currentframe(): return None
]==],
["unittest"] = [==[
import sys
class TestCase:
    def assertEqual(self, a, b, msg=None):
        if a != b:
            raise AssertionError(msg or "%r != %r" % (a, b))
    def assertTrue(self, a, msg=None):
        if not a:
            raise AssertionError(msg or "not true")
    def assertFalse(self, a, msg=None):
        if a:
            raise AssertionError(msg or "not false")
def main(*a, **k):
    pass
]==],
["gzip"] = [==[
def open(*a, **k):
    raise OSError("gzip is not available in this Python")
def compress(d): raise OSError("gzip is not available in this Python")
def decompress(d): raise OSError("gzip is not available in this Python")
class GzipFile:
    def __init__(self, *a, **k):
        raise OSError("gzip is not available in this Python")
]==],
}
