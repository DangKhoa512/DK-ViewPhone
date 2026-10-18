# Attribution and source

ĐK ViewPhone 1.0.0 is a derivative of TrollVNC by 82Flex and contributors.
Upstream: https://github.com/owngoal-dev/TrollVNC
Audited baseline: cfdb737e72977d961eb7d0a8110d2fe1a58551d7
Derivative source: https://github.com/DangKhoa512/DK-ViewPhone/tree/dev/roothide

The project remains GPL version 2. COPYING is preserved without changes. Source
copyright notices and third-party attribution are retained. Modified files are
identified by the derivative Git history and docs/CHANGES.md.

LibVNCServer/LibVNCClient, OpenSSL, libjpeg-turbo, libpng, LZO, Cyrus SASL and zlib
archives in lib/ are inherited unchanged from the upstream commit. noVNC, pako,
font and sound resources remain under their respective upstream licenses and
credits. Rebranding does not change these licenses. The build artifact includes
the complete project source at its build commit. The upstream repository does
not document matching source revisions/build recipes for every bundled static
archive; their provenance and corresponding-source completeness require a
separate distribution audit before a public binary release. No claim of a
completed third-party license/source audit is made by the package validator.

This software is based in part on the work of the Independent JPEG Group.
This product includes software developed by the OpenSSL Project for use in the
OpenSSL Toolkit (https://www.openssl.org/). This product includes cryptographic
software written by Eric Young (eay@cryptsoft.com).

Known upstream header/archive version strings: LibVNCServer 0.9.15, OpenSSL
1.1.1l, libjpeg-turbo 3.1.3 (build 20251210), LZO 2.10, Cyrus SASL headers 2.1.28,
and libpng 1.8.0.git (exact source commit unspecified). Unmodified license texts
are bundled in `third-party/`; sources.json records URLs and SHA256. noVNC's
license texts are taken from v1.6.0; the inherited JS snapshot is not tagged by
upstream, so this is a license reference, not a proven exact source revision.
The existing pako MIT license and sound credits stay with the web resources.
LZO is covered by the bundled GPLv2 text and its original header notices.

`src/DKRFBTLS.mm` adapts the six entry points of
[LibVNCServer 0.9.15 rfbssl_openssl.c](https://github.com/LibVNC/libvncserver/blob/LibVNCServer-0.9.15/src/libvncserver/rfbssl_openssl.c),
Copyright 2011 Gernot Tenchio, GPL-2.0-or-later. It adds serialized SSL lifecycle
ownership and bounded nonblocking I/O; the original static archive is unchanged.

Build tools (Theos and ldid) are used to compile/sign; they are not bundled as
host executables in the iPhone package. Apple SDKs are downloaded by the workflow
and are not included in the DEB/source artifact.
