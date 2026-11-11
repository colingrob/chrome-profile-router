from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from html import escape

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        body = ('<!doctype html><title>Router test</title><style>body{font:18px system-ui;padding:40px}code{overflow-wrap:anywhere}</style>'
                '<h1>Profile routing test</h1><p>This is a local test page.</p><code>' + escape(self.path) + '</code>').encode()
        self.send_response(200)
        self.send_header('Content-Type', 'text/html; charset=utf-8')
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)
    def log_message(self, *_):
        pass

ThreadingHTTPServer(('127.0.0.1', 18764), Handler).serve_forever()
