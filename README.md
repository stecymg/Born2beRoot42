# Born2beRoot

Mise en place et durcissement d'un serveur Debian sous machine virtuelle, avec partitionnement chiffré, politique de sécurité stricte et supervision automatisée.

Projet réalisé dans le cadre du cursus **École 42 Paris** (2022).

---

## Objectif

Configurer un serveur Debian minimaliste respectant un ensemble de contraintes de sécurité :

- Aucune interface graphique
- Disque chiffré et partitionné via LVM
- Accès distant restreint au seul protocole SSH, sur un port non standard
- Pare-feu actif n'autorisant que le strict nécessaire
- Politique de mots de passe et de privilèges durcie
- Supervision de l'état du serveur diffusée automatiquement à tous les utilisateurs connectés

---

## Environnement

| Élément | Choix |
|---|---|
| Hyperviseur | VirtualBox |
| Système | Debian (version stable) |
| Interface | Aucune — administration intégralement en ligne de commande |
| Contrôle d'accès | AppArmor |
| Pare-feu | UFW |
| Accès distant | OpenSSH, port 4242 |

**Pourquoi Debian plutôt que Rocky Linux ?** Debian repose sur un cycle de publication privilégiant la stabilité sur la fraîcheur des paquets, ce qui en fait une base répandue en environnement serveur. Sa documentation est abondante et son gestionnaire de paquets APT bien documenté, ce qui limitait le risque de blocage sur un premier projet d'administration système.

---

## Architecture disque

Le disque est chiffré avec **LUKS**, et **LVM** est monté par-dessus le volume déchiffré. Ce découpage isole les zones d'écriture sensibles : une saturation des journaux dans `/var/log` ou du répertoire d'un utilisateur dans `/home` ne peut pas immobiliser la racine du système.

```
sda
├── sda1                  → /boot (non chiffré)
└── sda5                  → conteneur LUKS
    └── LVMGroup (VG)
        ├── root          → /
        ├── swap          → [SWAP]
        ├── home          → /home
        ├── var           → /var
        ├── srv           → /srv
        ├── tmp           → /tmp
        └── var-log       → /var/log
```

Le dimensionnement suit la même logique : l'essentiel de l'espace revient à `/` et `/home`, tandis que `/var/log`, `/tmp` et `/srv` reçoivent des volumes plus réduits mais suffisants pour absorber leur croissance sans déborder. `/boot` reste hors du conteneur chiffré, puisqu'il doit être lisible avant le déverrouillage LUKS au démarrage.

Vérification :

```bash
lsblk
```

---

## Durcissement

### Accès SSH

Le service écoute sur le **port 4242** et non sur le 22. Cela n'apporte aucune sécurité cryptographique, mais élimine l'essentiel du bruit des scanners automatisés qui ciblent le port par défaut. La connexion en root est refusée : l'administration passe obligatoirement par un compte utilisateur puis une élévation via `sudo`, ce qui rend les actions privilégiées traçables.

```bash
sudo systemctl status ssh
ssh <user>@<ip> -p 4242
```

### Pare-feu

UFW est actif avec une politique de refus par défaut en entrée. Seul le port 4242 est ouvert.

```bash
sudo ufw status numbered
```

### Politique de mots de passe

Appliquée en deux couches :

- **`/etc/login.defs`** — durée de vie maximale de 30 jours, délai minimal de 2 jours avant modification, avertissement 7 jours avant expiration.
- **`/etc/pam.d/common-password`** — via `pam_pwquality` : longueur minimale de 10 caractères, au moins une majuscule et un chiffre, pas plus de 3 caractères identiques consécutifs, interdiction d'inclure le nom de l'utilisateur, et différence d'au moins 7 caractères avec l'ancien mot de passe.

Vérification de la politique appliquée à un compte :

```bash
sudo chage -l <user>
```

### Privilèges sudo

Configuration déportée dans `/etc/sudoers.d/` plutôt que par modification directe de `/etc/sudoers` — une erreur de syntaxe dans un fichier dédié est moins risquée et se corrige sans verrouiller l'accès administrateur.

Règles appliquées :

- Trois tentatives d'authentification maximum
- Message d'erreur personnalisé en cas d'échec
- Exécution restreinte à un TTY
- `secure_path` limitant les répertoires d'exécution
- **Journalisation systématique** des entrées et sorties dans `/var/log/sudo/`

C'est ce dernier point qui donne la traçabilité : chaque commande privilégiée laisse une trace horodatée. La journalisation repose sur deux mécanismes complémentaires — un fichier de log listant les commandes exécutées, et une arborescence d'entrées/sorties (`iolog`) conservant le contenu réel de chaque session, y compris ce qui s'est affiché à l'écran.

```bash
sudo ls /var/log/sudo/
```

### AppArmor

Activé au démarrage. AppArmor confine chaque programme à un profil définissant les fichiers et capacités auxquels il peut accéder — un contrôle d'accès obligatoire qui limite la portée d'une compromission applicative, là où les permissions UNIX classiques ne protègent que par utilisateur.

```bash
sudo aa-status
```

---

## Supervision

Le script [`monitoring.sh`](./monitoring.sh) collecte l'état du serveur et le diffuse à **toutes les sessions ouvertes** via `wall`.

Indicateurs remontés :

| Indicateur | Source |
|---|---|
| Architecture et noyau | `uname -a` |
| Processeurs physiques et logiques | `/proc/cpuinfo` |
| Mémoire utilisée / totale et pourcentage | `free` |
| Occupation disque | `df` |
| Charge CPU | `top` |
| Date du dernier démarrage | `uptime -s` |
| Présence de LVM | `lsblk` |
| Connexions TCP établies | `/proc/net/sockstat` |
| Utilisateurs connectés | `who` |
| Adresses IP et MAC | `hostname`, `ip link` |
| Nombre de commandes sudo exécutées | `/var/log/sudo/` |

### Planification

Diffusion toutes les 10 minutes depuis le démarrage, via la crontab de root :

```cron
*/10 * * * * /root/monitoring.sh
```

Le pas minimal de cron étant d'une minute, obtenir une fréquence inférieure suppose de décaler une seconde exécution :

```cron
*/1 * * * * /root/monitoring.sh
*/1 * * * * sleep 30 && /root/monitoring.sh
```

Consultation de la configuration :

```bash
sudo crontab -l
```

---

## Ce que le projet m'a apporté

- **Partitionnement et chiffrement** — comprendre l'empilement LUKS/LVM, et pourquoi isoler `/var/log` et `/home` relève de la disponibilité du service autant que de l'organisation.
- **Défense en profondeur** — constater qu'aucune mesure ne suffit seule : le pare-feu, le confinement AppArmor, la politique de mots de passe et la traçabilité sudo couvrent des surfaces d'attaque distinctes.
- **Traçabilité** — la journalisation des élévations de privilèges comme prérequis de toute administration à plusieurs mains.
- **Administration sans interface graphique** — travailler exclusivement en ligne de commande, en s'appuyant sur les pages de manuel plutôt que sur des tutoriels.

---

## Commandes de vérification

```bash
lsblk                              # partitions et volumes logiques
sudo aa-status                     # état d'AppArmor
getent group sudo                  # membres du groupe sudo
sudo systemctl status ssh          # état du service SSH
sudo ufw status numbered           # règles du pare-feu
sudo crontab -l                    # planification du monitoring
sudo chage -l <user>               # politique d'expiration d'un compte
```
