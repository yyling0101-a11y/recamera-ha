FROM ghcr.io/home-assistant/base:latest

RUN apk add --no-cache curl
COPY run.sh /run.sh
RUN chmod 755 /run.sh
LABEL io.hass.version="1.1.0" \
      io.hass.type="app" \
      io.hass.arch="aarch64|amd64"
CMD ["/run.sh"]
