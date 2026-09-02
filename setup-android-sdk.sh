#!/usr/bin/env bash
#
# setup-android-sdk.sh — Prepara el entorno y compila Ausgaben (APK debug instalable)
# para WSL2 sin Android Studio. Genera un APK debug firmado con la traducción al
# español incluida y lo copia a tu carpeta Downloads de Windows para instalarlo a mano.
#
# Uso:
#   ./setup-android-sdk.sh            # proceso completo
#   ./setup-android-sdk.sh --sdk-only # solo instala/configura el SDK (sin compilar)

set -euo pipefail

# ---------- Rutas y configuración ----------
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SDK_DIR="${ANDROID_HOME:-/opt/android-sdk}"
CMDLINE_DIR="$SDK_DIR/cmdline-tools/latest"
SDKMANAGER="$CMDLINE_DIR/bin/sdkmanager"
LOCAL_PROPS="$REPO_DIR/local.properties"

# Paquetes necesarios (compileSdk 34 / AGP 8.7.3)
SDK_PACKAGES=("platform-tools" "platforms;android-34" "build-tools;34.0.0")

# ---------- Funciones auxiliares ----------
info() { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
ok()   { printf '\033[1;32m   %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m   %s\033[0m\n' "$*"; }
die()  { printf '\033[1;31mERROR: %s\033[0m\n' "$*" >&2; exit 1; }

cmd_exists() { command -v "$1" >/dev/null 2>&1; }

# Usuario actual de Windows a partir del /mnt/c (path WSL2)
windows_user() {
    local uc
    uc="$(cmd.exe /c 'echo %USERNAME%' 2>/dev/null | tr -d '\r' || true)"
    if [ -n "$uc" ] && [ -d "/mnt/c/Users/$uc" ]; then
        printf '%s' "$uc"
    else
        # Fallback: primer perfil de usuario existente en /mnt/c/Users
        for d in /mnt/c/Users/*/; do
            b="$(basename "$d")"
            case "$b" in
                Public|Default|All\ Users|Default\ User) continue ;;
                *) printf '%s' "$b"; return 0 ;;
            esac
        done
    fi
}

# ---------- Sección A: Prerrequisitos ----------
info "Comprobando prerrequisitos"
if ! cmd_exists java; then
    die "No se encontró 'java'. Instala una JDK 17, p. ej.  sudo apt install openjdk-17-jdk-headless"
fi
JAVA_MAJOR="$(java -version 2>&1 | awk -F'"' '/version/ {print $2}' | cut -d. -f1)"
[ "${JAVA_MAJOR:-0}" -ge 17 ] || warn "Java $(java -version 2>&1 | head -1 | grep -o '\".*\"') detectado; se recomienda 17"

if ! cmd_exists curl; then
    info "Instalando curl"
    sudo apt-get update -y && sudo apt-get install -y curl
fi
if ! cmd_exists unzip; then
    info "Instalando unzip"
    sudo apt-get update -y && sudo apt-get install -y unzip
fi
ok "curl, unzip y Java disponibles"

# ---------- Sección B: Instalación del SDK (si falta) ----------
install_sdk() {
    if [ -x "$SDKMANAGER" ]; then
        ok "Android SDK ya presente en $SDK_DIR"
        return 0
    fi

    info "Instalando Android SDK command-line tools en $SDK_DIR"
    if [ ! -d "$SDK_DIR" ]; then
        sudo mkdir -p "$SDK_DIR" || die "No se pudo crear $SDK_DIR"
    fi
    sudo chown -R "$(id -u):$(id -g)" "$SDK_DIR" 2>/dev/null || true

    # Última versión estable de command-line tools para Linux
    local url="https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip"
    local tmp
    tmp="$(mktemp -d)"
    info "Descargando command-line tools…"
    curl -fL --retry 3 -o "$tmp/clt.zip" "$url" || die "Falló la descarga del SDK tools"

    mkdir -p "$CMDLINE_DIR"
    unzip -q "$tmp/clt.zip" -d "$tmp/extract"
    cp -r "$tmp/extract/cmdline-tools/." "$CMDLINE_DIR/"
    rm -rf "$tmp"

    if [ ! -x "$SDKMANAGER" ]; then
        die "No se pudo instalar sdkmanager en $SDKMANAGER"
    fi
    ok "Command-line tools instaladas"

    info "Aceptando licencias…"
    yes | "$SDKMANAGER" --licenses >/dev/null 2>&1 || true

    info "Instalando paquetes del SDK: ${SDK_PACKAGES[*]}"
    "$SDKMANAGER" "${SDK_PACKAGES[@]}"
    ok "Paquetes del SDK instalados"
}

sdk_only=0
[ "${1:-}" = "--sdk-only" ] && sdk_only=1

install_sdk

# ---------- Configurar local.properties ----------
info "Configurando local.properties"
if [ -f "$LOCAL_PROPS" ] && grep -q '^sdk.dir=' "$LOCAL_PROPS"; then
    ok "local.properties ya existe: $(grep '^sdk.dir=' "$LOCAL_PROPS")"
else
    printf 'sdk.dir=%s\n' "$SDK_DIR" > "$LOCAL_PROPS"
    ok "Creado $LOCAL_PROPS con sdk.dir=$SDK_DIR"
fi

if [ "$sdk_only" = 1 ]; then
    info "Solo SDK. Listo."
    exit 0
fi

# ---------- Sección C: Submódulo ----------
info "Inicializando el submódulo MPAndroidChart (obligatorio para compilar)"
cd "$REPO_DIR"
if [ -f .gitmodules ]; then
    git submodule update --init --recursive || die "Fallo al inicializar submódulos"
    ok "Submódulos inicializados"
else
    die ".gitmodules no encontrado en $REPO_DIR"
fi

# ---------- Sección D: Compilación ----------
info "Compilando APK debug (foss, con español)"
./gradlew :app:assembleFossDebug

APK="$(ls -t "$REPO_DIR"/app/build/outputs/apk/foss/debug/app-foss-debug.apk 2>/dev/null | head -1)"
if [ -z "$APK" ] || [ ! -f "$APK" ]; then
    die "No se encontró el APK compilado"
fi
ok "APK generado: $APK"

# ---------- Copiar a Windows ----------
info "Copiando el APK a tu carpeta Downloads de Windows"
WUSER="$(windows_user)"
WROOT="/mnt/c/Users/$WUSER"
if [ -n "$WUSER" ] && [ -d "$WROOT" ]; then
    WDEST="$WROOT/Downloads/Ausgaben-es-1.12-debug.apk"
    cp "$APK" "$WDEST"
    ok "APK copiado a: $WDEST"
else
    WDEST=""
    warn "No se pudo detectar tu carpeta de Windows bajo /mnt/c/Users — copia el APK manualmente:"
    warn "  $APK"
fi

# ---------- Resumen ----------
cat <<EOF

=============================================================
  Compilación terminada
=============================================================
  Traducción al español:   INCLUIDA (Ajustes → Idioma → Español)
  APK (debug, instalable): $APK
EOF
if [ -n "$WDEST" ]; then
    printf '  Copiado a Windows:    %s\n' "$WDEST"
fi
cat <<EOF

  Para instalarlo en tu teléfono:
    1. Copia el APK al teléfono (USB/nube) y ábrelo, o
    2. Instálalo por adb:
         adb install -r "$APK"
  Activa "Instalar apps de orígenes desconocidos" si el teléfono lo pide.
=============================================================
EOF
