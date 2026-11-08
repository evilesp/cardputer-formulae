#!/usr/bin/env rustc -run
// lifers: a few generations of the game of life as text, a Rust program. usage: lifers [GENERATIONS]
#[derive(Clone)]
struct World { w: usize, h: usize, cells: Vec<bool> }
impl World {
    fn new(w: usize, h: usize) -> Self { World { w, h, cells: vec![false; w * h] } }
    fn set(&mut self, x: usize, y: usize) { let i = y * self.w + x; self.cells[i] = true; }
    fn alive_near(&self, x: usize, y: usize) -> usize {
        let mut n = 0;
        for dy in [self.h - 1, 0, 1] {
            for dx in [self.w - 1, 0, 1] {
                if dx == 0 && dy == 0 { continue; }
                if self.cells[(y + dy) % self.h * self.w + (x + dx) % self.w] { n += 1; }
            }
        }
        n
    }
    fn step(&self) -> World {
        let mut next = World::new(self.w, self.h);
        for y in 0..self.h {
            for x in 0..self.w {
                let n = self.alive_near(x, y);
                if n == 3 || (n == 2 && self.cells[y * self.w + x]) { next.set(x, y); }
            }
        }
        next
    }
    fn show(&self) {
        for y in 0..self.h {
            let line: String = (0..self.w).map(|x| if self.cells[y * self.w + x] { '#' } else { '.' }).collect();
            println!("{}", line);
        }
        println!();
    }
}
fn main() {
    let gens: usize = std::env::args().nth(1).and_then(|s| s.parse().ok()).unwrap_or(3);
    let mut world = World::new(10, 6);
    for (x, y) in [(1, 0), (2, 1), (0, 2), (1, 2), (2, 2)] { world.set(x, y); }
    for _ in 0..gens { world.show(); world = world.step(); }
}
