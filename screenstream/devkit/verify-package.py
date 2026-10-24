#!/usr/bin/env python3
"""Validate native ScreenStream packaging without executing package contents."""
import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import struct
import tarfile
from package_format import ar_members,tar_members,check_macho,require

ROOT=Path(__file__).resolve().parents[1]
def validate(filename):
    raw=Path(filename).read_bytes(); members=ar_members(raw)
    control=tar_members(next(value for key,value in members.items() if key.startswith('control.tar')))
    payload=tar_members(next(value for key,value in members.items() if key.startswith('data.tar')))
    fields=dict(line.split(': ',1) for line in control['control'][1].decode('utf-8').splitlines() if ': ' in line and not line.startswith(' '))
    for key,value in {'Package':'com.dk.screenstream','Version':'0.1.0','Architecture':'iphoneos-arm64e','Name':'ĐK ScreenStream'}.items():
        require(fields.get(key)==value,'Unexpected '+key)
    require('firmware (>= 15.0)' in fields.get('Depends','') and 'preferenceloader' in fields.get('Depends',''),'Missing platform dependencies')
    require(not fields.get('Pre-Depends') and not fields.get('Conflicts') and not fields.get('Replaces'),'Compatibility dependency or package collision')
    for script in ('postinst','prerm'):
        info,data=control[script]
        require(info.mode&0o111,'Maintainer script is not executable: '+script)
        require(data==(ROOT/'layout/DEBIAN'/script).read_bytes().replace(b'\r\n',b'\n'),'Unexpected maintainer script')
        require(b'/var/jb' not in data and b'com.dk.viewphone' not in data,'Cross-package or hardcoded root path')
    prefixes=('usr/bin/','usr/share/dk-screenstream/','usr/share/doc/com.dk.screenstream/',
        'Library/PreferenceBundles/DKScreenStreamPrefs.bundle/','Library/PreferenceLoader/Preferences/',
        'Library/LaunchDaemons/')
    expected_binaries={'usr/bin/dkss-server','usr/bin/dkss-supervisor',
        'Library/PreferenceBundles/DKScreenStreamPrefs.bundle/DKScreenStreamPrefs'}
    binaries={}
    for name,(info,data) in payload.items():
        if not info.isfile(): continue
        require(name.startswith(prefixes),'Unexpected payload file: '+name)
        require(not any(part in name.split('/') for part in ('.git','.tools','node_modules','__pycache__')),'Development artifact packaged')
        require(not any(value in name for value in ('FarmBIOS','farmbase','IosCtlTweak','trollvnc','ViewPhone')),'Cross-engine/proprietary payload')
        if data[:4] in (b'\xcf\xfa\xed\xfe',b'\xca\xfe\xba\xbe',b'\xbe\xba\xfe\xca'):
            require(name in expected_binaries and info.mode&0o111,'Unexpected or non-executable binary')
            binaries[name]=check_macho(data)
        if name.endswith('.plist'): plistlib.loads(data)
    require(set(binaries)==expected_binaries,'Missing native binary')
    for name,entitlements in [('usr/bin/dkss-server','worker.entitlements'),('usr/bin/dkss-supervisor','supervisor.entitlements')]:
        require(binaries[name]['entitlements']==plistlib.loads((ROOT/'Daemon'/entitlements).read_bytes()),'Entitlements mismatch: '+name)
    daemon_name='Library/LaunchDaemons/com.dk.screenstream.plist'
    daemon=plistlib.loads(payload[daemon_name][1])
    require(daemon['Label']=='com.dk.screenstream' and daemon['ProgramArguments']==['/usr/bin/dkss-supervisor'],'LaunchDaemon identity mismatch')
    require(daemon['UserName']==daemon['GroupName']=='mobile' and daemon['KeepAlive'] and daemon['RunAtLoad'],'Unexpected daemon lifecycle')
    require(daemon['ThrottleInterval']>=30 and daemon['StandardOutPath']==daemon['StandardErrorPath']=='/dev/null','Unbounded daemon recovery/logging')
    plist=plistlib.loads(payload['Library/PreferenceBundles/DKScreenStreamPrefs.bundle/Root.plist'][1])
    items={item['key']:item for item in plist['items'] if 'key' in item}
    require(items['Enabled']['default'] is False and items['BindHost']['default']=='auto','Unexpected startup defaults')
    require(items['Preset']['default']=='balanced' and 'Token' not in items,'Unexpected preset or bundled token')
    require(all(item.get('defaults')=='com.dk.screenstream' for item in items.values()),'Preference domain collision')
    for name in ('index.html','viewer.js','style.css'):
        actual=payload['usr/share/dk-screenstream/web/'+name][1].replace(b'\r\n',b'\n')
        require(actual==(ROOT/'Web'/name).read_bytes().replace(b'\r\n',b'\n'),'Web asset differs from source')
    for name in ('COPYING','ATTRIBUTION.md'):
        require(payload['usr/share/doc/com.dk.screenstream/'+name][1].replace(b'\r\n',b'\n')==
            (ROOT/name).read_bytes().replace(b'\r\n',b'\n'),'License/attribution missing or changed')
    return {'status':'passed','package':fields,'sha256':hashlib.sha256(raw).hexdigest(),
        'binaries':binaries,'payload_entries':len(payload),'runtime_tested':False}

def main():
    parser=argparse.ArgumentParser(description=__doc__); parser.add_argument('package'); parser.add_argument('--report')
    args=parser.parse_args()
    try: result=validate(args.package)
    except (ValueError,KeyError,IndexError,StopIteration,struct.error,tarfile.TarError) as error:
        result={'status':'failed','error':str(error),'runtime_tested':False}
    if args.report: Path(args.report).write_text(json.dumps(result,indent=2,ensure_ascii=False)+'\n',encoding='utf-8')
    print(json.dumps({key:result[key] for key in ('status','sha256','payload_entries','error','runtime_tested') if key in result},indent=2))
    return 0 if result['status']=='passed' else 1
if __name__=='__main__': raise SystemExit(main())
