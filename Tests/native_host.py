import json
import pathlib
import struct
import subprocess
import unittest

ROOT = pathlib.Path(__file__).resolve().parent.parent
BINARY = ROOT / 'build/Chrome Profile Router.app/Contents/MacOS/ChromeProfileRouter'

def exchange(body):
    process = subprocess.run([str(BINARY), '--native'], input=body, capture_output=True, timeout=5)
    assert process.returncode == 0, process.stderr.decode()
    if not process.stdout:
        return None
    size, = struct.unpack('<I', process.stdout[:4])
    assert len(process.stdout) == size + 4
    return json.loads(process.stdout[4:])

def request(value):
    body = json.dumps(value).encode()
    return exchange(struct.pack('<I', len(body)) + body)

class NativeTests(unittest.TestCase):
    def test_ping(self):
        self.assertEqual(request({'action': 'ping'}), {'ok': True, 'version': '1.0.0'})
    def test_unsupported_action(self):
        self.assertFalse(request({'action': 'execute', 'command': 'anything'})['ok'])
    def test_unsupported_url(self):
        self.assertFalse(request({'action': 'choose', 'url': 'javascript:alert(1)'})['ok'])
    def test_missing_url(self):
        self.assertFalse(request({'action': 'choose'})['ok'])
    def test_non_object(self):
        self.assertFalse(request(['not', 'a', 'message'])['ok'])
    def test_truncated_message(self):
        self.assertFalse(exchange(struct.pack('<I', 12) + b'{}')['ok'])
    def test_oversized_message(self):
        self.assertFalse(exchange(struct.pack('<I', 524289))['ok'])
    def test_invalid_json(self):
        self.assertFalse(exchange(struct.pack('<I', 3) + b'bad')['ok'])
    def test_empty_input(self):
        self.assertIsNone(exchange(b''))

if __name__ == '__main__':
    unittest.main()
