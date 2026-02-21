#!/usr/bin/env bash
set -euo pipefail

die() { echo "ERROR: $*" >&2; exit 1; }

need_root() {
  [[ "${EUID:-$(id -u)}" -eq 0 ]] || die "Ejecuta como root: sudo $0"
}

# Devuelve valor ini actual (desde PHP CLI)
ini_get_val() {
  local key="$1"
  php -r "echo ini_get('$key');" 2>/dev/null || true
}

php_loaded_ini() {
  php -r '$f=php_ini_loaded_file(); echo $f ? $f : "none";' 2>/dev/null || true
}

prompt_with_current_and_default() {
  local __outvar="$1" key="$2" current="$3" recommended="$4" input=""
  echo
  echo "$key"
  echo "  Actual      : ${current:-"(vacío)"}"
  echo "  Recomendado : $recommended"
  read -r -p "  Nuevo valor (Enter = recomendado): " input || true
  input="${input:-$recommended}"
  printf -v "$__outvar" "%s" "$input"
}

valid_size() { [[ "$1" =~ ^[0-9]+([KMG]?)$ ]] || return 1; }
valid_int()  { [[ "$1" =~ ^-?[0-9]+$ ]] || return 1; }

to_bytes() {
  # 512M, 2G etc (IEC base 1024). Requiere numfmt.
  numfmt --from=iec "$1" 2>/dev/null || echo ""
}

write_ini_file() {
  local file="$1"
  local backup="${file}.$(date +%Y%m%d-%H%M%S).bak"

  if [[ -f "$file" ]]; then
    cp -a "$file" "$backup"
    echo "Backup: $backup"
  fi

  cat >"$file" <<EOF
; Managed by ajustar-php-limites.sh
upload_max_filesize = ${UPLOAD_MAX}
post_max_size = ${POST_MAX}
memory_limit = ${MEM_LIMIT}
max_execution_time = ${MAX_EXEC}
max_input_time = ${MAX_INPUT}
EOF
  echo "Escrito: $file"
}

edit_php_ini_inplace() {
  local file="$1"
  local backup="${file}.$(date +%Y%m%d-%H%M%S).bak"
  cp -a "$file" "$backup"
  echo "Backup: $backup"

  set_kv() {
    local key="$1" val="$2"
    if grep -qiE "^[[:space:]]*${key}[[:space:]]*=" "$file"; then
      sed -ri "s|^[[:space:]]*${key}[[:space:]]*=.*|${key} = ${val}|I" "$file"
    else
      echo "${key} = ${val}" >> "$file"
    fi
  }

  set_kv "upload_max_filesize" "${UPLOAD_MAX}"
  set_kv "post_max_size"       "${POST_MAX}"
  set_kv "memory_limit"        "${MEM_LIMIT}"
  set_kv "max_execution_time"  "${MAX_EXEC}"
  set_kv "max_input_time"      "${MAX_INPUT}"

  echo "Editado: $file"
}

restart_if_exists() {
  local svc="$1"
  if systemctl list-unit-files --type=service 2>/dev/null | awk '{print $1}' | grep -qx "${svc}.service"; then
    systemctl restart "${svc}.service"
    echo "Reiniciado: ${svc}.service"
  else
    echo "No existe servicio: ${svc}.service (omitido)"
  fi
}

show_effective_cli() {
  echo
  echo "Valores efectivos (PHP CLI):"
  php -i | egrep "upload_max_filesize|post_max_size|memory_limit|max_execution_time|max_input_time" || true
}

main() {
  need_root

  echo "PHP (CLI) está cargando php.ini: $(php_loaded_ini)"
  echo "Leyendo valores actuales desde PHP CLI (ini_get)..."

  CUR_UPLOAD="$(ini_get_val upload_max_filesize)"
  CUR_POST="$(ini_get_val post_max_size)"
  CUR_MEM="$(ini_get_val memory_limit)"
  CUR_MAX_EXEC="$(ini_get_val max_execution_time)"
  CUR_MAX_INPUT="$(ini_get_val max_input_time)"

  # Recomendados (propuesta)
  REC_UPLOAD="2G"
  REC_POST="2G"
  REC_MEM="512M"
  REC_MAX_EXEC="300"
  REC_MAX_INPUT="300"

  prompt_with_current_and_default UPLOAD_MAX "upload_max_filesize" "$CUR_UPLOAD" "$REC_UPLOAD"
  prompt_with_current_and_default POST_MAX   "post_max_size"       "$CUR_POST"   "$REC_POST"
  prompt_with_current_and_default MEM_LIMIT  "memory_limit"        "$CUR_MEM"    "$REC_MEM"
  prompt_with_current_and_default MAX_EXEC   "max_execution_time"  "$CUR_MAX_EXEC" "$REC_MAX_EXEC"
  prompt_with_current_and_default MAX_INPUT  "max_input_time"      "$CUR_MAX_INPUT" "$REC_MAX_INPUT"

  valid_size "$UPLOAD_MAX" || die "upload_max_filesize inválido: $UPLOAD_MAX (ej: 512M, 2G)"
  valid_size "$POST_MAX"   || die "post_max_size inválido: $POST_MAX (ej: 512M, 2G)"
  valid_size "$MEM_LIMIT"  || die "memory_limit inválido: $MEM_LIMIT (ej: 256M, 512M, 1G)"
  valid_int  "$MAX_EXEC"   || die "max_execution_time inválido: $MAX_EXEC"
  valid_int  "$MAX_INPUT"  || die "max_input_time inválido: $MAX_INPUT"

  # Validación post >= upload (si no son 0)
  if [[ "$UPLOAD_MAX" != "0" && "$POST_MAX" != "0" ]]; then
    command -v numfmt >/dev/null 2>&1 || die "Falta 'numfmt' (coreutils). Instálalo o usa valores coherentes manualmente."
    u_bytes="$(to_bytes "$UPLOAD_MAX")"
    p_bytes="$(to_bytes "$POST_MAX")"
    [[ -n "$u_bytes" && -n "$p_bytes" ]] || die "No puedo convertir tamaños; usa formatos tipo 512M/2G."
    (( p_bytes >= u_bytes )) || die "post_max_size ($POST_MAX) debe ser >= upload_max_filesize ($UPLOAD_MAX)"
  fi

  echo
  echo "Resumen de cambios propuestos:"
  echo "  upload_max_filesize: $CUR_UPLOAD  ->  $UPLOAD_MAX"
  echo "  post_max_size      : $CUR_POST    ->  $POST_MAX"
  echo "  memory_limit       : $CUR_MEM     ->  $MEM_LIMIT"
  echo "  max_execution_time : $CUR_MAX_EXEC -> $MAX_EXEC"
  echo "  max_input_time     : $CUR_MAX_INPUT -> $MAX_INPUT"
  echo
  read -r -p "¿Aplicar cambios y reiniciar servicios? (y/N): " ans || true
  [[ "${ans,,}" == "y" || "${ans,,}" == "yes" || "${ans,,}" == "s" || "${ans,,}" == "si" ]] || {
    echo "Cancelado. No se aplicó nada."
    exit 0
  }

  if [[ -d /etc/php.d ]]; then
    target="/etc/php.d/99-wp-upload.ini"
    write_ini_file "$target"
  else
    [[ -f /etc/php.ini ]] || die "No existe /etc/php.ini"
    edit_php_ini_inplace "/etc/php.ini"
  fi

  # Reinicios típicos (Rocky con Apache+PHP-FPM)
  restart_if_exists "php-fpm"
  restart_if_exists "httpd"

  show_effective_cli

  echo
  echo "Importante: WordPress usa el PHP del servidor (FPM/mod_php), no necesariamente el CLI."
  echo "Si en WordPress sigue saliendo bajo, revisa phpinfo() desde la web o el pool de php-fpm."
}

main "$@"
