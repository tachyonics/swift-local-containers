#!/bin/sh
# Per-connection handler invoked by socat via SYSTEM. Echoes $INJECTED_VAR
# as the HTTP response body.
#
# Drain the request headers before responding. Without this, the handler
# may write its response and exit while AsyncHTTPClient is still sending
# request bytes — socat closes the socket, the client sees the close
# mid-write and throws HTTPClientError.remoteConnectionClosed. Reading
# until the blank-line end-of-headers marker ensures the client has
# finished writing before we hang up. POSIX-portable: `read` strips the
# trailing LF but keeps the CR, so a blank HTTP header line ("\r\n")
# arrives here as just "\r" — which we detect by parameter-expansion
# stripping CR against a captured literal.
CR=$(printf '\r')
while IFS= read -r line; do
    case "${line%${CR}}" in
        "") break ;;
    esac
done
printf 'HTTP/1.1 200 OK\r\nContent-Length: %d\r\nConnection: close\r\n\r\n%s' "${#INJECTED_VAR}" "$INJECTED_VAR"
