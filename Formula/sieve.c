#!/usr/bin/env gcc -run
/* sieve: the primes up to N with the time it took, a C program. usage: sieve [N] */
#include <stdio.h>
#include <stdlib.h>
#include <time.h>
int main(int argc, char **argv) {
    int n = argc > 1 ? atoi(argv[1]) : 10000, count = 0;
    char *composite = malloc(n + 1);
    clock_t start = clock();
    for (int i = 2; i <= n; i++) {
        if (composite[i]) continue;
        count++;
        for (long j = (long)i * i; j <= n; j += i) composite[j] = 1;
    }
    printf("%d primes up to %d in %ld ms\n", count, n, (long)(clock() - start));
    free(composite);
    return 0;
}
