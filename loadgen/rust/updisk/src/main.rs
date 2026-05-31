//! updisk drives direct, random block I/O against a bounded scratch file using
//! io_uring. It keeps `iodepth` operations in flight at all times, which is
//! what produces the classic disk-bottleneck signal: device `%util` near 100%,
//! `aqu-sz` above 1, and rising `await` in `iostat -xz 1`.

use std::collections::HashMap;
use std::fs::{File, OpenOptions};
use std::io::Write;
use std::os::unix::fs::OpenOptionsExt;
use std::os::unix::io::AsRawFd;
use std::path::{Path, PathBuf};

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

fn main() {
    let m = load_cfg();
    let file = m.get("file").cloned().unwrap_or_else(|| "/tmp/use-practice.bin".into());
    let size = (get_int(&m, "size_mb", 256).max(1) as u64) * 1024 * 1024;
    let bs = (get_int(&m, "bs_k", 64).max(4) as usize) * 1024;
    let iodepth = get_int(&m, "iodepth", 16).clamp(1, 256) as usize;
    let rw = m.get("rw").cloned().unwrap_or_else(|| "randwrite".into());
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
