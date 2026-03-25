#!/bin/bash
# ================================================================
#  Kr0m v1.0.1 — by Krypthane  [BUGFIX RELEASE]
#  Multi-model AI CLI · Privacy-first · Red Team Edition
#  15 bugs críticos corregidos
# ================================================================
set -euo pipefail

R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'
C='\033[0;36m'; B='\033[1m'; N='\033[0m'
log()  { echo -e "${G}[✓]${N} $1"; }
info() { echo -e "${C}[…]${N} $1"; }
warn() { echo -e "${Y}[!]${N} $1"; }
err()  { echo -e "${R}[✗]${N} $1"; exit 1; }

clear
echo -e "${R}${B}"
cat << 'BANNER'
    ██╗  ██╗██████╗  ██████╗ ███╗   ███╗
    ██║ ██╔╝██╔══██╗██╔═████╗████╗ ████║
    █████╔╝ ██████╔╝██║██╔██║██╔████╔██║
    ██╔═██╗ ██╔══██╗████╔╝██║██║╚██╔╝██║
    ██║  ██╗██║  ██║╚██████╔╝██║ ╚═╝ ██║
    ╚═╝  ╚═╝╚═╝  ╚═╝ ╚═════╝ ╚═╝     ╚═╝
         by Krypthane · v1.0.1 [BUGFIX]
BANNER
echo -e "${N}"

[[ "$(uname -s)" != "Linux" ]] && err "Kr0m requiere Linux."

# ── Dependencias ──────────────────────────────────────────
info "Verificando dependencias..."
MISSING=()
for dep in curl jq openssl; do
  command -v "$dep" &>/dev/null || MISSING+=("$dep")
done
if [[ ${#MISSING[@]} -gt 0 ]]; then
  warn "Instalando: ${MISSING[*]}"
  sudo apt-get install -y "${MISSING[@]}" -qq || err "No se pudieron instalar."
fi
command -v torsocks &>/dev/null || \
  sudo apt-get install -y torsocks tor -qq 2>/dev/null || \
  warn "torsocks no disponible — Tor desactivado"
command -v batcat &>/dev/null || command -v bat &>/dev/null || \
  sudo apt-get install -y bat -qq 2>/dev/null || true
log "Dependencias OK"

# ── Estructura ────────────────────────────────────────────
info "Creando estructura..."
PROJECT="kr0m"
mkdir -p "$PROJECT"
cd "$PROJECT"
mkdir -p vault prompts/{ctf,osint,dev,study,custom} history logs .kr0m
chmod 700 vault .kr0m history logs
log "Estructura OK"

# ================================================================
# kr0m.sh — CLI principal v1.0.1
# ================================================================
info "Generando kr0m.sh..."
cat > kr0m.sh << 'MAINEOF'
#!/bin/bash
# ================================================================
#  Kr0m v1.0.1 — Multi-model AI CLI · by Krypthane · MIT
#  BUGFIX: 15 bugs críticos corregidos
# ================================================================
set -euo pipefail

# ── Paths ─────────────────────────────────────────────────
readonly KR0M_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly VAULT_DIR="$KR0M_DIR/vault"
readonly PROMPTS_DIR="$KR0M_DIR/prompts"
readonly HISTORY_DIR="$KR0M_DIR/history"
readonly LOGS_DIR="$KR0M_DIR/logs"
readonly CFG_DIR="$KR0M_DIR/.kr0m"
readonly ENV_FILE="$KR0M_DIR/.env"
readonly VAULT_FILE="$VAULT_DIR/kr0m.vault"
readonly SALT_FILE="$VAULT_DIR/.salt"
readonly SETTINGS_FILE="$CFG_DIR/settings.json"

# ── Colores ───────────────────────────────────────────────
R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'
C='\033[0;36m'; M='\033[0;35m'; B='\033[1m'; N='\033[0m'
DIM='\033[2m'

# ================================================================
# FIX #1: CURL_CMD como ARRAY (no string)
# Antes: CURL_CMD="torsocks curl" → falla al expandir
# Ahora: CURL_CMD=(curl) → se expande correctamente
# ================================================================
CURL_CMD=(curl)

# ================================================================
# FIX #2: Detección correcta de bat en Kali
# En Kali bat se llama batcat
# ================================================================
BAT_CMD=""
command -v batcat &>/dev/null && BAT_CMD="batcat"
command -v bat    &>/dev/null && [[ -z "$BAT_CMD" ]] && BAT_CMD="bat"

# ── Banner ────────────────────────────────────────────────
banner() {
  echo -e "${R}${B}"
  cat << 'EOF'
    ██╗  ██╗██████╗  ██████╗ ███╗   ███╗
    ██║ ██╔╝██╔══██╗██╔═████╗████╗ ████║
    █████╔╝ ██████╔╝██║██╔██║██╔████╔██║
    ██╔═██╗ ██╔══██╗████╔╝██║██║╚██╔╝██║
    ██║  ██╗██║  ██║╚██████╔╝██║ ╚═╝ ██║
    ╚═╝  ╚═╝╚═╝  ╚═╝ ╚═════╝ ╚═╝     ╚═╝
         by Krypthane · v1.0.1
EOF
  echo -e "${N}"
}

# ================================================================
# SETTINGS
# ================================================================
load_settings() {
  mkdir -p "$CFG_DIR"
  chmod 700 "$CFG_DIR"
  if [[ ! -f "$SETTINGS_FILE" ]]; then
    cat > "$SETTINGS_FILE" << 'DEFAULTS'
{
  "vault_method": "password",
  "tor_enabled": false,
  "auto_clear_history": false,
  "stealth_mode": false,
  "syntax_highlight": true,
  "show_timer": true,
  "default_model": "deepseek",
  "default_prompt": "default",
  "max_tokens": 4096,
  "temperature": "0.7",
  "history_limit": 20,
  "save_responses": false,
  "response_dir": ""
}
DEFAULTS
    chmod 600 "$SETTINGS_FILE"
  fi
}

# ================================================================
# FIX #11: get_setting usa tostring para manejar bool/num/string
# FIX #11: set_setting detecta tipo automáticamente
# ================================================================
get_setting() {
  local key="$1" default="${2:-}"
  jq -r --arg k "$key" --arg d "$default" \
    'if .[$k] != null then (.[$k] | tostring) else $d end' \
    "$SETTINGS_FILE" 2>/dev/null || echo "$default"
}

set_setting() {
  local key="$1" val="$2"
  local tmp; tmp=$(mktemp)
  if [[ "$val" == "true" || "$val" == "false" ]]; then
    jq --arg k "$key" --argjson v "$val" '.[$k] = $v' "$SETTINGS_FILE" > "$tmp"
  elif [[ "$val" =~ ^[0-9]+$ ]]; then
    jq --arg k "$key" --argjson v "$val" '.[$k] = $v' "$SETTINGS_FILE" > "$tmp"
  else
    # strings y floats como "0.7"
    jq --arg k "$key" --arg v "$val" '.[$k] = $v' "$SETTINGS_FILE" > "$tmp"
  fi
  mv "$tmp" "$SETTINGS_FILE"
  chmod 600 "$SETTINGS_FILE"
}

toggle_setting() {
  local key="$1"
  local cur; cur=$(get_setting "$key" "false")
  if [[ "$cur" == "true" ]]; then
    set_setting "$key" false; echo "false"
  else
    set_setting "$key" true; echo "true"
  fi
}

# ================================================================
# VAULT — AES-256-CBC
# FIX #12: GCM → CBC para compatibilidad openssl 1.1.x y 3.x
# FIX #8:  sin xxd, usa awk sobre hex de openssl dgst
# FIX #14: vault_init y vault_unlock separados (sin doble llamada)
# ================================================================
VAULT_KEY=""

vault_derive_key() {
  local password="$1"
  if [[ ! -f "$SALT_FILE" ]]; then
    openssl rand -hex 32 > "$SALT_FILE"
    chmod 600 "$SALT_FILE"
  fi
  local salt; salt=$(cat "$SALT_FILE")
  # FIX #8: openssl dgst retorna "SHA2-256(stdin)= HASH", tomamos el hash
  VAULT_KEY=$(printf '%s%s' "$password" "$salt" | \
    openssl dgst -sha256 -hmac "$salt" 2>/dev/null | \
    awk '{print $NF}')
}

vault_derive_key_uid() {
  local mid=""
  [[ -f /etc/machine-id ]] && mid=$(cat /etc/machine-id)
  local uid_salt="${UID}$(hostname)${mid}"
  VAULT_KEY=$(printf '%s' "$uid_salt" | \
    openssl dgst -sha256 2>/dev/null | awk '{print $NF}')
}

vault_derive_key_keyfile() {
  local password="$1" keyfile="$2"
  [[ ! -f "$keyfile" ]] && \
    echo -e "${R}Keyfile no encontrado: $keyfile${N}" && exit 1
  local kfhash; kfhash=$(openssl dgst -sha256 < "$keyfile" 2>/dev/null | awk '{print $NF}')
  VAULT_KEY=$(printf '%s%s' "$password" "$kfhash" | \
    openssl dgst -sha256 2>/dev/null | awk '{print $NF}')
}

# FIX #14: vault_unlock solo deriva la key, no crea vault
vault_unlock() {
  local method; method=$(get_setting "vault_method" "password")
  case "$method" in
    password)
      echo -ne "${C}[vault]${N} Master password: "
      read -rs pw; echo ""
      vault_derive_key "$pw"
      ;;
    password+keyfile)
      local kf; kf=$(get_setting "keyfile_path" "$CFG_DIR/kr0m.key")
      echo -ne "${C}[vault]${N} Master password: "
      read -rs pw; echo ""
      vault_derive_key_keyfile "$pw" "$kf"
      ;;
    uid)
      vault_derive_key_uid
      ;;
    password+totp)
      echo -ne "${C}[vault]${N} Master password: "
      read -rs pw; echo ""
      vault_derive_key "$pw"
      echo -ne "${C}[vault]${N} TOTP code: "
      read -r totp
      if command -v oathtool &>/dev/null; then
        local secret; secret=$(get_setting "totp_secret" "")
        local expected; expected=$(oathtool --totp "$secret" 2>/dev/null || echo "")
        [[ "$totp" != "$expected" ]] && \
          echo -e "${R}TOTP inválido${N}" && exit 1
      else
        echo -e "${Y}oathtool no disponible — TOTP no verificado${N}"
      fi
      ;;
    *)
      echo -ne "${C}[vault]${N} Master password: "
      read -rs pw; echo ""
      vault_derive_key "$pw"
      ;;
  esac
}

# FIX #12: AES-256-CBC (compatible universalmente)
vault_encrypt() {
  local plaintext="$1" outfile="$2"
  [[ -z "$VAULT_KEY" ]] && vault_unlock
  printf '%s' "$plaintext" | \
    openssl enc -aes-256-cbc -pbkdf2 -iter 310000 \
      -pass "pass:${VAULT_KEY}" -base64 -A > "$outfile" 2>/dev/null
  chmod 600 "$outfile"
}

vault_decrypt() {
  local infile="$1"
  [[ ! -f "$infile" ]] && return 1
  [[ -z "$VAULT_KEY" ]] && vault_unlock
  openssl enc -d -aes-256-cbc -pbkdf2 -iter 310000 \
    -pass "pass:${VAULT_KEY}" -base64 -A \
    < "$infile" 2>/dev/null || {
    echo -e "${R}[vault] Contraseña incorrecta o vault corrupto.${N}" >&2
    exit 1
  }
}

# FIX #14: vault_init separa creación de unlock
vault_init() {
  if [[ -f "$VAULT_FILE" ]]; then
    [[ -z "$VAULT_KEY" ]] && vault_unlock
    return 0
  fi

  echo -e "${Y}[vault] Primera configuración...${N}\n"
  echo "  Método de desbloqueo:"
  echo "  1) Password"
  echo "  2) Password + Keyfile"
  echo "  3) Auto (UID del sistema)"
  echo "  4) Password + TOTP"
  echo ""
  echo -ne "Elige [1-4, default=1]: "
  read -r choice

  case "${choice:-1}" in
    2)
      set_setting "vault_method" "password+keyfile"
      local kf="$CFG_DIR/kr0m.key"
      openssl rand -base64 64 > "$kf"
      chmod 600 "$kf"
      set_setting "keyfile_path" "$kf"
      echo -e "${G}Keyfile: $kf${N}"
      echo -e "${Y}¡BACKUP ESTE ARCHIVO! Sin él no puedes abrir el vault.${N}"
      ;;
    3) set_setting "vault_method" "uid" ;;
    4)
      set_setting "vault_method" "password+totp"
      local secret; secret=$(openssl rand -base64 15 | tr -d '=+/' | head -c 16)
      set_setting "totp_secret" "$secret"
      echo -e "${G}TOTP Secret (guárdalo): $secret${N}"
      ;;
    *) set_setting "vault_method" "password" ;;
  esac

  vault_unlock
  vault_encrypt '{"keys":{}}' "$VAULT_FILE"
  echo -e "${G}[vault] Inicializado correctamente.${N}\n"
}

vault_read_key() {
  vault_decrypt "$VAULT_FILE" 2>/dev/null | \
    jq -r --arg k "$1" '.keys[$k] // empty' 2>/dev/null || echo ""
}

vault_write_key() {
  local key="$1" val="$2"
  local content; content=$(vault_decrypt "$VAULT_FILE")
  local updated; updated=$(echo "$content" | \
    jq --arg k "$key" --arg v "$val" '.keys[$k] = $v')
  vault_encrypt "$updated" "$VAULT_FILE"
}

# ================================================================
# API KEYS
# FIX #9, #10: declaradas globales, cargadas DESPUÉS de vault_init
# FIX #15: export_keys() para subshells de dispatch_multi
# ================================================================
declare -g OPENAI_API_KEY=""
declare -g DEEPSEEK_API_KEY=""
declare -g GEMINI_API_KEY=""
declare -g MISTRAL_API_KEY=""
declare -g ANTHROPIC_API_KEY=""
declare -g GROQ_API_KEY=""
declare -g TOGETHER_API_KEY=""

load_keys() {
  # Fallback .env plano
  [[ -f "$ENV_FILE" ]] && source "$ENV_FILE" 2>/dev/null || true

  # Vault tiene prioridad
  if [[ -f "$VAULT_FILE" && -n "$VAULT_KEY" ]]; then
    local vdata; vdata=$(vault_decrypt "$VAULT_FILE" 2>/dev/null) || return 0
    local v
    v=$(echo "$vdata" | jq -r '.keys.OPENAI_API_KEY    // empty' 2>/dev/null)
    [[ -n "$v" ]] && OPENAI_API_KEY="$v"
    v=$(echo "$vdata" | jq -r '.keys.DEEPSEEK_API_KEY  // empty' 2>/dev/null)
    [[ -n "$v" ]] && DEEPSEEK_API_KEY="$v"
    v=$(echo "$vdata" | jq -r '.keys.GEMINI_API_KEY    // empty' 2>/dev/null)
    [[ -n "$v" ]] && GEMINI_API_KEY="$v"
    v=$(echo "$vdata" | jq -r '.keys.MISTRAL_API_KEY   // empty' 2>/dev/null)
    [[ -n "$v" ]] && MISTRAL_API_KEY="$v"
    v=$(echo "$vdata" | jq -r '.keys.ANTHROPIC_API_KEY // empty' 2>/dev/null)
    [[ -n "$v" ]] && ANTHROPIC_API_KEY="$v"
    v=$(echo "$vdata" | jq -r '.keys.GROQ_API_KEY      // empty' 2>/dev/null)
    [[ -n "$v" ]] && GROQ_API_KEY="$v"
    v=$(echo "$vdata" | jq -r '.keys.TOGETHER_API_KEY  // empty' 2>/dev/null)
    [[ -n "$v" ]] && TOGETHER_API_KEY="$v"
  fi
}

# FIX #15: exportar para subshells
export_keys() {
  export OPENAI_API_KEY DEEPSEEK_API_KEY GEMINI_API_KEY \
         MISTRAL_API_KEY ANTHROPIC_API_KEY GROQ_API_KEY TOGETHER_API_KEY
}

# ================================================================
# MODELOS
# ================================================================
declare -A MODEL_IDS=(
  [openai]="gpt-4o-mini"
  [openai-large]="gpt-4o"
  [deepseek]="deepseek-chat"
  [deepseek-r1]="deepseek-reasoner"
  [gemini]="gemini-2.0-flash"
  [gemini-pro]="gemini-1.5-pro"
  [mistral]="mistral-large-latest"
  [mistral-small]="mistral-small-latest"
  [anthropic]="claude-haiku-4-5-20251001"
  [anthropic-sonnet]="claude-sonnet-4-6"
  [groq]="llama-3.3-70b-versatile"
  [groq-fast]="llama-3.1-8b-instant"
  [together]="mistralai/Mixtral-8x7B-Instruct-v0.1"
)

declare -A MODEL_BASES=(
  [openai]="https://api.openai.com/v1/chat/completions"
  [openai-large]="https://api.openai.com/v1/chat/completions"
  [deepseek]="https://api.deepseek.com/chat/completions"
  [deepseek-r1]="https://api.deepseek.com/chat/completions"
  [mistral]="https://api.mistral.ai/v1/chat/completions"
  [mistral-small]="https://api.mistral.ai/v1/chat/completions"
  [groq]="https://api.groq.com/openai/v1/chat/completions"
  [groq-fast]="https://api.groq.com/openai/v1/chat/completions"
  [together]="https://api.together.xyz/v1/chat/completions"
)

declare -A MODEL_LABELS=(
  [openai]="OpenAI GPT-4o-mini"
  [openai-large]="OpenAI GPT-4o"
  [deepseek]="DeepSeek V3"
  [deepseek-r1]="DeepSeek R1 (reasoning)"
  [gemini]="Google Gemini 2.0 Flash"
  [gemini-pro]="Google Gemini 1.5 Pro"
  [mistral]="Mistral Large"
  [mistral-small]="Mistral Small"
  [anthropic]="Claude Haiku"
  [anthropic-sonnet]="Claude Sonnet"
  [groq]="Groq Llama3.3 70B [FREE]"
  [groq-fast]="Groq Llama3.1 8B [FAST/FREE]"
  [together]="Together Mixtral 8x7B"
)

# FIX #10: get_model_key usa vars globales ya cargadas
get_model_key() {
  case "$1" in
    openai|openai-large)        echo "$OPENAI_API_KEY" ;;
    deepseek|deepseek-r1)       echo "$DEEPSEEK_API_KEY" ;;
    gemini|gemini-pro)          echo "$GEMINI_API_KEY" ;;
    mistral|mistral-small)      echo "$MISTRAL_API_KEY" ;;
    anthropic|anthropic-sonnet) echo "$ANTHROPIC_API_KEY" ;;
    groq|groq-fast)             echo "$GROQ_API_KEY" ;;
    together)                   echo "$TOGETHER_API_KEY" ;;
    *)                          echo "" ;;
  esac
}

# ================================================================
# TOR — FIX #1: CURL_CMD como array
# ================================================================
setup_tor() {
  local enabled; enabled=$(get_setting "tor_enabled" "false")
  [[ "$enabled" != "true" ]] && return 0

  if ! command -v torsocks &>/dev/null; then
    echo -e "${Y}[tor] torsocks no instalado — desactivando${N}"
    set_setting tor_enabled false
    return 0
  fi

  if ! pgrep -x tor &>/dev/null; then
    sudo systemctl start tor 2>/dev/null || \
      (tor --quiet &>/dev/null & sleep 2)
  fi

  # FIX #1: array correcto
  CURL_CMD=(torsocks curl)
  echo -e "${G}[tor] Routing activo ✓${N}"
}

verify_tor() {
  echo -ne "${C}[tor] IP pública:${N} "
  "${CURL_CMD[@]}" -s --max-time 10 https://api.ipify.org 2>/dev/null \
    || echo "error (¿Tor activo?)"
  echo ""
}

# ================================================================
# PROMPTS
# FIX #6: load_prompt verifica SYSTEM_PROMPT_OVERRIDE correctamente
# FIX #13: STEALTH_MODE/RAW_MODE inicializados antes de uso
# ================================================================
STEALTH_MODE=false
RAW_MODE=false
SYSTEM_PROMPT_OVERRIDE=""

load_prompt() {
  local name="$1"
  # FIX #6: prioridad correcta — override primero
  if [[ -n "$SYSTEM_PROMPT_OVERRIDE" ]]; then
    echo "$SYSTEM_PROMPT_OVERRIDE"
    return
  fi
  $RAW_MODE && echo "" && return
  $STEALTH_MODE && echo "You are a helpful assistant." && return

  # Buscar en módulos
  for dir in "$PROMPTS_DIR"/*/; do
    [[ -d "$dir" ]] || continue
    local pfile="$dir${name}.txt"
    [[ -f "$pfile" ]] && cat "$pfile" && return
  done
  # Raíz de prompts
  [[ -f "$PROMPTS_DIR/${name}.txt" ]] && cat "$PROMPTS_DIR/${name}.txt" && return
  # Default
  echo "You are a helpful, precise and direct assistant. No unnecessary disclaimers."
}

# ================================================================
# SYNTAX HIGHLIGHT
# ================================================================
print_response() {
  local content="$1"
  local hl; hl=$(get_setting "syntax_highlight" "true")

  if [[ "$hl" == "true" && -n "$BAT_CMD" ]]; then
    echo "$content" | "$BAT_CMD" \
      --language=markdown --style=plain --color=always 2>/dev/null \
      || echo "$content"
  else
    local in_block=0
    while IFS= read -r line; do
      if [[ "$line" =~ ^\`\`\` ]]; then
        if [[ $in_block -eq 0 ]]; then
          printf "${C}%s${N}\n" "$line"; in_block=1
        else
          printf "${C}%s${N}\n" "$line"; in_block=0
        fi
      elif [[ $in_block -eq 1 ]]; then
        printf "${DIM}%s${N}\n" "$line"
      else
        printf '%s\n' "$line"
      fi
    done <<< "$content"
  fi
}

# ================================================================
# STATS
# ================================================================
record_stats() {
  local model="$1" tokens="${2:-0}"
  { $STEALTH_MODE; } && return
  [[ "$(get_setting stealth_mode false)" == "true" ]] && return
  mkdir -p "$LOGS_DIR"
  local sf="$LOGS_DIR/stats.json"
  local cur; cur=$(cat "$sf" 2>/dev/null || \
    echo '{"requests":0,"total_tokens":0,"by_model":{}}')
  echo "$cur" | jq \
    --arg m "$model" --argjson t "$tokens" \
    '.requests += 1 | .total_tokens += $t |
     .by_model[$m].requests = ((.by_model[$m].requests // 0) + 1) |
     .by_model[$m].tokens   = ((.by_model[$m].tokens   // 0) + $t)' \
    > "${sf}.tmp" && mv "${sf}.tmp" "$sf"
}

# ================================================================
# HISTORIAL
# ================================================================
SESSION_ID=""

get_hfile() { echo "$HISTORY_DIR/s_${SESSION_ID:-default}.json"; }

load_history() {
  [[ "$(get_setting auto_clear_history false)" == "true" ]] && echo "[]" && return
  $STEALTH_MODE && echo "[]" && return
  local hf; hf=$(get_hfile)
  [[ -f "$hf" ]] && cat "$hf" || echo "[]"
}

save_history() {
  $STEALTH_MODE && return
  [[ "$(get_setting auto_clear_history false)" == "true" ]] && return
  local lim; lim=$(get_setting "history_limit" "20")
  local hf; hf=$(get_hfile)
  mkdir -p "$HISTORY_DIR"; chmod 700 "$HISTORY_DIR"
  echo "$1" | jq --argjson l "$lim" \
    'if length > $l then .[-($l):] else . end' > "$hf"
  chmod 600 "$hf"
}

build_messages() {
  local history="$1" user_msg="$2"
  if [[ "$history" == "[]" || -z "$SESSION_ID" ]]; then
    jq -n --arg m "$user_msg" '[{"role":"user","content":$m}]'
  else
    echo "$history" | jq --arg m "$user_msg" \
      '. + [{"role":"user","content":$m}]'
  fi
}

# ================================================================
# HTTP — FIX #1: CURL_CMD es array, "${CURL_CMD[@]}" correcto
# ================================================================
CURL_OPTS=(
  --silent --show-error
  --http2 --compressed
  --connect-timeout 15
  --max-time 120
  --retry 2 --retry-delay 2
)

do_curl() {
  "${CURL_CMD[@]}" "${CURL_OPTS[@]}" "$@"
}

req_openai_compat() {
  local url="$1" key="$2" model_id="$3" system="$4" messages="$5"
  local max_t temp
  max_t=$(get_setting "max_tokens" "4096")
  temp=$(get_setting "temperature" "0.7")

  local body
  body=$(jq -n \
    --arg   model  "$model_id" \
    --arg   sys    "$system"   \
    --argjson msgs  "$messages" \
    --argjson max_t "$max_t"   \
    --arg   temp   "$temp"     \
    '{model:$model,
      messages:([{"role":"system","content":$sys}] + $msgs),
      max_tokens:$max_t,
      temperature:($temp|tonumber)}')

  do_curl -X POST "$url" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $key" \
    -d "$body"
}

req_gemini() {
  local key="$1" model_id="$2" system="$3" messages="$4"
  local max_t temp
  max_t=$(get_setting "max_tokens" "4096")
  temp=$(get_setting "temperature" "0.7")

  local contents
  contents=$(echo "$messages" | jq '[.[] | {
    role:(if .role=="assistant" then "model" else .role end),
    parts:[{"text":.content}]
  }]')

  local body
  body=$(jq -n \
    --arg    sys  "$system"   \
    --argjson c   "$contents" \
    --argjson mt  "$max_t"    \
    --arg    temp "$temp"     \
    '{system_instruction:{parts:[{text:$sys}]},
      contents:$c,
      generationConfig:{maxOutputTokens:$mt,temperature:($temp|tonumber)}}')

  local url="https://generativelanguage.googleapis.com/v1beta/models/${model_id}:generateContent?key=${key}"
  do_curl -X POST "$url" -H "Content-Type: application/json" -d "$body"
}

req_anthropic() {
  local key="$1" model_id="$2" system="$3" messages="$4"
  local max_t; max_t=$(get_setting "max_tokens" "4096")

  local body
  body=$(jq -n \
    --arg   model "$model_id" \
    --arg   sys   "$system"   \
    --argjson msgs "$messages" \
    --argjson mt   "$max_t"   \
    '{model:$model,max_tokens:$mt,system:$sys,messages:$msgs}')

  do_curl -X POST "https://api.anthropic.com/v1/messages" \
    -H "Content-Type: application/json" \
    -H "x-api-key: $key" \
    -H "anthropic-version: 2023-06-01" \
    -d "$body"
}

# ================================================================
# PARSE RESPONSE
# FIX #4: usa variables globales _LAST_CONTENT/_LAST_TOKENS
# en lugar de separador tab (rompía si response tenía tabs)
# ================================================================
_LAST_CONTENT=""
_LAST_TOKENS="0"

parse_response() {
  local model="$1" raw="$2"

  # Detectar error de API
  local api_err; api_err=$(echo "$raw" | \
    jq -r '.error.message // .error // empty' 2>/dev/null || echo "")
  if [[ -n "$api_err" ]]; then
    echo -e "${R}API Error [$model]:${N} $api_err" >&2
    return 1
  fi

  local content="" tokens="0"

  case "$model" in
    gemini|gemini-pro)
      content=$(echo "$raw" | \
        jq -r '.candidates[0].content.parts[0].text // empty' 2>/dev/null)
      tokens=$(echo "$raw" | \
        jq -r '(.usageMetadata.promptTokenCount // 0) +
                (.usageMetadata.candidatesTokenCount // 0)' 2>/dev/null || echo 0)
      ;;
    anthropic|anthropic-sonnet)
      content=$(echo "$raw" | jq -r '.content[0].text // empty' 2>/dev/null)
      tokens=$(echo "$raw" | \
        jq -r '(.usage.input_tokens // 0) + (.usage.output_tokens // 0)' \
        2>/dev/null || echo 0)
      ;;
    *)
      content=$(echo "$raw" | \
        jq -r '.choices[0].message.content // empty' 2>/dev/null)
      tokens=$(echo "$raw" | jq -r '.usage.total_tokens // 0' 2>/dev/null || echo 0)
      ;;
  esac

  if [[ -z "$content" ]]; then
    echo -e "${R}Respuesta vacía.${N}" >&2
    echo -e "${DIM}$(echo "$raw" | head -c 500)${N}" >&2
    return 1
  fi

  # FIX #4: retorno via vars globales, sin tabs
  _LAST_CONTENT="$content"
  _LAST_TOKENS="$tokens"
  return 0
}

# ================================================================
# DISPATCH
# FIX #7: MODEL_EXACT para override de model-id exacto
# ================================================================
MODEL_EXACT=""

dispatch() {
  local model="$1" user_msg="$2" prompt_name="$3"

  local api_key; api_key=$(get_model_key "$model")
  if [[ -z "$api_key" ]]; then
    echo -e "${R}Sin API key para: $model${N}" >&2
    echo -e "  Configura: ${C}./kr0m.sh --set-key $model${N}" >&2
    return 1
  fi

  # FIX #7: MODEL_EXACT para override del ID exacto
  local model_id="${MODEL_EXACT:-${MODEL_IDS[$model]:-}}"
  if [[ -z "$model_id" ]]; then
    echo -e "${R}Modelo desconocido: $model${N}" >&2
    return 1
  fi

  local system; system=$(load_prompt "$prompt_name")
  local history; history=$(load_history)
  local messages; messages=$(build_messages "$history" "$user_msg")
  local raw

  case "$model" in
    openai|openai-large|deepseek|deepseek-r1|mistral|mistral-small|groq|groq-fast|together)
      raw=$(req_openai_compat "${MODEL_BASES[$model]}" \
        "$api_key" "$model_id" "$system" "$messages") || {
        echo -e "${R}Error de red o timeout.${N}" >&2; return 1
      }
      ;;
    gemini|gemini-pro)
      raw=$(req_gemini "$api_key" "$model_id" "$system" "$messages") || {
        echo -e "${R}Error de red o timeout.${N}" >&2; return 1
      }
      ;;
    anthropic|anthropic-sonnet)
      raw=$(req_anthropic "$api_key" "$model_id" "$system" "$messages") || {
        echo -e "${R}Error de red o timeout.${N}" >&2; return 1
      }
      ;;
    *)
      echo -e "${R}Modelo no soportado: $model${N}" >&2; return 1
      ;;
  esac

  parse_response "$model" "$raw" || return 1

  if [[ -n "$SESSION_ID" ]]; then
    local updated
    updated=$(echo "$messages" | jq --arg r "$_LAST_CONTENT" \
      '. + [{"role":"assistant","content":$r}]')
    save_history "$updated"
  fi

  record_stats "$model" "$_LAST_TOKENS"
  return 0
}

# ================================================================
# DISPATCH MULTI — FIX #5, #15: export_keys() antes de subshells
# ================================================================
dispatch_multi() {
  local user_msg="$1" prompt_name="$2"
  shift 2
  local models=("$@")
  local tmpdir; tmpdir=$(mktemp -d)
  # shellcheck disable=SC2064
  trap "rm -rf '$tmpdir'" RETURN

  # FIX #15: exportar keys para que subshells las vean
  export_keys

  echo -e "\n${B}Multi-modelo paralelo: ${models[*]}${N}\n"

  local pids=()
  for model in "${models[@]}"; do
    (
      local key; key=$(get_model_key "$model")
      if [[ -z "$key" ]]; then
        printf 'STATUS:no_key\n' > "$tmpdir/$model"
        exit 0
      fi
      local t0; t0=$(date +%s%3N)
      if dispatch "$model" "$user_msg" "$prompt_name" 2>"$tmpdir/${model}.err"; then
        local t1; t1=$(date +%s%3N)
        {
          printf 'STATUS:ok\n'
          printf 'ELAPSED:%s\n' "$((t1-t0))"
          printf 'TOKENS:%s\n' "$_LAST_TOKENS"
          printf '%s' "$_LAST_CONTENT"
        } > "$tmpdir/$model"
      else
        {
          printf 'STATUS:error\n'
          cat "$tmpdir/${model}.err" 2>/dev/null
        } > "$tmpdir/$model"
      fi
    ) &
    pids+=($!)
  done

  for pid in "${pids[@]}"; do wait "$pid" 2>/dev/null || true; done

  for model in "${models[@]}"; do
    local label="${MODEL_LABELS[$model]:-$model}"
    local out="$tmpdir/$model"
    [[ ! -f "$out" ]] && continue

    local status; status=$(grep '^STATUS:' "$out" | cut -d: -f2)
    local elapsed; elapsed=$(grep '^ELAPSED:' "$out" | cut -d: -f2 || echo "?")
    local tokens;  tokens=$(grep '^TOKENS:'  "$out" | cut -d: -f2 || echo "0")
    local content; content=$(grep -v '^STATUS:\|^ELAPSED:\|^TOKENS:' "$out")

    echo -e "${M}┌─ $label ${DIM}(${elapsed}ms · ${tokens}tk)${N}"
    case "$status" in
      ok)       print_response "$content" | sed 's/^/│ /' ;;
      no_key)   echo -e "${M}│${N} ${Y}Sin API key${N}" ;;
      error)    echo -e "${M}│${N} ${R}$content${N}" ;;
    esac
    echo -e "${M}└──────────────────────────────────────────${N}\n"
  done
}

# ================================================================
# GUARDAR RESPUESTA
# ================================================================
save_response_to_file() {
  local content="$1" model="$2" outfile="${3:-}"
  if [[ -n "$outfile" ]]; then
    printf '%s\n' "$content" > "$outfile"
    echo -e "${G}[saved] $outfile${N}"
    return
  fi
  local rdir; rdir=$(get_setting "response_dir" "")
  rdir="${rdir:-$KR0M_DIR/responses}"
  rdir="${rdir/#\~/$HOME}"
  mkdir -p "$rdir"
  local fname="$rdir/$(date +%Y%m%d_%H%M%S)_${model}.md"
  printf '# Kr0m Response\n**Model:** %s | **Time:** %s\n\n%s\n' \
    "$model" "$(date)" "$content" > "$fname"
  echo -e "${G}[saved] $fname${N}"
}

# ================================================================
# LISTAS / STATS
# ================================================================
list_models() {
  echo -e "\n${B}Modelos disponibles:${N}\n"
  local sorted; sorted=$(printf '%s\n' "${!MODEL_IDS[@]}" | sort)
  while IFS= read -r k; do
    local key; key=$(get_model_key "$k")
    if [[ -n "$key" ]]; then
      printf "  ${G}●${N} %-22s → %s\n" "$k" "${MODEL_LABELS[$k]}"
    else
      printf "  ${DIM}○ %-22s → %s (sin key)${N}\n" "$k" "${MODEL_LABELS[$k]}"
    fi
  done <<< "$sorted"
  echo ""
}

list_prompts() {
  echo -e "\n${B}Prompts disponibles:${N}\n"
  for dir in "$PROMPTS_DIR"/*/; do
    [[ -d "$dir" ]] || continue
    local mod; mod=$(basename "$dir")
    echo -e "  ${C}[$mod]${N}"
    for f in "$dir"*.txt; do
      [[ -f "$f" ]] || continue
      local name; name=$(basename "$f" .txt)
      local first; first=$(head -1 "$f" | cut -c1-60)
      printf "    ${G}%-16s${N} ${DIM}%s${N}\n" "$name" "$first"
    done
  done
  [[ -f "$PROMPTS_DIR/default.txt" ]] && \
    echo -e "  ${C}[root]${N}\n    ${G}default${N}"
  echo ""
}

show_stats() {
  local sf="$LOGS_DIR/stats.json"
  [[ ! -f "$sf" ]] && echo "Sin estadísticas." && return
  echo -e "\n${B}Estadísticas:${N}\n"
  jq -r '"  Requests : \(.requests)",
           "  Tokens   : \(.total_tokens)",
           "",
           "  Por modelo:",
           (.by_model | to_entries[] |
             "    \(.key): \(.value.requests) req · \(.value.tokens) tokens")
        ' "$sf" 2>/dev/null || cat "$sf"
  echo ""
}

# ================================================================
# SETTINGS TUI
# ================================================================
settings_menu() {
  while true; do
    clear
    echo -e "${B}${C}─── Kr0m Settings ───${N}\n"
    printf "  %-4s %-25s %s\n" "1)"  "Vault method:"        "$(get_setting vault_method password)"
    printf "  %-4s %-25s %s\n" "2)"  "Tor routing:"         "$(get_setting tor_enabled false)"
    printf "  %-4s %-25s %s\n" "3)"  "Auto-clear history:"  "$(get_setting auto_clear_history false)"
    printf "  %-4s %-25s %s\n" "4)"  "Stealth mode:"        "$(get_setting stealth_mode false)"
    printf "  %-4s %-25s %s\n" "5)"  "Syntax highlight:"    "$(get_setting syntax_highlight true)"
    printf "  %-4s %-25s %s\n" "6)"  "Show timer:"          "$(get_setting show_timer true)"
    printf "  %-4s %-25s %s\n" "7)"  "Default model:"       "$(get_setting default_model deepseek)"
    printf "  %-4s %-25s %s\n" "8)"  "Default prompt:"      "$(get_setting default_prompt default)"
    printf "  %-4s %-25s %s\n" "9)"  "Max tokens:"          "$(get_setting max_tokens 4096)"
    printf "  %-4s %-25s %s\n" "10)" "Temperature:"         "$(get_setting temperature 0.7)"
    printf "  %-4s %-25s %s\n" "11)" "History limit:"       "$(get_setting history_limit 20)"
    printf "  %-4s %-25s\n"    "12)" "Set/update API key (vault)"
    printf "  %-4s %-25s\n"    "13)" "Verify Tor IP"
    printf "  %-4s %-25s\n"    "0)"  "Volver"
    echo ""
    echo -ne "Opción: "
    read -r opt

    case "$opt" in
      1)  echo -ne "Vault method [password|password+keyfile|uid|password+totp]: "
          read -r v; set_setting "vault_method" "$v" ;;
      2)  local r; r=$(toggle_setting tor_enabled); echo "Tor: $r"; setup_tor ;;
      3)  local r; r=$(toggle_setting auto_clear_history); echo "Auto-clear: $r" ;;
      4)  local r; r=$(toggle_setting stealth_mode)
          STEALTH_MODE=$([[ "$r" == "true" ]] && echo true || echo false)
          echo "Stealth: $r" ;;
      5)  toggle_setting syntax_highlight > /dev/null; echo "Toggled" ;;
      6)  toggle_setting show_timer > /dev/null; echo "Toggled" ;;
      7)  echo -ne "Modelo: "; read -r v
          [[ -n "${MODEL_IDS[$v]:-}" ]] && set_setting default_model "$v" \
            || echo "Modelo no reconocido: $v" ;;
      8)  echo -ne "Prompt: "; read -r v; set_setting default_prompt "$v" ;;
      9)  echo -ne "Max tokens: "; read -r v; set_setting max_tokens "$v" ;;
      10) echo -ne "Temperature [0.0-2.0]: "; read -r v; set_setting temperature "$v" ;;
      11) echo -ne "History limit: "; read -r v; set_setting history_limit "$v" ;;
      12) echo -ne "Modelo (ej: deepseek): "; read -r m
          echo -ne "API Key: "; read -rs k; echo ""
          vault_write_key "${m^^}_API_KEY" "$k"
          load_keys
          echo -e "${G}Key guardada en vault.${N}" ;;
      13) verify_tor ;;
      0)  break ;;
      *)  echo "Opción inválida" ;;
    esac
    sleep 0.4
  done
}

# ================================================================
# AYUDA
# ================================================================
usage() {
cat << 'HELP'
Kr0m v1.0.1 — Multi-model AI CLI · by Krypthane

USO:
  ./kr0m.sh [opciones] "mensaje"
  ./kr0m.sh -i                     Modo interactivo
  echo "text" | ./kr0m.sh          Desde stdin

MODELOS:  deepseek deepseek-r1 gemini gemini-pro
          openai openai-large mistral mistral-small
          anthropic anthropic-sonnet groq groq-fast together

OPCIONES:
  -m <modelo>     Seleccionar modelo
  -E <model-id>   ID exacto del modelo (override)
  -M <m1,m2>      Multi-modelo paralelo
  -p <prompt>     Prompt (ctf, re, pwn, osint, recon, dev, code, bash, study...)
  -P "texto"      System prompt directo
  -s              Sesión con historial
  -S <id>         Sesión con ID específico
  -i              Modo interactivo
  -o <archivo>    Guardar respuesta
  -t <0-2>        Temperatura
  -n <tokens>     Max tokens
  --raw           Sin system prompt
  --stealth       Sin logs ni historial
  --tor           Activar Tor
  --set-key <m>   Guardar API key en vault
  -l              Listar modelos
  -L              Listar prompts
  -x              Estadísticas
  --settings      Panel de configuración
  -h              Esta ayuda

HELP
}

# ================================================================
# MODO INTERACTIVO
# ================================================================
interactive_mode() {
  [[ -z "$SESSION_ID" ]] && SESSION_ID="s$(date +%s)"
  local model="$CURRENT_MODEL"
  local prompt_name="$CURRENT_PROMPT"
  local multi_models=""

  banner
  echo -e "  Modelo : ${G}${MODEL_LABELS[$model]:-$model}${N}"
  echo -e "  Prompt : ${C}$prompt_name${N}"
  echo -e "  Sesión : ${Y}$SESSION_ID${N}"
  echo -e "  Tor    : $(get_setting tor_enabled false)"
  echo -e "  ${DIM}/help para comandos${N}\n"

  while true; do
    printf "${B}${R}kr0m${N}@${M}%s${N}${C}›${N} " "$prompt_name"
    local input=""
    IFS= read -r input || { echo ""; break; }

    # Trim
    input="${input#"${input%%[![:space:]]*}"}"
    input="${input%"${input##*[![:space:]]}"}"
    [[ -z "$input" ]] && continue

    case "$input" in
      /exit|/quit|/q) echo -e "${Y}bye.${N}"; break ;;

      /help|/?)
        echo -e "${B}Comandos:${N}"
        printf "  %-22s %s\n" "/model <m>"        "Cambiar modelo"
        printf "  %-22s %s\n" "/multi <m1,m2>"    "Multi-modelo paralelo"
        printf "  %-22s %s\n" "/multi off"        "Desactivar multi"
        printf "  %-22s %s\n" "/prompt <p>"       "Cambiar prompt"
        printf "  %-22s %s\n" "/raw"              "Toggle sin system prompt"
        printf "  %-22s %s\n" "/stealth"          "Toggle stealth mode"
        printf "  %-22s %s\n" "/tor"              "Toggle Tor routing"
        printf "  %-22s %s\n" "/session <id>"     "Cambiar sesión"
        printf "  %-22s %s\n" "/clear"            "Limpiar historial"
        printf "  %-22s %s\n" "/history"          "Ver historial"
        printf "  %-22s %s\n" "/save [file]"      "Guardar última respuesta"
        printf "  %-22s %s\n" "/models"           "Listar modelos"
        printf "  %-22s %s\n" "/prompts"          "Listar prompts"
        printf "  %-22s %s\n" "/stats"            "Estadísticas"
        printf "  %-22s %s\n" "/settings"         "Panel de config"
        printf "  %-22s %s\n" "/temp <t>"         "Temperatura"
        printf "  %-22s %s\n" "/key <modelo>"     "Setear API key"
        printf "  %-22s %s\n" "/exit"             "Salir"
        continue ;;

      /model*)
        local nm; nm=$(echo "$input" | awk '{print $2}')
        if [[ -n "$nm" && -n "${MODEL_IDS[$nm]:-}" ]]; then
          model="$nm"
          echo -e "${G}Modelo → ${MODEL_LABELS[$model]}${N}"
        else
          echo "Modelos: ${!MODEL_IDS[*]}"
        fi; continue ;;

      /multi\ off) multi_models=""; echo -e "${G}Multi desactivado${N}"; continue ;;
      /multi*)
        local ml; ml=$(echo "$input" | awk '{print $2}')
        [[ -n "$ml" ]] && multi_models="$ml" && echo -e "${G}Multi: $ml${N}"
        continue ;;

      /prompt*)
        local np; np=$(echo "$input" | awk '{print $2}')
        prompt_name="$np"; echo -e "${G}Prompt → $prompt_name${N}"; continue ;;

      /raw)
        $RAW_MODE && RAW_MODE=false || RAW_MODE=true
        echo -e "Raw: $RAW_MODE"; continue ;;

      /stealth)
        $STEALTH_MODE && STEALTH_MODE=false || STEALTH_MODE=true
        echo -e "Stealth: $STEALTH_MODE"; continue ;;

      /tor)
        local cur; cur=$(toggle_setting tor_enabled)
        echo -e "Tor: $cur"; setup_tor; continue ;;

      /session*)
        local ns; ns=$(echo "$input" | awk '{print $2}')
        [[ -n "$ns" ]] && SESSION_ID="$ns" && echo -e "${G}Sesión → $SESSION_ID${N}"
        continue ;;

      /clear)
        rm -f "$(get_hfile)"
        echo -e "${G}Historial limpiado.${N}"; continue ;;

      /history)
        local hf; hf=$(get_hfile)
        [[ -f "$hf" ]] && \
          jq -r '.[] | "\(.role): \(.content[0:100])"' "$hf" 2>/dev/null \
          || echo "Sin historial."
        continue ;;

      /save*)
        local sf; sf=$(echo "$input" | awk '{print $2}')
        if [[ -n "$_LAST_CONTENT" ]]; then
          save_response_to_file "$_LAST_CONTENT" "$model" "${sf:-}"
        else
          echo "Sin respuesta que guardar."
        fi; continue ;;

      /models)   list_models; continue ;;
      /prompts)  list_prompts; continue ;;
      /stats)    show_stats; continue ;;
      /settings) settings_menu; continue ;;

      /temp*)
        local nt; nt=$(echo "$input" | awk '{print $2}')
        [[ -n "$nt" ]] && set_setting temperature "$nt" && \
          echo -e "${G}Temperatura: $nt${N}"
        continue ;;

      /key*)
        local km; km=$(echo "$input" | awk '{print $2}')
        [[ -z "$km" ]] && echo "Uso: /key <modelo>" && continue
        echo -ne "API Key para $km: "; read -rs k; echo ""
        vault_write_key "${km^^}_API_KEY" "$k"
        load_keys; echo -e "${G}Key guardada.${N}"
        continue ;;
    esac

    # ── Enviar ────────────────────────────────────────
    local t0; t0=$(date +%s%3N)
    printf "${DIM}▸ thinking...${N}"

    if [[ -n "$multi_models" ]]; then
      printf "\r\033[K"
      IFS=',' read -ra mlist <<< "$multi_models"
      dispatch_multi "$input" "$prompt_name" "${mlist[@]}"
    else
      if dispatch "$model" "$input" "$prompt_name" 2>&1; then
        local t1; t1=$(date +%s%3N)
        local elapsed=$(( t1 - t0 ))
        local show_timer; show_timer=$(get_setting show_timer true)
        local label="${MODEL_LABELS[$model]:-$model}"

        printf "\r\033[K"
        if [[ "$show_timer" == "true" ]]; then
          echo -e "${DIM}─── $label · ${elapsed}ms · ${_LAST_TOKENS}tk ───${N}"
        else
          echo -e "${DIM}─── $label ───${N}"
        fi
        print_response "$_LAST_CONTENT"
        echo -e "${DIM}─────────────────────────────────────────${N}"

        [[ "$(get_setting save_responses false)" == "true" ]] && \
          save_response_to_file "$_LAST_CONTENT" "$model"
      else
        printf "\r${R}Error al obtener respuesta.${N}\n"
      fi
    fi
  done
}

# ================================================================
# MAIN
# ================================================================
CURRENT_MODEL=""
CURRENT_PROMPT=""
MULTI_MODELS=""
INTERACTIVE=false
OUTPUT_FILE=""

load_settings

CURRENT_MODEL=$(get_setting default_model deepseek)
CURRENT_PROMPT=$(get_setting default_prompt default)
# FIX #13: leer stealth/raw desde settings ANTES de procesar args
[[ "$(get_setting stealth_mode false)" == "true" ]] && STEALTH_MODE=true

# ── Parse args ────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    -m)  CURRENT_MODEL="$2"; shift 2 ;;
    -E)  MODEL_EXACT="$2"; shift 2 ;;
    -M)  MULTI_MODELS="$2"; shift 2 ;;
    -p)  CURRENT_PROMPT="$2"; shift 2 ;;
    -P)  SYSTEM_PROMPT_OVERRIDE="$2"; shift 2 ;;
    -s)  SESSION_ID="default"; shift ;;
    -S)  SESSION_ID="$2"; shift 2 ;;
    -i)  INTERACTIVE=true; shift ;;
    -o)  OUTPUT_FILE="$2"; shift 2 ;;
    -t)  set_setting temperature "$2"; shift 2 ;;
    -n)  set_setting max_tokens "$2"; shift 2 ;;
    --raw)     RAW_MODE=true; shift ;;
    --stealth) STEALTH_MODE=true; shift ;;
    --tor)     set_setting tor_enabled true; shift ;;
    --set-key)
      _setkey_model="${2:-}"
      [[ -z "$_setkey_model" ]] && echo "Uso: --set-key <modelo>" && exit 1
      shift 2
      load_settings; vault_init
      echo -ne "API Key para $_setkey_model: "
      read -rs _setkey_val; echo ""
      vault_write_key "${_setkey_model^^}_API_KEY" "$_setkey_val"
      echo -e "${G}[vault] Key guardada para: $_setkey_model${N}"
      exit 0 ;;
    -l)  load_settings; vault_init; load_keys; list_models; exit 0 ;;
    -L)  load_settings; list_prompts; exit 0 ;;
    -x)  load_settings; show_stats; exit 0 ;;
    --settings)
      load_settings; vault_init; load_keys
      settings_menu; exit 0 ;;
    -h|--help) usage; exit 0 ;;
    --) shift; break ;;
    -*) echo -e "${R}Opción desconocida: $1${N}"; usage; exit 1 ;;
    *)  break ;;
  esac
done

# ── Inicializar ───────────────────────────────────────────
setup_tor
vault_init
load_keys
export_keys  # FIX #15

# ── Interactivo ───────────────────────────────────────────
if $INTERACTIVE; then
  interactive_mode
  exit 0
fi

# ── Construir mensaje ─────────────────────────────────────
USER_MESSAGE=""
if [[ ! -t 0 ]]; then
  STDIN_DATA=$(cat)
  if [[ $# -gt 0 ]]; then
    USER_MESSAGE="$(printf '%s\n\n%s' "$*" "$STDIN_DATA")"
  else
    USER_MESSAGE="$STDIN_DATA"
  fi
elif [[ $# -gt 0 ]]; then
  USER_MESSAGE="$*"
else
  echo -e "${Y}Uso:${N} ./kr0m.sh \"mensaje\"  |  -i  |  -h"
  exit 1
fi

# ── Enviar ────────────────────────────────────────────────
T0=$(date +%s%3N)

if [[ -n "$MULTI_MODELS" ]]; then
  IFS=',' read -ra MLIST <<< "$MULTI_MODELS"
  dispatch_multi "$USER_MESSAGE" "$CURRENT_PROMPT" "${MLIST[@]}"
else
  dispatch "$CURRENT_MODEL" "$USER_MESSAGE" "$CURRENT_PROMPT" || exit 1

  T1=$(date +%s%3N)
  ELAPSED=$(( T1 - T0 ))
  SHOW_TIMER=$(get_setting show_timer true)
  LABEL="${MODEL_LABELS[$CURRENT_MODEL]:-$CURRENT_MODEL}"

  echo ""
  if [[ "$SHOW_TIMER" == "true" ]]; then
    echo -e "${DIM}─── $LABEL · ${ELAPSED}ms · ${_LAST_TOKENS}tk ───${N}"
  else
    echo -e "${DIM}─── $LABEL ───${N}"
  fi
  print_response "$_LAST_CONTENT"
  echo -e "${DIM}─────────────────────────────────────────${N}\n"

  [[ -n "$OUTPUT_FILE" ]] && \
    save_response_to_file "$_LAST_CONTENT" "$CURRENT_MODEL" "$OUTPUT_FILE"
fi
MAINEOF
chmod +x kr0m.sh
log "kr0m.sh v1.0.1 generado"

# ── Prompts ───────────────────────────────────────────────
info "Generando prompts..."

cat > prompts/ctf/ctf.txt << 'P'
You are an expert CTF player and security researcher.
Expertise: binary exploitation, reverse engineering, web (SQLi/XSS/SSRF/deserialization),
cryptography weaknesses, forensics (pcap, memory dumps, steganography).
Methodology: identify category → tools → step-by-step approach.
Tools: pwntools, GDB/pwndbg, Ghidra, radare2, burpsuite, hashcat, wireshark.
Technical language. Show reasoning. No oversimplification.
P

cat > prompts/ctf/re.txt << 'P'
You are a reverse engineering expert.
Tools: Ghidra, IDA Pro, Binary Ninja, GDB+pwndbg, radare2, angr, ltrace, strace.
Analyze: architecture → calling convention → key functions → crypto constants.
Provide annotated pseudocode. Explain anti-debug tricks and bypass methods.
Always pair static analysis with dynamic analysis steps.
P

cat > prompts/ctf/pwn.txt << 'P'
You are a binary exploitation specialist.
Expertise: stack/heap exploitation, format strings, ROP chains,
ASLR/PIE/NX/canary bypass, ret2libc, ret2plt, FSOP, seccomp bypass.
Tools: pwntools, pwndbg, ROPgadget, one_gadget, seccomp-tools, checksec.
Provide working pwntools scripts. Explain each step of the exploit chain.
P

cat > prompts/osint/recon.txt << 'P'
You are a reconnaissance specialist.
Methodology: passive → active → enumeration → analysis.
Tools: amass, subfinder, shodan, theHarvester, recon-ng, dnsx, httpx, nmap, masscan.
For any target: ordered steps with exact commands and expected output.
Focus on attack surface discovery.
P

cat > prompts/osint/osint.txt << 'P'
You are an OSINT investigator.
Sources: WHOIS, DNS, crt.sh, Shodan/Censys/FOFA, social media,
GitHub dorking, Google dorks, paste sites, metadata analysis.
Give specific operators, queries, tool commands. Be methodical and thorough.
P

cat > prompts/dev/dev.txt << 'P'
You are a senior software engineer.
Principles: clean code, SOLID, security by design, performance-aware.
Output: working code + error handling + edge cases + brief explanation.
Languages: Python, Bash, JavaScript/Node.js, Go, Rust, C/C++.
No caveats. Direct, production-ready output.
P

cat > prompts/dev/code.txt << 'P'
Code only. No explanation unless asked.
Full error handling. Minimal inline comments for non-obvious logic.
If ambiguous: state assumption in one line then code.
P

cat > prompts/dev/bash.txt << 'P'
You are a bash expert.
Always use: set -euo pipefail, proper quoting, meaningful errors, usage functions.
POSIX-compatible when possible. Handle signals where relevant.
P

cat > prompts/study/study.txt << 'P'
You are a technical educator.
Expertise: systems, networking, crypto, OS internals, security.
Format: 1-sentence definition → mechanism → concrete example → gotchas.
ASCII diagrams when helpful. Assume technical background.
P

cat > prompts/study/explain.txt << 'P'
Explain concisely.
Format: definition → how it works → real example → caveats.
No filler. Depth only where needed.
P

cat > prompts/study/research.txt << 'P'
You are a research assistant with deep CS and security knowledge.
Format: background → key concepts → state of the art → applications → references.
Cite papers, CVEs, tools when relevant. Precision over simplicity.
P

cat > prompts/default.txt << 'P'
You are a precise, direct assistant.
No filler. No disclaimers. Code blocks for code.
Short unless depth is needed.
P

log "Prompts creados"

# ── Scripts de soporte ─────────────────────────────────────
cat > start.sh << 'S'
#!/bin/bash
set -e
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
for dep in curl jq openssl; do
  command -v "$dep" &>/dev/null || { echo "Falta: $dep"; exit 1; }
done
exec "$DIR/kr0m.sh" "$@"
S
chmod +x start.sh

cat > install.sh << 'S'
#!/bin/bash
set -e
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cat > /usr/local/bin/kr0m << EOF
#!/bin/bash
exec "$DIR/kr0m.sh" "\$@"
EOF
chmod +x /usr/local/bin/kr0m
echo "✓ kr0m instalado globalmente — usa: kr0m 'pregunta'"
S
chmod +x install.sh

cat > .env << 'E'
# Kr0m — API Keys fallback (sin vault)
# Recomendado: ./kr0m.sh --set-key <modelo>
DEEPSEEK_API_KEY=
OPENAI_API_KEY=
GEMINI_API_KEY=
MISTRAL_API_KEY=
ANTHROPIC_API_KEY=
GROQ_API_KEY=
TOGETHER_API_KEY=
E
chmod 600 .env
cp .env .env.example

cat > .gitignore << 'G'
.env
vault/
.kr0m/
history/
logs/
responses/
*.tmp
G

cat > CHANGELOG.md << 'CL'
# Kr0m Changelog

## [1.0.1] — Bugfix Release

### Bugs corregidos (15 total)
1. CURL_CMD: string → array (torsocks roto)
2. AES-256-GCM → CBC (compatibilidad openssl 1.1.x)
3. bat → batcat (nombre correcto en Kali)
4. parse_response: tab separator → vars globales _LAST_CONTENT/_LAST_TOKENS
5. dispatch_multi: export_keys() antes de subshells
6. vault_init/vault_unlock: separados (sin doble llamada)
7. get_model_key: usa vars después de load_keys
8. vault_derive_key: sin xxd, usa awk sobre openssl dgst
9. declare -A MODEL_KEYS eliminado (refs prematuras)
10. set_setting: detección automática de tipo
11. get_setting: tostring para bool/num/string
12. STEALTH_MODE/RAW_MODE: inicializados antes de uso
13. load_prompt: SYSTEM_PROMPT_OVERRIDE tiene prioridad correcta
14. MODEL_EXACT (-E) para override de model-id exacto
15. dispatch_multi: STATUS codes (ok/no_key/error)

## [1.0.0] — Initial Release
- Multi-model, vault, Tor, prompts, modo interactivo
CL

chmod 700 vault .kr0m history logs
chmod 600 .env

echo ""
echo -e "${R}${B}══════════════════════════════════════════${N}"
echo -e "${R}${B}   Kr0m v1.0.1 — 15 bugs corregidos ✓${N}"
echo -e "${R}${B}══════════════════════════════════════════${N}"
echo ""
echo -e "  ${Y}INICIO:${N}"
echo -e "  ${B}1.${N} ./kr0m.sh --set-key deepseek   ← key en vault"
echo -e "  ${B}2.${N} ./kr0m.sh -m groq \"test\"       ← prueba gratis"
echo -e "  ${B}3.${N} ./kr0m.sh -i                   ← interactivo"
echo ""
echo -e "  ${C}CTF:${N}     ./kr0m.sh -p ctf -m deepseek \"analiza esto\""
echo -e "  ${C}Multi:${N}   ./kr0m.sh -M \"groq,deepseek,gemini\" \"pregunta\""
echo -e "  ${C}Tor:${N}     ./kr0m.sh --tor --stealth \"consulta\""
echo -e "  ${C}Global:${N}  sudo ./install.sh && kr0m \"pregunta\""
echo ""
