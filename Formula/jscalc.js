#!/usr/bin/env node
// jscalc: a calculator with variables, a JavaScript program. usage: jscalc "EXPRESSION" (+ - * / ^, parentheses, sqrt sin cos ln, pi)
function tokenize(s) {
  const out = [];
  for (const m of s.matchAll(/\s*(\d+\.?\d*|[a-z]+|[-+*\/^()])/g)) out.push(m[1]);
  return out;
}
class Parser {
  constructor(tokens) { this.t = tokens; this.i = 0; }
  peek() { return this.t[this.i]; }
  next() { return this.t[this.i++]; }
  expr() {
    let v = this.term();
    while (this.peek() === "+" || this.peek() === "-") v = this.next() === "+" ? v + this.term() : v - this.term();
    return v;
  }
  term() {
    let v = this.pow();
    while (this.peek() === "*" || this.peek() === "/") v = this.next() === "*" ? v * this.pow() : v / this.pow();
    return v;
  }
  pow() {
    const b = this.atom();
    return this.peek() === "^" ? (this.next(), b ** this.pow()) : b;
  }
  atom() {
    const x = this.next();
    if (x === "(") { const v = this.expr(); this.next(); return v; }
    if (x === "-") return -this.atom();
    if (x === "pi") return Math.PI;
    if (/^[a-z]/.test(x)) {
      const f = { sqrt: Math.sqrt, sin: Math.sin, cos: Math.cos, ln: Math.log }[x];
      if (!f) throw new Error("unknown name " + x);
      return f(this.atom());
    }
    if (x === undefined) throw new Error("the expression ends too early");
    return parseFloat(x);
  }
}
const text = process.argv.slice(2).join(" ");
if (!text) { console.log('usage: jscalc "2*(3+4)^2"'); process.exit(1); }
try { console.log(new Parser(tokenize(text)).expr()); } catch (e) { console.log("error: " + e.message); process.exit(1); }
