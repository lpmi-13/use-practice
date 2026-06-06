//! uwait is the generic wait-state workload. It exists for scenarios where the
//! interesting signal is task state rather than disk, memory, or socket volume:
//!
//!   * `mode=kernelwait` — run CPU burner threads while many peer threads block
//!                         in a non-I/O uninterruptible kernel wait (`vfork`).
//!   * `mode=baseline`   — a low-activity heartbeat used as same-binary decoys.

use std::collections::HashMap;
use std::fs::{File, OpenOptions};
use std::io::{Read, Write};
use std::path::PathBuf;
use std::sync::atomic::{AtomicU64, Ordering};
use std::thread;
use std::time::Duration;

const PAGE_SIZE: usize = 4096;
static BURN_SINK: AtomicU64 = AtomicU64::new(0);
static BASE_SINK: AtomicU64 = AtomicU64::new(0);

fn cfg_path() -> PathBuf {
    if let Ok(p) = std::env::var("UW_CFG") {
        if !p.is_empty() {
            return PathBuf::from(p);
        }
    }
    let exe = std::env::current_exe().expect("current_exe");
    let dir = exe.parent().expect("exe dir").to_path_buf();
    let name = exe
        .file_name()
        .expect("exe name")
        .to_string_lossy()
        .to_string();
    dir.join(format!("{name}.cfg"))
}

fn load_cfg() -> HashMap<String, String> {
    let path = cfg_path();
    let mut m = HashMap::new();
    if let Ok(s) = std::fs::read_to_string(&path) {
        for line in s.lines() {
            let line = line.trim();
            if line.is_empty() || line.starts_with('#') {
                continue;
            }
            if let Some((k, v)) = line.split_once('=') {
                m.insert(k.trim().to_string(), v.trim().to_string());
            }
        }
    }
    let _ = std::fs::remove_file(&path); // leave no on-disk hint behind
    m
}

fn get_int(m: &HashMap<String, String>, k: &str, def: i64) -> i64 {
    m.get(k).and_then(|v| v.parse().ok()).unwrap_or(def)
}

fn get_str(m: &HashMap<String, String>, k: &str, def: &str) -> String {
    match m.get(k) {
        Some(v) if !v.is_empty() => v.clone(),
        _ => def.to_string(),
    }
}

fn main() {
    let m = load_cfg();
    match get_str(&m, "mode", "baseline").as_str() {
        "kernelwait" => run_kernelwait(&m),
        _ => run_baseline(&m),
    }
}

// --- kernel wait culprit ----------------------------------------------------

fn run_kernelwait(m: &HashMap<String, String>) {
    let burners = get_int(m, "burners", 1).clamp(0, 256) as usize;
    let waiters = get_int(m, "waiters", 32).clamp(1, 512) as usize;
    let hold_ms = get_int(m, "hold_ms", 5_000).clamp(100, 60_000) as u64;
    let pause_ms = get_int(m, "pause_ms", 25).clamp(0, 10_000) as u64;

    println!("uwait kernelwait burners={burners} waiters={waiters} hold_ms={hold_ms}");

    for i in 0..burners {
        thread::Builder::new()
            .name(format!("burn-{i}"))
            .spawn(move || burn(0x9E37_79B9_7F4A_7C15 ^ i as u64))
            .expect("spawn burner");
    }

    for i in 0..waiters {
        thread::Builder::new()
            .name(format!("kwait-{i}"))
            .stack_size(64 * 1024)
            .spawn(move || kernel_wait_loop(hold_ms, pause_ms))
            .expect("spawn kernel waiter");
    }

    loop {
        thread::sleep(Duration::from_secs(1));
    }
}

fn burn(seed: u64) {
    let mut x = seed | 1;
    let mut acc = 0u64;
    loop {
        for _ in 0..(1 << 16) {
            x ^= x << 13;
            x ^= x >> 7;
            x ^= x << 17;
            acc = acc.wrapping_add(x.wrapping_mul(x));
        }
        BURN_SINK.store(acc, Ordering::Relaxed);
    }
}

fn kernel_wait_loop(hold_ms: u64, pause_ms: u64) {
    loop {
        unsafe {
            vfork_sleep(hold_ms);
        }
        if pause_ms > 0 {
            thread::sleep(Duration::from_millis(pause_ms));
        }
    }
}

/// Block the calling thread in the kernel until the vfork child exits.
///
/// The child must not touch Rust runtime state after `vfork`, so it only issues
/// raw syscalls and then exits with `_exit`.
unsafe fn vfork_sleep(hold_ms: u64) {
    let ts = libc::timespec {
        tv_sec: (hold_ms / 1_000) as libc::time_t,
        tv_nsec: ((hold_ms % 1_000) * 1_000_000) as libc::c_long,
    };

    // This workload deliberately demonstrates the kernel wait created by
    // vfork. The child below must stay restricted to raw syscalls and _exit.
    #[allow(deprecated)]
    let pid = libc::vfork();
    if pid == 0 {
        let _ = libc::syscall(
            libc::SYS_nanosleep,
            &ts as *const libc::timespec,
            std::ptr::null_mut::<libc::timespec>(),
        );
        libc::_exit(0);
    }

    if pid > 0 {
        let mut status = 0;
        let _ = libc::waitpid(pid, &mut status, 0);
    } else {
        thread::sleep(Duration::from_millis(hold_ms.min(1_000)));
    }
}

// --- baseline (decoy) -------------------------------------------------------

struct Rng(u64);
impl Rng {
    fn next(&mut self) -> u64 {
        let mut x = self.0;
        x ^= x << 13;
        x ^= x >> 7;
        x ^= x << 17;
        self.0 = x;
        x
    }
}

fn run_baseline(m: &HashMap<String, String>) {
    let base_mb = get_int(m, "base_mb", 16).max(1) as usize;
    let scratch = get_str(m, "scratch", "");
    let blip = format!(
        "{}:{}",
        get_str(m, "blip_host", "127.0.0.1"),
        get_str(m, "blip_port", "9")
    );

    let mut buf = vec![1u8; base_mb * 1024 * 1024];
    for i in (0..buf.len()).step_by(PAGE_SIZE) {
        buf[i] = 1;
    }

    let mut rng = Rng(0xD00D_F00D_CAFE_BABE ^ std::process::id() as u64);
    let mut x = 1u64;
    let blob = vec![0u8; 8192];

    let udp = std::net::UdpSocket::bind("0.0.0.0:0").ok();
    if let Some(s) = &udp {
        let _ = s.connect(&blip);
    }

    let mut tick = 0u64;
    let mut disk_due = 10 + rng.next() % 20;
    let mut net_due = 7 + rng.next() % 15;

    loop {
        let n = 120_000 + rng.next() % 160_000;
        for _ in 0..n {
            x ^= x << 13;
            x ^= x >> 7;
            x ^= x << 17;
        }
        BASE_SINK.store(x, Ordering::Relaxed);
        buf[0] = x as u8;

        tick += 1;

        if tick >= disk_due && !scratch.is_empty() {
            if let Ok(mut f) = OpenOptions::new().create(true).write(true).open(&scratch) {
                let _ = f.write_all(&blob);
                let _ = f.sync_all();
            }
            if let Ok(mut f) = File::open(&scratch) {
                let mut sink = [0u8; 8192];
                let _ = f.read(&mut sink);
            }
            disk_due = tick + 10 + rng.next() % 20;
        }

        if tick >= net_due {
            if let Some(s) = &udp {
                let _ = s.send(&[0u8; 64]);
            }
            net_due = tick + 7 + rng.next() % 15;
        }

        thread::sleep(Duration::from_millis(150 + rng.next() % 150));
    }
}
