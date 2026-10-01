#!/usr/bin/env bash
# =============================================================================
# install.sh - Instalador de Odoo en local con un solo comando (Linux)
# Autor: @Carlitos6712 (https://github.com/Carlitos6712)
# Licencia: MIT
#
# Uso (copia y pega en la terminal):
#   curl -fsSL https://raw.githubusercontent.com/Carlitos6712/odoo-local/main/install.sh | bash
#
# Qué hace:
#   1. Instala git y curl si faltan.
#   2. Descarga el proyecto en ~/odoo-local (o lo actualiza si ya existe).
#   3. Crea el comando "odoo-local" para usarlo desde cualquier carpeta.
#   4. Ejecuta "./odoo.sh setup" (instala Docker si falta) y "./odoo.sh start".
#
# Variables opcionales:
#   ODOO_LOCAL_DIR   carpeta de instalación (por defecto: ~/odoo-local)
#   ODOO_LOCAL_REPO  repositorio a clonar (por defecto: el oficial en GitHub)
# =============================================================================

set -euo pipefail

# Todo el script vive dentro de funciones y solo se ejecuta en la última línea.
# Así, si la descarga con curl se corta a mitad, bash no ejecuta medio instalador.

REPO="${ODOO_LOCAL_REPO:-https://github.com/Carlitos6712/odoo-local.git}"
DESTINO="${ODOO_LOCAL_DIR:-$HOME/odoo-local}"
# Dónde se crea el comando global "odoo-local" y qué archivo de la terminal
# se usa para añadirlo al PATH (cambiables solo para pruebas).
BIN_DIR="${ODOO_LOCAL_BIN:-$HOME/.local/bin}"
RC_FILE="${ODOO_LOCAL_RC:-$HOME/.bashrc}"

if [ -t 1 ]; then
  VERDE=$'\033[0;32m'; AMARILLO=$'\033[0;33m'; ROJO=$'\033[0;31m'; AZUL=$'\033[0;34m'; RESET=$'\033[0m'
else
  VERDE=""; AMARILLO=""; ROJO=""; AZUL=""; RESET=""
fi
ok()    { printf '%s[OK]%s %s\n' "$VERDE" "$RESET" "$*"; }
aviso() { printf '%s[AVISO]%s %s\n' "$AMARILLO" "$RESET" "$*"; }
info()  { printf '%s[INFO]%s %s\n' "$AZUL" "$RESET" "$*"; }
error() { printf '%s[ERROR]%s %s\n' "$ROJO" "$RESET" "$*" >&2; exit 1; }

if [ "$(id -u)" -eq 0 ]; then SUDO=""; else SUDO="sudo"; fi

# -----------------------------------------------------------------------------
# instalar_si_falta
# Qué hace:   instala un programa con el gestor de paquetes de tu distribución
#             si todavía no está instalado.
# Parámetros: $1 = nombre del programa (y del paquete), por ejemplo "git".
# Ejemplo:    instalar_si_falta git
# Por debajo: "sudo apt-get install -y", "sudo dnf install -y", "sudo pacman -S"
#             o "sudo zypper install", según la distribución.
# -----------------------------------------------------------------------------
instalar_si_falta() {
  command -v "$1" >/dev/null 2>&1 && return 0
  info "Instalando $1 (se pedirá tu contraseña de administrador)..."
  if command -v apt-get >/dev/null 2>&1; then
    $SUDO apt-get update && $SUDO apt-get install -y "$1"
  elif command -v dnf >/dev/null 2>&1; then
    $SUDO dnf install -y "$1"
  elif command -v pacman >/dev/null 2>&1; then
    $SUDO pacman -S --needed --noconfirm "$1"
  elif command -v zypper >/dev/null 2>&1; then
    $SUDO zypper --non-interactive install "$1"
  else
    error "No sé instalar $1 en tu distribución. Instálalo a mano y repite el comando."
  fi
  ok "$1 instalado."
}

# -----------------------------------------------------------------------------
# descargar_proyecto
# Qué hace:   clona el proyecto en DESTINO. Si ya existe una copia, la
#             actualiza en vez de fallar. Si la carpeta existe pero es otra
#             cosa, se detiene sin tocarla.
# Parámetros: ninguno (usa REPO y DESTINO).
# Ejemplo:    descargar_proyecto
# Por debajo: "git clone" o "git pull --ff-only".
# -----------------------------------------------------------------------------
descargar_proyecto() {
  if [ -f "$DESTINO/odoo.sh" ] && [ -d "$DESTINO/.git" ]; then
    info "El proyecto ya está en $DESTINO. Buscando actualizaciones..."
    git -C "$DESTINO" pull --ff-only \
      || aviso "No se pudo actualizar (¿cambiaste archivos del proyecto?). Se usa la versión que ya tienes."
  elif [ -e "$DESTINO" ]; then
    error "La carpeta $DESTINO ya existe y no es este proyecto. Muévela o bórrala, o elige otra con: ODOO_LOCAL_DIR=/otra/carpeta"
  else
    info "Descargando el proyecto en $DESTINO..."
    git clone "$REPO" "$DESTINO" || error "No se pudo descargar el proyecto. Revisa tu conexión a Internet."
  fi
  ok "Proyecto listo en $DESTINO"
}

# -----------------------------------------------------------------------------
# crear_comando_global
# Qué hace:   crea el comando "odoo-local" para usar el proyecto desde cualquier
#             carpeta (por ejemplo, "odoo-local start") sin hacer "cd" antes.
#             Si ya existe otro programa con ese nombre, no lo toca.
# Parámetros: ninguno (usa DESTINO, BIN_DIR y RC_FILE).
# Ejemplo:    crear_comando_global
# Por debajo: "ln -sfn" de odoo.sh en ~/.local/bin/odoo-local y, si esa
#             carpeta no está en el PATH, añade una línea a ~/.bashrc.
# -----------------------------------------------------------------------------
crear_comando_global() {
  local enlace="$BIN_DIR/odoo-local"
  if [ -e "$enlace" ] && [ ! -L "$enlace" ]; then
    aviso "Ya existe $enlace y no es de este proyecto: no se crea el comando 'odoo-local'."
    return 0
  fi
  mkdir -p "$BIN_DIR"
  ln -sfn "$DESTINO/odoo.sh" "$enlace"
  ok "Comando 'odoo-local' disponible (por ejemplo: odoo-local status)."

  # Ubuntu y Debian añaden ~/.local/bin al PATH al iniciar sesión, pero solo si
  # la carpeta ya existía. Por si acaso, lo añadimos a .bashrc una sola vez.
  case ":$PATH:" in
    *":$BIN_DIR:"*) ;;
    *)
      if ! grep -qs "# odoo-local: PATH" "$RC_FILE"; then
        printf '\n# odoo-local: PATH\nexport PATH="%s:$PATH"\n' "$BIN_DIR" >> "$RC_FILE"
      fi
      aviso "Abre una terminal nueva para poder usar el comando 'odoo-local'."
      ;;
  esac
}

# -----------------------------------------------------------------------------
# main
# Qué hace:   ejecuta la instalación completa.
# Parámetros: ninguno.
# Ejemplo:    main
# Por debajo: "./odoo.sh setup" y "./odoo.sh start". Con "curl ... | bash"
#             el teclado no llega al script (llega el propio script), así que
#             conectamos odoo.sh a la terminal (/dev/tty) para que pueda
#             hacerte preguntas.
# -----------------------------------------------------------------------------
main() {
  [ "$(uname -s)" = "Linux" ] || error "Este instalador es solo para Linux."
  info "Instalando Odoo en local - por @Carlitos6712"
  instalar_si_falta curl
  instalar_si_falta git
  descargar_proyecto
  crear_comando_global
  cd "$DESTINO"

  # Comprobamos que /dev/tty se puede abrir de verdad (no basta con que exista).
  if { : < /dev/tty; } 2>/dev/null; then
    ./odoo.sh setup < /dev/tty
    ./odoo.sh start < /dev/tty
  else
    ./odoo.sh setup
    ./odoo.sh start
  fi

  ok "Instalación terminada. A partir de ahora, desde cualquier carpeta:"
  info "  odoo-local help      (o, dentro de $DESTINO: ./odoo.sh help)"
}

main "$@"
