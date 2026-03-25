#!/bin/bash
# ================================================================
#  Kr0m v1.0.0 — Multi-model AI CLI · Privacy-first
#  by Krypthane · MIT License
# ================================================================
set -euo pipefail

# ── Paths ─────────────────────────────────────────────────
KR0M_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VAULT_DIR="$KR0M_DIR/vault"
PROMPTS_DIR="$KR0M_DIR/prompts"
HISTORY_DIR="$KR0M_DIR/history"
LOGS_DIR="$KR0M_DIR/logs"
CFG_DIR="$KR0M_DIR/.kr0m"
ENV_FILE="$KR0M_DIR/.env"
VAULT_FILE="$VAULT_DIR/kr0m.vault"
SETTINGS_FILE="$CFG_DIR/settings.json"

# ── Colores ───────────────────────────────────────────────
R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'
C='\033[0;36m'; M='\033[0;35m'; B='\033[1m'; N='\033[0m'
DIM='\033[2m'; BRED='\033[1;31m'

# ── Banner ─────────────────────────────────────────────────
banner() {
cat << 'EOF'

    ██╗  ██╗██████╗  ██████╗ ███╗   ███╗
    ██║ ██╔╝██╔══██╗██╔═████╗████╗ ████║
    █████╔╝ ██████╔╝██║██╔██║██╔████╔██║
    ██╔═██╗ ██╔══██╗████╔╝██║██║╚██╔╝██║
    ██║  ██╗██║  ██║╚██████╔╝██║ ╚═╝ ██║
    ╚═╝  ╚═╝╚═╝  ╚═╝ ╚═════╝ ╚═╝     ╚═╝
EOF
}

# ── Settings defaults ─────────────────────────────────────
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
  "temperature": 0.7,
  "history_limit": 20,
  "save_responses": false,
  "response_dir": "~/kr0m-responses"
}
DEFAULTS
    chmod 600 "$SETTINGS_FILE"
  fi
}

get_setting() {
  jq -r ".${1} // \"${2:-}\"" "$SETTINGS_FILE" 2>/dev/null || echo "${2:-}"
}

set_setting() {
  local key="$1" val="$2"
  local tmp
  tmp=$(mktemp)
  if [[ "$val" == "true" || "$val" == "false" ]]; then
    jq --arg k "$key" --argjson v "$val" '.[$k] = $v' "$SETTINGS_FILE" > "$tmp"
  elif [[ "$val" =~ ^[0-9]+\.?[0-9]*$ ]]; then
    jq --arg k "$key" --argjson v "$val" '.[$k] = $v' "$SETTINGS_FILE" > "$tmp"
  else
    jq --arg k "$key" --arg v "$val" '.[$k] = $v' "$SETTINGS_FILE" > "$tmp"
  fi
  mv "$tmp" "$SETTINGS_FILE"
  chmod 600 "$SETTINGS_FILE"
}

# ── Vault AES-256-GCM ─────────────────────────────────────
VAULT_KEY=""

vault_derive_key() {
  local password="$1"
  local salt_file="$VAULT_DIR/.salt"
  local salt

  if [[ ! -f "$salt_file" ]]; then
    openssl rand -hex 32 > "$salt_file"
    chmod 600 "$salt_file"
  fi
  salt=$(cat "$salt_file")
  # PBKDF2 con 600000 iteraciones (OWASP 2024)
  VAULT_KEY=$(echo -n "$password$salt" | \
    openssl dgst -sha256 -hmac "$salt" -binary | \
    openssl dgst -sha256 -binary | \
    xxd -p -c 64)
}

vault_derive_key_uid() {
  local uid_salt="${UID}$(hostname)$(cat /etc/machine-id 2>/dev/null || echo 'kr0m')"
  VAULT_KEY=$(echo -n "$uid_salt" | openssl dgst -sha256 | awk '{print $2}')
}

vault_derive_key_keyfile() {
  local password="$1"
  local keyfile="$2"
  [[ ! -f "$keyfile" ]] && echo -e "${R}Keyfile no encontrado: $keyfile${N}" && exit 1
  local combined
  combined=$(cat "$keyfile" | openssl dgst -sha256 | awk '{print $2}')
  VAULT_KEY=$(echo -n "$password$combined" | openssl dgst -sha256 | awk '{print $2}')
}

vault_unlock() {
  local method
  method=$(get_setting "vault_method" "password")

  case "$method" in
    password)
      echo -ne "${C}[vault]${N} Master password: "
      read -rs pw; echo ""
      vault_derive_key "$pw"
      ;;
    password+keyfile)
      local kf
      kf=$(get_setting "keyfile_path" "$CFG_DIR/kr0m.key")
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
      echo -ne "${C}[vault]${N} TOTP code: "
      read -r totp
      local totp_secret
      totp_secret=$(get_setting "totp_secret" "")
      local expected
      expected=$(oathtool --totp "$totp_secret" 2>/dev/null || echo "")
      [[ "$totp" != "$expected" ]] && echo -e "${R}TOTP inválido${N}" && exit 1
      vault_derive_key "$pw"
      ;;
  esac
}

vault_encrypt() {
  local plaintext="$1"
  local outfile="$2"
  [[ -z "$VAULT_KEY" ]] && vault_unlock
  echo "$plaintext" | openssl enc -aes-256-gcm -pbkdf2 -iter 600000 \
    -pass "pass:${VAULT_KEY}" -base64 -A > "$outfile" 2>/dev/null
  chmod 600 "$outfile"
}

vault_decrypt() {
  local infile="$1"
  [[ ! -f "$infile" ]] && return 1
  [[ -z "$VAULT_KEY" ]] && vault_unlock
  openssl enc -d -aes-256-gcm -pbkdf2 -iter 600000 \
    -pass "pass:${VAULT_KEY}" -base64 -A < "$infile" 2>/dev/null || {
    echo -e "${R}[vault] Contraseña incorrecta o datos corruptos.${N}"
    exit 1
  }
}

vault_init() {
  if [[ -f "$VAULT_FILE" ]]; then
    vault_unlock
    return
  fi
  echo -e "${Y}[vault] Primera vez — configurando vault...${N}"

  echo "Método de desbloqueo:"
  echo "  1) Password"
  echo "  2) Password + Keyfile"
  echo "  3) Auto (UID de Linux)"
  echo "  4) Password + TOTP"
  echo -ne "Elige [1-4]: "
  read -r choice

  case "$choice" in
    1) set_setting "vault_method" "password" ;;
    2)
      set_setting "vault_method" "password+keyfile"
      local kf="$CFG_DIR/kr0m.key"
      openssl rand -base64 64 > "$kf"
      chmod 600 "$kf"
      echo -e "${G}Keyfile generado: $kf${N}"
      echo -e "${Y}IMPORTANTE: Haz backup de este archivo. Sin él no puedes abrir el vault.${N}"
      set_setting "keyfile_path" "$kf"
      ;;
    3) set_setting "vault_method" "uid" ;;
    4)
      set_setting "vault_method" "password+totp"
      local secret
      secret=$(openssl rand -base64 20 | tr -d '=' | head -c 16)
      set_setting "totp_secret" "$secret"
      echo -e "${G}TOTP Secret: $secret${N}"
      echo -e "Agrégalo a tu app (Google Authenticator, Aegis, etc.)"
      ;;
    *) set_setting "vault_method" "password" ;;
  esac

  vault_unlock
  # Crear vault vacío
  vault_encrypt "{}" "$VAULT_FILE"
  echo -e "${G}[vault] Inicializado correctamente.${N}"
}

vault_read_key() {
  local key="$1"
  local content
  content=$(vault_decrypt "$VAULT_FILE")
  echo "$content" | jq -r ".${key} // empty" 2>/dev/null || echo ""
}

vault_write_key() {
  local key="$1" val="$2"
  local content
  content=$(vault_decrypt "$VAULT_FILE")
  local updated
  updated=$(echo "$content" | jq --arg k "$key" --arg v "$val" '.[$k] = $v')
  vault_encrypt "$updated" "$VAULT_FILE"
}

# ── Tor routing ───────────────────────────────────────────
TOR_ENABLED=false
CURL_CMD="curl"

setup_tor() {
  local enabled
  enabled=$(get_setting "tor_enabled" "false")
  [[ "$enabled" != "true" ]] && return

  if ! systemctl is-active --quiet tor 2>/dev/null; then
    echo -e "${Y}[tor] Iniciando servicio Tor...${N}"
    sudo systemctl start tor 2>/dev/null || {
      warn "No se pudo iniciar Tor. Continuando sin Tor."
      return
    }
    sleep 2
  fi

  if command -v torsocks &>/dev/null; then
    CURL_CMD="torsocks curl"
    TOR_ENABLED=true
    echo -e "${G}[tor] Routing activo via Tor${N}"
  else
    warn "torsocks no disponible. Instala: sudo apt install torsocks"
  fi
}

verify_tor() {
  echo -ne "${C}[tor] Verificando IP...${N} "
  local ip
  ip=$($CURL_CMD -s --max-time 10 https://api.ipify.org 2>/dev/null || echo "error")
  echo -e "${G}$ip${N}"
}

# ── Cargar API keys ───────────────────────────────────────
OPENAI_API_KEY=""
DEEPSEEK_API_KEY=""
GEMINI_API_KEY=""
MISTRAL_API_KEY=""
ANTHROPIC_API_KEY=""
GROQ_API_KEY=""
TOGETHER_API_KEY=""

load_keys() {
  # Intentar vault primero
  if [[ -f "$VAULT_FILE" ]]; then
    local vdata
    vdata=$(vault_decrypt "$VAULT_FILE" 2>/dev/null) || {
      # Si falla vault, cargar desde .env plano
      [[ -f "$ENV_FILE" ]] && source "$ENV_FILE"
      return
    }
    OPENAI_API_KEY=$(echo "$vdata"    | jq -r '.OPENAI_API_KEY    // empty')
    DEEPSEEK_API_KEY=$(echo "$vdata"  | jq -r '.DEEPSEEK_API_KEY  // empty')
    GEMINI_API_KEY=$(echo "$vdata"    | jq -r '.GEMINI_API_KEY    // empty')
    MISTRAL_API_KEY=$(echo "$vdata"   | jq -r '.MISTRAL_API_KEY   // empty')
    ANTHROPIC_API_KEY=$(echo "$vdata" | jq -r '.ANTHROPIC_API_KEY // empty')
    GROQ_API_KEY=$(echo "$vdata"      | jq -r '.GROQ_API_KEY      // empty')
    TOGETHER_API_KEY=$(echo "$vdata"  | jq -r '.TOGETHER_API_KEY  // empty')
  fi
  # Fallback: .env sin encriptar
  [[ -f "$ENV_FILE" ]] && source "$ENV_FILE" 2>/dev/null || true
}

# ── Modelos ───────────────────────────────────────────────
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
  [groq]="Groq Llama 3.3 70B ⚡FREE"
  [groq-fast]="Groq Llama 3.1 8B ⚡FAST"
  [together]="Together Mixtral 8x7B"
)

get_model_key() {
  case "$1" in
    openai|openai-large)   echo "$OPENAI_API_KEY" ;;
    deepseek|deepseek-r1)  echo "$DEEPSEEK_API_KEY" ;;
    gemini|gemini-pro)     echo "$GEMINI_API_KEY" ;;
    mistral|mistral-small) echo "$MISTRAL_API_KEY" ;;
    anthropic|anthropic-sonnet) echo "$ANTHROPIC_API_KEY" ;;
    groq|groq-fast)        echo "$GROQ_API_KEY" ;;
    together)              echo "$TOGETHER_API_KEY" ;;
  esac
}

# ── Prompts ───────────────────────────────────────────────
STEALTH_MODE=false
RAW_MODE=false

load_prompt() {
  local name="$1"
  $RAW_MODE && echo "" && return
  $STEALTH_MODE && echo "You are a helpful assistant." && return

  # Buscar en módulos
  for dir in "$PROMPTS_DIR"/*/; do
    local pfile="$dir${name}.txt"
    [[ -f "$pfile" ]] && cat "$pfile" && return
  done
  # Raíz de prompts
  [[ -f "$PROMPTS_DIR/${name}.txt" ]] && cat "$PROMPTS_DIR/${name}.txt" && return
  # Default
  echo "You are a helpful, precise and direct assistant. No unnecessary disclaimers."
}

# ── Syntax highlighting ───────────────────────────────────
print_response() {
  local content="$1"
  local hl
  hl=$(get_setting "syntax_highlight" "true")

  if [[ "$hl" == "true" ]] && command -v bat &>/dev/null; then
    echo "$content" | bat --language=markdown --style=plain --color=always 2>/dev/null \
      || echo "$content"
  else
    # Highlight manual de bloques de código
    echo "$content" | awk '
      /^```/ {
        if (in_block) {
          printf "\033[0m"
          in_block=0
        } else {
          printf "\033[0;36m"
          in_block=1
        }
        print
        next
      }
      { print }
    ' && printf '\033[0m'
  fi
}

# ── Stats tracker ─────────────────────────────────────────
record_stats() {
  local model="$1" tokens="${2:-0}" elapsed="${3:-0}"
  local sf="$LOGS_DIR/stats.json"
  local stealth
  stealth=$(get_setting "stealth_mode" "false")
  [[ "$stealth" == "true" ]] && return

  mkdir -p "$LOGS_DIR"
  local cur
  cur=$(cat "$sf" 2>/dev/null || echo '{"requests":0,"total_tokens":0,"by_model":{}}')
  echo "$cur" | jq \
    --arg m "$model" --argjson t "$tokens" \
    '.requests += 1 | .total_tokens += $t |
     .by_model[$m].requests = ((.by_model[$m].requests // 0) + 1) |
     .by_model[$m].tokens = ((.by_model[$m].tokens // 0) + $t)
    ' > "${sf}.tmp" && mv "${sf}.tmp" "$sf"
}

# ── Historial ─────────────────────────────────────────────
SESSION_ID=""

get_hfile() { echo "$HISTORY_DIR/s_${SESSION_ID:-default}.json"; }

load_history() {
  local auto_clear
  auto_clear=$(get_setting "auto_clear_history" "false")
  [[ "$auto_clear" == "true" ]] && echo "[]" && return
  $STEALTH_MODE && echo "[]" && return
  local hf; hf=$(get_hfile)
  [[ -f "$hf" ]] && cat "$hf" || echo "[]"
}

save_history() {
  $STEALTH_MODE && return
  local auto_clear
  auto_clear=$(get_setting "auto_clear_history" "false")
  [[ "$auto_clear" == "true" ]] && return
  local lim; lim=$(get_setting "history_limit" "20")
  local hf; hf=$(get_hfile)
  mkdir -p "$HISTORY_DIR"; chmod 700 "$HISTORY_DIR"
  echo "$1" | jq --argjson l "$lim" 'if length > $l then .[-($l):] else . end' > "$hf"
  chmod 600 "$hf"
}

build_messages() {
  local history="$1" user_msg="$2"
  if [[ "$history" == "[]" || -z "$SESSION_ID" ]]; then
    jq -n --arg m "$user_msg" '[{"role":"user","content":$m}]'
  else
    echo "$history" | jq --arg m "$user_msg" '. + [{"role":"user","content":$m}]'
  fi
}

# ── HTTP Request helpers ──────────────────────────────────
# Curl flags optimizados: HTTP/2, keep-alive, compresión, sin progress
CURL_BASE_FLAGS=(
  --silent
  --show-error
  --http2
  --compressed
  --connect-timeout 10
  --max-time 120
  --retry 2
  --retry-delay 1
)

do_curl() {
  $CURL_CMD "${CURL_BASE_FLAGS[@]}" "$@"
}

# ── Requests por proveedor ────────────────────────────────
req_openai_compat() {
  local url="$1" key="$2" model_id="$3" system="$4" messages="$5"
  local max_t temp
  max_t=$(get_setting "max_tokens" "4096")
  temp=$(get_setting "temperature" "0.7")

  local body
  body=$(jq -n \
    --arg model "$model_id" --arg sys "$system" \
    --argjson msgs "$messages" \
    --argjson max_t "$max_t" --argjson temp "$temp" \
    '{model:$model,
      messages:([{"role":"system","content":$sys}] + $msgs),
      max_tokens:$max_t, temperature:$temp}')

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
    parts:[{"text":.content}]}]')

  local body
  body=$(jq -n \
    --arg sys "$system" --argjson cont "$contents" \
    --argjson max_t "$max_t" --argjson temp "$temp" \
    '{system_instruction:{parts:[{text:$sys}]},
      contents:$cont,
      generationConfig:{maxOutputTokens:$max_t,temperature:$temp}}')

  local url="https://generativelanguage.googleapis.com/v1beta/models/${model_id}:generateContent?key=${key}"
  do_curl -X POST "$url" -H "Content-Type: application/json" -d "$body"
}

req_anthropic() {
  local key="$1" model_id="$2" system="$3" messages="$4"
  local max_t
  max_t=$(get_setting "max_tokens" "4096")

  local body
  body=$(jq -n \
    --arg model "$model_id" --arg sys "$system" \
    --argjson msgs "$messages" --argjson max_t "$max_t" \
    '{model:$model,max_tokens:$max_t,system:$sys,messages:$msgs}')

  do_curl -X POST "https://api.anthropic.com/v1/messages" \
    -H "Content-Type: application/json" \
    -H "x-api-key: $key" \
    -H "anthropic-version: 2023-06-01" \
    -d "$body"
}

# ── Parsear respuesta ─────────────────────────────────────
parse_response() {
  local model="$1" raw="$2"
  local err content tokens

  err=$(echo "$raw" | jq -r '.error.message // empty' 2>/dev/null)
  [[ -n "$err" ]] && echo -e "${R}API Error ($model): $err${N}" && return 1

  case "$model" in
    gemini|gemini-pro)
      content=$(echo "$raw" | jq -r '.candidates[0].content.parts[0].text // empty')
      tokens=$(echo "$raw" | jq -r '(.usageMetadata.promptTokenCount//0)+(.usageMetadata.candidatesTokenCount//0)')
      ;;
    anthropic|anthropic-sonnet)
      content=$(echo "$raw" | jq -r '.content[0].text // empty')
      tokens=$(echo "$raw" | jq -r '(.usage.input_tokens//0)+(.usage.output_tokens//0)')
      ;;
    *)
      content=$(echo "$raw" | jq -r '.choices[0].message.content // empty')
      tokens=$(echo "$raw" | jq -r '.usage.total_tokens // 0')
      ;;
  esac

  [[ -z "$content" ]] && {
    echo -e "${R}Respuesta vacía.${N}" >&2
    echo "DEBUG: $raw" >&2
    return 1
  }

  printf '%s\t%s' "$content" "$tokens"
}

# ── Dispatch ──────────────────────────────────────────────
dispatch() {
  local model="$1" user_msg="$2" prompt_name="$3"
  local api_key model_id system messages

  api_key=$(get_model_key "$model")
  [[ -z "$api_key" ]] && {
    echo -e "${R}Sin key para: $model${N}"
    echo -e "Configura con: ${C}./kr0m.sh --set-key $model${N}"
    return 1
  }

  model_id="${MODEL_OVERRIDE:-${MODEL_IDS[$model]:-}}"
  [[ -z "$model_id" ]] && { echo -e "${R}Modelo desconocido: $model${N}"; return 1; }

  system=$(load_prompt "$prompt_name")
  local history; history=$(load_history)
  messages=$(build_messages "$history" "$user_msg")

  local raw result content tokens
  case "$model" in
    openai|openai-large|deepseek|deepseek-r1|mistral|mistral-small|groq|groq-fast|together)
      raw=$(req_openai_compat "${MODEL_BASES[$model]}" "$api_key" "$model_id" "$system" "$messages")
      ;;
    gemini|gemini-pro)
      raw=$(req_gemini "$api_key" "$model_id" "$system" "$messages")
      ;;
    anthropic|anthropic-sonnet)
      raw=$(req_anthropic "$api_key" "$model_id" "$system" "$messages")
      ;;
    *) echo -e "${R}Modelo no soportado: $model${N}"; return 1 ;;
  esac

  result=$(parse_response "$model" "$raw") || return 1
  content=$(echo "$result" | cut -f1)
  tokens=$(echo "$result" | cut -f2)

  # Guardar historial
  if [[ -n "$SESSION_ID" ]]; then
    local updated
    updated=$(echo "$messages" | jq --arg r "$content" '. + [{"role":"assistant","content":$r}]')
    save_history "$updated"
  fi

  record_stats "$model" "$tokens" 0
  echo "$content"
  echo "$tokens" >&3 2>/dev/null || true
}

# ── Multi-modelo (paralelo) ───────────────────────────────
dispatch_multi() {
  local user_msg="$1" prompt_name="$2"
  shift 2
  local models=("$@")
  local tmpdir; tmpdir=$(mktemp -d)

  echo -e "\n${B}Multi-modelo: ${models[*]}${N}\n"

  local pids=()
  for model in "${models[@]}"; do
    (
      local key; key=$(get_model_key "$model")
      [[ -z "$key" ]] && echo -e "${R}Sin key: $model${N}" > "$tmpdir/$model" && exit 0
      local t_start; t_start=$(date +%s%3N)
      local res; res=$(dispatch "$model" "$user_msg" "$prompt_name" 2>/dev/null) || \
        res="${R}[error]${N}"
      local t_end; t_end=$(date +%s%3N)
      local elapsed=$(( t_end - t_start ))
      {
        echo "ELAPSED:$elapsed"
        echo "$res"
      } > "$tmpdir/$model"
    ) &
    pids+=($!)
  done

  # Esperar todos
  for pid in "${pids[@]}"; do wait "$pid" 2>/dev/null || true; done

  # Mostrar resultados
  for model in "${models[@]}"; do
    local label="${MODEL_LABELS[$model]:-$model}"
    local out="$tmpdir/$model"
    if [[ -f "$out" ]]; then
      local elapsed; elapsed=$(grep '^ELAPSED:' "$out" | cut -d: -f2)
      local content; content=$(grep -v '^ELAPSED:' "$out")
      echo -e "${M}┌─ $label ${DIM}(${elapsed}ms)${N}"
      echo -e "${M}│${N}"
      print_response "$content" | sed 's/^/│ /'
      echo -e "${M}└──────────────────────────────────────────${N}\n"
    fi
  done
  rm -rf "$tmpdir"
}

# ── Guardar respuesta ─────────────────────────────────────
save_response() {
  local content="$1" model="$2"
  local rdir; rdir=$(get_setting "response_dir" "$KR0M_DIR/responses")
  rdir="${rdir/#\~/$HOME}"
  mkdir -p "$rdir"
  local fname="$rdir/$(date +%Y%m%d_%H%M%S)_${model}.md"
  {
    echo "# Kr0m Response"
    echo "**Model:** $model | **Time:** $(date)"
    echo ""
    echo "$content"
  } > "$fname"
  echo -e "${G}[saved] $fname${N}"
}

# ── Settings TUI ─────────────────────────────────────────
settings_menu() {
  while true; do
    clear
    echo -e "${B}${C}[Settings]${N}\n"
    echo -e "  1) Vault method:      $(get_setting vault_method password)"
    echo -e "  2) Tor routing:       $(get_setting tor_enabled false)"
    echo -e "  3) Auto-clear hist:   $(get_setting auto_clear_history false)"
    echo -e "  4) Stealth mode:      $(get_setting stealth_mode false)"
    echo -e "  5) Syntax highlight:  $(get_setting syntax_highlight true)"
    echo -e "  6) Show timer:        $(get_setting show_timer true)"
    echo -e "  7) Default model:     $(get_setting default_model deepseek)"
    echo -e "  8) Default prompt:    $(get_setting default_prompt default)"
    echo -e "  9) Max tokens:        $(get_setting max_tokens 4096)"
    echo -e " 10) Temperature:       $(get_setting temperature 0.7)"
    echo -e " 11) History limit:     $(get_setting history_limit 20)"
    echo -e " 12) Set/update API key"
    echo -e " 13) Verify Tor IP"
    echo -e "  0) Volver"
    echo ""
    echo -ne "Opción: "
    read -r opt
    case "$opt" in
      1) echo -ne "Vault method [password|password+keyfile|uid|password+totp]: "
         read -r v; set_setting "vault_method" "$v" ;;
      2) local cur; cur=$(get_setting tor_enabled false)
         [[ "$cur" == "true" ]] && set_setting tor_enabled false || set_setting tor_enabled true ;;
      3) local cur; cur=$(get_setting auto_clear_history false)
         [[ "$cur" == "true" ]] && set_setting auto_clear_history false || set_setting auto_clear_history true ;;
      4) local cur; cur=$(get_setting stealth_mode false)
         [[ "$cur" == "true" ]] && set_setting stealth_mode false || set_setting stealth_mode true ;;
      5) local cur; cur=$(get_setting syntax_highlight true)
         [[ "$cur" == "true" ]] && set_setting syntax_highlight false || set_setting syntax_highlight true ;;
      6) local cur; cur=$(get_setting show_timer true)
         [[ "$cur" == "true" ]] && set_setting show_timer false || set_setting show_timer true ;;
      7) echo -ne "Modelo [${!MODEL_IDS[*]}]: "; read -r v; set_setting default_model "$v" ;;
      8) echo -ne "Prompt: "; read -r v; set_setting default_prompt "$v" ;;
      9) echo -ne "Max tokens: "; read -r v; set_setting max_tokens "$v" ;;
     10) echo -ne "Temperature [0.0-2.0]: "; read -r v; set_setting temperature "$v" ;;
     11) echo -ne "History limit: "; read -r v; set_setting history_limit "$v" ;;
     12) echo -ne "Modelo: "; read -r m
         echo -ne "API Key: "; read -rs k; echo ""
         vault_write_key "${m^^}_API_KEY" "$k"
         echo -e "${G}Key guardada en vault.${N}" ;;
     13) verify_tor ;;
      0) break ;;
    esac
  done
}

# ── Listar modelos ────────────────────────────────────────
list_models() {
  echo -e "\n${B}Modelos disponibles:${N}\n"
  for k in "${!MODEL_LABELS[@]}"; do
    local key; key=$(get_model_key "$k")
    if [[ -n "$key" ]]; then
      echo -e "  ${G}●${N} ${B}$k${N}\t→ ${MODEL_LABELS[$k]}"
    else
      echo -e "  ${DIM}○ $k\t→ ${MODEL_LABELS[$k]} (sin key)${N}"
    fi
  done | sort
  echo ""
}

# ── Listar prompts ────────────────────────────────────────
list_prompts() {
  echo -e "\n${B}Prompts disponibles:${N}\n"
  for dir in "$PROMPTS_DIR"/*/; do
    local mod; mod=$(basename "$dir")
    echo -e "  ${C}[$mod]${N}"
    for f in "$dir"*.txt 2>/dev/null; do
      [[ -f "$f" ]] || continue
      local name; name=$(basename "$f" .txt)
      echo -e "    ${G}$name${N}"
    done
  done
  echo ""
}

# ── Stats ─────────────────────────────────────────────────
show_stats() {
  local sf="$LOGS_DIR/stats.json"
  [[ ! -f "$sf" ]] && echo "Sin estadísticas." && return
  echo -e "\n${B}Estadísticas:${N}\n"
  jq -r '"  Total requests : \(.requests)",
           "  Total tokens   : \(.total_tokens)",
           "",
           "  Por modelo:",
           (.by_model | to_entries[] |
             "    \(.key): \(.value.requests) req · \(.value.tokens) tokens")
        ' "$sf" 2>/dev/null
  echo ""
}

# ── Ayuda ─────────────────────────────────────────────────
usage() {
cat << 'HELP'
Kr0m v1.0.0 — Multi-model AI CLI · by Krypthane

USO:
  ./kr0m.sh [opciones] "mensaje"
  ./kr0m.sh -i                    modo interactivo
  echo "msg" | ./kr0m.sh          desde stdin

OPCIONES:
  -m <modelo>       Modelo (deepseek, gemini, groq, openai, mistral, anthropic...)
  -M <multi>        Multi-modelo: -M "deepseek,gemini,groq"
  -p <prompt>       Nombre de prompt (ctf, osint, dev, study, recon...)
  -P <"texto">      System prompt directo
  -s                Sesión con historial
  -S <id>           Sesión específica
  -i                Modo interactivo
  -o <file>         Guardar respuesta a archivo
  -t <0-2>          Temperatura
  -n <tokens>       Max tokens
  --raw             Sin system prompt
  --stealth         Sin logs ni historial (esta sesión)
  --tor             Forzar Tor esta sesión
  --set-key <m>     Guardar API key en vault
  -l                Listar modelos
  -L                Listar prompts
  -x                Estadísticas
  --settings        Panel de configuración
  -h                Ayuda

ATAJOS DE MODELO:
  ./kr0m.sh -m groq "pregunta"    # Gratis, rápido
  ./kr0m.sh -m deepseek "código"  # Default
  ./kr0m.sh -M "groq,deepseek,gemini" "compara esto"  # Multi

PROMPTS:
  ctf, re, pwn       → CTF / Reverse engineering
  recon, osint       → Recon & OSINT
  dev, code          → Programación
  study, explain     → Estudio / Explicaciones

HELP
}

# ── Modo interactivo ──────────────────────────────────────
interactive_mode() {
  [[ -z "$SESSION_ID" ]] && SESSION_ID="s$(date +%s)"
  local model="$CURRENT_MODEL"
  local prompt_name="$CURRENT_PROMPT"

  echo -e "${R}${B}"
  banner
  echo -e "${N}"
  echo -e "  Modelo  : ${G}${MODEL_LABELS[$model]:-$model}${N}"
  echo -e "  Prompt  : ${C}$prompt_name${N}"
  echo -e "  Sesión  : ${Y}$SESSION_ID${N}"
  echo -e "  Tor     : $(get_setting tor_enabled false)"
  echo -e "  Stealth : $STEALTH_MODE"
  echo -e "  ${DIM}/help para comandos${N}\n"

  while true; do
    echo -ne "${B}${R}kr0m${N}${B}@${M}${prompt_name}${N} ${C}›${N} "
    local input
    IFS= read -r input

    input="${input#"${input%%[![:space:]]*}"}"
    input="${input%"${input##*[![:space:]]}"}"
    [[ -z "$input" ]] && continue

    case "$input" in
      /exit|/quit|/q) echo -e "${Y}Session ended.${N}"; break ;;
      /help|/?)
        echo -e "${B}Comandos:${N}"
        echo "  /model <m>     Cambiar modelo"
        echo "  /multi <m,m>   Multi-modelo"
        echo "  /prompt <p>    Cambiar prompt"
        echo "  /raw           Toggle sin system prompt"
        echo "  /stealth       Toggle stealth mode"
        echo "  /tor           Toggle Tor"
        echo "  /clear         Limpiar historial"
        echo "  /history       Ver historial"
        echo "  /save          Guardar última respuesta"
        echo "  /models        Listar modelos"
        echo "  /prompts       Listar prompts"
        echo "  /stats         Estadísticas"
        echo "  /settings      Panel de config"
        echo "  /temp <t>      Temperatura"
        echo "  /exit          Salir"
        continue ;;
      /model*)
        local nm; nm=$(echo "$input" | awk '{print $2}')
        [[ -n "${MODEL_IDS[$nm]:-}" ]] && model="$nm" && echo -e "${G}Modelo → ${MODEL_LABELS[$model]}${N}" \
          || echo "Modelos: ${!MODEL_IDS[*]}"
        continue ;;
      /multi*)
        local ml; ml=$(echo "$input" | awk '{print $2}')
        [[ -n "$ml" ]] && MULTI_MODELS="$ml" && echo -e "${G}Multi-modelo: $ml${N}"
        continue ;;
      /prompt*)
        local np; np=$(echo "$input" | awk '{print $2}')
        prompt_name="$np"
        echo -e "${G}Prompt → $prompt_name${N}"
        continue ;;
      /raw) $RAW_MODE && RAW_MODE=false || RAW_MODE=true
            echo -e "Raw mode: $RAW_MODE"; continue ;;
      /stealth) $STEALTH_MODE && STEALTH_MODE=false || STEALTH_MODE=true
                echo -e "Stealth: $STEALTH_MODE"; continue ;;
      /tor) local cur; cur=$(get_setting tor_enabled false)
            [[ "$cur" == "true" ]] && set_setting tor_enabled false || set_setting tor_enabled true
            setup_tor; continue ;;
      /clear) rm -f "$(get_hfile)"; echo -e "${G}Historial limpiado.${N}"; continue ;;
      /history)
        local hf; hf=$(get_hfile)
        [[ -f "$hf" ]] && jq -r '.[] | "\(.role): \(.content[0:100])..."' "$hf" \
          || echo "Sin historial."
        continue ;;
      /models) list_models; continue ;;
      /prompts) list_prompts; continue ;;
      /stats) show_stats; continue ;;
      /settings) settings_menu; continue ;;
      /temp*)
        local nt; nt=$(echo "$input" | awk '{print $2}')
        [[ -n "$nt" ]] && set_setting temperature "$nt" && echo -e "${G}Temperatura: $nt${N}"
        continue ;;
    esac

    # Timer start
    local t_start; t_start=$(date +%s%3N)
    echo -ne "${DIM}▸ thinking...${N}"

    local response
    if [[ -n "${MULTI_MODELS:-}" ]]; then
      echo -e "\r\033[K"
      IFS=',' read -ra mlist <<< "$MULTI_MODELS"
      dispatch_multi "$input" "$prompt_name" "${mlist[@]}"
      LAST_RESPONSE="[multi-model]"
    else
      # fd3 para tokens
      local tok_tmp; tok_tmp=$(mktemp)
      exec 3>"$tok_tmp"
      response=$(dispatch "$model" "$input" "$prompt_name") || {
        echo -e "\r${R}Error al obtener respuesta.${N}"
        exec 3>&-; rm -f "$tok_tmp"; continue
      }
      exec 3>&-
      local tokens; tokens=$(cat "$tok_tmp" 2>/dev/null || echo 0)
      rm -f "$tok_tmp"
      LAST_RESPONSE="$response"

      local t_end; t_end=$(date +%s%3N)
      local elapsed=$(( t_end - t_start ))
      local show_timer; show_timer=$(get_setting show_timer true)

      echo -e "\r\033[K"
      echo -e "${DIM}─── ${MODEL_LABELS[$model]:-$model} $(
        [[ "$show_timer" == "true" ]] && echo "· ${elapsed}ms · ${tokens}tk"
      ) ───${N}"
      print_response "$response"
      echo -e "${DIM}────────────────────────────────────────────${N}"
    fi

    # ¿Guardar?
    local save_r; save_r=$(get_setting save_responses false)
    [[ "$save_r" == "true" ]] && save_response "$LAST_RESPONSE" "$model"
  done
}

# ── MAIN ──────────────────────────────────────────────────
load_settings

CURRENT_MODEL=$(get_setting default_model deepseek)
CURRENT_PROMPT=$(get_setting default_prompt default)
MODEL_OVERRIDE=""
MULTI_MODELS=""
LAST_RESPONSE=""
INTERACTIVE=false
SAVE_TO=""
OUTPUT_FILE=""
STDIN_DATA=""

# Flags de privacidad desde settings
[[ "$(get_setting stealth_mode false)" == "true" ]] && STEALTH_MODE=true

# Args
while [[ $# -gt 0 ]]; do
  case "$1" in
    -m) CURRENT_MODEL="$2"; shift 2 ;;
    -M) MULTI_MODELS="$2"; shift 2 ;;
    -p) CURRENT_PROMPT="$2"; shift 2 ;;
    -P) SYSTEM_PROMPT_OVERRIDE="$2"; RAW_MODE=false; shift 2 ;;
    -s) SESSION_ID="default"; shift ;;
    -S) SESSION_ID="$2"; shift 2 ;;
    -i) INTERACTIVE=true; shift ;;
    -o) OUTPUT_FILE="$2"; shift 2 ;;
    -t) set_setting temperature "$2"; shift 2 ;;
    -n) set_setting max_tokens "$2"; shift 2 ;;
    --raw) RAW_MODE=true; shift ;;
    --stealth) STEALTH_MODE=true; shift ;;
    --tor) set_setting tor_enabled true; shift ;;
    --set-key) echo -ne "API Key para $2: "; read -rs k; echo ""
               vault_write_key "${2^^}_API_KEY" "$k"
               echo -e "${G}Guardada en vault.${N}"; exit 0 ;;
    -l) list_models; exit 0 ;;
    -L) list_prompts; exit 0 ;;
    -x) show_stats; exit 0 ;;
    --settings) settings_menu; exit 0 ;;
    -h|--help) usage; exit 0 ;;
    --) shift; break ;;
    -*) echo -e "${R}Opción desconocida: $1${N}"; exit 1 ;;
    *) break ;;
  esac
done

# Setup Tor si está activo
setup_tor

# Init vault y cargar keys
vault_init
load_keys

# Modo interactivo
$INTERACTIVE && interactive_mode && exit 0

# Stdin pipe
if [[ ! -t 0 ]]; then
  STDIN_DATA=$(cat)
  if [[ $# -gt 0 ]]; then
    USER_MESSAGE="$*\n\n$STDIN_DATA"
  else
    USER_MESSAGE="$STDIN_DATA"
  fi
elif [[ $# -gt 0 ]]; then
  USER_MESSAGE="$*"
else
  echo -e "${Y}Uso:${N} ./kr0m.sh \"mensaje\" | ./kr0m.sh -i | ./kr0m.sh -h"
  exit 1
fi

# Timer
T_START=$(date +%s%3N)

if [[ -n "$MULTI_MODELS" ]]; then
  IFS=',' read -ra MLIST <<< "$MULTI_MODELS"
  dispatch_multi "$USER_MESSAGE" "$CURRENT_PROMPT" "${MLIST[@]}"
else
  TOK_TMP=$(mktemp)
  exec 3>"$TOK_TMP"
  RESPONSE=$(dispatch "$CURRENT_MODEL" "$USER_MESSAGE" "$CURRENT_PROMPT") || exit 1
  exec 3>&-
  TOKENS=$(cat "$TOK_TMP" 2>/dev/null || echo 0)
  rm -f "$TOK_TMP"

  T_END=$(date +%s%3N)
  ELAPSED=$(( T_END - T_START ))
  SHOW_TIMER=$(get_setting show_timer true)
  LABEL="${MODEL_LABELS[$CURRENT_MODEL]:-$CURRENT_MODEL}"

  echo -e "\n${DIM}─── $LABEL $([[ "$SHOW_TIMER" == "true" ]] && echo "· ${ELAPSED}ms · ${TOKENS}tk") ───${N}"
  print_response "$RESPONSE"
  echo -e "${DIM}────────────────────────────────────────────${N}\n"

  # Guardar a archivo si se pidió
  [[ -n "$OUTPUT_FILE" ]] && {
    echo "$RESPONSE" > "$OUTPUT_FILE"
    echo -e "${G}[saved] $OUTPUT_FILE${N}"
  }
fi

