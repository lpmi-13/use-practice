//! updisk is the generic Rust workload used by the disk scenario. Every service
//! in that scenario runs this same binary; a config file picks its behavior:
//!
//!   * `mode=disk`     — keep `iodepth` direct (`O_DIRECT`) random I/O ops in
//!                       flight via io_uring, producing the classic disk
//!                       bottleneck signal (`%util` ~100%, `aqu-sz` > 1, rising
//!                       `await`). This is the culprit.
//!   * `mode=baseline` — a low-activity heartbeat (small resident set, sub-1%
//!                       CPU, occasional tiny buffered I/O). These are the
//!                       decoys the culprit hides among.

use std::collections::HashMap;
use std::fs::{File, OpenOptions};
use std::io::{Read, Write};
use std::os::unix::fs::OpenOptionsExt;
use std::os::unix::io::AsRawFd;
use std::path::{Path, PathBuf};
use std::time::Duration;

use io_uring::{opcode, types, IoUring};

const ALIGN: usize = 4096;

fn cfg_path() -> PathBuf {
    if let Ok(p) = std::env::var("UP_CFG") {
        if !p.is_empty() {
            return PathBuf::from(p);
        }
    }
    let exe = std::env::current_exe().expect("current_exe");
    let dir = exe.parent().expect("exe dir").to_path_buf();
    let name = exe.file_name().expect("exe name").to_string_lossy().to_string();
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
        "disk" => run_disk(&m),
        _ => run_baseline(&m),
    }
}

/// Minimal xorshift PRNG, enough to scatter offsets without pulling in a crate.
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

// --- baseline (decoy) -------------------------------------------------------

/// A low-activity service that touches all four resources at a tiny, jittered
/// rate: a held resident set (memory), a sub-1% CPU tick, occasional small
/// buffered disk I/O, and occasional tiny UDP traffic. Each decoy seeds its own
/// rhythm from its PID so the fleet doesn't blip in lockstep, like a real host.
fn run_baseline(m: &HashMap<String, String>) {
    let base_mb = get_int(m, "base_mb", 16).max(1) as usize;
    let scratch = get_str(m, "scratch", "");
    let blip = format!(
        "{}:{}",
        get_str(m, "blip_host", "127.0.0.1"),
        get_str(m, "blip_port", "9")
    );

    // Held resident set.
    let mut buf = vec![1u8; base_mb * 1024 * 1024];

    let mut rng = Rng(0xDEAD_BEEF_CAFE_F00D ^ std::process::id() as u64);
    let mut x: u64 = 1;
    let blob = vec![0u8; 8192];

    // Pre-connected UDP socket for the tiny network blips.
    let udp = std::net::UdpSocket::bind("0.0.0.0:0").ok();
    if let Some(s) = &udp {
        let _ = s.connect(&blip);
    }

    // Cadences measured in ~200 ms ticks, randomized per service.
    let mut tick: u64 = 0;
    let mut disk_due = 10 + rng.next() % 20; // ~2-6 s
    let mut net_due = 7 + rng.next() % 15; // ~1.5-4.5 s

    loop {
        // Sub-1% CPU tick, slightly varied so it isn't a flat line.
        let n = 120_000 + rng.next() % 160_000;
        for _ in 0..n {
            x ^= x << 13;
            x ^= x >> 7;
            x ^= x << 17;
        }
        buf[0] = x as u8; // keep the buffer (and compiler) honest

        tick += 1;

        // Tiny buffered disk blip.
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

        // Tiny network blip.
        if tick >= net_due {
            if let Some(s) = &udp {
                let _ = s.send(&[0u8; 64]);
            }
            net_due = tick + 7 + rng.next() % 15;
        }

        std::thread::sleep(Duration::from_millis(150 + rng.next() % 150));
    }
}

// --- disk (culprit) ---------------------------------------------------------

fn alloc_aligned(size: usize) -> *mut u8 {
    unsafe {
        let mut ptr: *mut libc::c_void = std::ptr::null_mut();
        if libc::posix_memalign(&mut ptr, ALIGN, size) != 0 {
            panic!("posix_memalign failed");
        }
        libc::memset(ptr, 0, size);
        ptr as *mut u8
    }
}

/// Fill the scratch file with real data so reads hit the device rather than
/// being served as zeros from sparse holes.
fn prefill(path: &Path, size: u64) -> std::io::Result<()> {
    let mut f = File::create(path)?;
    let chunk = vec![0u8; 1 << 20];
    let mut written = 0u64;
    while written < size {
        let n = std::cmp::min(chunk.len() as u64, size - written) as usize;
        f.write_all(&chunk[..n])?;
        written += n as u64;
    }
    f.sync_all()
}

fn open_target(path: &Path) -> (File, bool) {
    match OpenOptions::new()
        .read(true)
        .write(true)
        .custom_flags(libc::O_DIRECT)
        .open(path)
    {
        Ok(f) => (f, true),
        // tmpfs and some overlay configs reject O_DIRECT; fall back to buffered
        // so the workload still runs (with a weaker signal) instead of dying.
        Err(_) => (
            OpenOptions::new()
                .read(true)
                .write(true)
                .open(path)
                .expect("open scratch file"),
            false,
        ),
    }
}

fn run_disk(m: &HashMap<String, String>) {
    let file = get_str(m, "file", "/tmp/use-practice.bin");
    let size = (get_int(m, "size_mb", 256).max(1) as u64) * 1024 * 1024;
    let bs = (get_int(m, "bs_k", 64).max(4) as usize) * 1024;
    let iodepth = get_int(m, "iodepth", 16).clamp(1, 256) as usize;
    let rw = get_str(m, "rw", "randwrite");
    let path = PathBuf::from(&file);

    prefill(&path, size).expect("prefill scratch file");

    let (f, direct) = open_target(&path);
    println!("updisk rw={rw} bs={bs} iodepth={iodepth} direct={direct}");
    let fd = types::Fd(f.as_raw_fd());

    let nblocks = size / bs as u64;
    let bufs: Vec<*mut u8> = (0..iodepth).map(|_| alloc_aligned(bs)).collect();

    let mut ring = IoUring::new(iodepth as u32).expect("io_uring init");
    let mut rng = Rng(0x9E37_79B9_7F4A_7C15 ^ std::process::id() as u64);

    let build_op = |slot: usize, rng: &mut Rng| -> io_uring::squeue::Entry {
        let off = (rng.next() % nblocks) * bs as u64;
        let is_write = match rw.as_str() {
            "randread" => false,
            "randrw" => slot % 2 == 0,
            _ => true,
        };
        if is_write {
            opcode::Write::new(fd, bufs[slot], bs as u32)
                .offset(off)
                .build()
                .user_data(slot as u64)
        } else {
            opcode::Read::new(fd, bufs[slot], bs as u32)
                .offset(off)
                .build()
                .user_data(slot as u64)
        }
    };

    // Prime the ring with a full set of in-flight operations.
    for slot in 0..iodepth {
        let e = build_op(slot, &mut rng);
        unsafe {
            ring.submission().push(&e).expect("prime sq push");
        }
    }
    ring.submit().expect("initial submit");

    loop {
        ring.submit_and_wait(1).expect("submit_and_wait");

        let mut done: Vec<usize> = Vec::new();
        {
            let cq = ring.completion();
            for cqe in cq {
                done.push(cqe.user_data() as usize);
            }
        }

        for slot in done {
            let e = build_op(slot, &mut rng);
            unsafe {
                if ring.submission().push(&e).is_err() {
                    ring.submit().ok();
                    let _ = ring.submission().push(&e);
                }
            }
        }
        ring.submit().expect("resubmit");
    }
}
