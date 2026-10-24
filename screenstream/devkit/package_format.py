# GPL-2.0-only. Reused from DK ViewPhone devkit/verify-package.py.
# Original archive and Mach-O CodeDirectory verification, retained unchanged.
import hashlib
import io
from pathlib import PurePosixPath
import plistlib
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
