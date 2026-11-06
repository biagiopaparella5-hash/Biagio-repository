# Pulizia decoder TIM Vision (Android TV)

Strumento per ridurre pubblicità, telemetria e trovare eventuali app spia sul
decoder TIM Vision con Android TV, **senza root e in modo reversibile**.

> Cosa NON si può fare: le promozioni dentro l'app TIM Vision e il suo catalogo
> sono parte del servizio e non si eliminano senza rompere la visione. Lo script
> protegge di proposito tutti i pacchetti TIM e del produttore del decoder.

## 1. Prepara il decoder (5 minuti)

1. **Impostazioni → Preferenze dispositivo → Info** → premi 7 volte su
   **Build** finché compare "Sei uno sviluppatore".
2. **Impostazioni → Preferenze dispositivo → Opzioni sviluppatore** → attiva
   **Debug USB** (e, se presente, **Debug ADB tramite rete**).
3. Annota l'**indirizzo IP** del decoder: Impostazioni → Rete e Internet → la tua rete.

Se le Opzioni sviluppatore sono bloccate dal firmware TIM, salta ai passi 5 e 6:
funzionano comunque.

## 2. Prepara il PC

Scarica **Android SDK Platform-Tools** (gratuito, ufficiale Google):
<https://developer.android.com/tools/releases/platform-tools>

- **Windows**: estrai lo zip, installa [Git for Windows](https://git-scm.com/download/win)
  e lancia lo script da **Git Bash** (aggiungi la cartella platform-tools al PATH,
  oppure `export ADB=/c/percorso/platform-tools/adb.exe`).
- **macOS**: `brew install android-platform-tools`
- **Linux**: `sudo apt install adb`

PC e decoder devono essere sulla stessa rete di casa.

## 3. Collegati e analizza (nessuna modifica)

```bash
./pulizia-decoder.sh connetti 192.168.1.50
```

Sulla TV compare "Consentire il debug?": scegli **Consenti sempre**.

```bash
./pulizia-decoder.sh analizza > report.txt
```

Il report mostra:

| Sezione | Cosa cercare |
|---|---|
| 1. Provenienza app | Le righe con `!` sono app **non installate dal Play Store**. Se non sai cosa sono, sono le prime sospette. |
| 2. Permessi sensibili | Un'app di giochi o un "cleaner" con microfono, posizione o `SYSTEM_ALERT_WINDOW` è un campanello d'allarme. |
| 3. Accessibilità | Dovrebbe essere `null`. Un servizio qui può leggere tutto ciò che appare a schermo: tipico degli spyware. |
| 4. Notifiche | Dovrebbe essere `null` o app note. |
| 5. Tastiera | Dovrebbe essere la tastiera Google (Gboard/Leanback) o quella del produttore. |
| 6. Amministratori | Su un decoder normale vuoto o solo componenti TIM/produttore. Un'app sconosciuta qui è molto sospetta. |
| 7. Installatori | Solo Play Store/installer di sistema. Un file manager o browser qui va revocato. |

Per un'app sospetta: `./pulizia-decoder.sh disattiva-app nome.pacchetto`,
oppure rimuovila del tutto (se è stata installata da te) con
`adb uninstall nome.pacchetto`. In caso di dubbio cerca il nome del pacchetto
su Google prima di toccarlo, o mandami il report.

## 4. Togli pubblicità e telemetria Google

Apri `lista-disattivazione.txt`, togli il `#` davanti alle app opzionali che
non usi, poi:

```bash
./pulizia-decoder.sh disattiva --prova   # mostra cosa farebbe, senza toccare nulla
./pulizia-decoder.sh disattiva           # fa un backup e disattiva
adb reboot
```

Se qualcosa non va:

```bash
./pulizia-decoder.sh ripristina
```

Riattiva tutto quello che lo script ha disattivato. Le app non vengono mai
cancellate dal firmware, e un ripristino di fabbrica del decoder le rimette
comunque tutte.

## 5. Blocca pubblicità e tracker a livello di rete (consigliato)

È il metodo più efficace e funziona anche se il firmware TIM non lascia
disattivare nulla.

- **Router**: imposta come DNS quelli di un servizio filtrante, ad esempio
  AdGuard DNS `94.140.14.14` / `94.140.15.15`, oppure un profilo
  [NextDNS](https://nextdns.io) (gratuito fino a 300.000 richieste/mese).
  Ottimo se hai un Raspberry Pi: [Pi-hole](https://pi-hole.net) o AdGuard Home.
- **Solo decoder**: Impostazioni → Rete → la tua rete → impostazioni IP
  **statiche** → DNS 1 e 2 come sopra.

Se dopo il filtro TIM Vision non parte, aggiungi alla whitelist i domini
`timvision.it` e `telecomitalia.it`.

## 6. Altre impostazioni da fare dal telecomando

- **Impostazioni → Preferenze dispositivo → Info → Stato/Legale → Annunci**:
  attiva **Disattiva personalizzazione annunci** e **Reimposta ID pubblicità**.
- **Impostazioni → Preferenze dispositivo → Utilizzo e diagnostica**: disattiva.
- **Impostazioni → Account → Google → Assistente/Ricerca**: disattiva
  "Contenuti personalizzati" e la cronologia.
- **Impostazioni → App → Accesso speciale app**: controlla "Accessibilità",
  "Amministratori dispositivo", "Installa app sconosciute" e "Mostra sopra
  altre app" e togli ogni app che non riconosci.
- **Home**: tieni premuto sulle righe/canali che non vuoi → **Rimuovi**.
  Con Google TV puoi anche attivare la **Modalità solo app**
  (Impostazioni → Account → il tuo account → Modalità solo app): sparisce tutta
  la parte di suggerimenti.
- **Launcher alternativo (opzionale)**: [Projectivy Launcher](https://play.google.com/store/apps/details?id=com.spocky.projengmenu)
  o [FLauncher](https://gitlab.com/flauncher/flauncher) (open source) dal Play Store
  danno una home senza pubblicità. Non disattivare mai il launcher originale.

## 7. Chiudi tutto a fine lavoro

Spegni **Debug USB / Debug ADB tramite rete** nelle Opzioni sviluppatore:
lasciarlo acceso permette a chiunque sulla tua rete di provare a collegarsi al
decoder.

## Se pensi davvero che ci sia uno spyware

1. Salva il report (`analizza`) come prova.
2. Fai **Impostazioni → Preferenze dispositivo → Info → Ripristino dati di fabbrica**:
   cancella qualsiasi app installata successivamente.
3. Cambia la password dell'account Google usato sul decoder e controlla in
   <https://myaccount.google.com/device-activity> i dispositivi collegati.
4. Reinstalla solo app dal Play Store.
