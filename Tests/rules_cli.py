import json
import pathlib
import subprocess
import tempfile
import unittest

BINARY = pathlib.Path(__file__).resolve().parent.parent / 'build/Chrome Profile Router.app/Contents/MacOS/ChromeProfileRouter'

class CLITests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.file = pathlib.Path(self.directory.name) / 'rules.json'
        self.file.write_text(json.dumps({'version': 1, 'rules': [
            {'id': 'specific', 'pattern': r'^https://router-test\.invalid/work(?:/|$)', 'profile': 'Default'},
            {'id': 'ask', 'pattern': r'^https://router-test\.invalid/', 'ask': True}
        ]}))

    def tearDown(self):
        self.directory.cleanup()

    def run_cli(self, *args, success=True):
        result = subprocess.run([str(BINARY), *args, '--rules-file', str(self.file)], capture_output=True, text=True, timeout=5)
        self.assertEqual(result.returncode, 0 if success else 1, result.stderr + result.stdout)
        return json.loads(result.stdout)

    def test_profiles(self):
        result = self.run_cli('--profiles')
        self.assertTrue(all(set(profile) == {'id', 'name'} for profile in result))

    def test_validate(self):
        self.assertEqual(self.run_cli('--validate-rules')['rules'], 2)

    def test_explain_match(self):
        result = self.run_cli('--explain', 'https://router-test.invalid/work/pr/123')
        self.assertEqual(result['rule'], 'specific')
        self.assertEqual(result['source'], 'custom')
        # Default may not exist on every developer's Mac; then the picker is correct.
        ids = [p['id'] for p in self.run_cli('--profiles')]
        self.assertEqual(result['action'], 'open' if 'Default' in ids else 'ask')

    def test_explain_ask(self):
        result = self.run_cli('--explain', 'https://router-test.invalid/other')
        self.assertEqual((result['rule'], result['action']), ('ask', 'ask'))

    def test_bad_config(self):
        self.file.write_text('{')
        self.assertFalse(self.run_cli('--validate-rules', success=False)['ok'])

    def test_missing_explicit_file(self):
        self.file.unlink()
        self.assertFalse(self.run_cli('--validate-rules', success=False)['ok'])

    def test_invalid_url(self):
        self.assertFalse(self.run_cli('--explain', 'javascript:alert(1)', success=False)['ok'])

    def test_no_url_echo(self):
        result = self.run_cli('--explain', 'https://router-test.invalid/work?secret=demo-sensitive-value')
        self.assertNotIn('demo-sensitive-value', json.dumps(result))

if __name__ == '__main__':
    unittest.main()
