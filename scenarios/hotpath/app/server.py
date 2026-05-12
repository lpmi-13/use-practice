import json
import os
import socket
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

ROLE = socket.gethostname()
CULPRIT = os.environ.get("CULPRIT", "")
HOT_ENDPOINT = os.environ.get("HOT_ENDPOINT", "")
HOT_SIZE = int(os.environ.get("HOT_SIZE", "600"))
IS_CULPRIT = ROLE == CULPRIT


def light_work():
    s = 0
    for i in range(500):
        s += i * i
    return s


def handle_search():
    if IS_CULPRIT and HOT_ENDPOINT == "search":
        total = 0
        for i in range(HOT_SIZE):
            for j in range(HOT_SIZE):
                total += (i * j) % 7
        return total
    return light_work()


def handle_report():
    if IS_CULPRIT and HOT_ENDPOINT == "report":
        total = 0
        for i in range(HOT_SIZE):
            for j in range(HOT_SIZE):
                total += (i * j) % 7
        return total
    return light_work()


def handle_aggregate():
    if IS_CULPRIT and HOT_ENDPOINT == "aggregate":
        total = 0
        for i in range(HOT_SIZE):
            for j in range(HOT_SIZE):
                total += (i * j) % 7
        return total
    return light_work()


def handle_export():
    if IS_CULPRIT and HOT_ENDPOINT == "export":
        total = 0
        for i in range(HOT_SIZE):
            for j in range(HOT_SIZE):
                total += (i * j) % 7
        return total
    return light_work()


ROUTES = {
    "/search": handle_search,
    "/report": handle_report,
    "/aggregate": handle_aggregate,
    "/export": handle_export,
}


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        fn = ROUTES.get(self.path)
        if fn is None:
            self.send_response(404)
            self.end_headers()
            return
        v = fn()
        body = json.dumps({"role": ROLE, "result": v}).encode()
        self.send_response(200)
        self.send_header("content-type", "application/json")
        self.send_header("content-length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *_a, **_kw):
        pass


if __name__ == "__main__":
    print(f"role={ROLE} culprit={IS_CULPRIT} hot_endpoint={HOT_ENDPOINT!r} hot_size={HOT_SIZE}", flush=True)
    ThreadingHTTPServer(("0.0.0.0", 8000), Handler).serve_forever()
