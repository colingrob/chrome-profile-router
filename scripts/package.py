"""Package local app metadata and generate deterministic local vector-based icons."""
import base64
import hashlib
import json
import pathlib
import plistlib
import subprocess
import sys
import tempfile

root = pathlib.Path(__file__).resolve().parent.parent
app = pathlib.Path(sys.argv[1])
manifest_path = root / 'extension/manifest.json'
manifest = json.loads(manifest_path.read_text())
if 'key' not in manifest:
    # The public key fixes the unpacked extension ID across profiles and install paths.
    # No private signing key is needed or retained for an unpacked extension.
    with tempfile.TemporaryDirectory() as tmp:
        private = pathlib.Path(tmp) / 'key.pem'
        subprocess.run(['openssl', 'genrsa', '-out', str(private), '2048'], check=True, capture_output=True)
        public = subprocess.check_output(['openssl', 'rsa', '-in', str(private), '-pubout', '-outform', 'DER'], stderr=subprocess.DEVNULL)
    manifest['key'] = base64.b64encode(public).decode()
    manifest_path.write_text(json.dumps(manifest, indent=2) + '\n')
public = base64.b64decode(manifest['key'])
extension_id = ''.join(chr(ord('a') + int(n, 16)) for n in hashlib.sha256(public).hexdigest()[:32])
(root / 'extension-id.txt').write_text(extension_id + '\n')
plist = {
    'CFBundleName': 'Chrome Profile Router',
    'CFBundleDisplayName': 'Chrome Profile Router',
    'CFBundleIdentifier': 'local.colin.chrome-profile-router',
    'CFBundleExecutable': 'ChromeProfileRouter',
    'CFBundlePackageType': 'APPL',
    'CFBundleShortVersionString': '1.1.0',
    'CFBundleVersion': '2',
    'LSMinimumSystemVersion': '13.0',
    'LSUIElement': True,
    'NSHighResolutionCapable': True,
    'CFBundleIconFile': 'AppIcon',
    'CFBundleDocumentTypes': [
        {'CFBundleTypeName': 'HTML document', 'CFBundleTypeRole': 'Viewer', 'LSHandlerRank': 'Alternate', 'LSItemContentTypes': ['public.html', 'public.xhtml']}
    ],
    'CFBundleURLTypes': [
        {'CFBundleURLName': 'Web links', 'CFBundleTypeRole': 'Viewer', 'CFBundleURLSchemes': ['http', 'https']},
        {'CFBundleURLName': 'Profile picker', 'CFBundleTypeRole': 'Viewer', 'CFBundleURLSchemes': ['chromeroute']}
    ],
    'NSPrincipalClass': 'NSApplication',
}
(app / 'Contents/Info.plist').write_bytes(plistlib.dumps(plist))
subprocess.run(['xcrun', 'swift', str(root / 'scripts/icons.swift'), str(root / 'extension'), str(app / 'Contents/Resources')], check=True)
print('Extension ID:', extension_id)
