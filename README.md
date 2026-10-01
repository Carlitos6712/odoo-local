# Odoo en local con Docker

Instala, arranca y usa **Odoo 18** en tu ordenador con un solo comando por acción.
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
No ensucia tu ordenador y funciona igual en Windows, macOS y Linux.
Aquí usamos dos fiambreras: una con Odoo y otra con su base de datos (PostgreSQL).

## 2. Requisitos

Solo necesitas **Docker Desktop** (incluye `docker compose`) y **Git**.

| Sistema | Cómo instalar Docker |
|---|---|
| Windows 10/11 | [Docker Desktop para Windows](https://docs.docker.com/desktop/setup/install/windows-install/). Acepta activar WSL 2 si lo pide y reinicia. |
| macOS | [Docker Desktop para Mac](https://docs.docker.com/desktop/setup/install/mac-install/). Elige la versión de tu chip (Apple o Intel). |
| Linux | [Docker Engine](https://docs.docker.com/engine/install/) o [Docker Desktop para Linux](https://docs.docker.com/desktop/setup/install/linux/). Después: `sudo usermod -aG docker $USER` y cierra sesión. |

Git: [descargar Git](https://git-scm.com/downloads).

Después de instalar, **abre Docker Desktop** y espera a que diga que está en marcha.

**Solo en Windows**, la primera vez, permite ejecutar scripts. Abre PowerShell y ejecuta:

```powershell
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
```

## 3. Inicio rápido

**Linux / macOS** (Terminal):

```bash
git clone https://github.com/Carlitos6712/odoo-local.git && cd odoo-local
./odoo.sh setup
./odoo.sh start
```

**Windows** (PowerShell):

```powershell
git clone https://github.com/Carlitos6712/odoo-local.git; cd odoo-local
.\odoo.ps1 setup
.\odoo.ps1 start
```

Abre la URL que muestra `start` (normalmente **http://localhost:8069**). ¡Listo!

> La primera vez, `setup` descarga cerca de 1 GB. Puede tardar unos minutos.

## 4. Primer uso de Odoo

### 4.1. Crear la base de datos

Al abrir http://localhost:8069 verás un formulario. Rellénalo así:

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

Odoo te deja dentro al terminar. Si no, entra en http://localhost:8069
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

Atajo: añade `?debug=1` a la URL, por ejemplo `http://localhost:8069/odoo?debug=1`.

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

En Windows usa `.\odoo.ps1` en lugar de `./odoo.sh`.

> Regla rápida: ¿cambiaste solo Python? `restart`. ¿Cambiaste campos, vistas o XML? `update`.

## 6. Referencia de comandos

| Linux / macOS | Windows | Qué hace |
|---|---|---|
| `./odoo.sh setup` | `.\odoo.ps1 setup` | Comprueba Docker, crea `.env` y descarga las imágenes |
| `./odoo.sh start` | `.\odoo.ps1 start` | Arranca Odoo y muestra la URL |
| `./odoo.sh stop` | `.\odoo.ps1 stop` | Apaga Odoo sin borrar datos |
| `./odoo.sh restart` | `.\odoo.ps1 restart` | Reinicia Odoo (tras cambiar código) |
| `./odoo.sh status` | `.\odoo.ps1 status` | Muestra si los contenedores están corriendo |
| `./odoo.sh logs` | `.\odoo.ps1 logs` | Logs en vivo (Ctrl+C para salir) |
| `./odoo.sh shell` | `.\odoo.ps1 shell` | Terminal dentro del contenedor de Odoo |
| `./odoo.sh update <modulo> <base>` | `.\odoo.ps1 update <modulo> <base>` | Actualiza un módulo en una base de datos |
| `./odoo.sh new-module <nombre>` | `.\odoo.ps1 new-module <nombre>` | Crea un módulo de ejemplo en `addons/` |
| `./odoo.sh backup <base>` | `.\odoo.ps1 backup <base>` | Copia la base de datos y sus archivos a `backups/` |
| `./odoo.sh reset` | `.\odoo.ps1 reset` | **Borra todo** (pide escribir `si`) |
| `./odoo.sh help` | `.\odoo.ps1 help` | Lista los comandos |

**Cambiar la versión de Odoo:** edita `ODOO_VERSION` en `.env`, ejecuta `setup` y luego `start`.
Una base de datos creada con una versión no se abre con otra.

## 7. Problemas frecuentes

**Ya tengo otro Odoo instalado. ¿Se pisan?**
No. Esta instalación es independiente:
- Usa sus propios contenedores, volúmenes y red (todo empieza por `odoo-local`).
- Su PostgreSQL no se publica en tu ordenador: no choca con otro PostgreSQL ni con el puerto 5432.
- Si el puerto 8069 está ocupado, `setup` y `start` eligen el siguiente libre (8070, 8071...),
  lo guardan en `.env` y te muestran la URL correcta.
- `reset` solo borra los datos de **esta** instalación.

Un detalle: el navegador comparte la sesión entre `localhost:8069` y `localhost:8070`.
Si entras en los dos, uno te cierra la sesión del otro.
Solución: abre este Odoo con `127.0.0.1` (por ejemplo, http://127.0.0.1:8070)
y el otro con `localhost`. O usa una ventana privada.

**"El puerto 8069 ya está ocupado"**
Los scripts lo resuelven solos eligiendo otro puerto (mira el aviso amarillo).
Si quieres uno concreto, cambia `ODOO_PORT` en `.env` y ejecuta `start`.

**"Docker no está arrancado"**
Abre Docker Desktop y espera a que diga que está en marcha. Repite el comando.
En Linux sin Docker Desktop: `sudo systemctl start docker`.

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

**Permisos en Linux**
- *"permission denied ... docker.sock":* tu usuario no está en el grupo `docker`.
  Ejecuta `sudo usermod -aG docker $USER` y cierra sesión (o reinicia).
- *Odoo no puede leer tu módulo:* los archivos de `addons/` deben poder leerse por todos.
  Ejecuta `chmod -R a+rX addons`.
- *"Permission denied" al ejecutar el script:* ejecuta `chmod +x odoo.sh`.

**Windows: "la ejecución de scripts está deshabilitada"**
Ejecuta una vez: `Set-ExecutionPolicy -Scope CurrentUser RemoteSigned`.

## 8. Cómo funciona por dentro

```
   Tu navegador
        │  http://localhost:8069
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
