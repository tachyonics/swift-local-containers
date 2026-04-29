# syntax=docker/dockerfile:1
#
# Tiny fixture used by EnvInjectionIntegrationTests. Listens on 8080 and
# echoes $INJECTED_VAR as the response body — proves an env var supplied by
# @DockerfileContainer(environment:) reaches the running container.
#
# Alpine + busybox nc keeps the build to a ~3MB image and a few seconds
# (vs the Swift toolchain pull a real fixture would need). The explicit
# `Connection: close` tells AsyncHTTPClient to expect connection close
# rather than keep-alive — busybox nc closes after one response.

FROM alpine:latest
EXPOSE 8080
CMD ["sh", "-c", "while true; do printf 'HTTP/1.1 200 OK\\r\\nContent-Length: %d\\r\\nConnection: close\\r\\n\\r\\n%s' ${#INJECTED_VAR} \"$INJECTED_VAR\" | nc -l -p 8080; done"]
