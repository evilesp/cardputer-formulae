#!/usr/bin/env g++ -run
// matrixcalc: powers of a 2x2 matrix (Fibonacci numbers), a C++ program. usage: matrixcalc [N]
#include <iostream>
#include <vector>
#include <string>
using namespace std;
struct Mat {
    long long a, b, c, d;
    Mat operator*(const Mat& o) const { return {a * o.a + b * o.c, a * o.b + b * o.d, c * o.a + d * o.c, c * o.b + d * o.d}; }
};
Mat power(Mat m, int n) {
    Mat r{1, 0, 0, 1};
    while (n > 0) {
        if (n & 1) r = r * m;
        m = m * m;
        n >>= 1;
    }
    return r;
}
int main(int argc, char** argv) {
    int n = argc > 1 ? stoi(argv[1]) : 10;
    vector<long long> fib;
    for (int i = 0; i <= n; i++) fib.push_back(power(Mat{1, 1, 1, 0}, i).b);
    for (auto x : fib) cout << x << " ";
    cout << endl;
    return 0;
}
