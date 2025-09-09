## Terraform Variable, Datenquellen und Modulparameter

### Variablen (`variable`)

| Name                | Typ     | Beschreibung                                                                 |
|---------------------|----------|------------------------------------------------------------------------------|
| `config_dir`        | `string` | Pfad zum Verzeichnis mit den YAML-Konfigurationsdateien                     |
| `openstack-network` | `string` | Name des OpenStack-Netzwerks für die DB-VMs                                 |

---

### Datenquellen (`data`)

| Name                                         | Typ                                | Beschreibung                                                                |
|----------------------------------------------|-------------------------------------|-----------------------------------------------------------------------------|
| `openstack_images_image_v2.dbaas`            | OpenStack Image Lookup              | Holt das jeweils aktuellste Image pro Datenbankdeployment                  |
| `openstack_keymanager_secret_v1.*`           | OpenStack Secrets (Monitoring/Token)| Liest Monitoring-Zugangsdaten und Backup-Token aus Keymanager              |

---

### Locals (`locals`)

| Name                | Beschreibung                                                                 |
|---------------------|------------------------------------------------------------------------------|
| `verfahren_files`   | Liste der YAML-Dateien in `specialist-procedures`                            |
| `*_config_file`     | Dekodierte Datenbank-spezifische YAML-Dateien (`postgres`, `mariadb`, etc.) |
| `global_config_file`| Globale Konfigurationswerte                                                  |
| `standardize_config`| Zusammengeführte und normierte Konfig pro DB-Typ                             |
| `deployments`       | Geparste Inhalte der `specialist-procedures/*.yaml`                          |
| `vm_config`         | Final zusammengeführte Datenbank-Konfiguration je Deployment                 |
| `vm_image_config`   | `vm_config` + OpenStack-Image-ID je Instanz                                  |
| `cred_vm_config`    | `vm_image_config` + generiertes DB-Passwort                                  |
| `updated_vm_config` | `cred_vm_config` + private IPs aus den Modulen                               |
| `db_mon_secrets`    | Dekodierte Monitoring-Passwörter aus OpenStack Secrets                       |

---

### Ressourcen (`resource`)

| Name                                     | Typ                              | Beschreibung                                                   |
|------------------------------------------|-----------------------------------|----------------------------------------------------------------|
| `random_password.mon_password`           | Zufallspasswort                   | Passwort für Monitoring-Zugang                                 |
| `random_password.db_password`            | Zufallspasswörter pro Deployment  | DB-spezifisches Root-Passwort pro Instanz                      |
| `openstack_keymanager_secret_v1.*`       | OpenStack Secrets                 | Speichert generierte Passwörter im OpenStack Keymanager        |
| `openstack_compute_keypair_v2.dbaas-deploy` | SSH-Keypair                    | SSH-Key für Deployment                                         |

---

### Module (`module`)

| Name             | Quelle                      | Wichtige Parameter                                    | Beschreibung                                        |
|------------------|------------------------------|-------------------------------------------------------|-----------------------------------------------------|
| `db_postgresql`  | `../../modules/db_postgresql`| `vm_config`, `dbaas_mon_pw`, `dbaas_backup_token`     | Erstellt PostgreSQL-Datenbankinstanzen              |
| `db_mariadb`     | `../../modules/db_mariadb`   | `vm_config`, `dbaas_mon_pw`, `dbaas_backup_token`     | Erstellt MariaDB-Datenbankinstanzen                 |
| `db_mysql`       | `../../modules/db_mysql`     | `vm_config`, `dbaas_mon_pw`, `dbaas_backup_token`     | Erstellt MySQL-Datenbankinstanzen                   |
| `db_mssql`       | `../../modules/db_mssql`     | `vm_config`, `dbaas_mon_pw`, `dbaas_backup_token`     | Erstellt MSSQL-Datenbankinstanzen                   |
| `loadbalancer`   | `../../modules/loadbalancer` | `configmap`, `network`, `openstack-project`           | Erstellt Loadbalancer-Konfiguration für VMs         |
| `dns-records`    | `../../modules/dns-records`  | `db_vm_config`, `openstack-project`                   | Erstellt DNS-Records für VMs                        |
| `monitoring_sync`| `../../modules/monitoring_sync`| `db_vm_config`, `environment`, `openstack-project`  | Synchronisiert VMs mit dem Monitoring-System        |

---

### Backend-Konfiguration

| Einstellung        | Wert                                                           | Beschreibung                                  |
|--------------------|----------------------------------------------------------------|-----------------------------------------------|
| `backend "http"`   | GitLab HTTP Remote Backend                                     | Terraform-Status wird remote in GitLab gespeichert |
| `address`          | `https://git.thlv.de/api/v4/projects/350/terraform/state/test-kramer` | Pfad zum Terraform-Statusfile                 |
