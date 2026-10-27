#!/usr/bin/env python3
"""Exercise packaging in disposable projects with fake Apple services (no uploads)."""
import hashlib
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
import tempfile
import zipfile

SOURCE = Path(__file__).resolve().parents[1]
DRIVER = r'''#!PYTHON
import hashlib,json,os,sys,zipfile,shutil
from pathlib import Path
name=Path(sys.argv[0]).name;a=sys.argv[1:]
with open(os.environ['RELEASE_COMMAND_LOG'],'a') as log: log.write(name+' '+ ' '.join(a)+'\n')
if name=='security': print('1) '+ 'A'*40 +' "Developer ID Application: Fixture"')
elif name=='swift':
 if a[0]=='build':
  if '--show-bin-path' in a: print(os.environ['FAKE_PRODUCTS'])
 else:
  archive=Path(a[-1]);data=archive.read_bytes()
  (archive.parent/'update.json').write_text(json.dumps(dict(version=a[-3],architecture=a[-2],filename=archive.name,bytes=len(data),sha256=hashlib.sha256(data).hexdigest(),signature='fixture')))
elif name=='ditto':
 if '-k' in a:
  source=Path(a[-2]);destination=Path(a[-1])
  with zipfile.ZipFile(destination,'w') as z:
   for f in source.rglob('*'):
    if f.is_file(): z.write(f,str(Path(source.name)/f.relative_to(source)))
 else: shutil.copytree(a[-2],a[-1],dirs_exist_ok=True)
elif name=='rsync': shutil.copytree(a[-2].rstrip('/'),a[-1],dirs_exist_ok=True)
elif name=='hdiutil':
 if a[0]=='create': Path(a[-1]).write_bytes(b'DMG fixture')
elif name=='xcrun':
 if a[0]=='--find': print('/fixture/'+a[1])
 elif a[0]=='notarytool':
  print(json.dumps({'status':'Invalid' if os.environ.get('REJECT_NOTARY') else 'Accepted','id':'fixture-job'}))
 elif a[0]=='stapler':
  p=Path(a[-1]);ticket=p/'Contents/FixtureTicket' if p.suffix=='.app' else p.with_suffix('.ticket')
  if a[1]=='staple': ticket.write_text('fixture ticket')
  elif a[1]=='validate': assert ticket.exists()
'''


def fixture(base):
    (base/'scripts').mkdir()
    for name in ['build-dmg.sh','release-preflight.sh','sign-update.swift','check-size.py']:
        shutil.copy2(SOURCE/'scripts'/name,base/'scripts'/name)
    (base/'Resources').mkdir()
    (base/'Resources/Info.plist').write_bytes(plistlib.dumps({'CFBundleShortVersionString':'1.0.0'}))
    (base/'Resources/AppIcon.icns').write_bytes(b'icon')
    products=base/'products';products.mkdir()
    for name in ['LSwitcher','LSwitcherUpdater']: (products/name).write_bytes(b'executable fixture')
    bundle=products/'LSwitcher_LSwitcherCore.bundle';bundle.mkdir();(bundle/'lexicon').write_bytes(b'fixture')
    commands=base/'bin';commands.mkdir()
    for name in ['swift','strip','codesign','ditto','rsync','hdiutil','xcrun','spctl','security']:
        p=commands/name;p.write_text(DRIVER.replace('PYTHON',sys.executable,1));p.chmod(0o755)
    env=dict(os.environ)
    for key in ['SIGN_IDENTITY','NOTARY_PROFILE','REQUIRE_NOTARIZATION','WITH_UPDATE','UPDATE_SIGNING_KEY','UNIVERSAL','REGENERATE_ICONS']:
        env.pop(key,None)
    env.update(PATH=str(commands)+':'+env['PATH'],FAKE_PRODUCTS=str(products),RELEASE_COMMAND_LOG=str(base/'commands.log'))
    return env


with tempfile.TemporaryDirectory(prefix='lswitcher-release-checks-') as directory:
    base=Path(directory)
    # Validate prerequisites before a build or Apple submission can start.
    early=base/'early';early.mkdir();env=fixture(early)
    for values,expected in [({'REQUIRE_NOTARIZATION':'1'},'SIGN_IDENTITY'),
                            ({'REQUIRE_NOTARIZATION':'1','SIGN_IDENTITY':'Developer ID Application: Fixture'},'NOTARY_PROFILE'),
                            ({'SIGN_IDENTITY':'Apple Development: Wrong'},'No matching')]:
        result=subprocess.run(['bash','scripts/build-dmg.sh','--preflight-only'],cwd=early,env=dict(env,**values),capture_output=True,text=True)
        assert result.returncode!=0 and expected in result.stderr,(expected,result.stderr)
    for mode in ['adhoc','trusted','rejected']:
        project=base/mode;project.mkdir();env=fixture(project)
        if mode!='adhoc':
            key=project/'fixture.key';key.write_bytes(bytes(32))
            env.update(SIGN_IDENTITY='Developer ID Application: Fixture',NOTARY_PROFILE='fixture',REQUIRE_NOTARIZATION='1',WITH_UPDATE='1',UPDATE_SIGNING_KEY=str(key))
        if mode=='rejected': env['REJECT_NOTARY']='1'
        result=subprocess.run(['bash','scripts/build-dmg.sh'],cwd=project,env=env,capture_output=True,text=True)
        if mode=='rejected':
            assert result.returncode!=0 and not (project/'dist/update.json').exists(),result.stderr
            continue
        assert result.returncode==0,result.stdout+result.stderr
        if mode=='trusted':
            manifest=json.loads((project/'dist/update.json').read_text());archive=project/'dist'/manifest['filename']
            with zipfile.ZipFile(archive) as z: assert 'LSwitcher.app/Contents/FixtureTicket' in z.namelist()
            assert manifest['sha256']==hashlib.sha256(archive.read_bytes()).hexdigest()
            assert manifest['bytes']==archive.stat().st_size
            log=(project/'commands.log').read_text()
            assert log.index('stapler staple') < log.index('swift scripts/sign-update.swift')
            assert log.count('stapler validate')==2 and log.count('spctl --assess')==2
print('Release workflow fixtures passed: preflight failures, ad-hoc build, stapled final update ZIP and rejection before publication (Apple services mocked).')
