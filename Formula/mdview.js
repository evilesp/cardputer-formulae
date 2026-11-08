#!/usr/bin/env node
// mdview: shows a Markdown file in the terminal, in colours: headings, lists, quotes, code, tables, bold and links.
//   mdview FILE.md   or   cat FILE.md | mdview
const fs = require('fs');

const C = { reset: '\x1b[0m', bold: '\x1b[1m', dim: '\x1b[2m', red: '\x1b[31m', green: '\x1b[32m', yellow: '\x1b[33m', blue: '\x1b[34m', magenta: '\x1b[35m', cyan: '\x1b[36m' };
const useColor = !process.env.NO_COLOR;
const paint = (c, s) => (useColor ? c + s + C.reset : s);
const width = (process.stdout && process.stdout.columns) || 56;

function inline(text) {
  return text
    .replace(/!?\[([^\]]*)\]\(([^)]*)\)/g, (_, a, b) => paint(C.blue, a) + paint(C.dim, ' <' + b + '>'))
    .replace(/`([^`]+)`/g, (_, a) => paint(C.yellow, a))
    .replace(/\*\*([^*]+)\*\*/g, (_, a) => paint(C.bold, a))
    .replace(/__([^_]+)__/g, (_, a) => paint(C.bold, a))
    .replace(/\*([^*]+)\*/g, (_, a) => paint(C.cyan, a));
}

function visible(s) {
  return s.replace(/\x1b\[[0-9;]*m/g, '').length;
}

function wrap(text, indent, first) {
  const words = text.split(/\s+/).filter((w) => w.length > 0);
  const lines = [];
  let line = first;
  let size = first.length;
  for (const word of words) {
    const n = visible(word);
    if (size + n + 1 > width && size > indent.length) {
      lines.push(line);
      line = indent + word;
      size = indent.length + n;
    } else {
      const gap = size > indent.length && line !== first ? ' ' : '';
      line += gap + word;
      size += gap.length + n;
    }
  }
  lines.push(line);
  return lines.join('\n');
}

function table(rows) {
  const cells = rows.filter((r) => !/^\s*\|?[\s:|-]+\|?\s*$/.test(r)).map((r) => r.replace(/^\s*\|/, '').replace(/\|\s*$/, '').split('|').map((c) => c.trim()));
  const widths = [];
  for (const row of cells) {
    row.forEach((c, i) => {
      widths[i] = Math.max(widths[i] || 0, c.length);
    });
  }
  const out = [];
  cells.forEach((row, i) => {
    const text = row.map((c, k) => c + ' '.repeat(widths[k] - c.length)).join(' | ');
    out.push(i === 0 ? paint(C.bold, text) : text);
    if (i === 0) out.push(widths.map((w) => '-'.repeat(w)).join('-+-'));
  });
  return out.join('\n');
}

function render(source) {
  const lines = source.split('\n');
  const out = [];
  let i = 0;
  while (i < lines.length) {
    const line = lines[i];
    let m;
    if (/^```/.test(line)) {
      i++;
      while (i < lines.length && !/^```/.test(lines[i])) {
        out.push(paint(C.green, '  ' + lines[i]));
        i++;
      }
      i++;
      continue;
    }
    if ((m = /^(#{1,6})\s+(.*)$/.exec(line))) {
      const level = m[1].length;
      const title = m[2].replace(/\s*#+\s*$/, '');
      out.push('');
      out.push(paint(level === 1 ? C.magenta + C.bold : level === 2 ? C.cyan + C.bold : C.bold, title));
      if (level === 1) out.push(paint(C.magenta, '='.repeat(Math.min(title.length, width))));
      if (level === 2) out.push(paint(C.cyan, '-'.repeat(Math.min(title.length, width))));
      i++;
      continue;
    }
    if (/^\s*\|.*\|\s*$/.test(line)) {
      const rows = [];
      while (i < lines.length && /^\s*\|.*\|\s*$/.test(lines[i])) rows.push(lines[i++]);
      out.push(table(rows));
      continue;
    }
    if ((m = /^(\s*)([-*+]|\d+\.)\s+(.*)$/.exec(line))) {
      const pad = m[1];
      const mark = /\d/.test(m[2]) ? m[2] : '*';
      const head = pad + paint(C.yellow, mark) + ' ';
      const indent = pad + ' '.repeat(mark.length + 1);
      const first = head;
      out.push(wrap(inline(m[3]), indent, first));
      i++;
      continue;
    }
    if ((m = /^>\s?(.*)$/.exec(line))) {
      out.push(paint(C.dim, '| ' + m[1]));
      i++;
      continue;
    }
    if (/^(-{3,}|\*{3,}|_{3,})\s*$/.test(line)) {
      out.push(paint(C.dim, '-'.repeat(width)));
      i++;
      continue;
    }
    if (line.trim() === '') {
      if (out.length > 0 && out[out.length - 1] !== '') out.push('');
      i++;
      continue;
    }
    const para = [];
    while (i < lines.length && lines[i].trim() !== '' && !/^(#{1,6}\s|```|>|\s*[-*+]\s|\s*\d+\.\s|\s*\|)/.test(lines[i])) para.push(lines[i++]);
    if (para.length === 0) {
      para.push(lines[i++]);
    }
    out.push(wrap(inline(para.join(' ')), '', ''));
  }
  return out.join('\n');
}

function main() {
  const args = process.argv.slice(2);
  if (args[0] === '-h' || args[0] === '--help') {
    console.log('usage: mdview FILE.md   (or a pipe)');
    return;
  }
  let text;
  try {
    text = fs.readFileSync(args.length ? args[0] : 0, 'utf8');
  } catch (e) {
    console.error('mdview: ' + args[0] + ': no such file');
    process.exit(1);
  }
  console.log(render(text));
}

main();
