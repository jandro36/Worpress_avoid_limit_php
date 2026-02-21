# Ajustar límites PHP para WordPress (uploads/imports)

¿Te suena esto? Tienes una migración urgente, un `.wpress` enorme, y WordPress te responde con un “el archivo es demasiado grande”.  
Esa sensación de estar a **un paso**… y que el servidor te cierre la puerta, quema.

Este script te ayuda a recuperar el control: lee los límites actuales de PHP, te propone valores recomendados (pensados para importaciones/migraciones) y, cuando confirmas, aplica el cambio y reinicia servicios.

## Por qué existe este script

Plugins de migración como *All‑in‑One WP Migration* (y similares) terminan dependiendo del límite real que permite tu PHP/servidor.  
Si PHP está capado (2M/8M), tu importación no tiene ninguna oportunidad: no es “tu culpa”, es configuración.

Este script automatiza el “ritual” típico:
- Ver valores actuales.
- Elegir nuevos límites razonables.
- Aplicar cambios con backup.
- Reiniciar PHP-FPM/Apache para que se apliquen. (Reiniciar PHP‑FPM es clave para que cargue la nueva config.) [web:77]

## Requisitos

- Linux (probado en entornos tipo Rocky/CentOS/RHEL)
- `bash`, `php` en CLI y `systemctl`
- Ejecutar como `root` (o con `sudo`)
- Recomendado: `numfmt` (coreutils) para validar tamaños

## Uso rápido

1. Descarga/clona el repo y da permisos:
   ```bash
   chmod +x ajustar-php-limites.sh

