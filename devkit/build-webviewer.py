#!/usr/bin/env python3
"""Build an offline noVNC bundle. Node is used only on the build host."""
from pathlib import Path
import os
import re
import subprocess

root = Path(__file__).resolve().parents[1]
web = root / 'layout/usr/share/trollvnc/webclients'
subprocess.run(['npm.cmd' if os.name == 'nt' else 'npm', 'exec', '--yes',
                '--package=esbuild@0.25.12', '--', 'esbuild', str(web / 'viewer.js'),
                '--bundle', '--format=iife', '--target=chrome100,edge100', '--minify',
                '--legal-comments=inline', '--outfile=' + str(web / 'viewer.bundle.js')], check=True, cwd=root)
html = (root / 'devkit/webviewer-index.html').read_text(encoding='utf-8')
theme = '<style id="dk-theme">' + (web / 'viewer.css').read_text(encoding='utf-8') + '</style>'
html = re.sub(r'<style id="dk-theme">.*?</style>|<link rel="stylesheet" href="viewer.css">', lambda _: theme, html, flags=re.S)
html = html.replace('type="module" src="viewer.js"', 'defer src="viewer.bundle.js"')
assert len(html.encode()) < 32768, 'LibVNCServer template substitution uses a 32 KiB buffer'
(web / 'index.vnc').write_text(html, encoding='utf-8')
