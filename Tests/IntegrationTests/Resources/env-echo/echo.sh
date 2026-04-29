#!/bin/sh
# Per-connection handler invoked by socat via SYSTEM. Echoes $INJECTED_VAR
# as the HTTP response body.
printf 'HTTP/1.1 200 OK\r\nContent-Length: %d\r\nConnection: close\r\n\r\n%s' "${#INJECTED_VAR}" "$INJECTED_VAR"
