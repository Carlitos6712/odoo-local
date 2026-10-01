# addons/

Aquí van tus módulos propios de Odoo. Cada módulo es una carpeta.

- Crea uno de ejemplo con `./odoo.sh new-module mi_modulo`.
- Docker monta esta carpeta en `/mnt/extra-addons` dentro del contenedor.
- Tras crear un módulo: `./odoo.sh restart` y, en Odoo, **Apps > Actualizar lista de aplicaciones**.
- Tras cambiar un módulo ya instalado: `./odoo.sh update mi_modulo mi_base`.
