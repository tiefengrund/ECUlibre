# Erstellung der administrativen Zugänge für DBAs

Administrative Zugangsdaten (inkl. Passwort-Hashes) können entweder direkt auf einem bestehenden Datenbanksystem oder lokal auf einem beliebigen Linux/Unix-System generiert werden.

---

## PostgreSQL

### In der Datenbank

#### SCRAM-SHA-256 Hash generieren
```sql
SELECT 'SCRAM-SHA-256$4096:' || encode(gen_salt('scram-sha-256'), 'base64') || '$' ||
       encode(digest('password' || gen_salt('scram-sha-256'), 'sha256'), 'base64');
```

#### Alternativ: bcrypt-Hash mit `crypt()`
```sql
SELECT crypt('mypassword', gen_salt('bf', 8));
```

#### Benutzer mit Passwort erstellen
```sql
CREATE USER myuser WITH PASSWORD 'mypassword';
```

Hinweis: PostgreSQL speichert Passwörter intern in der konfigurierten `password_encryption`-Methode. Empfohlen: `scram-sha-256`.

---

### Lokal auf der Kommandozeile (mit Python)

Erzeuge einen SHA-256-basierten Passwort-Hash:
```bash
python3 -c "
import crypt, getpass
password = getpass.getpass('Password: ')
print(crypt.crypt(password, crypt.mksalt(crypt.METHOD_SHA256)))
"
```

Sichere Methode zur lokalen Passwortverarbeitung ohne Anzeige im Terminal.

---

## MariaDB / MySQL

### Lokal auf der Kommandozeile (Bash)

SHA-256 Hash generieren:
```bash
echo -n 'mypassword' | openssl dgst -sha256 -binary | xxd -p
```

Hinweis: Je nach MySQL/MariaDB-Version ist das direkte Setzen eines SHA-256-Hashes nur mit geeigneter Plugin-Konfiguration möglich (z. B. `caching_sha2_password` oder `sha256_password`).


30 kisten halber liter
urkundenpapier
