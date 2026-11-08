// loc: counts the lines of code in a folder, per language: code, comments and blank lines.
//   loc [PATH...]
use std::collections::HashMap;
use std::env;
use std::fs;
use std::path::Path;

#[derive(Default, Clone)]
struct Count {
    files: u64,
    code: u64,
    comment: u64,
    blank: u64,
}

fn language(ext: &str) -> Option<(&'static str, &'static str)> {
    match ext {
        "rs" => Some(("Rust", "//")),
        "c" | "h" => Some(("C", "//")),
        "cpp" | "cc" | "hpp" => Some(("C++", "//")),
        "py" => Some(("Python", "#")),
        "js" | "mjs" => Some(("JavaScript", "//")),
        "go" => Some(("Go", "//")),
        "lua" => Some(("Lua", "--")),
        "sh" | "bash" => Some(("Shell", "#")),
        "md" => Some(("Markdown", "")),
        _ => None,
    }
}

fn count_file(path: &Path, comment: &str, c: &mut Count) {
    let text = match fs::read_to_string(path) {
        Ok(t) => t,
        Err(_) => return,
    };
    c.files += 1;
    let mut in_block = false;
    let c_like = comment == "//";
    for line in text.lines() {
        let t = line.trim();
        if t.is_empty() {
            c.blank += 1;
        } else if in_block {
            c.comment += 1;
            if t.contains("*/") {
                in_block = false;
            }
        } else if c_like && t.starts_with("/*") {
            c.comment += 1;
            if !t.contains("*/") {
                in_block = true;
            }
        } else if !comment.is_empty() && t.starts_with(comment) {
            c.comment += 1;
        } else {
            c.code += 1;
        }
    }
}

fn walk(dir: &Path, totals: &mut HashMap<String, Count>) {
    let entries = match fs::read_dir(dir) {
        Ok(e) => e,
        Err(e) => {
            eprintln!("loc: {}: {}", dir.display(), e);
            return;
        }
    };
    let mut names: Vec<_> = Vec::new();
    for entry in entries {
        if let Ok(e) = entry {
            names.push(e.path());
        }
    }
    names.sort();
    for path in names {
        let name = path.file_name().map(|s| s.to_string_lossy().to_string()).unwrap_or_default();
        if name.starts_with('.') || name == "target" || name == "node_modules" {
            continue;
        }
        if path.is_dir() {
            walk(&path, totals);
        } else if let Some(ext) = path.extension() {
            let ext = ext.to_string_lossy().to_string();
            if let Some((lang, comment)) = language(&ext) {
                let c = totals.entry(lang.to_string()).or_default();
                count_file(&path, comment, c);
            }
        }
    }
}

fn main() {
    let args: Vec<String> = env::args().skip(1).collect();
    if args.iter().any(|a| a == "-h" || a == "--help") {
        println!("usage: loc [PATH...]");
        return;
    }
    let mut totals: HashMap<String, Count> = HashMap::new();
    if args.is_empty() {
        walk(Path::new("."), &mut totals);
    }
    for a in &args {
        let p = Path::new(a);
        if p.is_dir() {
            walk(p, &mut totals);
        } else if let Some(ext) = p.extension() {
            let ext = ext.to_string_lossy().to_string();
            if let Some((lang, comment)) = language(&ext) {
                count_file(p, comment, totals.entry(lang.to_string()).or_default());
            }
        } else {
            eprintln!("loc: {}: not a source file", a);
        }
    }
    let mut rows: Vec<(String, Count)> = totals.into_iter().collect();
    rows.sort_by(|a, b| b.1.code.cmp(&a.1.code).then(a.0.cmp(&b.0)));
    println!("{:<12} {:>6} {:>8} {:>8} {:>8}", "language", "files", "code", "comment", "blank");
    let mut sum = Count::default();
    for (name, c) in &rows {
        println!("{:<12} {:>6} {:>8} {:>8} {:>8}", name, c.files, c.code, c.comment, c.blank);
        sum.files += c.files;
        sum.code += c.code;
        sum.comment += c.comment;
        sum.blank += c.blank;
    }
    println!("{:<12} {:>6} {:>8} {:>8} {:>8}", "total", sum.files, sum.code, sum.comment, sum.blank);
}
