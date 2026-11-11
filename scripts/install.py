import json
import pathlib
import shlex
import shutil
import subprocess

root = pathlib.Path(__file__).resolve().parent.parent
home = pathlib.Path.home()
destination = home / 'Applications/Chrome Profile Router.app'
destination.parent.mkdir(exist_ok=True)
if destination.exists():
    backup = root / 'build/Chrome Profile Router.previous.app'
    if backup.exists():
        shutil.rmtree(backup)
    shutil.move(str(destination), str(backup))
shutil.copytree(root / 'build/Chrome Profile Router.app', destination)
support = home / 'Library/Application Support/Chrome Profile Router'
support.mkdir(parents=True, exist_ok=True, mode=0o700)
extension = support / 'extension'
shutil.copytree(root / 'extension', extension, dirs_exist_ok=True)
wrapper = support / 'native-host'
executable = destination / 'Contents/MacOS/ChromeProfileRouter'
wrapper.write_text('#!/bin/sh\nexec ' + shlex.quote(str(executable)) + ' --native "$@"\n')
wrapper.chmod(0o700)
hosts = home / 'Library/Application Support/Google/Chrome/NativeMessagingHosts'
hosts.mkdir(parents=True, exist_ok=True)
manifest = {
    'name': 'local.colin.chrome_profile_router',
    'description': 'Chrome Profile Router local companion',
    'path': str(wrapper),
    'type': 'stdio',
    'allowed_origins': ['chrome-extension://' + (root / 'extension-id.txt').read_text().strip() + '/']
}
(hosts / 'local.colin.chrome_profile_router.json').write_text(json.dumps(manifest, indent=2) + '\n')
subprocess.run(['/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister', '-f', str(destination)], check=True)
print('Installed app:', destination)
print('Load unpacked extension from:', extension)
print('Open the app, click Set up, and select it as the default browser in System Settings.')
