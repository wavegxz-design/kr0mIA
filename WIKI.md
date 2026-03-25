# Kr0m — Wiki

## Arquitectura

```
kr0m/
├── kr0m.sh          ← CLI principal (todo en uno)
├── start.sh         ← wrapper de inicio
├── install.sh       ← instalación global
├── .env             ← keys en plano (fallback)
├── .env.example
├── vault/
│   ├── kr0m.vault   ← keys encriptadas AES-256-GCM
│   └── .salt        ← salt para KDF
├── .kr0m/
│   ├── settings.json ← configuración
│   └── kr0m.key     ← keyfile opcional
├── prompts/
│   ├── ctf/         ← ctf.txt, re.txt, pwn.txt
│   ├── osint/       ← recon.txt, osint.txt
│   ├── dev/         ← dev.txt, code.txt, bash.txt
│   ├── study/       ← study.txt, explain.txt, research.txt
│   └── custom/      ← tus propios prompts
├── history/         ← sesiones (JSON por sesión)
├── logs/
│   └── stats.json   ← estadísticas de uso
└── README.md
```

## Agregar un prompt custom

```bash
# Crear archivo en prompts/custom/
cat > prompts/custom/miprompt.txt << 'EOF'
Tu system prompt aquí.
EOF

# Usar
./kr0m.sh -p miprompt "mensaje"
```

## Agregar un modelo custom (OpenAI-compatible)

Edita `kr0m.sh` y agrega en los arrays:
```bash
MODEL_IDS[mimodelo]="model-id-exacto"
MODEL_BASES[mimodelo]="https://api.miproveedor.com/v1/chat/completions"
MODEL_LABELS[mimodelo]="Mi Modelo Custom"
```
Luego en `get_model_key()`:
```bash
mimodelo) echo "$MI_API_KEY" ;;
```

## Backup del vault

```bash
# Backup encriptado
cp vault/kr0m.vault ~/backup/kr0m.vault.bak
cp vault/.salt ~/backup/kr0m.salt.bak
cp .kr0m/kr0m.key ~/backup/kr0m.key.bak  # si usas keyfile
```

## Rotar API key

```bash
./kr0m.sh --set-key deepseek
# Ingresa la nueva key
```
