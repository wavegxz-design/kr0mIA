#!/bin/bash
set -e
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
G='\033[0;32m'; N='\033[0m'

# Crear wrapper global
cat > /usr/local/bin/kr0m << EOF
#!/bin/bash
exec "$DIR/kr0m.sh" "\$@"
EOF
chmod +x /usr/local/bin/kr0m

echo -e "${G}[✓] kr0m instalado globalmente. Usa: kr0m \"pregunta\"${N}"
