from pathlib import Path
import json,subprocess,shutil,tempfile,hashlib,plistlib
root=Path(__file__).resolve().parents[1]
helper=root/'dist/LSwitcher.app/Contents/MacOS/LSwitcherUpdater'
with tempfile.TemporaryDirectory(prefix='lswitcher-updater-check-') as name:
 base=Path(name).resolve(); target=base/'LSwitcher.app';work=base/'work';work.mkdir()
 # A disposable previous-version fixture; never change /Applications.
 shutil.copytree(root/'dist/LSwitcher.app',target)
 info=target/'Contents/Info.plist'
 metadata=plistlib.loads(info.read_bytes());metadata['CFBundleShortVersionString']='0.0.0'
 info.write_bytes(plistlib.dumps(metadata))
 subprocess.run(['codesign','--force','--sign','-',str(target)],check=True)
 package=json.loads((root/'dist/update.json').read_text())
 shutil.copy2(root/'dist/update.json',work/'update.json')
 archive=work/package['filename'];shutil.copy2(root/'dist'/package['filename'],archive)
 before=hashlib.sha256((target/'Contents/MacOS/LSwitcher').read_bytes()).hexdigest()
 original=archive.read_bytes();archive.write_bytes(original[:-1]+bytes([original[-1]^1]))
 alias=str(work).replace('/private/var/', '/var/', 1)
 command=[str(helper),str(target),alias,'999999','--test-no-launch']
 assert subprocess.run(command).returncode!=0,'Tampered archive accepted'
 assert hashlib.sha256((target/'Contents/MacOS/LSwitcher').read_bytes()).hexdigest()==before
 archive.write_bytes(original)
 for field,value in [('version','999.0.0'),('architecture','invalid'),('signature','invalid')]:
  invalid=dict(package);invalid[field]=value
  (work/'update.json').write_text(json.dumps(invalid))
  assert subprocess.run(command).returncode!=0,'Tampered manifest accepted'
  assert hashlib.sha256((target/'Contents/MacOS/LSwitcher').read_bytes()).hexdigest()==before
 (work/'update.json').write_text(json.dumps(package))
 assert subprocess.run(command).returncode==0,'Signed update failed'
 assert (work/'Previous-LSwitcher.app').exists(),'Previous version missing'
 assert (target/'Contents/MacOS/LSwitcher').read_bytes()==(root/'dist/LSwitcher.app/Contents/MacOS/LSwitcher').read_bytes()
 assert subprocess.run(command).returncode!=0,'Same version reinstalled'
 print('Updater integration: tampered payload rejected without changing target; signed upgrade installed; previous version retained; same-version reinstall rejected.')
