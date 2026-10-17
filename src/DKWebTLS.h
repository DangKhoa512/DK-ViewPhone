// GPL-2.0-only. HTTPS for packaged static assets; RFB/WSS stays in LibVNCServer.
#pragma once
bool DKWebTLSStart(const char *bind, int port, const char *root,
                   const char *certificate, const char *key, int vncPort);
void DKWebTLSStop(void);
