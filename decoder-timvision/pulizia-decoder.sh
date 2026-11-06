#!/usr/bin/env bash
# Pulizia del decoder TIM Vision (Android TV) via ADB.
#
# Tutte le operazioni sono REVERSIBILI: le app vengono disattivate
# (pm disable-user), non cancellate dal firmware. Con "ripristina"
# si torna esattamente allo stato precedente.
#
# Uso:
#   ./pulizia-decoder.sh connetti <IP_DECODER>
#   ./pulizia-decoder.sh analizza            # report su app sospette e permessi
#   ./pulizia-decoder.sh backup              # salva lo stato attuale
#   ./pulizia-decoder.sh disattiva [--prova] # disattiva le app in lista-disattivazione.txt
#   ./pulizia-decoder.sh disattiva-app <pacchetto>
#   ./pulizia-decoder.sh ripristina          # riattiva tutto ciò che lo script ha disattivato
#   ./pulizia-decoder.sh riattiva-app <pacchetto>

set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LISTA="$DIR/lista-disattivazione.txt"
REGISTRO="$DIR/disattivate-dallo-script.txt"
BACKUP_DIR="$DIR/backup"

# Pacchetti che lo script NON tocca mai, anche se finiscono per errore in lista:
# servizi TIM / operatore, firmware del produttore, componenti vitali di Android TV.
PROTETTI_REGEX='(tim|telecom|sagem|technicolor|arris|skyworth|kaonmedia|android\.tv\.settings|^com\.android\.(systemui|settings|providers|phone|shell|packageinstaller|inputdevices|tv\.settings)|^android$|(launcher|launcherx)$|setupwraith|^com\.google\.android\.(gms|gsf|tv\.remote\.service|vending|webview|tvsetup)|^com\.android\.vending|webview|inputmethod|tv\.inputs|tvinput|hdmi|bluetooth|nfc|networkstack|permissioncontroller|^com\.android\.server)'

ADB="${ADB:-adb}"

errore() { echo "ERRORE: $*" >&2; exit 1; }

richiedi_adb() {
  command -v "$ADB" >/dev/null 2>&1 || errore "adb non trovato. Installa 'Android SDK Platform-Tools' (vedi README.md)."
  local stato
  stato="$("$ADB" get-state 2>/dev/null || true)"
  [[ "$stato" == "device" ]] || errore "Nessun decoder collegato/autorizzato. Esegui prima: $0 connetti <IP_DECODER> e accetta il popup sulla TV."
}

sh_tv() { "$ADB" shell "$@" 2>/dev/null | tr -d '\r'; }

protetto() { [[ "$1" =~ $PROTETTI_REGEX ]]; }

installato() { sh_tv pm list packages | grep -qx "package:$1"; }

cmd_connetti() {
  local ip="${1:-}"
  [[ -n "$ip" ]] || errore "Specifica l'IP del decoder (Impostazioni > Rete > stato)."
  command -v "$ADB" >/dev/null 2>&1 || errore "adb non trovato (vedi README.md)."
  [[ "$ip" == *:* ]] || ip="$ip:5555"
  echo "Connessione a $ip ... sulla TV comparirà 'Consentire debug USB?': scegli 'Consenti sempre'."
  "$ADB" connect "$ip"
  "$ADB" wait-for-device
  echo "Modello: $(sh_tv getprop ro.product.manufacturer) $(sh_tv getprop ro.product.model) - Android $(sh_tv getprop ro.build.version.release)"
}

cmd_backup() {
  richiedi_adb
  mkdir -p "$BACKUP_DIR"
  local f
  f="$BACKUP_DIR/stato-$(date +%Y%m%d-%H%M%S).txt"
  {
    echo "# Backup stato decoder - $(date)"
    echo "# Modello: $(sh_tv getprop ro.product.model) / build $(sh_tv getprop ro.build.fingerprint)"
    echo "## TUTTI I PACCHETTI (con installer)"
    sh_tv pm list packages -i -f
    echo "## PACCHETTI GIA' DISATTIVATI"
    sh_tv pm list packages -d
    echo "## IMPOSTAZIONI SENSIBILI"
    echo "accessibilita=$(sh_tv settings get secure enabled_accessibility_services)"
    echo "listener_notifiche=$(sh_tv settings get secure enabled_notification_listeners)"
    echo "tastiera=$(sh_tv settings get secure default_input_method)"
  } > "$f"
  echo "Backup salvato in: $f"
}

cmd_analizza() {
  richiedi_adb
  echo "=== Decoder: $(sh_tv getprop ro.product.manufacturer) $(sh_tv getprop ro.product.model), Android $(sh_tv getprop ro.build.version.release), patch sicurezza $(sh_tv getprop ro.build.version.security_patch) ==="
  echo

  echo "=== 1. App installate dall'utente/terze parti e loro provenienza ==="
  echo "    (installer=null o diverso da com.android.vending = NON dal Play Store -> da verificare)"
  local riga pkg inst
  while IFS= read -r riga; do
    pkg="${riga#package:}"; pkg="${pkg%% *}"
    inst="${riga##*installer=}"
    if [[ "$inst" == "com.android.vending" ]]; then
      printf '    %-55s Play Store\n' "$pkg"
    else
      printf '  ! %-55s installer=%s  <-- SIDELOAD, verifica\n' "$pkg" "$inst"
    fi
  done < <(sh_tv pm list packages -3 -i | sort)
  echo

  echo "=== 2. App con permessi sensibili CONCESSI ==="
  local perms='RECORD_AUDIO|CAMERA|ACCESS_FINE_LOCATION|ACCESS_COARSE_LOCATION|READ_CONTACTS|READ_SMS|READ_PHONE_STATE|SYSTEM_ALERT_WINDOW|READ_EXTERNAL_STORAGE|READ_MEDIA_|PACKAGE_USAGE_STATS|QUERY_ALL_PACKAGES|REQUEST_INSTALL_PACKAGES'
  local trovati
  while IFS= read -r pkg; do
    pkg="${pkg#package:}"
    trovati="$(sh_tv dumpsys package "$pkg" | grep -E "android\.permission\.($perms)[A-Z_]*: granted=true" | sed -E 's/^ *android\.permission\.([A-Z_]+).*/\1/' | sort -u | paste -sd, - || true)"
    [[ -n "$trovati" ]] && printf '    %-55s %s\n' "$pkg" "$trovati"
  done < <(sh_tv pm list packages -3 | sort)
  echo "    (le app di sistema non sono elencate: vedi 'pm list packages -s' se vuoi approfondire)"
  echo

  echo "=== 3. Servizi di accessibilità attivi (possono leggere TUTTO lo schermo) ==="
  echo "    $(sh_tv settings get secure enabled_accessibility_services)"
  echo "=== 4. App che leggono le notifiche ==="
  echo "    $(sh_tv settings get secure enabled_notification_listeners)"
  echo "=== 5. Tastiera predefinita (una tastiera sconosciuta può registrare ciò che digiti) ==="
  echo "    $(sh_tv settings get secure default_input_method)"
  echo "=== 6. Amministratori del dispositivo ==="
  sh_tv dumpsys device_policy | grep -E '^\s*(Admin|admin=|ComponentInfo)' | sed 's/^/    /' || echo "    nessuno"
  echo "=== 7. App autorizzate a installare altre app ==="
  sh_tv appops query-op REQUEST_INSTALL_PACKAGES allow 2>/dev/null | sed 's/^/    /' || echo "    (non disponibile su questa versione)"
  echo "=== 8. Installazione da origini sconosciute (globale, vecchie versioni) ==="
  echo "    install_non_market_apps=$(sh_tv settings get secure install_non_market_apps)"
  echo "=== 9. Debug ADB via rete attivo (spegnilo a fine lavoro!) ==="
  echo "    adb_enabled=$(sh_tv settings get global adb_enabled)"
  echo
  echo "=== 10. App della lista di disattivazione presenti sul decoder ==="
  local p
  while IFS= read -r p; do
    if installato "$p"; then
      if sh_tv pm list packages -d | grep -qx "package:$p"; then
        printf '    %-55s gia'"'"' disattivata\n' "$p"
      else
        printf '    %-55s ATTIVA -> verrà disattivata\n' "$p"
      fi
    fi
  done < <(leggi_lista)
}

leggi_lista() {
  [[ -f "$LISTA" ]] || errore "File $LISTA mancante."
  sed -e 's/#.*//' -e 's/[[:space:]]//g' "$LISTA" | grep -v '^$' || true
}

disattiva_uno() {
  local p="$1" prova="${2:-0}"
  if protetto "$p"; then echo "  SALTATA (protetta): $p"; return; fi
  if ! installato "$p"; then echo "  non presente:       $p"; return; fi
  if [[ "$prova" == 1 ]]; then echo "  [prova] disattiverei: $p"; return; fi
  if sh_tv pm disable-user --user 0 "$p" | grep -q 'disabled'; then
    grep -qx "$p" "$REGISTRO" 2>/dev/null || echo "$p" >> "$REGISTRO"
    echo "  disattivata:        $p"
  else
    echo "  NON riuscita:       $p (il firmware potrebbe impedirlo)"
  fi
}

cmd_disattiva() {
  richiedi_adb
  local prova=0
  [[ "${1:-}" == "--prova" ]] && prova=1
  [[ "$prova" == 1 ]] || cmd_backup
  echo "Disattivazione app da $LISTA ..."
  local p
  while IFS= read -r p; do disattiva_uno "$p" "$prova"; done < <(leggi_lista)
  [[ "$prova" == 1 ]] || echo "Fatto. Riavvia il decoder: $ADB reboot"
}

cmd_disattiva_app() {
  richiedi_adb
  [[ -n "${1:-}" ]] || errore "Specifica il nome del pacchetto."
  disattiva_uno "$1"
}

cmd_riattiva_app() {
  richiedi_adb
  [[ -n "${1:-}" ]] || errore "Specifica il nome del pacchetto."
  sh_tv pm enable "$1"
  sh_tv cmd package install-existing "$1" >/dev/null || true
  if [[ -f "$REGISTRO" ]]; then
    grep -vx "$1" "$REGISTRO" > "$REGISTRO.tmp" || true
    mv "$REGISTRO.tmp" "$REGISTRO"
  fi
}

cmd_ripristina() {
  richiedi_adb
  [[ -s "$REGISTRO" ]] || errore "Nessuna app registrata come disattivata dallo script."
  local p
  while IFS= read -r p; do
    [[ -n "$p" ]] || continue
    echo "  riattivo: $p"
    sh_tv pm enable "$p" || true
    sh_tv cmd package install-existing "$p" >/dev/null || true
  done < "$REGISTRO"
  : > "$REGISTRO"
  echo "Ripristino completato. Riavvia il decoder: $ADB reboot"
}

case "${1:-}" in
  connetti)      shift; cmd_connetti "$@" ;;
  analizza)      cmd_analizza ;;
  backup)        cmd_backup ;;
  disattiva)     shift; cmd_disattiva "$@" ;;
  disattiva-app) shift; cmd_disattiva_app "$@" ;;
  riattiva-app)  shift; cmd_riattiva_app "$@" ;;
  ripristina)    cmd_ripristina ;;
  *) sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'; exit 1 ;;
esac
