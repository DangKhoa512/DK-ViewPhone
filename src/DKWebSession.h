#pragma once
#include <rfb/rfb.h>
#include <cstdlib>

// LibVNCServer 0.9.15 parses this path during webSocketsCheck, before
// newClientHook. DK ViewPhone does not route VNC sessions by request path.
// Dispose it before client threads start: rfbCloseClient can run from both
// input and output threads and frees wspath without clearing it, even while
// the socket is awaiting asynchronous shutdown. Keeping NULL makes those
// repeated engine closes safe for both WS and WSS without replacing the engine.
inline void DKReleaseWebSocketRequestPath(rfbClientPtr client) {
    std::free(client->wspath);
    client->wspath = nullptr;
}
