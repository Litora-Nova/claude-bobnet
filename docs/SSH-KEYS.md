# SSH-Keys — Server mit GitHub/GitLab & untereinander verbinden

Runbook für jeden neuen Server im Verbund (Dev-Server, Deploy-Ziele).
**Merksatz: Der SSH-Public-Key (`*.pub`) ist öffentlich und darf überall stehen.
Tokens/PATs sind SECRETS — niemals in Docs, Commits oder Chats.**

## 1) Key erzeugen (ohne Passphrase = ssh ohne Passwort)

```bash
[ -f ~/.ssh/id_ed25519 ] || ssh-keygen -t ed25519 -N "" -f ~/.ssh/id_ed25519 -C "$(whoami)@$(hostname)"
cat ~/.ssh/id_ed25519.pub
```

## 2) Bei GitHub + GitLab hinterlegen (Web-Weg, empfohlen)

Den `cat`-Output aus Schritt 1 einfügen bei:

| Forge | URL | Pfad im UI |
|---|---|---|
| GitHub | https://github.com/settings/keys | „New SSH key" |
| GitLab | https://gitlab.com/-/user_settings/ssh_keys | „Add new key" |

## 3) Testen

```bash
ssh -T git@github.com   # erwartet: "Hi <user>! You've successfully authenticated…"
ssh -T git@gitlab.com   # erwartet: "Welcome to GitLab, @<user>!"
```

## 4) Server-zu-Server: Public Key in `authorized_keys` pushen

Von einer Maschine, die bereits Zugang zum Zielserver hat (z. B. dem Mac),
den Public Key der **Quell**-Maschine ans Ziel anhängen:

```bash
echo '<PUBKEY-ZEILE aus Schritt 1>' | ssh <user>@<zielserver> \
  'mkdir -p ~/.ssh && chmod 700 ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys'
```

Danach kann die Quell-Maschine passwortlos auf den Zielserver:
`ssh <user>@<zielserver>`.

## Hinweis für reine Deploy-Zielserver

Statt eines Account-Keys (Zugriff auf ALLE Repos des Accounts) lieber
**Deploy Keys pro Repo (read-only)**: GitLab → Projekt → Settings → Repository →
Deploy Keys · GitHub → Repo → Settings → Deploy keys. Gleicher Public Key,
minimaler Blast-Radius.
