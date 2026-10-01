# Odoo en local con Docker (Linux)

Instala, arranca y usa **Odoo 18** en tu Linux desde la terminal, con un solo comando por acción.
Pensado para quien nunca ha usado Odoo ni Docker.

Autor: [@Carlitos6712](https://github.com/Carlitos6712) · Licencia MIT

---

## 1. Qué es Odoo y qué es Docker

**Odoo** es un programa de gestión para empresas (ERP).
Se usa desde el navegador, como una página web.
Tiene "apps" que instalas según lo que necesites: Ventas, Inventario, Facturación, CRM...
También puedes crear tus propios módulos en Python.

**Docker** ejecuta programas dentro de "contenedores".
Piensa en un contenedor como una fiambrera: lleva dentro el programa y todo lo que necesita.
No ensucia tu sistema: Odoo y su base de datos no se instalan en tu Linux, viven en sus fiambreras.
Aquí usamos dos: una con Odoo y otra con su base de datos (PostgreSQL).

## 2. Requisitos

- Un Linux basado en **Debian/Ubuntu** (también Mint, Pop!_OS, Zorin...), **Fedora**, **Arch** u **openSUSE**.
- Un usuario con permiso de administrador (`sudo`).
- **Git**, para descargar este proyecto.

No hace falta instalar Docker a mano: `./odoo.sh setup` lo instala si falta (te pregunta antes).

**Abrir una terminal:** pulsa `Ctrl` + `Alt` + `T`, o busca "Terminal" en el menú de aplicaciones.

**Instalar Git** (si `git --version` da error):

| Distribución | Comando |
|---|---|
| Debian, Ubuntu, Mint... | `sudo apt install -y git` |
| Fedora | `sudo dnf install -y git` |
| Arch | `sudo pacman -S git` |
| openSUSE | `sudo zypper install git` |

## 3. Inicio rápido

Copia y pega **este único comando** en la terminal:

```bash
curl -fsSL https://raw.githubusercontent.com/Carlitos6712/odoo-local/main/install.sh | bash
```

¿Te dice `curl: orden no encontrada`? Usa este otro (hace lo mismo con `wget`):

```bash
wget -qO- https://raw.githubusercontent.com/Carlitos6712/odoo-local/main/install.sh | bash
```

Al terminar verás la URL de Odoo (normalmente **http://localhost:8079**). Ábrela en el navegador. ¡Listo!

Qué hace el instalador:
1. Instala `git`, `curl`, Docker y Docker Compose si faltan. Te pide tu contraseña (`sudo`) y confirmación.
2. Descarga el proyecto en `~/odoo-local` (si ya estaba, lo actualiza).
3. Crea el comando `odoo-local`, que funciona desde cualquier carpeta.
4. Arranca el servicio de Docker y lo deja activado al encender el equipo.
5. Añade tu usuario al grupo `docker`, para no tener que escribir `sudo` cada vez.
6. Crea el archivo `.env` con la configuración.
7. Descarga Odoo y PostgreSQL (cerca de 1 GB; tarda unos minutos) y arranca Odoo.

Puedes repetir el comando sin miedo: lo que ya está hecho se salta.

Después, para el día a día, abre una terminal **nueva** y usa `odoo-local` desde cualquier carpeta
(mira la sección 6):

```bash
odoo-local status
odoo-local help
```

`odoo-local <comando>` y `./odoo.sh <comando>` (dentro de `~/odoo-local`) hacen exactamente lo mismo.

> Al escribir la contraseña de `sudo` no se ve nada en pantalla. Es normal: escríbela y pulsa Enter.

<details>
<summary>Instalación manual, paso a paso (si prefieres no usar el instalador)</summary>

```bash
git clone https://github.com/Carlitos6712/odoo-local.git
cd ~/odoo-local
./odoo.sh setup
./odoo.sh start
```

Si `git clone` dice que `odoo-local` ya existe, ya lo descargaste antes:
no lo repitas, sigue desde `cd ~/odoo-local`.

</details>

## 4. Primer uso de Odoo

### 4.1. Crear la base de datos

Al abrir la URL verás un formulario. Rellénalo así:

| Campo | Qué poner |
|---|---|
| Master Password | `admin` (está en `config/odoo.conf`) |
| Database Name | Un nombre sin espacios, por ejemplo `mi_empresa` |
| Email | Tu usuario para entrar, por ejemplo `admin` |
| Password | La contraseña para entrar. Elige una y apúntala |
| Phone number | Opcional |
| Language | `Spanish / Español` |
| Country | Tu país |
| Demo data | Márcalo si quieres datos de ejemplo para practicar |

Pulsa **Create database**. Tarda uno o dos minutos.

> **Importante:** la *master password* protege el gestor de bases de datos
> (crear, copiar y borrar bases). Se guarda en `config/odoo.conf`.
> Si la cambias, apúntala: la necesitarás para gestionar tus bases.

### 4.2. Iniciar sesión

Odoo te deja dentro al terminar. Si no, entra en la URL de antes
con el **Email** y la **Password** del paso anterior.

### 4.3. Instalar una app

1. Abre el menú **Aplicaciones** (Apps).
2. Busca **Ventas** o **Inventario**.
3. Pulsa **Activar**.
4. Espera. La app aparece en el menú principal.

### 4.4. Activar el modo desarrollador

El modo desarrollador muestra opciones técnicas. Lo necesitas para trabajar con módulos.

1. Ve a **Ajustes**.
2. Baja hasta el final de la página.
3. Pulsa **Activar el modo de desarrollador**.

Atajo: añade `?debug=1` a la URL, por ejemplo `http://localhost:8079/odoo?debug=1`.

## 5. Desarrollar un módulo

1. Crea un módulo de ejemplo:
   ```bash
   ./odoo.sh new-module biblioteca
   ```
   Se crea `addons/biblioteca/` con un modelo, una lista, un formulario y un menú.
2. Reinicia Odoo para que lo vea:
   ```bash
   ./odoo.sh restart
   ```
3. En Odoo, con el modo desarrollador activo: **Aplicaciones > Actualizar lista de aplicaciones**.
4. Quita el filtro "Aplicaciones" del buscador, busca `biblioteca` y pulsa **Activar**.
5. Cambia el código (por ejemplo, añade un campo en `models/biblioteca.py` y en la vista).
6. Aplica los cambios en tu base de datos:
   ```bash
   ./odoo.sh update biblioteca mi_empresa
   ```

> Regla rápida: ¿cambiaste solo Python? `restart`. ¿Cambiaste campos, vistas o XML? `update`.

## 6. Referencia de comandos

| Comando | Qué hace |
|---|---|
| `./odoo.sh setup` | Instala Docker si falta, crea `.env` y descarga las imágenes |
| `./odoo.sh start` | Arranca Odoo y muestra la URL |
| `./odoo.sh stop` | Apaga Odoo sin borrar datos |
| `./odoo.sh restart` | Reinicia Odoo (tras cambiar código) |
| `./odoo.sh status` | Muestra si los contenedores están corriendo |
| `./odoo.sh logs` | Logs en vivo (Ctrl+C para salir) |
| `./odoo.sh shell` | Terminal dentro del contenedor de Odoo |
| `./odoo.sh update <modulo> <base>` | Actualiza un módulo en una base de datos |
| `./odoo.sh new-module <nombre>` | Crea un módulo de ejemplo en `addons/` |
| `./odoo.sh backup <base>` | Copia la base de datos y sus archivos a `backups/` |
| `./odoo.sh restore <archivo> [base]` | Restaura una copia de `backups/` como base nueva |
| `./odoo.sh reset` | **Borra todo** (pide escribir `si`) |
| `./odoo.sh help` | Lista los comandos |

Si instalaste con el comando de una línea, cambia `./odoo.sh` por `odoo-local`
y úsalo desde cualquier carpeta (por ejemplo, `odoo-local start`).

**Copias de seguridad:**

```bash
./odoo.sh backup mi_empresa
./odoo.sh restore backups/mi_empresa_2026-10-01_1530.dump
```

`restore` crea una base **nueva** con el nombre original (`mi_empresa`). Si ya existe,
indica otro nombre al final: `./odoo.sh restore backups/mi_empresa_2026-10-01_1530.dump mi_empresa_copia`.
Nunca sobrescribe una base que ya tengas.

**Cambiar la versión de Odoo:** edita `ODOO_VERSION` en `.env`, ejecuta `setup` y luego `start`.
Una base de datos creada con una versión no se abre con otra.

## 7. Problemas frecuentes

**Ya tengo otro Odoo instalado. ¿Se pisan?**
No. Esta instalación es independiente:
- Usa sus propios contenedores, volúmenes y red (todo empieza por `odoo-local`).
  Si ya hay otra instalación con ese nombre en otra carpeta, `setup` y `start`
  usan `odoo-local-2`, `odoo-local-3`... y lo guardan en `.env` (`COMPOSE_PROJECT_NAME`).
- Su PostgreSQL no se publica en tu equipo: no choca con otro PostgreSQL ni con el puerto 5432.
- Usa el puerto **8079**, no el 8069 habitual de Odoo. Así no le quita el puerto
  a tu otro Odoo, aunque esté apagado cuando instalas este.
- Si el 8079 también está ocupado, `setup` y `start` eligen el siguiente libre (8080, 8081...),
  lo guardan en `.env` y te muestran la URL correcta.
- `reset` solo borra los datos de **esta** instalación.

Un detalle: el navegador comparte la sesión entre `localhost:8069` y `localhost:8079`.
Si entras en los dos, uno te cierra la sesión del otro.
Solución: abre este Odoo con `127.0.0.1` (por ejemplo, http://127.0.0.1:8079)
y el otro con `localhost`. O usa una ventana privada.

**"El puerto ya está ocupado"**
Los scripts lo resuelven solos eligiendo otro puerto (mira el aviso amarillo).
Si quieres uno concreto, cambia `ODOO_PORT` en `.env` y ejecuta `start`.

**"Docker está parado"**
Arráncalo con `sudo systemctl start docker` y repite el comando.

**"permission denied ... docker.sock"**
Tu usuario no está en el grupo `docker`. Ejecuta `./odoo.sh setup`: lo arregla.
Los scripts funcionan enseguida; para usar `docker` a mano sin `sudo`, cierra sesión y vuelve a entrar.

**"Permission denied" al ejecutar `./odoo.sh`**
El archivo perdió el permiso de ejecución. Ejecuta `chmod +x odoo.sh`.

**Odoo no puede leer mi módulo**
Los archivos de `addons/` deben poder leerse por todos. Ejecuta `chmod -R a+rX addons`.

**Olvidé la contraseña**
- *Master password:* mírala en `config/odoo.conf` (línea `admin_passwd`).
- *Contraseña de mi usuario:* abre una terminal en el contenedor y cámbiala:
  ```bash
  ./odoo.sh shell
  odoo shell -d mi_empresa --db_host "$HOST" --db_user "$USER" --db_password "$PASSWORD" --no-http
  ```
  Dentro escribe (cambia `admin` por tu usuario):
  ```python
  env['res.users'].search([('login', '=', 'admin')]).password = 'nueva_clave'
  env.cr.commit()
  exit()
  ```

**Mi módulo no aparece en Aplicaciones**
1. Ejecuta `./odoo.sh restart`.
2. Activa el modo desarrollador.
3. **Aplicaciones > Actualizar lista de aplicaciones**.
4. Quita el filtro "Aplicaciones" del buscador y busca por nombre técnico.
Si sigue sin salir, mira `./odoo.sh logs`: suele ser un error en `__manifest__.py`.

**Mi distribución no está en la lista**
`setup` no sabrá instalar Docker. Instálalo con la [guía oficial](https://docs.docker.com/engine/install/)
y vuelve a ejecutar `./odoo.sh setup`: el resto funciona igual.

## 8. Cómo funciona por dentro

```
   Tu navegador
        │  http://localhost:8079
        ▼
┌─────────────────────────┐        ┌──────────────────────────┐
│  Contenedor "odoo"      │        │  Contenedor "db"         │
│  Odoo 18 (Python)       │──────▶ │  PostgreSQL 16           │
│                         │  SQL   │                          │
│  /mnt/extra-addons ◀────┼── ./addons (tus módulos)           │
│  /etc/odoo         ◀────┼── ./config/odoo.conf               │
└───────────┬─────────────┘        └────────────┬─────────────┘
            │                                   │
            ▼                                   ▼
   Volumen "odoo-web-data"            Volumen "odoo-db-data"
   (adjuntos e imágenes)              (bases de datos)
```

- `stop` apaga los contenedores. Los volúmenes siguen ahí: no pierdes nada.
- `reset` borra contenedores **y** volúmenes: empiezas de cero.
- Odoo solo escucha en `127.0.0.1`: nadie de tu red puede entrar.

## 9. Autor

Creado por **@Carlitos6712** · [github.com/Carlitos6712](https://github.com/Carlitos6712)

Licencia [MIT](LICENSE).
