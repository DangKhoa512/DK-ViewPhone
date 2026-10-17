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

Build tools (Theos and ldid) are used to compile/sign; they are not bundled as
host executables in the iPhone package. Apple SDKs are downloaded by the workflow
and are not included in the DEB/source artifact.
