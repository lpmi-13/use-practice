import os
import threading
import time
import urllib.request

TARGETS = [t for t in os.environ.get("TARGETS", "").split(",") if t]
ENDPOINTS = ["/search", "/report", "/aggregate", "/export"]
RPS_PER_TARGET = int(os.environ.get("RPS_PER_TARGET", "40"))


def worker(target):
    interval = 1.0 / RPS_PER_TARGET
    i = 0
    while True:
        ep = ENDPOINTS[i % len(ENDPOINTS)]
        try:
            urllib.request.urlopen(f"http://{target}:8000{ep}", timeout=30).read()
        except Exception:
            time.sleep(0.5)
        i += 1
        time.sleep(interval)


def main():
    print(f"loadgen targets={TARGETS} rps_per_target={RPS_PER_TARGET}", flush=True)
    threads = [threading.Thread(target=worker, args=(t,), daemon=True) for t in TARGETS]
    for t in threads:
        t.start()
    for t in threads:
        t.join()


if __name__ == "__main__":
    main()
