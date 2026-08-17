#!/bin/sh
set -eu

SOURCE_DIR="${1:-$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)}"
INSTALL_DIR="${INSTALL_DIR:-/usr/lib/linkview-topology}"
CGI_DIR="${CGI_DIR:-/www/cgi-bin}"
DATA_DIR="${DATA_DIR:-/var/lib/linkview}"

command -v lua >/dev/null
lua -e 'require("lsqlite3")'

mkdir -p "$INSTALL_DIR" "$CGI_DIR" "$DATA_DIR"
cp -R "$SOURCE_DIR/src" "$SOURCE_DIR/bin" "$SOURCE_DIR/config.lua" \
      "$SOURCE_DIR/schema.sql" "$INSTALL_DIR/"
chmod 0755 "$INSTALL_DIR/bin/topology-cli.lua" "$INSTALL_DIR/src/api.lua"
ln -sf "$INSTALL_DIR/src/api.lua" "$CGI_DIR/topology"
TOPOLOGY_HOME="$INSTALL_DIR" "$INSTALL_DIR/bin/topology-cli.lua" init

echo "installed: $INSTALL_DIR"
echo "API: /cgi-bin/topology?action=metadata"
