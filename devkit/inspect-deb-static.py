#!/usr/bin/env python3
"""Inventory an untrusted DEB as data; never run scripts or create its symlinks."""
import argparse
import hashlib
import importlib.util
import io
import json
from pathlib import Path, PurePosixPath
import plistlib
import shutil
import struct
import tarfile


def macho(raw, depth=0):
    if depth > 1:
        raise ValueError('Nested fat Mach-O')
    if raw[:4] in (b'\xca\xfe\xba\xbe', b'\xca\xfe\xba\xbf', b'\xbe\xba\xfe\xca', b'\xbf\xba\xfe\xca'):
        endian = '>' if raw[0] == 0xca else '<'
        wide = raw[:4] in (b'\xca\xfe\xba\xbf', b'\xbf\xba\xfe\xca')
        count = struct.unpack_from(endian + 'I', raw, 4)[0]
        stride = 32 if wide else 20
        if count > 64 or 8 + count * stride > len(raw):
            raise ValueError('Invalid fat slice table')
        slices = []
        for index in range(count):
            values = struct.unpack_from(endian + ('IIQQII' if wide else '5I'), raw, 8 + index * stride)
            cpu, subtype, start, length, alignment = values[:5]
            if not length or start + length > len(raw):
                raise ValueError('Invalid fat slice bounds')
            slices.append({'cpu_type':cpu, 'cpu_subtype':subtype, 'offset':start, 'size':length,
                           'macho':macho(raw[start:start + length], depth + 1)})
        return {'fat':True, 'slices':slices}
    if raw[:4] not in (b'\xcf\xfa\xed\xfe', b'\xfe\xed\xfa\xcf'):
        return None
    endian = '<' if raw[:4] == b'\xcf\xfa\xed\xfe' else '>'
    _, cpu, subtype, kind, count, extent, flags, _ = struct.unpack_from(endian + '8I', raw)
    if count > 8192 or 32 + extent > len(raw):
        raise ValueError('Invalid Mach-O command table')
    result = {'cpu_type':cpu, 'cpu_subtype':subtype, 'file_type':kind, 'flags':flags,
              'dependencies':[], 'rpaths':[], 'segments':[], 'sections':[], 'commands':[]}
    offset = 32
    for _ in range(count):
        command, size = struct.unpack_from(endian + 'II', raw, offset)
        if size < 8 or offset + size > 32 + extent:
            raise ValueError('Invalid Mach-O command bounds')
        result['commands'].append({'command':command, 'file_offset':offset, 'size':size})
        if command in (0xc,0xd,0x80000018,0x8000001f,0x80000023,0x8000001c):
            start = struct.unpack_from(endian + 'I', raw, offset + 8)[0]
            if not 8 <= start < size:
                raise ValueError('Invalid Mach-O string offset')
            value = raw[offset + start:offset + size].split(b'\0')[0].decode('utf-8', errors='replace')
            if command == 0xd: result['install_name'] = value
            else: result['rpaths' if command == 0x8000001c else 'dependencies'].append(value)
        elif command == 0x19:
            fields = struct.unpack_from(endian + '16s4Q4I', raw, offset + 8)
            name, address, vm_size, file_offset, file_size, maxprot, initprot, sections, segflags = fields
            result['segments'].append({'name':name.rstrip(b'\0').decode(), 'address':address,
                'vm_size':vm_size, 'offset':file_offset, 'file_size':file_size})
            if 72 + sections * 80 > size:
                raise ValueError('Invalid section table')
            for index in range(sections):
                s = struct.unpack_from(endian + '16s16sQQ8I', raw, offset + 72 + index * 80)
                result['sections'].append({'name':s[0].rstrip(b'\0').decode(),
                    'segment':s[1].rstrip(b'\0').decode(), 'address':s[2], 'size':s[3],
                    'offset':s[4], 'flags':s[8], 'reserved1':s[9], 'reserved2':s[10]})
        elif command in (0x21,0x2c):
            crypt_offset, crypt_size, crypt_id = struct.unpack_from(endian + 'III', raw, offset + 8)
            result['encryption'] = {'offset':crypt_offset, 'size':crypt_size, 'crypt_id':crypt_id}
        elif command == 0x80000028:
            result['entry_file_offset'] = struct.unpack_from(endian + 'Q', raw, offset + 8)[0]
        elif command == 0x1d:
            start, length = struct.unpack_from(endian + 'II', raw, offset + 8)
            result['signature'] = {'offset':start, 'size':length}
            blob = raw[start:start + length]
            if len(blob) >= 12:
                magic, total, entries = struct.unpack_from('>III', blob)
                if magic == 0xfade0cc0 and total <= len(blob) and entries <= 64:
                    for index in range(entries):
                        slot, position = struct.unpack_from('>II', blob, 12 + index * 8)
                        if position + 8 > total: raise ValueError('Invalid signature slot')
                        _, span = struct.unpack_from('>II', blob, position)
                        if span < 8 or position + span > total: raise ValueError('Invalid signature blob')
                        if slot == 5:
                            result['entitlements'] = plistlib.loads(blob[position + 8:position + span])
        offset += size
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('package', type=Path)
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    spec = importlib.util.spec_from_file_location('deb_validator', Path(__file__).with_name('verify-package.py'))
    validator = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(validator)
    raw = args.package.read_bytes()
    members = validator.ar_members(raw)
    destination = args.output.resolve()
    destination.mkdir(parents=True, exist_ok=True)
    package_hash = hashlib.sha256(raw).hexdigest()
    existing = destination / 'package.deb'
    if existing.exists() and hashlib.sha256(existing.read_bytes()).hexdigest() != package_hash:
        raise ValueError('Output already contains a different package')
    shutil.copyfile(args.package, existing)
    manifest = {'input_name':args.package.name, 'sha256':package_hash, 'size':len(raw),
                'execution':'NONE', 'files':[], 'binaries':{}}
    for group in ('control', 'data'):
        archive_data = next(data for name, data in members.items() if name.startswith(group + '.tar'))
        base = destination / group
        base.mkdir(exist_ok=True)
        total = 0
        with tarfile.open(fileobj=io.BytesIO(archive_data), mode='r:*') as archive:
            for member in archive:
                name = member.name.removeprefix('./').rstrip('/')
                if not name or name == '.': continue
                parts = PurePosixPath(name).parts
                if member.name.startswith('/') or '..' in parts or any(':' in part or '\\' in part for part in parts):
                    raise ValueError('Unsafe archive member: ' + member.name)
                entry = {'archive':group, 'path':name, 'size':member.size,
                         'mode':oct(member.mode), 'type':member.type.decode('ascii'),
                         'link_target':member.linkname or None}
                if member.isfile():
                    total += member.size
                    if member.size > 128 * 1024 * 1024 or total > 512 * 1024 * 1024:
                        raise ValueError('Archive exceeds static analysis size limits')
                    content = archive.extractfile(member).read()
                    target = base.joinpath(*parts)
                    target.parent.mkdir(parents=True, exist_ok=True)
                    if target.is_symlink(): raise ValueError('Refusing existing symlink')
                    target.write_bytes(content)
                    entry['sha256'] = hashlib.sha256(content).hexdigest()
                    binary = macho(content)
                    if binary: manifest['binaries'][name] = binary
                elif not (member.isdir() or member.issym()):
                    raise ValueError('Unsupported archive member type')
                manifest['files'].append(entry)
    (destination / 'inventory.json').write_text(json.dumps(manifest, indent=2, ensure_ascii=False) + '\n', encoding='utf-8')
    print(json.dumps({'sha256':package_hash, 'bytes':len(raw), 'files':len(manifest['files']),
                      'binaries':list(manifest['binaries']), 'execution':'NONE'}, ensure_ascii=True))


if __name__ == '__main__':
    main()
