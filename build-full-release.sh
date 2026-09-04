#!/usr/bin/env bash
#
# build-full-release.sh — Compila un APK release FIRMADO de la versión FULL (con Wear/GMS)
# para poder instalarlo y actualizarlo en tu teléfono sin repetir el
# "conflicto con un paquete".
#
# - Si no existe keystore, lo genera (keytool). El keystore se guarda en el repo
#   (~/Ausgaben/release.keystore) y sus contraseñas en ~/Ausgaben/keystore.properties.
#   IMPORTANTE: conserva BOTH archivos (el .keystore y el keystore.properties):
#   los necesitas para firmar futuras actualizaciones. Están en .gitignore.
# - Compila :app:assembleFullRelease (firmado).
# - Copia el APK a tu carpeta Downloads de Windows.
#
# Uso:
#   ./build-full-release.sh
#
# Variables opcionales (para no teclear en prompts):
#   KS_ALIAS, KS_PASS, KS_DNAME, KS_VALIDITY, KS_FILE, KS_PROPERTIES

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KS_FILE="${KS_FILE:-$REPO_DIR/release.keystore}"
KS_PROPS="${KS_PROPERTIES:-$REPO_DIR/keystore.properties}"
KS_ALIAS="${KS_ALIAS:-ausgaben}"
KS_VALIDITY="${KS_VALIDITY:-10000}"   # 10.000 días ≈ 27 años

# ---------- Funciones ----------
info() { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
ok()   { printf '\033[1;32m   %s\033[0m\n' "$*"; }
die()  { printf '\033[1;31mERROR: %s\033[0m\n' "$*" >&2; exit 1; }
cmd_exists() { command -v "$1" >/dev/null 2>&1; }

windows_user() {
    local uc
    uc="$(cmd.exe /c 'echo %USERNAME%' 2>/dev/null | tr -d '\r' || true)"
    if [ -n "$uc" ] && [ -d "/mnt/c/Users/$uc" ]; then
        printf '%s' "$uc"
    else
        for d in /mnt/c/Users/*/; do
            b="$(basename "$d")"
            case "$b" in Public|Default|All\ Users|Default\ User) continue ;; *) printf '%s' "$b"; return 0 ;; esac
        done
    fi
}

# ---------- Prerrequisitos ----------
info "Comprobando keytool (parte de la JDK)"
cmd_exists keytool || die "No se encontró 'keytool'. Asegúrate de tener instalada una JDK (sudo apt install openjdk-17-jdk-headless)"

# ---------- Generar o reutilizar el keystore ----------
if [ -f "$KS_FILE" ] && [ -f "$KS_PROPS" ]; then
    info "Keystore ya existente. Reutilizando (conserva siempre el mismo keystore al actualizar)."
else
    info "Generando un nuevo keystore de firma."
    if [ -f "$KS_FILE" ]; then
        die "Ya existe $KS_FILE pero falta $KS_PROPS. Constrúyelo a mano o borra el keystore si quieres generar uno nuevo."
    fi
    if [ -z "${KS_PASS:-}" ]; then
        read -rsp "Contraseña del keystore (no se muestra): " KS_PASS; echo
    fi
    [ -n "$KS_PASS" ] || die "La contraseña no puede estar vacía."

    KS_DNAME="${KS_DNAME:-CN=Ausgaben, OU=Personal, O=Personal, L=, ST=, C=ES}"
    keytool -genkeypair -v \
        -keystore "$KS_FILE" \
        -alias "$KS_ALIAS" \
        -keyalg RSA -keysize 3072 \
        -validity "$KS_VALIDITY" \
        -storepass "$KS_PASS" \
        -keypass "$KS_PASS" \
        -dname "$KS_DNAME"

    cat > "$KS_PROPS" <<EOF
storeFile=$KS_FILE
storePassword=$KS_PASS
keyAlias=$KS_ALIAS
keyPassword=$KS_PASS
EOF
    chmod 600 "$KS_PROPS"
    ok "Keystore creado: $KS_FILE"
    ok "Configuración guardada: $KS_PROPS  (¡no la pierdas! la necesitas para actualizaciones)"
fi

# ---------- local.properties (por si todavía no existe) ----------
if [ ! -f "$REPO_DIR/local.properties" ]; then
    S="${ANDROID_HOME:-/opt/android-sdk}"
    printf 'sdk.dir=%s\n' "$S" > "$REPO_DIR/local.properties"
    ok "Creado local.properties con sdk.dir=$S"
fi

# ---------- Submódulo ----------
info "Comprobando submódulo MPAndroidChart"
cd "$REPO_DIR"
[ -d third_party/MPAndroidChart ] || git submodule update --init --recursive

# ---------- Compilar release firmado ----------
info "Compilando :app:assembleFullRelease (firmado)"
./gradlew :app:assembleFullRelease

# Cuando hay keystore.properties, Gradle produce "app-full-release.apk" firmado.
APK="$(ls -t "$REPO_DIR"/app/build/outputs/apk/full/release/app-full-release.apk 2>/dev/null | head -1)"
if [ -z "$APK" ]; then
    APK="$(ls -t "$REPO_DIR"/app/build/outputs/apk/full/release/app-full-release-unsigned.apk 2>/dev/null | head -1)"
fi
if [ -z "$APK" ] || [ ! -f "$APK" ]; then
    die "No se encontró el APK release. Revisa que keystore.properties apunte correctamente."
fi
ok "APK firmado generado: $APK"

# ---------- Copiar a Windows ----------
info "Copiando a tu carpeta Downloads de Windows"
WUSER="$(windows_user)"
WDEST=""
if [ -n "$WUSER" ] && [ -d "/mnt/c/Users/$WUSER" ]; then
    OUT_NAME="Ausgaben-full-es-release.apk"
    cp "$APK" "/mnt/c/Users/$WUSER/Downloads/$OUT_NAME"
    WDEST="/mnt/c/Users/$WUSER/Downloads/$OUT_NAME"
    ok "Copiado a: $WDEST"
else
    warn "No se detectó /mnt/c/Users — copia manualmente: $APK"
fi

cat <<EOF

=============================================================
  Completo. APK release FULL FIRMADO listo.
=============================================================
  APK:            $APK
  Versión:        FULL (con Wear Data Layer / Google Play Services)
  Español:        INCLUIDO (Ajustes → Idioma → Español)
  Método:         cp "$APK" → teléfono → abrir (o adb install)
EOF
[ -n "$WDEST" ] && printf '  Windows:        %s\n' "$WDEST"
cat <<EOF

  Si ya tenías Ausgaben instalada y manda "conflicto de paquete":
    → Desinstala la versión anterior y luego instala este APK.
  Para futuras actualizaciones REDUCE la correr con el MISMO keystore;
    conserva release.keystore y keystore.properties.
=============================================================
EOF
