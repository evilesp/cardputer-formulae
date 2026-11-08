/* hxd: a hex dump and patch tool, in the manner of xxd.
 *   hxd [-c COLS] [-s SKIP] [-l LEN] [-u] [-p] FILE     the bytes in hex and text
 *   hxd -r TEXTFILE OUT                                  makes the bytes again from the dump
 *   hxd -f BYTES FILE                                    finds a hex string, prints the offsets
 *   hxd -w OFFSET BYTES FILE                             writes hex bytes at an offset */
#include <ctype.h>
#include <getopt.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int columns = 16;
static long skip_bytes = 0;
static long max_len = -1;
static int upper = 0;
static int plain = 0;

static int hexval(int c) {
    if (c >= '0' && c <= '9') return c - '0';
    if (c >= 'a' && c <= 'f') return c - 'a' + 10;
    if (c >= 'A' && c <= 'F') return c - 'A' + 10;
    return -1;
}

static int parse_hex(const char *s, unsigned char *out, int max) {
    int n = 0;
    while (*s && n < max) {
        while (*s == ' ') s++;
        if (!*s) break;
        int a = hexval(s[0]);
        int b = s[1] ? hexval(s[1]) : -1;
        if (a < 0 || b < 0) return -1;
        out[n++] = (unsigned char)(a * 16 + b);
        s += 2;
    }
    return n;
}

static int dump(const char *path) {
    FILE *f = fopen(path, "rb");
    if (!f) {
        perror(path);
        return 1;
    }
    if (skip_bytes > 0) fseek(f, skip_bytes, SEEK_SET);
    unsigned char line[64];
    long off = skip_bytes;
    long left = max_len;
    const char *fmt = upper ? "%02X" : "%02x";
    for (;;) {
        int want = columns;
        if (left >= 0 && left < want) want = (int)left;
        if (want == 0) break;
        int got = (int)fread(line, 1, want, f);
        if (got <= 0) break;
        if (plain) {
            for (int i = 0; i < got; i++) printf(fmt, line[i]);
            putchar('\n');
        } else {
            printf("%08lx: ", off);
            for (int i = 0; i < columns; i++) {
                if (i < got) printf(fmt, line[i]);
                else printf("  ");
                if (i % 2 == 1) putchar(' ');
            }
            putchar(' ');
            for (int i = 0; i < got; i++) putchar(isprint(line[i]) ? line[i] : '.');
            putchar('\n');
        }
        off += got;
        if (left >= 0) left -= got;
    }
    fclose(f);
    return 0;
}

static int reverse(const char *in, const char *out) {
    FILE *f = fopen(in, "r");
    if (!f) {
        perror(in);
        return 1;
    }
    FILE *o = fopen(out, "wb");
    if (!o) {
        perror(out);
        fclose(f);
        return 1;
    }
    char text[512];
    long total = 0;
    while (fgets(text, sizeof text, f)) {
        char *p = strchr(text, ':');
        p = p ? p + 1 : text;
        int spaces = 0;
        while (*p) {
            if (*p == ' ') {
                spaces++;
                p++;
                if (spaces >= 2) break;
                continue;
            }
            spaces = 0;
            int a = hexval(p[0]);
            int b = p[1] ? hexval(p[1]) : -1;
            if (a < 0 || b < 0) break;
            fputc(a * 16 + b, o);
            total++;
            p += 2;
        }
    }
    fclose(f);
    fclose(o);
    printf("%ld bytes written to %s\n", total, out);
    return 0;
}

static int find_bytes(const char *hex, const char *path) {
    unsigned char want[64];
    int n = parse_hex(hex, want, 64);
    if (n <= 0) {
        fprintf(stderr, "hxd: bad hex string\n");
        return 2;
    }
    FILE *f = fopen(path, "rb");
    if (!f) {
        perror(path);
        return 1;
    }
    int matched = 0, found = 0;
    long off = 0;
    int c;
    while ((c = fgetc(f)) != EOF) {
        if (c == want[matched]) {
            matched++;
            if (matched == n) {
                printf("%08lx\n", off - n + 1);
                found++;
                matched = 0;
            }
        } else {
            matched = c == want[0] ? 1 : 0;
        }
        off++;
    }
    fclose(f);
    fprintf(stderr, "%d found\n", found);
    return found ? 0 : 1;
}

static int patch(long off, const char *hex, const char *path) {
    unsigned char bytes[256];
    int n = parse_hex(hex, bytes, 256);
    if (n <= 0) {
        fprintf(stderr, "hxd: bad hex string\n");
        return 2;
    }
    FILE *f = fopen(path, "r+b");
    if (!f) {
        perror(path);
        return 1;
    }
    fseek(f, off, SEEK_SET);
    fwrite(bytes, 1, n, f);
    fclose(f);
    printf("%d bytes written at %08lx\n", n, off);
    return 0;
}

static void usage(void) {
    puts("usage: hxd [-c COLS] [-s SKIP] [-l LEN] [-u] [-p] FILE");
    puts("       hxd -r DUMP OUT | hxd -f HEX FILE | hxd -w OFFSET HEX FILE");
}

int main(int argc, char **argv) {
    int c;
    int mode = 0;
    while ((c = getopt(argc, argv, "c:s:l:uprfwh")) != -1) {
        switch (c) {
            case 'c':
                columns = atoi(optarg);
                if (columns < 1 || columns > 64) columns = 16;
                break;
            case 's': skip_bytes = strtol(optarg, NULL, 0); break;
            case 'l': max_len = strtol(optarg, NULL, 0); break;
            case 'u': upper = 1; break;
            case 'p': plain = 1; break;
            case 'r':
            case 'f':
            case 'w': mode = c; break;
            default:
                usage();
                return c == 'h' ? 0 : 2;
        }
    }
    int left = argc - optind;
    if (mode == 'r' && left == 2) return reverse(argv[optind], argv[optind + 1]);
    if (mode == 'f' && left == 2) return find_bytes(argv[optind], argv[optind + 1]);
    if (mode == 'w' && left == 3) return patch(strtol(argv[optind], NULL, 0), argv[optind + 1], argv[optind + 2]);
    if (mode == 0 && left == 1) return dump(argv[optind]);
    usage();
    return 2;
}
