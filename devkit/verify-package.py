#!/usr/bin/env python3
"""Validate the real roothide DEB, including every Mach-O CodeDirectory hash.

Only the standard library is required. This checks ad-hoc signatures, not Apple
trust or on-device jailbreak compatibility. Never executes package contents.
"""
import argparse
import hashlib
import io
import json
import plistlib
from pathlib import Path, PurePosixPath
import re
import struct
import tarfile


def require(condition, message):
    if not condition:
        raise ValueError(message)


def ar_members(raw):
    require(raw.startswith(b'!<arch>\n'), 'Not a Debian ar archive')
    members = {}
    offset = 8
    while offset < len(raw):
        header = raw[offset:offset + 60]
        require(len(header) == 60 and header[58:] == b'`\n', 'Invalid ar header')
        name = header[:16].decode('ascii').strip().rstrip('/')
        size = int(header[48:58])
        offset += 60
        require(name not in members and offset + size <= len(raw), 'Duplicate/truncated ar member')
        members[name] = raw[offset:offset + size]
        offset += size + size % 2
    require(members.get('debian-binary') == b'2.0\n', 'Invalid debian-binary marker')
    require(len(members) == 3, 'Unexpected Debian archive members')
    return members


def tar_members(raw):
    files = {}
    with tarfile.open(fileobj=io.BytesIO(raw), mode='r:*') as archive:
        for member in archive:
            name = member.name.removeprefix('./').rstrip('/')
            if not name or name == '.':
                continue
            require(not member.name.startswith('/') and '..' not in PurePosixPath(name).parts,
                    f'Unsafe archive path: {member.name}')
            require(name not in files, f'Duplicate payload: {name}')
            require(member.isfile() or member.isdir() or member.issym(), f'Unexpected node: {name}')
            require(not (member.mode & 0o6000), f'Unexpected setuid/setgid: {name}')
            if member.issym():
                require(not member.linkname.startswith('/') and '..' not in PurePosixPath(member.linkname).parts,
                        f'Unsafe symlink: {name}')
            data = archive.extractfile(member).read() if member.isfile() else b''
            files[name] = (member, data)
    return files


def check_signature(binary, offset, size):
    require(offset >= 32 and size >= 12 and offset + size <= len(binary), 'Invalid signature range')
    blob = binary[offset:offset + size]
    magic, length, count = struct.unpack_from('>III', blob)
    require(magic == 0xfade0cc0 and length <= len(blob), 'Missing embedded signature superblob')
    blobs = {}
    for index in range(count):
        slot, start = struct.unpack_from('>II', blob, 12 + index * 8)
        _, extent = struct.unpack_from('>II', blob, start)
        require(extent >= 8 and start + extent <= length, 'Invalid signature blob bounds')
        blobs[slot] = blob[start:start + extent]
    directories = 0
    for slot, directory in blobs.items():
        if slot != 0 and not 0x1000 <= slot <= 0x1005:
            continue
        fields = struct.unpack_from('>9I4B', directory)
        magic, _, _, _, hash_offset, _, specials, slots, limit, hash_size, hash_type, _, page = fields
        require(magic == 0xfade0c02 and limit == offset, 'Invalid CodeDirectory coverage')
        require(page <= 30, 'Invalid signature page size')
        algorithm = {1: 'sha1', 2: 'sha256', 3: 'sha256', 4: 'sha384'}.get(hash_type)
        require(algorithm is not None, f'Unsupported signature hash {hash_type}')
        require(hash_size == ({1:20, 2:32, 3:20, 4:48}[hash_type]), 'Invalid hash size')
        chunk_size = (1 << page) if page else limit
        require(chunk_size > 0 and slots == (limit + chunk_size - 1) // chunk_size,
                'Invalid signature code-slot count')
        for index in range(slots):
            digest = hashlib.new(algorithm, binary[index * chunk_size:min((index + 1) * chunk_size, limit)]).digest()[:hash_size]
            stored = directory[hash_offset + index * hash_size:hash_offset + (index + 1) * hash_size]
            require(digest == stored, f'Mach-O code signature mismatch at page {index}')
        for special in range(1, specials + 1):
            start = hash_offset - special * hash_size
            stored = directory[start:start + hash_size]
            if special in blobs:
                digest = hashlib.new(algorithm, blobs[special]).digest()[:hash_size]
                require(digest == stored, f'Signature special slot {special} mismatch')
        directories += 1
    require(directories > 0, 'No CodeDirectory found')
    entitlements = blobs.get(5)
    return plistlib.loads(entitlements[8:]) if entitlements else {}


def check_macho(binary):
    # Device outputs must be thin arm64; fat/unexpected slices cannot silently pass.
    require(binary[:4] == b'\xcf\xfa\xed\xfe', 'Expected a thin 64-bit little-endian Mach-O')
    _, cpu, subtype, filetype, commands, command_bytes, _, _ = struct.unpack_from('<8I', binary)
    require(cpu == 0x0100000c and subtype & 0xffffff == 0, 'Expected arm64 (iPhone 6s/7), not arm64e-only')
    require(filetype in (2, 6, 8), 'Unexpected Mach-O file type')
    require(32 + command_bytes <= len(binary), 'Truncated Mach-O commands')
    offset = 32
    signature = None
    dependencies = []
    rpaths = []
    for _ in range(commands):
        command, size = struct.unpack_from('<II', binary, offset)
        require(size >= 8 and offset + size <= 32 + command_bytes, 'Invalid Mach-O command bounds')
        if command == 0x1d:
            signature = struct.unpack_from('<II', binary, offset + 8)
        if command in (0xc, 0x80000018, 0x8000001f, 0x80000023, 0x8000001c):
            start = struct.unpack_from('<I', binary, offset + 8)[0]
            require(start < size, 'Invalid Mach-O path offset')
            path = binary[offset + start:offset + size].split(b'\0')[0].decode()
            require(not any(p in path for p in ('/var/jb', '/Users/', '/home/', '.jbroot-')), f'Host/rootless path: {path}')
            (rpaths if command == 0x8000001c else dependencies).append(path)
        offset += size
    require(signature is not None, 'Unsigned Mach-O')
    return {'architecture': 'arm64', 'dependencies': dependencies, 'rpaths': rpaths,
            'entitlements': check_signature(binary, *signature)}


def validate(path):
    raw = Path(path).read_bytes()
    members = ar_members(raw)
    control_names = [name for name in members if name.startswith('control.tar')]
    data_names = [name for name in members if name.startswith('data.tar')]
    require(len(control_names) == len(data_names) == 1, 'Missing control/data tar')
    controls = tar_members(members[control_names[0]])
    payload = tar_members(members[data_names[0]])
    control = controls['control'][1].decode('utf-8')
    fields = dict(line.split(': ', 1) for line in control.splitlines() if ': ' in line and not line.startswith(' '))
    for name, expected in {'Package':'com.dk.viewphone', 'Version':'1.1.2', 'Architecture':'iphoneos-arm64e',
                           'Name':'ĐK ViewPhone', 'Conflicts':'com.82flex.trollvnc',
                           'Replaces':'com.82flex.trollvnc', 'Provides':'com.82flex.trollvnc'}.items():
        require(fields.get(name) == expected, f'Invalid {name}: {fields.get(name)}')
    require('firmware (>= 15.0)' in fields.get('Depends', ''), 'Missing iOS 15 dependency')
    for script in ('postinst', 'prerm'):
        info, content = controls[script]
        require(info.mode & 0o111 and content.startswith(b'#!/usr/bin/env bash\n'), f'Invalid script {script}')
        require(b'\r' not in content and b'/var/jb' not in re.sub(rb'#.*', b'', content), f'Invalid script path/line endings: {script}')
        expected = (Path(__file__).resolve().parents[1] / 'layout/DEBIAN' / script).read_bytes().replace(b'\r\n', b'\n')
        require(content == expected, f'Unexpected maintainer script content: {script}')
    daemon_name = 'Library/LaunchDaemons/com.82flex.trollvnc.plist'
    daemon = plistlib.loads(payload[daemon_name][1])
    require(daemon['Label'] == 'com.82flex.trollvnc', 'Daemon label mismatch')
    require(daemon['ProgramArguments'] == ['/usr/bin/dkviewphone-watchdog'], 'Daemon executable mismatch')
    require(daemon['StandardOutPath'] == daemon['StandardErrorPath'] == '/dev/null', 'Unbounded daemon output')
    require(daemon['UserName'] == 'mobile' and daemon['RunAtLoad'] and daemon['KeepAlive'], 'Daemon lifecycle changed')
    require(not any('PASSWORD' in key for key in daemon.get('EnvironmentVariables', {})), 'Bundled password in daemon')
    required = ['usr/bin/trollvncserver', 'Library/PreferenceBundles/TrollVNCPrefs.bundle/TrollVNCPrefs',
                'Library/ControlCenter/Bundles/CCTrollVNC.bundle/CCTrollVNC',
                'Library/PreferenceLoader/Preferences/TrollVNCPrefs/Root.plist',
                'usr/share/trollvnc/webclients/novnc/vnc.html', 'usr/share/doc/com.dk.viewphone/COPYING',
                'usr/share/trollvnc/webclients/index.vnc', 'usr/share/trollvnc/webclients/viewer.css',
                'usr/share/trollvnc/webclients/viewer.js', 'usr/share/trollvnc/webclients/viewer.bundle.js',
                'usr/share/doc/com.dk.viewphone/third-party/OpenSSL-LICENSE',
                'usr/share/doc/com.dk.viewphone/third-party/noVNC-MPL-2.0', 'usr/bin/dkviewphone-watchdog']
    for name in required:
        require(name in payload and payload[name][1], f'Missing required payload: {name}')
    binaries = {}
    for name, (info, content) in payload.items():
        parts = PurePosixPath(name).parts
        require(not any(p in ('.git','.tools','.theos','__pycache__','node_modules','.aws','.codex') for p in parts), f'Garbage/private directory: {name}')
        require(not any(p.startswith('._') or p in ('.DS_Store','.env','id_rsa','id_ed25519','Managed.plist') for p in parts), f'Garbage/private file: {name}')
        require(not name.endswith(('.pem','.key','.p12','.mobileprovision','.ipa','.tipa','.log','.a','.dSYM')), f'Unexpected sensitive/build file: {name}')
        require(not name.startswith('var/jb/'), 'Rootless payload in roothide package')
        if name.endswith('.plist'):
            plistlib.loads(content)
        if content[:4] in (b'\xcf\xfa\xed\xfe', b'\xca\xfe\xba\xbe', b'\xbe\xba\xfe\xca'):
            require(info.mode & 0o111, f'Non-executable Mach-O: {name}')
            binaries[name] = check_macho(content)
        require(b'-----BEGIN PRIVATE KEY-----' not in content and b'ghp_' not in content,
                f'Possible bundled secret: {name}')
    require(all(name in binaries for name in required[:3]), 'Missing required Mach-O binaries')
    require('usr/bin/dkviewphone-watchdog' in binaries, 'Missing watchdog Mach-O')
    watchdog_entitlements = plistlib.loads((Path(__file__).resolve().parents[1] / 'src/dkviewphone-watchdog.entitlements').read_bytes())
    require(binaries['usr/bin/dkviewphone-watchdog']['entitlements'] == watchdog_entitlements, 'Watchdog entitlements mismatch')
    for name in required[1:3]:
        bundle = str(PurePosixPath(name).parent)
        info = plistlib.loads(payload[bundle + '/Info.plist'][1])
        require(info['CFBundleExecutable'] == PurePosixPath(name).name, f'Bundle executable mismatch: {bundle}')
        require(info.get('CFBundleDisplayName') == 'ĐK ViewPhone', f'Bundle display name mismatch: {bundle}')
    root = plistlib.loads(payload['Library/PreferenceBundles/TrollVNCPrefs.bundle/Root.plist'][1])
    defaults = {item['key']:item.get('default') for item in root['items'] if 'key' in item}
    require(defaults.get('Enabled') is False and defaults.get('BindHost') == '127.0.0.1', 'Unsafe startup defaults')
    require(not defaults.get('FullPassword') and not defaults.get('ViewOnlyPassword'), 'Bundled password in Settings')
    require(defaults.get('AllowUnauthenticatedLAN') is False, 'Passwordless LAN must require explicit opt-in')
    require(defaults.get('LANWebViewerEnabled') is False and defaults.get('WebViewerTrustedLAN') is False,
            'Web access must default off and require consent for plaintext LAN')
    require(defaults.get('HttpPort') == 5801 and defaults.get('RemoteControlEnabled') is True,
            'Unexpected web defaults')
    web = 'usr/share/trollvnc/webclients/'
    source_root = Path(__file__).resolve().parents[1]
    assets = {}
    for name in ('index.vnc', 'viewer.css', 'viewer.js', 'viewer.bundle.js', 'novnc/core/rfb.js'):
        content = payload[web + name][1]
        require(content.replace(b'\r\n', b'\n') == (source_root / 'layout' / web / name).read_bytes().replace(b'\r\n', b'\n'),
                f'Packaged web asset differs from source: {name}')
        assets[name] = hashlib.sha256(content).hexdigest()
    entitlements_path = Path(__file__).resolve().parents[1] / 'app/TrollVNC/TrollVNC/TrollVNC.entitlements'
    expected_entitlements = plistlib.loads(entitlements_path.read_bytes())
    require(binaries[required[0]]['entitlements'] == expected_entitlements, 'Server entitlements differ from upstream source')
    return {'status':'passed', 'package': fields, 'sha256':hashlib.sha256(raw).hexdigest(),
            'payload_entries':len(payload), 'binaries':binaries, 'signature_check':'CodeDirectory code-page and embedded special-slot hashes',
            'web_assets':assets, 'runtime_tested':False, 'apple_trust_tested':False}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('package')
    parser.add_argument('--report')
    args = parser.parse_args()
    try:
        report = validate(args.package)
    except (ValueError, KeyError, IndexError, struct.error, tarfile.TarError) as error:
        report = {'status':'failed', 'error':str(error), 'runtime_tested':False}
    output = json.dumps(report, indent=2, ensure_ascii=False)
    if args.report:
        Path(args.report).write_text(output + '\n', encoding='utf-8')
    if report['status'] == 'passed':
        print(json.dumps({'status':report['status'], 'package':report['package']['Package'],
            'version':report['package']['Version'], 'package_architecture':report['package']['Architecture'],
            'sha256':report['sha256'], 'payload_entries':report['payload_entries'],
            'verified_binaries':list(report['binaries']), 'runtime_tested':False}, indent=2, ensure_ascii=False))
    else:
        print(output)
    return 0 if report['status'] == 'passed' else 1


if __name__ == '__main__':
    raise SystemExit(main())
