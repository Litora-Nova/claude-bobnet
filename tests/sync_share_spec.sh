#!/usr/bin/env bash
# tests/sync_share_spec.sh — Black-Box-Spec für bin/sync-share.
#
# Spec-Quelle: team-rules/comms.md §6 (Bobiverse-Sync, Whitelist-only) + Header von
# bin/sync-share + team-rules/sync-share.items:
#   - erzeugt .stignore-Whitelist: Negationen für die Items, Catch-all '*' als LETZTE Zeile
#   - legt fehlende Items an (Ordner bzw. leere Datei), überschreibt nichts
#   - Projekt-Override _dev_team/team-rules/sync-share.items ersetzt die Engine-Liste
#   - Sicherheits-Bremsen: verweigert /, $HOME und Secret-Pfade in der Whitelist
#   - idempotent; --no-register (Default) fasst keine Sync-Dienst-Config an
. "$(dirname "${BASH_SOURCE[0]}")/_helper.sh"

SYNC_SHARE="$ENGINE_ROOT/bin/sync-share"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "sync_share_spec:"

# --- Happy path: Default-Whitelist auf frischer Projekt-Wurzel ---
PROJ="$TMP/acme"
mkdir -p "$PROJ"
OUT="$(bash "$SYNC_SHARE" "$PROJ" --label acme --no-register 2>&1)"
RC=$?
it "läuft auf frischer Wurzel durch (Exit 0)";   eq "$RC" "0"
it "legt .stignore an";                          ok test -s "$PROJ/.stignore"
it "legt _inbox.md an (leer ok)";                ok test -e "$PROJ/_inbox.md"
it "legt _inbox/ an";                            ok test -d "$PROJ/_inbox"
it "legt plan/ an";                              ok test -d "$PROJ/plan"
it "legt share/ an";                             ok test -d "$PROJ/share"

it "Whitelist: Negation für _inbox.md";          file_has "$PROJ/.stignore" '!/_inbox.md'
it "Whitelist: Negation für plan-Inhalte";       file_has "$PROJ/.stignore" '!/plan/**'
it "Whitelist: Negation für share-Inhalte";      file_has "$PROJ/.stignore" '!/share/**'
it "Whitelist: Warn-Header vorhanden";           file_has "$PROJ/.stignore" 'NICHT LÖSCHEN'
LAST="$(grep -v '^$' "$PROJ/.stignore" | tail -1)"
it "Catch-all '*' ist die LETZTE Zeile";         eq "$LAST" "*"
FIRST_MATCH="$(grep -nE '^\*$' "$PROJ/.stignore" | head -1 | cut -d: -f1)"
NEG_AFTER="$(awk -v n="$FIRST_MATCH" 'NR>n && /^!/' "$PROJ/.stignore")"
it "keine Negation NACH dem Catch-all";          eq "$NEG_AFTER" ""

# --- Nichts überschreiben + idempotent ---
echo "wichtig" > "$PROJ/_inbox.md"
bash "$SYNC_SHARE" "$PROJ" --label acme --no-register >/dev/null 2>&1
it "überschreibt vorhandene _inbox.md NICHT";    file_has "$PROJ/_inbox.md" "wichtig"
SUM1="$(cksum "$PROJ/.stignore")"
bash "$SYNC_SHARE" "$PROJ" --label acme --no-register >/dev/null 2>&1
SUM2="$(cksum "$PROJ/.stignore")"
it "idempotent: .stignore deterministisch";      eq "$SUM1" "$SUM2"

# --- Projekt-Override ersetzt die Engine-Liste ---
mkdir -p "$PROJ/_dev_team/team-rules"
printf '_inbox.md\ndocs\n' > "$PROJ/_dev_team/team-rules/sync-share.items"
bash "$SYNC_SHARE" "$PROJ" --label acme --no-register >/dev/null 2>&1
it "Override: docs/ wird angelegt";              ok test -d "$PROJ/docs"
it "Override: docs in Whitelist";                file_has "$PROJ/.stignore" '!/docs'
OUT="$(grep -c '!/plan' "$PROJ/.stignore" || true)"
it "Override ERSETZT Engine-Liste (kein plan)";  eq "$OUT" "0"

# --- Sicherheits-Bremsen ---
it "verweigert \$HOME als Share-Wurzel"
not_ok bash "$SYNC_SHARE" "$HOME" --label home --no-register
printf '.secrets\n' > "$PROJ/_dev_team/team-rules/sync-share.items"
OUT="$(bash "$SYNC_SHARE" "$PROJ" --label acme --no-register 2>&1)"
RC=$?
it "verweigert Secret-Pfad in der Whitelist";    neq "$RC" "0"
it "Fehlermeldung nennt den Secret-Refuse";      contains "$OUT" "REFUSED"

# --- Pflicht-Args ---
mkdir -p "$TMP/p2"
bash "$SYNC_SHARE" "$TMP/p2" --no-register >/dev/null 2>&1
RC=$?
it "ohne --uid/--label → Fehler";                neq "$RC" "0"

# --- Anzeigename-Schema (PO-Kanon 2026-06-11): ID=--uid, Label=--name, --label=Alias ---
mkdir -p "$TMP/proj_name"
it "--uid (neues Schema) funktioniert";          ok bash "$SYNC_SHARE" "$TMP/proj_name" --uid acme --no-register
it "--name mit Leerzeichen akzeptiert";          ok bash "$SYNC_SHARE" "$TMP/proj_name" --uid acme --name "Acme Inc" --no-register
it "--label bleibt Alias für --uid (v1-Kompat)"; ok bash "$SYNC_SHARE" "$TMP/proj_name" --label acme --no-register
timeout 5 bash "$SYNC_SHARE" "$TMP/proj_name" --uid acme --name >/dev/null 2>&1
RC=$?
it "--name ohne Wert am Ende → Fehler statt Hang"; neq "$RC" "0"
it "… kein timeout-Kill (RC≠124)";                neq "$RC" "124"

# --- Item-Normalisierung: führende/trailing Slashes werden getrimmt (kein Ordner '/') ---
PROJ_SL="$TMP/proj_slash"
mkdir -p "$PROJ_SL/_dev_team/team-rules"
printf '/plan/\n/share\ndocs/\n' > "$PROJ_SL/_dev_team/team-rules/sync-share.items"
bash "$SYNC_SHARE" "$PROJ_SL" --label acme --no-register >/dev/null 2>&1
it "Slash-Item '/plan/' → Ordner plan/";         ok test -d "$PROJ_SL/plan"
it "Slash-Item '/share' → Ordner share/";        ok test -d "$PROJ_SL/share"
it "Slash-Item 'docs/' → Ordner docs/";          ok test -d "$PROJ_SL/docs"
it "Slash-Item → saubere Negation '!/plan'";     file_has "$PROJ_SL/.stignore" '!/plan'
NEG_SL="$(grep -c '!//' "$PROJ_SL/.stignore" || true)"
it "kein doppelter Slash '!//' in Whitelist";    eq "$NEG_SL" "0"

# --- Negation folgt dem REALEN Typ: existiert das Item schon als Ordner, kommt '/**' dazu ---
# (auch wenn der Name 'wie eine Datei' aussieht — die Heuristik betrifft nur das Neu-Anlegen)
PROJ_RT="$TMP/proj_realtype"
mkdir -p "$PROJ_RT/_dev_team/team-rules"
printf 'release.notes\n' > "$PROJ_RT/_dev_team/team-rules/sync-share.items"
mkdir -p "$PROJ_RT/release.notes"   # existiert als ORDNER trotz Punkt-Name
bash "$SYNC_SHARE" "$PROJ_RT" --label acme --no-register >/dev/null 2>&1
it "existierender Ordner mit Punkt-Name → '/**'"; file_has "$PROJ_RT/.stignore" '!/release.notes/**'

# --- Heuristik-Grenze (dokumentierter Ist-Zustand): Punkt-Name OHNE Vorab-Ordner = Datei ---
# Ein als Ordner gemeinter Versions-Name wie 'v1.2' wird als leere DATEI angelegt und ohne
# '/**' negiert. Bekannte Kante der 'enthält Punkt = Datei'-Heuristik (an Lead gemeldet).
PROJ_HU="$TMP/proj_heur"
mkdir -p "$PROJ_HU/_dev_team/team-rules"
printf 'v1.2\n' > "$PROJ_HU/_dev_team/team-rules/sync-share.items"
bash "$SYNC_SHARE" "$PROJ_HU" --label acme --no-register >/dev/null 2>&1
it "Heuristik: Punkt-Name → Datei (Ist-Zustand)"; ok test -f "$PROJ_HU/v1.2"

# --- Whitelist-Datei fehlt in Engine UND Projekt → harter Abbruch ---
FAKE_ENGINE="$TMP/fake_engine"
mkdir -p "$FAKE_ENGINE/bin"
cp "$SYNC_SHARE" "$FAKE_ENGINE/bin/sync-share"   # KEIN team-rules/ im Fake-Engine-Root
mkdir -p "$TMP/proj_noitems"
OUT="$(bash "$FAKE_ENGINE/bin/sync-share" "$TMP/proj_noitems" --label acme --no-register 2>&1)"
RC=$?
it "fehlende Items-Datei (Engine+Projekt) → Abbruch"; neq "$RC" "0"
it "Abbruch-Meldung nennt sync-share.items";          contains "$OUT" "sync-share.items"
it "ohne Items-Datei KEINE .stignore geschrieben";    file_missing "$TMP/proj_noitems/.stignore"

# --- relativer Projekt-Pfad wird zu absolut aufgelöst ---
mkdir -p "$TMP/proj_rel"
( cd "$TMP" && bash "$SYNC_SHARE" "./proj_rel" --label acme --no-register >/dev/null 2>&1 )
it "relativer Pfad → .stignore am absoluten Ort";  ok test -s "$TMP/proj_rel/.stignore"

# --- '/' als Share-Wurzel wird verweigert (zweite Sicherheits-Bremse neben \$HOME) ---
it "verweigert '/' als Share-Wurzel"
not_ok bash "$SYNC_SHARE" "/" --label root --no-register

# --- HIGH-1-Regression: Option ohne Wert am ENDE darf nicht hängen (Endlosschleifen-Bug) ---
mkdir -p "$TMP/proj_hang"
timeout 5 bash "$SYNC_SHARE" "$TMP/proj_hang" --label >/dev/null 2>&1
RC=$?
it "--label ohne Wert am Ende → Fehler statt Hang";   neq "$RC" "0"
it "… kein timeout-Kill (RC≠124)";                    neq "$RC" "124"
timeout 5 bash "$SYNC_SHARE" "$TMP/proj_hang" --label acme --device >/dev/null 2>&1
RC=$?
it "--device ohne Wert am Ende → Fehler statt Hang";  neq "$RC" "0"
it "… kein timeout-Kill (RC≠124)";                    neq "$RC" "124"

# --- BUG-2-Regression: Whitespace-only-Whitelist = leer → harter Abbruch, keine .stignore ---
PROJ_WS="$TMP/proj_ws"
mkdir -p "$PROJ_WS/_dev_team/team-rules"
printf '   \n\t\n  \n' > "$PROJ_WS/_dev_team/team-rules/sync-share.items"
OUT="$(bash "$SYNC_SHARE" "$PROJ_WS" --label acme --no-register 2>&1)"
RC=$?
it "Whitespace-only-Whitelist → Abbruch";             neq "$RC" "0"
it "Abbruch-Meldung sagt 'leer'";                     contains "$OUT" "leer"
it "keine .stignore bei Whitespace-Whitelist";        file_missing "$PROJ_WS/.stignore"

# --- Secret-Refuse-Härtung: gängige Secret-Träger werden als Item verweigert ---
PROJ_SEC="$TMP/proj_sec"
mkdir -p "$PROJ_SEC/_dev_team/team-rules"
for bad in '.env' '.env.production' 'config/credentials.yml.enc' 'id_rsa' 'secrets.yml' \
           'config/database.yml' 'configuration.yml' 'api-token.txt' 'server.pem' 'tls.key'; do
  printf '%s\n' "$bad" > "$PROJ_SEC/_dev_team/team-rules/sync-share.items"
  OUT="$(bash "$SYNC_SHARE" "$PROJ_SEC" --label acme --no-register 2>&1)"
  RC=$?
  it "Secret-Refuse: '$bad' verweigert";              neq "$RC" "0"
done

# --- KANTE-2-Regression: Secret-Refuse ist CASE-INSENSITIV ---
# (Sync-Ziel kann ein case-insensitives FS sein — macOS-Default: .ENV == .env)
for bad in '.ENV' '.Env.Production' 'ID_RSA' 'Credentials.yml.enc' 'SECRETS.YML' 'Server.PEM'; do
  printf '%s\n' "$bad" > "$PROJ_SEC/_dev_team/team-rules/sync-share.items"
  OUT="$(bash "$SYNC_SHARE" "$PROJ_SEC" --label acme --no-register 2>&1)"
  RC=$?
  it "Secret-Refuse case-insensitiv: '$bad' verweigert"; neq "$RC" "0"
done

# --- Glob-/Traversal-Items werden verweigert (kein Whitelist-Aushebeln, kein mkdir außerhalb) ---
PROJ_TRV="$TMP/proj_trv"
mkdir -p "$PROJ_TRV/_dev_team/team-rules"
for bad in '*' 'docs/*' '../evil' 'a/../b'; do
  printf '%s\n' "$bad" > "$PROJ_TRV/_dev_team/team-rules/sync-share.items"
  OUT="$(bash "$SYNC_SHARE" "$PROJ_TRV" --label acme --no-register 2>&1)"
  RC=$?
  it "unsicheres Item '$bad' verweigert";             neq "$RC" "0"
done
it "kein mkdir außerhalb der Wurzel passiert";        file_missing "$TMP/evil"

# --- MED-1-Fix: trailing '/' = expliziter Ordner-Marker (Punkt-Name wird trotzdem Ordner) ---
PROJ_V="$TMP/proj_vdir"
mkdir -p "$PROJ_V/_dev_team/team-rules"
printf 'v1.2/\n' > "$PROJ_V/_dev_team/team-rules/sync-share.items"
bash "$SYNC_SHARE" "$PROJ_V" --label acme --no-register >/dev/null 2>&1
it "Dir-Marker 'v1.2/' → Ordner (trotz Punkt)";       ok test -d "$PROJ_V/v1.2"
it "Dir-Marker → Negation mit '/**'";                 file_has "$PROJ_V/.stignore" '!/v1.2/**'

# --- Refuse-Grund-Nachweis: die Verweigerung kommt WIRKLICH vom Secret-Refuse, nicht zufällig ---
# (sonst wäre ein grüner Refuse-Check nicht aussagekräftig)
PROJ_RG="$TMP/proj_refgrund"
mkdir -p "$PROJ_RG/_dev_team/team-rules"
printf '.env\n' > "$PROJ_RG/_dev_team/team-rules/sync-share.items"
OUT="$(bash "$SYNC_SHARE" "$PROJ_RG" --label acme --no-register 2>&1)"
it "Secret-Refuse nennt den konkreten Pfad";          contains "$OUT" "Secret-Pfad '.env'"

# --- Negativ-Kontrolle: legitime Items laufen DURCH (Filter nicht generell zu aggressiv) ---
PROJ_OK="$TMP/proj_legit"
mkdir -p "$PROJ_OK/_dev_team/team-rules"
printf 'plan\ndocs\nenvironment\nshare\n' > "$PROJ_OK/_dev_team/team-rules/sync-share.items"
bash "$SYNC_SHARE" "$PROJ_OK" --label acme --no-register >/dev/null 2>&1
RC=$?
it "legitime Items (plan/docs/environment/share) → OK"; eq "$RC" "0"
it "… 'environment' nicht fälschlich als '.env' geblockt"; file_has "$PROJ_OK/.stignore" '!/environment'

# --- Anzeigename-Schema, Registrierungs-Auflösung (PO-Kanon 2026-06-11) ---
# Black-Box-Trick: ein Fake-'syncthing' im PATH macht den --register-Pfad beobachtbar,
# OHNE den echten Sync-Dienst anzufassen. 'config folders list' → leer (Share existiert
# nicht → add-Pfad), 'folders add' druckt das ID- und das Label-Token EINZELN (so prüfen
# wir Argument-Grenzen, nicht nur "$*"). Damit wird testbar, was im --no-register-Modus
# unsichtbar bleibt: ID = --uid, Syncthing-LABEL = --name (Default = --uid), --label = Alias.
FAKEBIN="$TMP/fakebin"
mkdir -p "$FAKEBIN"
cat > "$FAKEBIN/syncthing" <<'FAKE'
#!/usr/bin/env bash
case "$*" in
  *"config folders list"*) exit 0 ;;          # Share existiert nicht → add-Pfad
  *"folders add"*)
    prev=""
    for a in "$@"; do
      [ "$prev" = "--id" ]    && echo "ID_TOKEN=[$a]"
      [ "$prev" = "--label" ] && echo "LABEL_TOKEN=[$a]"
      prev="$a"
    done ;;
esac
FAKE
chmod +x "$FAKEBIN/syncthing"
add_args() { PATH="$FAKEBIN:$PATH" bash "$SYNC_SHARE" "$@" --register 2>&1; }

mkdir -p "$TMP/reg"
# Default: ohne --name ist das Syncthing-LABEL gleich der --uid (jetzt black-box beobachtbar)
OUT="$(add_args "$TMP/reg" --uid acme)"
it "register: ID = --uid";                          contains "$OUT" "ID_TOKEN=[acme]"
it "register: Default-Label = --uid (kein --name)"; contains "$OUT" "LABEL_TOKEN=[acme]"

# --name setzt das Syncthing-LABEL; Leerzeichen bleiben EIN Token (korrektes Quoting)
OUT="$(add_args "$TMP/reg" --uid acme --name "Acme Inc")"
it "register: --name → Syncthing-LABEL";            contains "$OUT" "LABEL_TOKEN=[Acme Inc]"
it "register: --name lässt ID = --uid unberührt";   contains "$OUT" "ID_TOKEN=[acme]"

# Alias-Disziplin: --label darf eine bereits gesetzte --uid NICHT überschreiben — beide Reihenfolgen
OUT="$(add_args "$TMP/reg" --uid acme --label other)"
it "Alias: --uid x --label y → ID bleibt x";        contains "$OUT" "ID_TOKEN=[acme]"
it "… und --label landet NICHT in der ID";          not_contains "$OUT" "ID_TOKEN=[other]"
OUT="$(add_args "$TMP/reg" --label other --uid acme)"
it "Alias: --label y --uid x → ID bleibt x";        contains "$OUT" "ID_TOKEN=[acme]"
it "… (label-zuerst) --label nicht in der ID";      not_contains "$OUT" "ID_TOKEN=[other]"

# --name beeinflusst NUR die Registrierung, NICHT die Whitelist/Artefakte (Trennung Label↔Sync-Inhalt)
PROJ_NM="$TMP/proj_nameonly"
mkdir -p "$PROJ_NM"
bash "$SYNC_SHARE" "$PROJ_NM" --uid acme --name "Acme Inc" --no-register >/dev/null 2>&1
it "--name taucht NICHT in der .stignore auf";       not_ok grep -qF "Acme Inc" "$PROJ_NM/.stignore"
# Whitelist mit --name muss byte-gleich der ohne --name sein (Anzeigename ≠ Sync-Inhalt)
PROJ_NM2="$TMP/proj_noname"
mkdir -p "$PROJ_NM2"
bash "$SYNC_SHARE" "$PROJ_NM2" --uid acme --no-register >/dev/null 2>&1
it ".stignore identisch mit/ohne --name";            eq "$(sed 's#'"$PROJ_NM"'#X#;s#'"$PROJ_NM2"'#X#' "$PROJ_NM/.stignore" | cksum)" "$(sed 's#'"$PROJ_NM"'#X#;s#'"$PROJ_NM2"'#X#' "$PROJ_NM2/.stignore" | cksum)"

# --- usage/--help-Regression: die sed-Range (2,33) muss die NEUEN Optionen einschließen ---
# (Der Commit weitete 2,29 → 2,33; eine spätere Verschiebung würde --uid/--name still abschneiden.)
HELP="$(bash "$SYNC_SHARE" --help 2>&1)"
it "--help: zeigt --uid";                            contains "$HELP" "--uid"
it "--help: zeigt --name";                           contains "$HELP" "--name"
it "--help: zeigt --label als DEPRECATED";           contains "$HELP" "DEPRECATED"
it "--help: zeigt --device (Range-Ende nicht zu kurz)"; contains "$HELP" "--device"
it "--help: leckt keinen Code (kein 'set -uo')";     not_contains "$HELP" "set -uo pipefail"

summary
