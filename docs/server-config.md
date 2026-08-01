# relp-server.conf — Explications pédagogiques

Configuration du serveur RELP+mTLS sur LOG-FRONT-01, isolée du flux
imtcp existant (port 514, en clair) déjà en place sur cette machine.

## Détail des instructions

- **`module(load="imrelp" tls.tlslib="openssl")`** : Charge le
  module d'entrée RELP (Reliable Event Logging Protocol).
  Contrairement à `imtcp` (flux existant en clair sur le port 514),
  `imrelp` garantit l'accusé de réception de chaque message ET
  supporte nativement le chiffrement TLS avec authentification
  mutuelle (mTLS). Le paramètre `tls.tlslib="openssl"` force
  explicitement l'utilisation de la bibliothèque OpenSSL (l'autre
  driver possible étant GnuTLS, moins courant sur Debian) — ce
  paramètre se déclare obligatoirement au niveau du **module**, pas
  de l'input (`imrelp` n'accepte pas `tls.tlslib` comme paramètre
  d'input, seulement de module).

- **`template(name="RelpRemoteLogs" ...)`** : Modèle de stockage qui
  indique à rsyslog comment générer dynamiquement le chemin et le nom
  des fichiers de logs reçus, ici triés par `%HOSTNAME%` dans
  `/var/log/remote-relp/`, un répertoire séparé du `/var/log/remote/`
  utilisé par le flux imtcp existant. Ce `template()` est déclaré au
  **niveau global** du fichier, avant le `ruleset` — en RainerScript,
  un template ne peut pas être imbriqué à l'intérieur d'un bloc
  `ruleset() { }` : seules les actions et instructions de traitement
  y ont leur place.

- **`ruleset(name="relp_in") { ... }`** : Définit un traitement
  **isolé**, appliqué uniquement aux messages entrant par cette
  input RELP précise. Sans ce ruleset dédié, une règle `*.*
  ?RemoteLogs` écrite au niveau global capterait aussi les messages
  locaux, ceux d'`imtcp`, d'`imklog`, etc. — mélangeant deux flux qui
  doivent rester distincts (un chiffré/authentifié, un en clair).

  - **`*.* ?RelpRemoteLogs`** : Règle de routage. Le premier
    astérisque signifie "toutes les facilités" (auth, cron, mail,
    sys, etc.), le second "tous les niveaux de criticité" (info,
    warning, err, debug...). Le point d'interrogation signifie
    "applique le template dynamique suivant" — envoie donc tous ces
    logs reçus par RELP vers le chemin généré par `RelpRemoteLogs`.

  - **`stop`** : Arrête le traitement du message dans ce ruleset une
    fois écrit, pour éviter qu'il ne soit évalué une seconde fois par
    d'autres règles globales du système.

- **`input(type="imrelp" port="6514" ruleset="relp_in" ...)`** : Crée
  le point d'écoute. Demande à rsyslog d'ouvrir le port 6514 (port
  dédié RELP+TLS, distinct du 514 déjà utilisé par imtcp) et de
  rattacher tout ce qui y arrive au ruleset `relp_in` défini
  au-dessus, plutôt qu'au traitement par défaut.

  - **`tls="on"`** : Active obligatoirement le chiffrement TLS sur ce
    port — sans quoi n'importe quelle machine du réseau pourrait
    envoyer des logs en clair, non authentifiés.

  - **`tls.cacert`** : Chemin vers le certificat public de la CA
    locale. Sert au serveur à vérifier que le certificat présenté par
    un client a bien été signé par cette autorité de confiance —
    c'est la pierre angulaire du mTLS.

  - **`tls.mycert`** / **`tls.myprivkey`** : Certificat public et clé
    privée **du serveur lui-même**, présentés au client pour qu'il
    vérifie l'identité du serveur (partie "authentification du
    serveur" du mTLS).

  - **`tls.authmode="certvalid"`** : Mode d'authentification strict.
    Exige que le client présente un certificat valide, signé par la
    CA de confiance. Sans ce mode explicite, TLS chiffrerait la
    connexion mais n'authentifierait pas forcément l'identité du
    client — ce qui ne remplirait pas l'exigence de mTLS (chiffrement
    seul ≠ authentification mutuelle).

## Fonctionnement du module d'entrée (IM)

Le serveur **REÇOIT et CAPTURE** le log : il reste passif sur le
réseau et écoute. Quand un log arrive sur le port 6514, `imrelp` le
fait entrer dans le système rsyslog pour qu'il soit traité et écrit
dans un fichier. Le module d'entrée (**I**nput **M**odule) agit comme
un entonnoir de réception : sa fonction est de capter ce qui arrive
de l'extérieur, avant que le ruleset ne décide où l'écrire.

## Choix assumé : pas de drop de privilèges (rsyslogd tourne en root)

Une première itération de cette conf incluait `$PrivDropToUser` /
`$PrivDropToGroup` vers un compte de service dédié `rsyslog-svc`,
dans une logique de moindre privilège. Ce choix a été abandonné après
test : `$PrivDropToUser` s'applique au **process rsyslogd dans son
ensemble** (il n'existe qu'une seule instance rsyslogd sur cette VM,
qui charge à la fois cette conf RELP et la conf système d'origine).
Le drop de privilèges cassait donc l'écriture des flux syslog
préexistants (`/var/log/auth.log`, `/var/log/syslog`...), qui
nécessitent des droits root/adm indépendants de notre flux RELP.

Isoler proprement le drop de privilèges au seul flux RELP nécessiterait
une seconde instance rsyslogd dédiée (processus, conf et permissions
séparés) — hors périmètre de ce lab. Pour ce TP, rsyslogd continue
donc de tourner en root, comme c'était déjà le cas avant nos
modifications, ce qui reste cohérent avec le comportement par défaut
du paquet Debian `rsyslog` (qui ne crée d'ailleurs pas d'utilisateur
système dédié par défaut).