#!/usr/bin/env bash
# tests/dashboard_theme_spec.sh — Black-Box-Spec gegen die PUREN, exportierten
# Funktionen der Tenant-/Theme-Schicht (#9):
#   theme.ts  → themeIdOf(tenant, team)  : Theme-Vorrang-Kette pro Modus +
#                                          i18n(value, locale) : Locale-Auflösung
#   tenant.ts → tenantFromProject(p)     : Registry-Eintrag → Tenant (Happy-Path:
#                                          standup-Ableitung, uid/name-Fallback,
#                                          themeId/label/icon/responsibility-Passthrough)
#
# WARUM hier node --experimental-strip-types: diese Helfer sind .ts (nicht .mjs),
# aber ihre Logik-Pfade brauchen KEINE Nuxt-Runtime — nur node:path + process.env.
# Die type-only-Imports (./tenant, ./team) werden beim Type-Stripping entfernt.
#   ⇒ als Bash-Spec SINNVOLL testbar (keine Mocks, keine HTTP-Schicht).
# BEWUSST NICHT hier: der createError-throw von tenantFromProject (fehlt path/standup)
#   und tenantOf(event) — die brauchen Nuxts Auto-Imports/H3-Event. Die beobachtbare
#   Semantik davon (404 bei unbekannter uid, Skip kaputter Einträge) testet die
#   HTTP-Spec gegen den laufenden Dev-Server.
#
# Skip-Disziplin: läuft die node-strip-types-Variante nicht (zu altes node), SKIPPT
# die Spec GRÜN (CI-sicher) statt rot zu werden — wie die HTTP-Spec ohne Server.
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/_helper.sh"

THEME_TS="$ENGINE_ROOT/dashboard/server/utils/theme.ts"
TENANT_TS="$ENGINE_ROOT/dashboard/server/utils/tenant.ts"

# --- Voraussetzungen / sauberer Skip -----------------------------------------
if [ ! -f "$THEME_TS" ] || [ ! -f "$TENANT_TS" ]; then
  it "dashboard tenant/theme utils vorhanden — sonst SKIP grün"
  printf '  ⊘ SKIP: %s oder %s fehlt (kein Dashboard in diesem Checkout)\n' "$THEME_TS" "$TENANT_TS"
  summary; exit $?
fi
if ! command -v node >/dev/null 2>&1 || ! node --experimental-strip-types --input-type=module -e "0" >/dev/null 2>&1; then
  it "node --experimental-strip-types verfügbar — sonst SKIP grün"
  printf '  ⊘ SKIP: node mit --experimental-strip-types nicht verfügbar (CI-sicher grün)\n'
  summary; exit $?
fi

# Helfer: eine JS-Zeile gegen das gestrippte .ts-Modul ausführen, stdout zurück.
nt() {  # nt <import-from-theme.ts-expr>
  node --experimental-strip-types --input-type=module -e \
    "import {themeIdOf, i18n} from 'file://$THEME_TS'; console.log($1)" 2>/dev/null
}
np() {  # np <import-from-tenant.ts-expr>
  node --experimental-strip-types --input-type=module -e \
    "import {tenantFromProject} from 'file://$TENANT_TS'; console.log($1)" 2>/dev/null
}

# ── themeIdOf — Modus A (Tenant, uid gesetzt): NUXT_THEME wird IGNORIERT ───────
# Vorrang: registry-theme > team.config.theme > 'bobiverse'.
export NUXT_THEME='envtheme'   # darf im Tenant-Modus NIE durchschlagen

it "Modus A: registry-theme hat Vorrang (registry > config > default)"
eq "$(nt "themeIdOf({uid:'x', themeId:'regtheme'}, {config:{theme:'cfgtheme'}})")" "regtheme"

it "Modus A: ohne registry-theme greift team.config.theme"
eq "$(nt "themeIdOf({uid:'x', themeId:null}, {config:{theme:'cfgtheme'}})")" "cfgtheme"

it "Modus A: ohne beides → Engine-Default 'bobiverse'"
eq "$(nt "themeIdOf({uid:'x', themeId:null}, {config:{}})")" "bobiverse"

it "Modus A: NUXT_THEME wird im Tenant-Modus IGNORIERT (Auflage #9)"
# trotz NUXT_THEME=envtheme bleibt es bei config/default — NICHT envtheme
eq "$(nt "themeIdOf({uid:'x', themeId:null}, {config:{theme:'cfgtheme'}})")" "cfgtheme"

# ── themeIdOf — Modus B (Env-Fallback, uid==null): NUXT_THEME zählt ───────────
it "Modus B: NUXT_THEME hat Vorrang (env > config > default)"
eq "$(nt "themeIdOf({uid:null}, {config:{theme:'cfgtheme'}})")" "envtheme"

unset NUXT_THEME
it "Modus B: ohne NUXT_THEME greift team.config.theme"
eq "$(nt "themeIdOf({uid:null}, {config:{theme:'cfgtheme'}})")" "cfgtheme"

it "Modus B: ohne beides → Engine-Default 'bobiverse'"
eq "$(nt "themeIdOf({uid:null}, {config:{}})")" "bobiverse"

# ── i18n — Locale-Auflösung (Plain passthrough; locale → de → en → erster) ─────
it "i18n: gewünschte Locale wird gewählt"
eq "$(nt "i18n({de:'Hallo', en:'Hi'}, 'de')")" "Hallo"

it "i18n: fehlende Locale → de-Fallback"
eq "$(nt "i18n({de:'Hallo', en:'Hi'}, 'fr')")" "Hallo"

it "i18n: fehlt de → en-Fallback"
eq "$(nt "i18n({en:'Hi'}, 'fr')")" "Hi"

it "i18n: nur exotische Locale-Keys → erster Wert"
eq "$(nt "i18n({fr:'Bonjour'}, 'es')")" "Bonjour"

it "i18n: Plain-String wird durchgereicht"
eq "$(nt "i18n('plain', 'de')")" "plain"

it "i18n: undefined → leerer String (kein Crash)"
eq "$(nt "'['+i18n(undefined)+']'")" "[]"

# ── tenantFromProject — Happy-Path (Registry-Eintrag → Tenant) ────────────────
it "tenantFromProject: standup aus path abgeleitet (path/_dev_team/standup)"
eq "$(np "tenantFromProject({uid:'x', path:'/tmp/p'}).standupDir")" "/tmp/p/_dev_team/standup"

it "tenantFromProject: explizites standup hat Vorrang vor der path-Ableitung"
eq "$(np "tenantFromProject({uid:'x', path:'/tmp/p', standup:'/tmp/explicit'}).standupDir")" "/tmp/explicit"

it "tenantFromProject: teamConfigPath liegt im standupDir"
eq "$(np "tenantFromProject({uid:'x', path:'/tmp/p'}).teamConfigPath")" "/tmp/p/_dev_team/standup/team.config.json"

it "tenantFromProject: themeId aus Registry durchgereicht"
eq "$(np "String(tenantFromProject({uid:'x', path:'/tmp/p', theme:'mytheme'}).themeId)")" "mytheme"

it "tenantFromProject: ohne Registry-theme → themeId null (Kette entscheidet später)"
eq "$(np "String(tenantFromProject({uid:'x', path:'/tmp/p'}).themeId)")" "null"

it "tenantFromProject: uid-Fallback auf name (id-lose Alt-Einträge)"
eq "$(np "tenantFromProject({name:'noUid', path:'/tmp/q'}).uid")" "noUid"

it "tenantFromProject: label/icon/responsibility werden durchgereicht (#7)"
eq "$(np "[tenantFromProject({uid:'x', path:'/tmp/p', label:'L', icon:'i.png', responsibility:'R'})].map(t=>t.label+'|'+t.icon+'|'+t.responsibility)[0]")" "L|i.png|R"

it "tenantFromProject: label-Fallback auf name, wenn label fehlt"
eq "$(np "tenantFromProject({uid:'x', name:'theName', path:'/tmp/p'}).label")" "theName"

# ── themeOf → personaOf/avatarFileOf/displayNameOf: Name-Override treibt das Gesicht ─
# "mit dem Namen automatisch das Bild": heisst ein Member wie eine Theme-Persona (Rename
# Bob→Basil), gewinnt DEREN Avatar/Bio — `id` bleibt der strukturelle Join, `name` treibt
# die Identitaet. Temp-Theme mit id-Persona (Bob) + gleichnamiger Override-Persona (Basil).
SPEC_THEMES="$(mktemp -d)"
mkdir -p "$SPEC_THEMES/t1/avatars"
cat > "$SPEC_THEMES/t1/theme.json" <<'JSON'
{ "id":"t1", "defaultAvatar":"fallback.png", "personas": {
  "BOB-techlead": { "name":"Bob",   "avatar":"Bob.png",   "bio":"lead"  },
  "FUN-basil":    { "name":"Basil", "avatar":"Basil.png", "bio":"basil" }
} }
JSON
nth() {  # nth <expr über th = themeOf(...)>
  NUXT_THEMES_DIR="$SPEC_THEMES" node --experimental-strip-types --input-type=module -e \
    "import {themeOf} from 'file://$THEME_TS'; const th=themeOf({uid:'x',themeId:'t1'},{config:{},TEAM:{Basil:{name:'Basil',id:'BOB-techlead'},Bob:{name:'Bob',id:'BOB-techlead'}}}); console.log($1)" 2>/dev/null
}

it "themeOf: Name-Override treibt den Avatar (Basil → Basil.png, NICHT Bobs Bild)"
eq "$(nth "th.avatarFileOf('Basil')")" "Basil.png"

it "themeOf: ohne Override bleibt die id-Persona (Bob → Bob.png)"
eq "$(nth "th.avatarFileOf('Bob')")" "Bob.png"

it "themeOf: displayName folgt dem Namen (Basil)"
eq "$(nth "th.displayNameOf('Basil')")" "Basil"

it "themeOf: bio folgt der Namens-Persona (Basil-Bio)"
eq "$(nth "th.bioOf('Basil')")" "basil"

it "themeOf: unbekannter Name ohne Persona → defaultAvatar (nie leer/Emoji)"
eq "$(nth "th.avatarFileOf('Ghost')")" "fallback.png"

# uid-Log-Key → Persona (der `bobnet-infra.log → Garfield`-Fall): memberOf löst den
# Log-Key (uid) auf den Member, Anzeige+Avatar folgen dessen Persona-Namen — NICHT dem uid.
nthu() {  # team MIT memberOf (uid→Member); agentName = Log-Key
  NUXT_THEMES_DIR="$SPEC_THEMES" node --experimental-strip-types --input-type=module -e \
    "import {themeOf} from 'file://$THEME_TS'; const M={name:'Basil',id:'BOB-techlead',uid:'trend-lead'}; const team={config:{},TEAM:{Basil:M},memberOf:(k)=>({Basil:M,'trend-lead':M})[k]}; const th=themeOf({uid:'x',themeId:'t1'},team); console.log($1)" 2>/dev/null
}
it "themeOf: uid-Log-Key → Persona-Avatar (trend-lead → Basil.png, nicht default)"
eq "$(nthu "th.avatarFileOf('trend-lead')")" "Basil.png"

it "themeOf: uid-Log-Key → Anzeige-Name der Persona (trend-lead → Basil, nicht 'trend-lead')"
eq "$(nthu "th.displayNameOf('trend-lead')")" "Basil"

rm -rf "$SPEC_THEMES"

summary
