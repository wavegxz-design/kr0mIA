<div align="center">

```
    ██╗  ██╗██████╗  ██████╗ ███╗   ███╗
    ██║ ██╔╝██╔══██╗██╔═████╗████╗ ████║
    █████╔╝ ██████╔╝██║██╔██║██╔████╔██║
    ██╔═██╗ ██╔══██╗████╔╝██║██║╚██╔╝██║
    ██║  ██╗██║  ██║╚██████╔╝██║ ╚═╝ ██║
    ╚═╝  ╚═╝╚═╝  ╚═╝ ╚═════╝ ╚═╝     ╚═╝
```

**Multi-model AI CLI · Privacy-first · Red Team Edition**

![License](https://img.shields.io/badge/license-MIT-red)
![Platform](https://img.shields.io/badge/platform-Linux%20%7C%20Kali-blue)
![Shell](https://img.shields.io/badge/shell-bash-green)

</div>

## Features

- **7 modelos de AI** — OpenAI, DeepSeek, Gemini, Mistral, Anthropic, Groq, Together
- **Vault AES-256-GCM** — API keys encriptadas localmente (PBKDF2 600k iter)
- **Tor routing** — todas las requests via torsocks
- **Multi-modelo paralelo** — la misma pregunta a N modelos simultáneamente
- **Prompts especializados** — CTF, RE, OSINT, Dev, Bash, Study, Recon
- **Stealth mode** — sin logs, sin historial
- **Syntax highlighting** — bloques de código con bat
- **Timer por respuesta** — latencia visible
- **Sesiones con historial** — conversaciones persistentes
- **Settings TUI** — todo configurable sin editar archivos

## Instalación

```bash
bash setup-kr0m.sh

# Opcional: instalar globalmente
sudo ./install.sh
```

## Inicio rápido

```bash
# Configurar key en vault (encriptado)
./kr0m.sh --set-key deepseek

# Primera consulta
./kr0m.sh "qué es un buffer overflow"

# Modo interactivo
./kr0m.sh -i

# Otro modelo
./kr0m.sh -m groq "dame un one-liner bash para monitorear puertos abiertos"

# Con prompt especializado
./kr0m.sh -p ctf "analiza este binario: file challenge && checksec challenge"

# Multi-modelo paralelo
./kr0m.sh -M "deepseek,gemini,groq" "explica ASLR"

# Con Tor
./kr0m.sh --tor -m deepseek "consulta privada"

# Desde stdin
cat exploit.py | ./kr0m.sh -p pwn "revisa este exploit"

# Guardar respuesta
./kr0m.sh -o respuesta.md "explica ROP chains"
```

## Modelos

| Alias | Modelo | Gratis |
|-------|--------|--------|
| `deepseek` | DeepSeek V3 | No |
| `deepseek-r1` | DeepSeek R1 (reasoning) | No |
| `gemini` | Gemini 2.0 Flash | Sí (tier) |
| `gemini-pro` | Gemini 1.5 Pro | No |
| `openai` | GPT-4o-mini | No |
| `openai-large` | GPT-4o | No |
| `mistral` | Mistral Large | No |
| `anthropic` | Claude Haiku | No |
| `groq` | Llama 3.3 70B | **Sí** |
| `groq-fast` | Llama 3.1 8B | **Sí** |
| `together` | Mixtral 8x7B | No |

> **Tip**: usa `groq` o `groq-fast` para tests, es gratis.

## Prompts

```bash
./kr0m.sh -L          # listar todos

# CTF & Security
-p ctf        → CTF solver completo
-p re         → Reverse engineering
-p pwn        → Binary exploitation
-p recon      → Reconnaissance
-p osint      → OSINT investigation

# Dev
-p dev        → Senior engineer
-p code       → Solo código, sin explicación
-p bash       → Bash expert

# Estudio
-p study      → Explicaciones técnicas
-p explain    → Definición rápida
-p research   → Investigación profunda
```

## Comandos interactivos (`-i`)

| Comando | Acción |
|---------|--------|
| `/model groq` | Cambiar modelo |
| `/multi deepseek,gemini` | Activar multi-modelo |
| `/prompt ctf` | Cambiar prompt |
| `/stealth` | Toggle stealth mode |
| `/tor` | Toggle Tor |
| `/raw` | Toggle sin system prompt |
| `/save` | Guardar última respuesta |
| `/clear` | Limpiar historial |
| `/stats` | Estadísticas de uso |
| `/settings` | Panel de configuración |

## Privacidad

```bash
# Vault — encripta todas las keys
./kr0m.sh --set-key deepseek   # guarda en vault AES-256-GCM

# Tor — todas las requests via Tor
./kr0m.sh --tor "consulta"
# O activar permanente:
./kr0m.sh --settings → Tor routing: true

# Stealth — sin logs, sin historial
./kr0m.sh --stealth "consulta"

# Auto-clear — borra historial automáticamente
# Configurable en --settings
```

## Seguridad del vault

- Encriptación: AES-256-GCM
- KDF: PBKDF2-SHA256 · 600,000 iteraciones (OWASP 2024)
- Salt: 32 bytes aleatorios por instalación
- Métodos de desbloqueo: password / password+keyfile / UID / password+TOTP

## Licencia

MIT © 2025 Krypthane
