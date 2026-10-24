# Source and licenses

DK ScreenStream is an independent GPL-2.0-only project. See COPYING.

CoreAnimation/IOSurface capture API usage is informed by the existing GPLv2
TrollVNC engine (82Flex and contributors, audited upstream commit
cfdb737e72977d961eb7d0a8110d2fe1a58551d7). Its engine is preserved in DK ViewPhone.
ScreenStream implements its own resource lifecycle, scaler, JPEG encoder and
transport. Network address/recovery policy code is reused from DK ViewPhone
under GPL-2.0-only, retaining source notices.

Apple SDK frameworks are platform dependencies, not copied into the package.
`Capture/IOSurfaceSPI.h` is the existing project's Apple BSD interface header
(Copyright 2015 Apple Inc.). Its full notice and disclaimer are retained in the
header, which is also installed in the package documentation.
Private API declarations describe system interfaces and require a compatible
jailbreak; binary compatibility must be tested on the target device.

FarmBIOS was inspected statically as technical reference. No FarmBIOS binary,
implementation, asset, pairing secret or license component is included here.
The independent DKSS protocol is not a FarmBIOS compatibility protocol.
