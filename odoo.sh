#!/usr/bin/env bash
# =============================================================================
# odoo.sh - Gestiona Odoo en local con Docker (Linux y macOS)
# Autor: @Carlitos6712 (https://github.com/Carlitos6712)
# Licencia: MIT
#
# Uso:  ./odoo.sh <comando> [argumentos]
#       ./odoo.sh help        -> lista todos los comandos
#
# El equivalente para Windows es odoo.ps1 (mismos comandos).
# =============================================================================

# -e: salir si un comando falla; -u: error si se usa una variable sin definir;
# -o pipefail: un fallo en medio de una tubería (a | b) también cuenta como fallo.
set -euo pipefail

# Trabajamos siempre desde la carpeta del script, aunque se llame desde otro sitio,
# para que docker compose encuentre docker-compose.yml y .env.
cd "$(dirname "$0")"

# -----------------------------------------------------------------------------
# Colores y mensajes
# Solo usamos colores si la salida es una terminal; así los logs redirigidos
# a un archivo no se llenan de códigos raros.
# -----------------------------------------------------------------------------
if [ -t 1 ]; then
  VERDE=$'\033[0;32m'; AMARILLO=$'\033[0;33m'; ROJO=$'\033[0;31m'
  AZUL=$'\033[0;34m'; NEGRITA=$'\033[1m'; RESET=$'\033[0m'
else
  VERDE=""; AMARILLO=""; ROJO=""; AZUL=""; NEGRITA=""; RESET=""
fi

ok()    { printf '%s[OK]%s %s\n' "$VERDE" "$RESET" "$*"; }
aviso() { printf '%s[AVISO]%s %s\n' "$AMARILLO" "$RESET" "$*"; }
info()  { printf '%s[INFO]%s %s\n' "$AZUL" "$RESET" "$*"; }
# error: muestra el mensaje en rojo por la salida de errores y termina el script.
error() { printf '%s[ERROR]%s %s\n' "$ROJO" "$RESET" "$*" >&2; exit 1; }

# -----------------------------------------------------------------------------
# cargar_env
# Qué hace:   lee las variables de .env (puerto, usuario de base de datos...).
# Parámetros: ninguno.
# Ejemplo:    cargar_env; echo "$ODOO_PORT"
# Por debajo: "source .env" con exportación automática (set -a).
# -----------------------------------------------------------------------------
cargar_env() {
  if [ -f .env ]; then
    set -a
    # shellcheck disable=SC1091
    . ./.env
    set +a
  fi
  # Valores por defecto por si .env no existe o le falta alguna variable.
  ODOO_PORT="${ODOO_PORT:-8069}"
  DB_USER="${DB_USER:-odoo}"
}

# -----------------------------------------------------------------------------
# comprobar_docker
# Qué hace:   verifica que Docker y Docker Compose v2 están instalados y que
#             Docker está arrancado. Si no, explica cómo arreglarlo y sale.
# Parámetros: ninguno.
# Ejemplo:    comprobar_docker
# Por debajo: "docker --version", "docker compose version" y "docker info".
# -----------------------------------------------------------------------------
comprobar_docker() {
  if ! command -v docker >/dev/null 2>&1; then
    error "Docker no está instalado. Instala Docker Desktop: https://docs.docker.com/get-docker/"
  fi
  if ! docker compose version >/dev/null 2>&1; then
    error "Falta Docker Compose v2 (el comando 'docker compose'). Actualiza Docker Desktop o instala el plugin: https://docs.docker.com/compose/install/"
  fi
  local salida
  if ! salida="$(docker info 2>&1)"; then
    # Distinguimos el caso típico de Linux: Docker funciona, pero tu usuario
    # no tiene permiso para hablar con él.
    if printf '%s' "$salida" | grep -qi "permission denied"; then
      error "Tu usuario no tiene permiso para usar Docker. Ejecuta: sudo usermod -aG docker \$USER  y después cierra sesión y vuelve a entrar (o reinicia)."
    fi
    error "Docker no está arrancado. Abre Docker Desktop (o en Linux: sudo systemctl start docker) y espera a que diga 'running'."
  fi
}

# -----------------------------------------------------------------------------
# odoo_corriendo
# Qué hace:   devuelve éxito (0) si el contenedor de Odoo está en marcha.
# Parámetros: ninguno.
# Ejemplo:    if odoo_corriendo; then echo "sí"; fi
# Por debajo: "docker compose ps --status running --services".
# -----------------------------------------------------------------------------
odoo_corriendo() {
  docker compose ps --status running --services 2>/dev/null | grep -qx odoo
}

# -----------------------------------------------------------------------------
# puerto_ocupado
# Qué hace:   comprueba si algo ya escucha en un puerto local.
# Parámetros: $1 = número de puerto.
# Ejemplo:    puerto_ocupado 8069 && echo "ocupado"
# Por debajo: intenta abrir una conexión con /dev/tcp (incluido en bash,
#             funciona igual en Linux y macOS sin instalar nada).
# -----------------------------------------------------------------------------
puerto_ocupado() {
  (exec 3<>"/dev/tcp/127.0.0.1/$1") 2>/dev/null
}

# -----------------------------------------------------------------------------
# esperar_odoo
# Qué hace:   espera hasta que Odoo responda por HTTP (máximo 3 minutos).
#             El primer arranque tarda más porque Odoo prepara sus archivos.
# Parámetros: ninguno (usa ODOO_PORT).
# Ejemplo:    esperar_odoo
# Por debajo: "curl http://localhost:PUERTO/web/login" cada 3 segundos.
# -----------------------------------------------------------------------------
esperar_odoo() {
  local url="http://localhost:${ODOO_PORT}/web/login" intentos=60
  printf 'Esperando a que Odoo responda'
  while [ "$intentos" -gt 0 ]; do
    if curl -fsS -o /dev/null "$url" 2>/dev/null; then
      printf '\n'
      return 0
    fi
    printf '.'
    sleep 3
    intentos=$((intentos - 1))
  done
  printf '\n'
  return 1
}

# -----------------------------------------------------------------------------
# cmd_setup
# Qué hace:   prepara todo para el primer uso: comprueba Docker, crea .env
#             desde .env.example si no existe y descarga las imágenes.
# Parámetros: ninguno.
# Ejemplo:    ./odoo.sh setup
# Por debajo: "cp .env.example .env" y "docker compose pull".
# -----------------------------------------------------------------------------
cmd_setup() {
  comprobar_docker
  ok "Docker está instalado y arrancado."
  if [ -f .env ]; then
    ok ".env ya existe; no se modifica."
  else
    [ -f .env.example ] || error "No encuentro .env.example. ¿Estás en la carpeta del repositorio?"
    cp .env.example .env
    ok ".env creado a partir de .env.example."
  fi
  mkdir -p addons backups
  info "Descargando imágenes de Odoo y PostgreSQL (la primera vez puede tardar varios minutos)..."
  docker compose pull || error "No se pudieron descargar las imágenes. Revisa tu conexión a Internet y que ODOO_VERSION/POSTGRES_VERSION en .env sean válidas."
  ok "Todo listo. Ahora ejecuta: ./odoo.sh start"
}

# -----------------------------------------------------------------------------
# cmd_start
# Qué hace:   levanta Odoo y PostgreSQL en segundo plano, espera a que Odoo
#             responda y muestra la URL.
# Parámetros: ninguno.
# Ejemplo:    ./odoo.sh start
# Por debajo: "docker compose up -d".
# -----------------------------------------------------------------------------
cmd_start() {
  comprobar_docker
  cargar_env
  [ -f .env ] || aviso "No existe .env; se usan valores por defecto. Ejecuta ./odoo.sh setup para crearlo."
  # Si Odoo ya está corriendo, el puerto lo ocupa él mismo: no es un problema.
  if ! odoo_corriendo && puerto_ocupado "$ODOO_PORT"; then
    error "El puerto $ODOO_PORT ya está ocupado por otro programa (¿otro Odoo?). Ciérralo o cambia ODOO_PORT en .env (por ejemplo, 8070)."
  fi
  info "Arrancando contenedores..."
  docker compose up -d || error "No se pudieron arrancar los contenedores. Mira los detalles con: ./odoo.sh logs"
  if esperar_odoo; then
    ok "Odoo está listo: ${NEGRITA}http://localhost:${ODOO_PORT}${RESET}"
  else
    error "Odoo no responde tras 3 minutos. Revisa los errores con: ./odoo.sh logs"
  fi
}

# -----------------------------------------------------------------------------
# cmd_stop
# Qué hace:   apaga los contenedores. Los datos se conservan en los volúmenes.
# Parámetros: ninguno.
# Ejemplo:    ./odoo.sh stop
# Por debajo: "docker compose stop".
# -----------------------------------------------------------------------------
cmd_stop() {
  comprobar_docker
  docker compose stop
  ok "Odoo apagado. Tus datos siguen guardados."
}

# -----------------------------------------------------------------------------
# cmd_restart
# Qué hace:   reinicia solo Odoo. Útil tras cambiar código Python de un módulo
#             o el archivo config/odoo.conf.
# Parámetros: ninguno.
# Ejemplo:    ./odoo.sh restart
# Por debajo: "docker compose restart odoo".
# -----------------------------------------------------------------------------
cmd_restart() {
  comprobar_docker
  cargar_env
  odoo_corriendo || error "Odoo no está arrancado. Usa: ./odoo.sh start"
  docker compose restart odoo
  if esperar_odoo; then
    ok "Odoo reiniciado: http://localhost:${ODOO_PORT}"
  else
    error "Odoo no responde tras reiniciar. Revisa los errores con: ./odoo.sh logs"
  fi
}

# -----------------------------------------------------------------------------
# cmd_status
# Qué hace:   muestra si los contenedores están corriendo.
# Parámetros: ninguno.
# Ejemplo:    ./odoo.sh status
# Por debajo: "docker compose ps".
# -----------------------------------------------------------------------------
cmd_status() {
  comprobar_docker
  cargar_env
  docker compose ps
  if odoo_corriendo; then
    ok "Odoo está corriendo en http://localhost:${ODOO_PORT}"
  else
    aviso "Odoo está apagado. Arráncalo con: ./odoo.sh start"
  fi
}

# -----------------------------------------------------------------------------
# cmd_logs
# Qué hace:   muestra los logs de Odoo en vivo. Pulsa Ctrl+C para salir
#             (Odoo sigue funcionando).
# Parámetros: ninguno.
# Ejemplo:    ./odoo.sh logs
# Por debajo: "docker compose logs -f --tail 100 odoo".
# -----------------------------------------------------------------------------
cmd_logs() {
  comprobar_docker
  info "Mostrando logs de Odoo. Pulsa Ctrl+C para salir."
  docker compose logs -f --tail 100 odoo
}

# -----------------------------------------------------------------------------
# cmd_shell
# Qué hace:   abre una terminal dentro del contenedor de Odoo. Escribe "exit"
#             para salir.
# Parámetros: ninguno.
# Ejemplo:    ./odoo.sh shell
# Por debajo: "docker compose exec odoo bash".
# -----------------------------------------------------------------------------
cmd_shell() {
  comprobar_docker
  odoo_corriendo || error "Odoo no está arrancado. Usa: ./odoo.sh start"
  info "Terminal dentro del contenedor de Odoo. Escribe 'exit' para salir."
  docker compose exec odoo bash
}

# -----------------------------------------------------------------------------
# cmd_update
# Qué hace:   actualiza un módulo de addons/ en una base de datos (aplica
#             cambios en modelos, vistas, datos XML...) y reinicia Odoo.
# Parámetros: $1 = nombre del módulo (carpeta en addons/)
#             $2 = nombre de la base de datos
# Ejemplo:    ./odoo.sh update mi_modulo mi_empresa
# Por debajo: ejecuta "odoo -u MODULO -d BASE --stop-after-init --no-http"
#             dentro del contenedor (sin HTTP para no chocar con el servidor
#             que ya usa el puerto) y luego "docker compose restart odoo".
# -----------------------------------------------------------------------------
cmd_update() {
  local modulo="${1:-}" base="${2:-}"
  [ -n "$modulo" ] && [ -n "$base" ] || error "Uso: ./odoo.sh update <modulo> <base_de_datos>"
  [ -d "addons/$modulo" ] || error "No existe la carpeta addons/$modulo. Revisa el nombre del módulo."
  comprobar_docker
  cargar_env
  odoo_corriendo || error "Odoo no está arrancado. Usa: ./odoo.sh start"
  info "Actualizando el módulo '$modulo' en la base de datos '$base'..."
  # Las comillas simples hacen que $HOST, $USER y $PASSWORD se lean DENTRO del
  # contenedor, donde docker-compose.yml las define con los datos de PostgreSQL.
  docker compose exec -T odoo sh -c \
    'odoo -c /etc/odoo/odoo.conf --db_host "$HOST" --db_user "$USER" --db_password "$PASSWORD" -d "$1" -u "$2" --stop-after-init --no-http' \
    _ "$base" "$modulo" \
    || error "Falló la actualización. Causas típicas: la base '$base' no existe, el módulo no está instalado en ella o hay un error en su código (lee el mensaje de arriba)."
  docker compose restart odoo >/dev/null
  esperar_odoo || error "Odoo no responde tras la actualización. Revisa: ./odoo.sh logs"
  ok "Módulo '$modulo' actualizado en '$base'."
}

# -----------------------------------------------------------------------------
# cmd_new_module
# Qué hace:   crea un módulo de ejemplo mínimo en addons/<nombre> con
#             __manifest__.py, un modelo, sus vistas, un menú y permisos.
# Parámetros: $1 = nombre técnico del módulo (minúsculas, números y "_",
#             empezando por letra). Ejemplo: biblioteca
# Ejemplo:    ./odoo.sh new-module biblioteca
# Por debajo: solo crea archivos en addons/; no ejecuta Docker. Después hay
#             que reiniciar Odoo y "Actualizar lista de aplicaciones".
# -----------------------------------------------------------------------------
cmd_new_module() {
  local nombre="${1:-}"
  [ -n "$nombre" ] || error "Uso: ./odoo.sh new-module <nombre>   (ejemplo: ./odoo.sh new-module biblioteca)"
  # Odoo usa el nombre de la carpeta como identificador técnico: debe ser un
  # nombre válido de paquete Python.
  [[ "$nombre" =~ ^[a-z][a-z0-9_]*$ ]] || error "Nombre no válido: '$nombre'. Usa solo minúsculas, números y '_', empezando por letra (ejemplo: mi_modulo)."
  local dir="addons/$nombre"
  [ ! -e "$dir" ] || error "Ya existe $dir. Elige otro nombre."

  # Nombres derivados: modelo técnico (biblioteca.item) y título legible (Biblioteca).
  local modelo="${nombre}.item" titulo
  titulo="$(printf '%s' "$nombre" | tr '_' ' ')"
  titulo="$(printf '%s' "${titulo:0:1}" | tr '[:lower:]' '[:upper:]')${titulo:1}"
  local id_modelo="${nombre}_item"
  # Nombre de clase Python en CamelCase: biblioteca_libros -> BibliotecaLibrosItem
  local clase
  clase="$(printf '%s' "$nombre" | awk -F_ '{for(i=1;i<=NF;i++) printf "%s%s", toupper(substr($i,1,1)), substr($i,2)}')Item"

  mkdir -p "$dir/models" "$dir/views" "$dir/security"

  cat > "$dir/__init__.py" <<EOF
from . import models
EOF

  cat > "$dir/__manifest__.py" <<EOF
# Manifiesto: Odoo lo lee para saber qué es el módulo y qué archivos cargar.
{
    "name": "$titulo",
    "summary": "Módulo de ejemplo creado con odoo.sh new-module",
    "version": "1.0.0",
    "author": "Tu nombre",
    "license": "LGPL-3",
    # Módulos de los que depende. "base" siempre está instalado.
    "depends": ["base"],
    # Archivos de datos que se cargan al instalar/actualizar, en este orden.
    # Los permisos van primero para que el menú sea visible.
    "data": [
        "security/ir.model.access.csv",
        "views/${nombre}_views.xml",
    ],
    # True = aparece como aplicación en el menú Apps (no solo como módulo).
    "application": True,
}
EOF

  cat > "$dir/models/__init__.py" <<EOF
from . import ${nombre}
EOF

  cat > "$dir/models/${nombre}.py" <<EOF
from odoo import fields, models


class ${clase}(models.Model):
    # Nombre técnico del modelo: Odoo crea la tabla "${id_modelo}" en PostgreSQL.
    _name = "${modelo}"
    _description = "Registro de ${titulo}"

    name = fields.Char(string="Nombre", required=True)
    description = fields.Text(string="Descripción")
    active = fields.Boolean(string="Activo", default=True)
EOF

  cat > "$dir/views/${nombre}_views.xml" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<odoo>
    <!-- Vista de lista: la tabla que ves al abrir el menú. -->
    <record id="${id_modelo}_view_list" model="ir.ui.view">
        <field name="name">${modelo}.list</field>
        <field name="model">${modelo}</field>
        <field name="arch" type="xml">
            <list>
                <field name="name"/>
                <field name="description"/>
            </list>
        </field>
    </record>

    <!-- Vista de formulario: la ficha para crear o editar un registro. -->
    <record id="${id_modelo}_view_form" model="ir.ui.view">
        <field name="name">${modelo}.form</field>
        <field name="model">${modelo}</field>
        <field name="arch" type="xml">
            <form>
                <sheet>
                    <group>
                        <field name="name"/>
                        <field name="description"/>
                        <field name="active"/>
                    </group>
                </sheet>
            </form>
        </field>
    </record>

    <!-- Acción: qué se abre al pulsar el menú (lista y formulario). -->
    <record id="${id_modelo}_action" model="ir.actions.act_window">
        <field name="name">${titulo}</field>
        <field name="res_model">${modelo}</field>
        <field name="view_mode">list,form</field>
    </record>

    <!-- Menú principal de la aplicación y submenú que abre la acción. -->
    <menuitem id="${nombre}_menu_root" name="${titulo}"/>
    <menuitem id="${id_modelo}_menu" name="Registros" parent="${nombre}_menu_root" action="${id_modelo}_action"/>
</odoo>
EOF

  # Sin esta regla de acceso, nadie (ni el administrador) podría ver el modelo.
  cat > "$dir/security/ir.model.access.csv" <<EOF
id,name,model_id:id,group_id:id,perm_read,perm_write,perm_create,perm_unlink
access_${id_modelo}_user,${modelo} user,model_${id_modelo},base.group_user,1,1,1,1
EOF

  ok "Módulo creado en $dir"
  info "Siguientes pasos:"
  info "  1. ./odoo.sh restart"
  info "  2. En Odoo: Apps > Actualizar lista de aplicaciones (requiere modo desarrollador)"
  info "  3. Busca '$titulo' en Apps y pulsa Activar"
}

# -----------------------------------------------------------------------------
# cmd_backup
# Qué hace:   exporta una base de datos y su filestore a backups/ con la fecha
#             en el nombre.
# Parámetros: $1 = nombre de la base de datos.
# Ejemplo:    ./odoo.sh backup mi_empresa
#             -> backups/mi_empresa_2026-10-01_1530.dump
#             -> backups/mi_empresa_2026-10-01_1530_filestore.tar.gz
# Por debajo: "pg_dump -Fc" dentro del contenedor db, "tar" del filestore en
#             el contenedor odoo y "docker compose cp" para traer los archivos.
#             Se copia con "cp" (y no con ">") para que el archivo binario no
#             se corrompa en ningún sistema operativo.
#             Para restaurar: pg_restore -U USUARIO -d NUEVA_BASE archivo.dump
# -----------------------------------------------------------------------------
cmd_backup() {
  local base="${1:-}"
  [ -n "$base" ] || error "Uso: ./odoo.sh backup <base_de_datos>"
  comprobar_docker
  cargar_env
  docker compose ps --status running --services 2>/dev/null | grep -qx db \
    || error "La base de datos no está arrancada. Usa: ./odoo.sh start"
  mkdir -p backups
  local fecha nombre
  fecha="$(date +%Y-%m-%d_%H%M)"
  nombre="${base}_${fecha}"

  info "Exportando la base de datos '$base'..."
  docker compose exec -T db pg_dump -U "$DB_USER" -Fc -f "/tmp/${nombre}.dump" "$base" \
    || error "No se pudo exportar '$base'. ¿Existe esa base de datos? Revisa el nombre en http://localhost:${ODOO_PORT}/web/database/manager"
  docker compose cp "db:/tmp/${nombre}.dump" "backups/${nombre}.dump" >/dev/null
  docker compose exec -T db rm -f "/tmp/${nombre}.dump"
  ok "Base de datos guardada en backups/${nombre}.dump"

  # El filestore (adjuntos e imágenes) solo existe si Odoo está corriendo y la
  # base ya guardó algún archivo; si no, avisamos sin fallar.
  if odoo_corriendo && docker compose exec -T odoo test -d "/var/lib/odoo/filestore/$base"; then
    docker compose exec -T odoo tar -czf "/tmp/${nombre}_filestore.tar.gz" -C /var/lib/odoo/filestore "$base"
    docker compose cp "odoo:/tmp/${nombre}_filestore.tar.gz" "backups/${nombre}_filestore.tar.gz" >/dev/null
    docker compose exec -T odoo rm -f "/tmp/${nombre}_filestore.tar.gz"
    ok "Filestore guardado en backups/${nombre}_filestore.tar.gz"
  else
    aviso "No se encontró filestore para '$base' (o Odoo está apagado); solo se guardó la base de datos."
  fi
}

# -----------------------------------------------------------------------------
# cmd_reset
# Qué hace:   BORRA TODO: contenedores, bases de datos y filestore. No toca
#             addons/ ni backups/. Pide confirmación escribiendo "si".
# Parámetros: ninguno.
# Ejemplo:    ./odoo.sh reset
# Por debajo: "docker compose down -v --remove-orphans".
# -----------------------------------------------------------------------------
cmd_reset() {
  comprobar_docker
  aviso "Esto BORRA todas las bases de datos y archivos de Odoo. No se puede deshacer."
  aviso "Tus módulos en addons/ y tus copias en backups/ NO se borran."
  local respuesta
  read -r -p "Escribe 'si' para confirmar: " respuesta
  if [ "$respuesta" != "si" ]; then
    info "Cancelado. No se ha borrado nada."
    return 0
  fi
  docker compose down -v --remove-orphans
  ok "Todo borrado. Empieza de cero con: ./odoo.sh start"
}

# -----------------------------------------------------------------------------
# cmd_help
# Qué hace:   lista todos los comandos. Es el comando por defecto.
# Parámetros: ninguno.
# Ejemplo:    ./odoo.sh help
# Por debajo: solo imprime texto.
# -----------------------------------------------------------------------------
cmd_help() {
  cat <<EOF
${NEGRITA}Odoo en local con Docker${RESET} - por @Carlitos6712

Uso: ./odoo.sh <comando> [argumentos]

  ${VERDE}setup${RESET}                     Comprueba Docker, crea .env y descarga las imágenes
  ${VERDE}start${RESET}                     Arranca Odoo y muestra la URL
  ${VERDE}stop${RESET}                      Apaga Odoo (los datos se conservan)
  ${VERDE}restart${RESET}                   Reinicia Odoo (tras cambiar código de un módulo)
  ${VERDE}status${RESET}                    Muestra si los contenedores están corriendo
  ${VERDE}logs${RESET}                      Muestra los logs en vivo (Ctrl+C para salir)
  ${VERDE}shell${RESET}                     Abre una terminal dentro del contenedor de Odoo
  ${VERDE}update${RESET} <modulo> <base>    Actualiza un módulo de addons/ en una base de datos
  ${VERDE}new-module${RESET} <nombre>       Crea un módulo de ejemplo en addons/
  ${VERDE}backup${RESET} <base>             Guarda una copia de la base de datos en backups/
  ${VERDE}reset${RESET}                     BORRA TODO (pide confirmación)
  ${VERDE}help${RESET}                      Muestra esta ayuda
EOF
}

# -----------------------------------------------------------------------------
# Punto de entrada: elige la función según el primer argumento.
# Sin argumentos se muestra la ayuda.
# -----------------------------------------------------------------------------
main() {
  local comando="${1:-help}"
  [ $# -gt 0 ] && shift
  case "$comando" in
    setup)      cmd_setup ;;
    start)      cmd_start ;;
    stop)       cmd_stop ;;
    restart)    cmd_restart ;;
    status)     cmd_status ;;
    logs)       cmd_logs ;;
    shell)      cmd_shell ;;
    update)     cmd_update "$@" ;;
    new-module) cmd_new_module "$@" ;;
    backup)     cmd_backup "$@" ;;
    reset)      cmd_reset ;;
    help|-h|--help) cmd_help ;;
    *) cmd_help; error "Comando desconocido: '$comando'" ;;
  esac
}

main "$@"
