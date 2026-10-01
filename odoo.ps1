# =============================================================================
# odoo.ps1 - Gestiona Odoo en local con Docker (Windows PowerShell)
# Autor: @Carlitos6712 (https://github.com/Carlitos6712)
# Licencia: MIT
#
# Uso:  .\odoo.ps1 <comando> [argumentos]
#       .\odoo.ps1 help        -> lista todos los comandos
#
# Equivalente de odoo.sh (Linux/macOS): mismos comandos y mismo comportamiento.
# Compatible con Windows PowerShell 5.1 y PowerShell 7.
# Este archivo se guarda en UTF-8 con BOM para que PowerShell 5.1 muestre bien
# las tildes y la "ñ".
# =============================================================================

param(
    [Parameter(Position = 0)] [string] $Comando = "help",
    [Parameter(Position = 1, ValueFromRemainingArguments = $true)] [string[]] $Argumentos = @()
)

# Equivalente a "set -euo pipefail" de bash:
#  - Stop: cualquier error de PowerShell detiene el script.
#  - StrictMode: error si se usa una variable sin definir.
# Los programas externos (docker) no lanzan excepciones; por eso comprobamos
# $LASTEXITCODE después de cada llamada con la función Test-Exito.
$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

# Trabajamos siempre desde la carpeta del script para que docker compose
# encuentre docker-compose.yml y .env.
Set-Location -Path $PSScriptRoot

# -----------------------------------------------------------------------------
# Mensajes con colores: verde OK, amarillo aviso, rojo error.
# -----------------------------------------------------------------------------
function Write-Ok    ([string] $Texto) { Write-Host "[OK] " -ForegroundColor Green -NoNewline; Write-Host $Texto }
function Write-Aviso ([string] $Texto) { Write-Host "[AVISO] " -ForegroundColor Yellow -NoNewline; Write-Host $Texto }
function Write-Info  ([string] $Texto) { Write-Host "[INFO] " -ForegroundColor Cyan -NoNewline; Write-Host $Texto }
# Write-Fallo: muestra el error en rojo y termina el script con código 1.
function Write-Fallo ([string] $Texto) { Write-Host "[ERROR] " -ForegroundColor Red -NoNewline; Write-Host $Texto; exit 1 }

# -----------------------------------------------------------------------------
# Test-Exito
# Qué hace:   comprueba si el último programa externo terminó bien; si no,
#             muestra el mensaje de error y sale.
# Parámetros: -Mensaje = explicación de la causa probable y cómo resolverla.
# Ejemplo:    docker compose pull; Test-Exito "No se pudieron descargar las imágenes."
# Por debajo: lee la variable automática $LASTEXITCODE.
# -----------------------------------------------------------------------------
function Test-Exito ([string] $Mensaje) {
    if ($LASTEXITCODE -ne 0) { Write-Fallo $Mensaje }
}

# -----------------------------------------------------------------------------
# Invoke-Silencioso
# Qué hace:   ejecuta un programa externo capturando su salida (también la de
#             error) sin que PowerShell 5.1 lo trate como excepción.
# Parámetros: -Bloque = scriptblock con el comando a ejecutar.
# Ejemplo:    $r = Invoke-Silencioso { docker info }; if ($r.Codigo -ne 0) { ... }
# Por debajo: ejecuta el bloque con "2>&1" y ErrorActionPreference=Continue.
# -----------------------------------------------------------------------------
function Invoke-Silencioso ([scriptblock] $Bloque) {
    $anterior = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        $salida = & $Bloque 2>&1 | Out-String
        return [pscustomobject]@{ Codigo = $LASTEXITCODE; Salida = $salida }
    } finally {
        $ErrorActionPreference = $anterior
    }
}

# -----------------------------------------------------------------------------
# Get-Entorno
# Qué hace:   lee las variables de .env (puerto, usuario de base de datos...)
#             y devuelve un diccionario con valores por defecto.
# Parámetros: ninguno.
# Ejemplo:    $cfg = Get-Entorno; $cfg.ODOO_PORT
# Por debajo: lee .env línea a línea ignorando comentarios.
# -----------------------------------------------------------------------------
function Get-Entorno {
    $cfg = @{ ODOO_PORT = "8069"; DB_USER = "odoo" }
    if (Test-Path ".env") {
        foreach ($linea in Get-Content ".env") {
            if ($linea -match '^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*?)\s*$') {
                $cfg[$Matches[1]] = $Matches[2].Trim('"', "'")
            }
        }
    }
    return $cfg
}

# -----------------------------------------------------------------------------
# Test-Docker
# Qué hace:   verifica que Docker y Docker Compose v2 están instalados y que
#             Docker está arrancado. Si no, explica cómo arreglarlo y sale.
# Parámetros: ninguno.
# Ejemplo:    Test-Docker
# Por debajo: "docker compose version" y "docker info".
# -----------------------------------------------------------------------------
function Test-Docker {
    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
        Write-Fallo "Docker no está instalado. Instala Docker Desktop: https://docs.docker.com/desktop/setup/install/windows-install/"
    }
    if ((Invoke-Silencioso { docker compose version }).Codigo -ne 0) {
        Write-Fallo "Falta Docker Compose v2 (el comando 'docker compose'). Actualiza Docker Desktop."
    }
    $info = Invoke-Silencioso { docker info }
    if ($info.Codigo -ne 0) {
        if ($info.Salida -match "permission denied") {
            Write-Fallo "Tu usuario no tiene permiso para usar Docker. En Linux ejecuta: sudo usermod -aG docker `$USER y vuelve a iniciar sesión."
        }
        Write-Fallo "Docker no está arrancado. Abre Docker Desktop y espera a que diga 'Engine running'."
    }
}

# -----------------------------------------------------------------------------
# Test-ServicioCorriendo
# Qué hace:   devuelve $true si el servicio indicado (odoo o db) está en marcha.
# Parámetros: -Servicio = "odoo" o "db".
# Ejemplo:    if (Test-ServicioCorriendo "odoo") { ... }
# Por debajo: "docker compose ps --status running --services".
# -----------------------------------------------------------------------------
function Test-ServicioCorriendo ([string] $Servicio = "odoo") {
    $r = Invoke-Silencioso { docker compose ps --status running --services }
    return ($r.Codigo -eq 0) -and (($r.Salida -split "\r?\n") -contains $Servicio)
}

# -----------------------------------------------------------------------------
# Test-PuertoOcupado
# Qué hace:   comprueba si algo ya escucha en un puerto local.
# Parámetros: -Puerto = número de puerto.
# Ejemplo:    if (Test-PuertoOcupado 8069) { ... }
# Por debajo: intenta una conexión TCP a 127.0.0.1 (funciona en cualquier
#             versión de Windows sin permisos de administrador).
# -----------------------------------------------------------------------------
function Test-PuertoOcupado ([int] $Puerto) {
    $cliente = New-Object System.Net.Sockets.TcpClient
    try {
        $intento = $cliente.BeginConnect("127.0.0.1", $Puerto, $null, $null)
        return ($intento.AsyncWaitHandle.WaitOne(500) -and $cliente.Connected)
    } catch {
        return $false
    } finally {
        $cliente.Close()
    }
}

# -----------------------------------------------------------------------------
# Wait-Odoo
# Qué hace:   espera hasta que Odoo responda por HTTP (máximo 3 minutos).
# Parámetros: -Puerto = puerto de Odoo.
# Ejemplo:    if (Wait-Odoo 8069) { ... }
# Por debajo: Invoke-WebRequest a http://localhost:PUERTO/web/login cada 3 s.
# -----------------------------------------------------------------------------
function Wait-Odoo ([string] $Puerto) {
    $url = "http://localhost:$Puerto/web/login"
    Write-Host "Esperando a que Odoo responda" -NoNewline
    for ($i = 0; $i -lt 60; $i++) {
        try {
            $null = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 5
            Write-Host ""
            return $true
        } catch {
            Write-Host "." -NoNewline
            Start-Sleep -Seconds 3
        }
    }
    Write-Host ""
    return $false
}

# -----------------------------------------------------------------------------
# Invoke-Setup
# Qué hace:   prepara todo para el primer uso: comprueba Docker, crea .env
#             desde .env.example si no existe y descarga las imágenes.
# Parámetros: ninguno.
# Ejemplo:    .\odoo.ps1 setup
# Por debajo: "Copy-Item .env.example .env" y "docker compose pull".
# -----------------------------------------------------------------------------
function Invoke-Setup {
    Test-Docker
    Write-Ok "Docker está instalado y arrancado."
    if (Test-Path ".env") {
        Write-Ok ".env ya existe; no se modifica."
    } else {
        if (-not (Test-Path ".env.example")) { Write-Fallo "No encuentro .env.example. ¿Estás en la carpeta del repositorio?" }
        Copy-Item ".env.example" ".env"
        Write-Ok ".env creado a partir de .env.example."
    }
    New-Item -ItemType Directory -Force -Path "addons", "backups" | Out-Null
    Write-Info "Descargando imágenes de Odoo y PostgreSQL (la primera vez puede tardar varios minutos)..."
    docker compose pull
    Test-Exito "No se pudieron descargar las imágenes. Revisa tu conexión a Internet y que ODOO_VERSION/POSTGRES_VERSION en .env sean válidas."
    Write-Ok "Todo listo. Ahora ejecuta: .\odoo.ps1 start"
}

# -----------------------------------------------------------------------------
# Invoke-Start
# Qué hace:   levanta Odoo y PostgreSQL en segundo plano, espera a que Odoo
#             responda y muestra la URL.
# Parámetros: ninguno.
# Ejemplo:    .\odoo.ps1 start
# Por debajo: "docker compose up -d".
# -----------------------------------------------------------------------------
function Invoke-Start {
    Test-Docker
    $cfg = Get-Entorno
    if (-not (Test-Path ".env")) { Write-Aviso "No existe .env; se usan valores por defecto. Ejecuta .\odoo.ps1 setup para crearlo." }
    # Si Odoo ya está corriendo, el puerto lo ocupa él mismo: no es un problema.
    if (-not (Test-ServicioCorriendo "odoo") -and (Test-PuertoOcupado $cfg.ODOO_PORT)) {
        Write-Fallo "El puerto $($cfg.ODOO_PORT) ya está ocupado por otro programa (¿otro Odoo?). Ciérralo o cambia ODOO_PORT en .env (por ejemplo, 8070)."
    }
    Write-Info "Arrancando contenedores..."
    docker compose up -d
    Test-Exito "No se pudieron arrancar los contenedores. Mira los detalles con: .\odoo.ps1 logs"
    if (Wait-Odoo $cfg.ODOO_PORT) {
        Write-Ok "Odoo está listo: http://localhost:$($cfg.ODOO_PORT)"
    } else {
        Write-Fallo "Odoo no responde tras 3 minutos. Revisa los errores con: .\odoo.ps1 logs"
    }
}

# -----------------------------------------------------------------------------
# Invoke-Stop
# Qué hace:   apaga los contenedores. Los datos se conservan en los volúmenes.
# Parámetros: ninguno.
# Ejemplo:    .\odoo.ps1 stop
# Por debajo: "docker compose stop".
# -----------------------------------------------------------------------------
function Invoke-Stop {
    Test-Docker
    docker compose stop
    Test-Exito "No se pudieron apagar los contenedores. Comprueba que Docker Desktop sigue abierto."
    Write-Ok "Odoo apagado. Tus datos siguen guardados."
}

# -----------------------------------------------------------------------------
# Invoke-Restart
# Qué hace:   reinicia solo Odoo. Útil tras cambiar código Python de un módulo
#             o el archivo config\odoo.conf.
# Parámetros: ninguno.
# Ejemplo:    .\odoo.ps1 restart
# Por debajo: "docker compose restart odoo".
# -----------------------------------------------------------------------------
function Invoke-Restart {
    Test-Docker
    $cfg = Get-Entorno
    if (-not (Test-ServicioCorriendo "odoo")) { Write-Fallo "Odoo no está arrancado. Usa: .\odoo.ps1 start" }
    docker compose restart odoo
    Test-Exito "No se pudo reiniciar Odoo. Revisa: .\odoo.ps1 logs"
    if (Wait-Odoo $cfg.ODOO_PORT) {
        Write-Ok "Odoo reiniciado: http://localhost:$($cfg.ODOO_PORT)"
    } else {
        Write-Fallo "Odoo no responde tras reiniciar. Revisa los errores con: .\odoo.ps1 logs"
    }
}

# -----------------------------------------------------------------------------
# Invoke-Status
# Qué hace:   muestra si los contenedores están corriendo.
# Parámetros: ninguno.
# Ejemplo:    .\odoo.ps1 status
# Por debajo: "docker compose ps".
# -----------------------------------------------------------------------------
function Invoke-Status {
    Test-Docker
    $cfg = Get-Entorno
    docker compose ps
    if (Test-ServicioCorriendo "odoo") {
        Write-Ok "Odoo está corriendo en http://localhost:$($cfg.ODOO_PORT)"
    } else {
        Write-Aviso "Odoo está apagado. Arráncalo con: .\odoo.ps1 start"
    }
}

# -----------------------------------------------------------------------------
# Invoke-Logs
# Qué hace:   muestra los logs de Odoo en vivo. Pulsa Ctrl+C para salir
#             (Odoo sigue funcionando).
# Parámetros: ninguno.
# Ejemplo:    .\odoo.ps1 logs
# Por debajo: "docker compose logs -f --tail 100 odoo".
# -----------------------------------------------------------------------------
function Invoke-Logs {
    Test-Docker
    Write-Info "Mostrando logs de Odoo. Pulsa Ctrl+C para salir."
    docker compose logs -f --tail 100 odoo
}

# -----------------------------------------------------------------------------
# Invoke-Shell
# Qué hace:   abre una terminal dentro del contenedor de Odoo. Escribe "exit"
#             para salir.
# Parámetros: ninguno.
# Ejemplo:    .\odoo.ps1 shell
# Por debajo: "docker compose exec odoo bash".
# -----------------------------------------------------------------------------
function Invoke-Shell {
    Test-Docker
    if (-not (Test-ServicioCorriendo "odoo")) { Write-Fallo "Odoo no está arrancado. Usa: .\odoo.ps1 start" }
    Write-Info "Terminal dentro del contenedor de Odoo. Escribe 'exit' para salir."
    docker compose exec odoo bash
}

# -----------------------------------------------------------------------------
# Invoke-Update
# Qué hace:   actualiza un módulo de addons\ en una base de datos (aplica
#             cambios en modelos, vistas, datos XML...) y reinicia Odoo.
# Parámetros: -Modulo = nombre del módulo (carpeta en addons\)
#             -Base   = nombre de la base de datos
# Ejemplo:    .\odoo.ps1 update mi_modulo mi_empresa
# Por debajo: ejecuta "odoo -u MODULO -d BASE --stop-after-init --no-http"
#             dentro del contenedor (sin HTTP para no chocar con el servidor
#             que ya usa el puerto) y luego "docker compose restart odoo".
# -----------------------------------------------------------------------------
function Invoke-Update ([string] $Modulo, [string] $Base) {
    if (-not $Modulo -or -not $Base) { Write-Fallo "Uso: .\odoo.ps1 update <modulo> <base_de_datos>" }
    if (-not (Test-Path "addons\$Modulo" -PathType Container)) { Write-Fallo "No existe la carpeta addons\$Modulo. Revisa el nombre del módulo." }
    Test-Docker
    $cfg = Get-Entorno
    if (-not (Test-ServicioCorriendo "odoo")) { Write-Fallo "Odoo no está arrancado. Usa: .\odoo.ps1 start" }
    Write-Info "Actualizando el módulo '$Modulo' en la base de datos '$Base'..."
    # Las comillas simples hacen que $HOST, $USER y $PASSWORD se lean DENTRO del
    # contenedor. No usamos comillas dobles internas porque PowerShell 5.1 las
    # elimina al pasar argumentos a programas externos.
    docker compose exec -T odoo sh -c 'odoo -c /etc/odoo/odoo.conf --db_host $HOST --db_user $USER --db_password $PASSWORD -d $1 -u $2 --stop-after-init --no-http' _ $Base $Modulo
    Test-Exito "Falló la actualización. Causas típicas: la base '$Base' no existe, el módulo no está instalado en ella o hay un error en su código (lee el mensaje de arriba)."
    docker compose restart odoo | Out-Null
    if (-not (Wait-Odoo $cfg.ODOO_PORT)) { Write-Fallo "Odoo no responde tras la actualización. Revisa: .\odoo.ps1 logs" }
    Write-Ok "Módulo '$Modulo' actualizado en '$Base'."
}

# -----------------------------------------------------------------------------
# Write-ArchivoUtf8
# Qué hace:   escribe un archivo en UTF-8 SIN BOM. Odoo no entiende el BOM en
#             los CSV de permisos, y Set-Content de PowerShell 5.1 lo añade.
# Parámetros: -Ruta, -Contenido.
# Ejemplo:    Write-ArchivoUtf8 "addons\x\__init__.py" "from . import models"
# Por debajo: [System.IO.File]::WriteAllText con UTF8Encoding($false).
# -----------------------------------------------------------------------------
function Write-ArchivoUtf8 ([string] $Ruta, [string] $Contenido) {
    $completa = Join-Path (Get-Location) $Ruta
    [System.IO.File]::WriteAllText($completa, $Contenido + "`n", (New-Object System.Text.UTF8Encoding $false))
}

# -----------------------------------------------------------------------------
# New-Modulo
# Qué hace:   crea un módulo de ejemplo mínimo en addons\<nombre> con
#             __manifest__.py, un modelo, sus vistas, un menú y permisos.
# Parámetros: -Nombre = nombre técnico (minúsculas, números y "_",
#             empezando por letra). Ejemplo: biblioteca
# Ejemplo:    .\odoo.ps1 new-module biblioteca
# Por debajo: solo crea archivos en addons\; no ejecuta Docker. Después hay
#             que reiniciar Odoo y "Actualizar lista de aplicaciones".
# -----------------------------------------------------------------------------
function New-Modulo ([string] $Nombre) {
    if (-not $Nombre) { Write-Fallo "Uso: .\odoo.ps1 new-module <nombre>   (ejemplo: .\odoo.ps1 new-module biblioteca)" }
    # Odoo usa el nombre de la carpeta como identificador técnico: debe ser un
    # nombre válido de paquete Python. -cmatch distingue mayúsculas.
    if ($Nombre -cnotmatch '^[a-z][a-z0-9_]*$') {
        Write-Fallo "Nombre no válido: '$Nombre'. Usa solo minúsculas, números y '_', empezando por letra (ejemplo: mi_modulo)."
    }
    $dir = "addons\$Nombre"
    if (Test-Path $dir) { Write-Fallo "Ya existe $dir. Elige otro nombre." }

    # Nombres derivados: modelo técnico (biblioteca.item) y título legible (Biblioteca).
    $modelo = "$Nombre.item"
    $idModelo = "${Nombre}_item"
    $titulo = $Nombre -replace '_', ' '
    $titulo = $titulo.Substring(0, 1).ToUpper() + $titulo.Substring(1)
    # Nombre de clase Python en CamelCase: biblioteca_libros -> BibliotecaLibrosItem
    $clase = (($Nombre -split '_' | Where-Object { $_ } | ForEach-Object { $_.Substring(0, 1).ToUpper() + $_.Substring(1) }) -join '') + "Item"

    New-Item -ItemType Directory -Force -Path "$dir\models", "$dir\views", "$dir\security" | Out-Null

    Write-ArchivoUtf8 "$dir\__init__.py" "from . import models"

    Write-ArchivoUtf8 "$dir\__manifest__.py" @"
# Manifiesto: Odoo lo lee para saber qué es el módulo y qué archivos cargar.
{
    "name": "$titulo",
    "summary": "Módulo de ejemplo creado con odoo.ps1 new-module",
    "version": "1.0.0",
    "author": "Tu nombre",
    "license": "LGPL-3",
    # Módulos de los que depende. "base" siempre está instalado.
    "depends": ["base"],
    # Archivos de datos que se cargan al instalar/actualizar, en este orden.
    # Los permisos van primero para que el menú sea visible.
    "data": [
        "security/ir.model.access.csv",
        "views/${Nombre}_views.xml",
    ],
    # True = aparece como aplicación en el menú Apps (no solo como módulo).
    "application": True,
}
"@

    Write-ArchivoUtf8 "$dir\models\__init__.py" "from . import $Nombre"

    Write-ArchivoUtf8 "$dir\models\$Nombre.py" @"
from odoo import fields, models


class ${clase}(models.Model):
    # Nombre técnico del modelo: Odoo crea la tabla "$idModelo" en PostgreSQL.
    _name = "$modelo"
    _description = "Registro de $titulo"

    name = fields.Char(string="Nombre", required=True)
    description = fields.Text(string="Descripción")
    active = fields.Boolean(string="Activo", default=True)
"@

    Write-ArchivoUtf8 "$dir\views\${Nombre}_views.xml" @"
<?xml version="1.0" encoding="utf-8"?>
<odoo>
    <!-- Vista de lista: la tabla que ves al abrir el menú. -->
    <record id="${idModelo}_view_list" model="ir.ui.view">
        <field name="name">$modelo.list</field>
        <field name="model">$modelo</field>
        <field name="arch" type="xml">
            <list>
                <field name="name"/>
                <field name="description"/>
            </list>
        </field>
    </record>

    <!-- Vista de formulario: la ficha para crear o editar un registro. -->
    <record id="${idModelo}_view_form" model="ir.ui.view">
        <field name="name">$modelo.form</field>
        <field name="model">$modelo</field>
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
    <record id="${idModelo}_action" model="ir.actions.act_window">
        <field name="name">$titulo</field>
        <field name="res_model">$modelo</field>
        <field name="view_mode">list,form</field>
    </record>

    <!-- Menú principal de la aplicación y submenú que abre la acción. -->
    <menuitem id="${Nombre}_menu_root" name="$titulo"/>
    <menuitem id="${idModelo}_menu" name="Registros" parent="${Nombre}_menu_root" action="${idModelo}_action"/>
</odoo>
"@

    # Sin esta regla de acceso, nadie (ni el administrador) podría ver el modelo.
    Write-ArchivoUtf8 "$dir\security\ir.model.access.csv" @"
id,name,model_id:id,group_id:id,perm_read,perm_write,perm_create,perm_unlink
access_${idModelo}_user,$modelo user,model_$idModelo,base.group_user,1,1,1,1
"@

    Write-Ok "Módulo creado en $dir"
    Write-Info "Siguientes pasos:"
    Write-Info "  1. .\odoo.ps1 restart"
    Write-Info "  2. En Odoo: Apps > Actualizar lista de aplicaciones (requiere modo desarrollador)"
    Write-Info "  3. Busca '$titulo' en Apps y pulsa Activar"
}

# -----------------------------------------------------------------------------
# Invoke-Backup
# Qué hace:   exporta una base de datos y su filestore a backups\ con la fecha
#             en el nombre.
# Parámetros: -Base = nombre de la base de datos.
# Ejemplo:    .\odoo.ps1 backup mi_empresa
#             -> backups\mi_empresa_2026-10-01_1530.dump
#             -> backups\mi_empresa_2026-10-01_1530_filestore.tar.gz
# Por debajo: "pg_dump -Fc" dentro del contenedor db, "tar" del filestore en
#             el contenedor odoo y "docker compose cp" para traer los archivos.
#             No usamos ">" porque PowerShell 5.1 convierte la salida a texto
#             UTF-16 y corrompería el archivo binario.
#             Para restaurar: pg_restore -U USUARIO -d NUEVA_BASE archivo.dump
# -----------------------------------------------------------------------------
function Invoke-Backup ([string] $Base) {
    if (-not $Base) { Write-Fallo "Uso: .\odoo.ps1 backup <base_de_datos>" }
    Test-Docker
    $cfg = Get-Entorno
    if (-not (Test-ServicioCorriendo "db")) { Write-Fallo "La base de datos no está arrancada. Usa: .\odoo.ps1 start" }
    New-Item -ItemType Directory -Force -Path "backups" | Out-Null
    $nombre = "{0}_{1}" -f $Base, (Get-Date -Format "yyyy-MM-dd_HHmm")

    Write-Info "Exportando la base de datos '$Base'..."
    docker compose exec -T db pg_dump -U $cfg.DB_USER -Fc -f "/tmp/$nombre.dump" $Base
    Test-Exito "No se pudo exportar '$Base'. ¿Existe esa base de datos? Revisa el nombre en http://localhost:$($cfg.ODOO_PORT)/web/database/manager"
    docker compose cp "db:/tmp/$nombre.dump" "backups/$nombre.dump" | Out-Null
    Test-Exito "No se pudo copiar la copia de seguridad a la carpeta backups."
    docker compose exec -T db rm -f "/tmp/$nombre.dump"
    Write-Ok "Base de datos guardada en backups\$nombre.dump"

    # El filestore solo existe si Odoo está corriendo y la base ya guardó algún
    # archivo; si no, avisamos sin fallar.
    $hayFilestore = (Test-ServicioCorriendo "odoo") -and ((Invoke-Silencioso { docker compose exec -T odoo test -d "/var/lib/odoo/filestore/$Base" }).Codigo -eq 0)
    if ($hayFilestore) {
        docker compose exec -T odoo tar -czf "/tmp/${nombre}_filestore.tar.gz" -C /var/lib/odoo/filestore $Base
        Test-Exito "No se pudo comprimir el filestore."
        docker compose cp "odoo:/tmp/${nombre}_filestore.tar.gz" "backups/${nombre}_filestore.tar.gz" | Out-Null
        Test-Exito "No se pudo copiar el filestore a la carpeta backups."
        docker compose exec -T odoo rm -f "/tmp/${nombre}_filestore.tar.gz"
        Write-Ok "Filestore guardado en backups\${nombre}_filestore.tar.gz"
    } else {
        Write-Aviso "No se encontró filestore para '$Base' (o Odoo está apagado); solo se guardó la base de datos."
    }
}

# -----------------------------------------------------------------------------
# Invoke-Reset
# Qué hace:   BORRA TODO: contenedores, bases de datos y filestore. No toca
#             addons\ ni backups\. Pide confirmación escribiendo "si".
# Parámetros: ninguno.
# Ejemplo:    .\odoo.ps1 reset
# Por debajo: "docker compose down -v --remove-orphans".
# -----------------------------------------------------------------------------
function Invoke-Reset {
    Test-Docker
    Write-Aviso "Esto BORRA todas las bases de datos y archivos de Odoo. No se puede deshacer."
    Write-Aviso "Tus módulos en addons\ y tus copias en backups\ NO se borran."
    $respuesta = Read-Host "Escribe 'si' para confirmar"
    if ($respuesta -cne "si") {
        Write-Info "Cancelado. No se ha borrado nada."
        return
    }
    docker compose down -v --remove-orphans
    Test-Exito "No se pudo borrar todo. Comprueba que Docker Desktop sigue abierto."
    Write-Ok "Todo borrado. Empieza de cero con: .\odoo.ps1 start"
}

# -----------------------------------------------------------------------------
# Show-Ayuda
# Qué hace:   lista todos los comandos. Es el comando por defecto.
# Parámetros: ninguno.
# Ejemplo:    .\odoo.ps1 help
# Por debajo: solo imprime texto.
# -----------------------------------------------------------------------------
function Show-Ayuda {
    Write-Host "Odoo en local con Docker - por @Carlitos6712" -ForegroundColor White
    Write-Host ""
    Write-Host "Uso: .\odoo.ps1 <comando> [argumentos]"
    Write-Host ""
    $comandos = @(
        @("setup",                  "Comprueba Docker, crea .env y descarga las imágenes"),
        @("start",                  "Arranca Odoo y muestra la URL"),
        @("stop",                   "Apaga Odoo (los datos se conservan)"),
        @("restart",                "Reinicia Odoo (tras cambiar código de un módulo)"),
        @("status",                 "Muestra si los contenedores están corriendo"),
        @("logs",                   "Muestra los logs en vivo (Ctrl+C para salir)"),
        @("shell",                  "Abre una terminal dentro del contenedor de Odoo"),
        @("update <modulo> <base>", "Actualiza un módulo de addons\ en una base de datos"),
        @("new-module <nombre>",    "Crea un módulo de ejemplo en addons\"),
        @("backup <base>",          "Guarda una copia de la base de datos en backups\"),
        @("reset",                  "BORRA TODO (pide confirmación)"),
        @("help",                   "Muestra esta ayuda")
    )
    foreach ($c in $comandos) {
        Write-Host ("  {0,-26}" -f $c[0]) -ForegroundColor Green -NoNewline
        Write-Host $c[1]
    }
}

# -----------------------------------------------------------------------------
# Punto de entrada: elige la función según el primer argumento.
# Sin argumentos se muestra la ayuda.
# -----------------------------------------------------------------------------
$arg1 = if ($Argumentos.Count -ge 1) { $Argumentos[0] } else { "" }
$arg2 = if ($Argumentos.Count -ge 2) { $Argumentos[1] } else { "" }

switch ($Comando.ToLower()) {
    "setup"      { Invoke-Setup }
    "start"      { Invoke-Start }
    "stop"       { Invoke-Stop }
    "restart"    { Invoke-Restart }
    "status"     { Invoke-Status }
    "logs"       { Invoke-Logs }
    "shell"      { Invoke-Shell }
    "update"     { Invoke-Update $arg1 $arg2 }
    "new-module" { New-Modulo $arg1 }
    "backup"     { Invoke-Backup $arg1 }
    "reset"      { Invoke-Reset }
    { $_ -in "help", "-h", "--help" } { Show-Ayuda }
    default      { Show-Ayuda; Write-Fallo "Comando desconocido: '$Comando'" }
}
