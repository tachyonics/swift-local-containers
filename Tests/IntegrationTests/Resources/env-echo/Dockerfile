# syntax=docker/dockerfile:1
#
# Tiny fixture used by EnvInjectionIntegrationTests. Listens on 8080 and
# echoes $INJECTED_VAR as the response body — proves an env var supplied by
# @DockerfileContainer(environment:) reaches the running container.
#
# Alpine + socat keeps the build small and fast (no Swift toolchain pull).
# socat with `fork` spawns a fresh handler per connection, so the
# `.port` wait strategy's TCP probe and the test's HTTP request can both
# complete reliably — busybox `nc -l` handles only one connection before
# exiting and was racy in CI between the wait and the test request.
#
# The per-connection HTTP response is built in echo.sh rather than inline
# in CMD: too many layers of quoting (Dockerfile JSON → sh -c → socat
# SYSTEM → handler shell) garble the printf format string when inlined.

FROM alpine:latest
RUN apk add --no-cache socat
COPY echo.sh /echo.sh
RUN chmod +x /echo.sh
EXPOSE 8080
CMD ["socat", "TCP-LISTEN:8080,fork,reuseaddr", "SYSTEM:/echo.sh"]
