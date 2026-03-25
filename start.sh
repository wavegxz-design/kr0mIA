#!/bin/bash
set -e
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
R='\033[0;31m'; G='\033[0;32m'; N='\033[0m'; B='\033[1m'

for dep in curl jq openssl; do
  command -v "$dep" &>/dev/null || { echo -e "${R}Falta: $dep${N}"; exit 1; }
done

exec "$DIR/kr0m.sh" "$@"
