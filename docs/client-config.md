# relp-client.conf — Explications pédagogiques

Configuration cliente RELP+mTLS. Cette VM capte ses logs locaux et
les envoie chiffrés/authentifiés vers le serveur LOG-FRONT-01
(172.16.1.18:6514). Placeholder `__CN__` à remplacer par le hostname
exact de la machine avant déploiement (doit correspondre au CN signé
via `generate-client-cert.sh` sur LOG-FRONT-01).

## Détail des instructions

- **`module(load="imuxsock")`** : Capte les logs émis localement sur
  cette machine, notamment ceux envoyés via la commande `logger` ou
  par les daemons système qui écrivent sur `/dev/log`. Sans ce
  module, le client n'a rien de local à transmettre via RELP — c'est
  la porte d'entrée des messages avant leur envoi.

- **`module(load="omrelp" tls.tlslib="openssl")`** : Charge le
  module de **sortie** RELP (`om` = Output Module, à l'inverse
  d'`imrelp` qui est un Input Module côté serveur). Force
  explicitement la bibliothèque OpenSSL pour le TLS, par cohérence
  avec la configuration serveur (attention : `"openssl"`, jamais
  `"ossl"` qui est invalide).

- **`action(type="omrelp" ...)`** : Définit l'action d'envoi
  effective — c'est ce bloc qui déclenche réellement la transmission
  des logs captés vers le serveur distant.

  - **`target="172.16.1.18"`** : Adresse IP de LOG-FRONT-01 sur le
    réseau `172.16.1.0/24`, la machine qui héberge le serveur RELP.

  - **`port="6514"`** : Port dédié RELP+TLS sur lequel `imrelp` du
    serveur est en écoute — distinct du port 514 utilisé par le flux
    `imtcp` existant en clair sur LOG-FRONT-01.

  - **`tls="on"`** : Active obligatoirement le chiffrement TLS pour
    cette connexion sortante.

  - **`tls.cacert`** : Chemin vers le certificat public de la CA
    locale. Permet au **client** de vérifier que le serveur auquel il
    se connecte est bien légitime — c'est la partie
    "authentification du serveur" du mTLS, symétrique à ce que le
    serveur fait pour authentifier le client.

  - **`tls.mycert`** / **`tls.myprivkey`** : Certificat public et clé
    privée **de cette machine cliente précise**, présentés au serveur
    pour prouver son identité (partie "authentification du client" du
    mTLS). Le CN unique par machine (au lieu d'un CN générique
    partagé) permet de tracer et de révoquer individuellement le
    certificat d'une VM compromise, sans impacter les autres clients.

  - **`tls.authmode="certvalid"`** : Exige que le certificat présenté
    par le serveur soit lui-même valide et signé par la CA de
    confiance. Sans ce mode explicite, la connexion serait chiffrée
    mais l'identité du serveur ne serait pas réellement vérifiée —
    insuffisant pour une exigence de mTLS.

## Fonctionnement du module de sortie (OM)

Le client **ENVOIE** le log : contrairement au serveur qui reste
passif à écouter, le client est actif — il capte ses propres
événements locaux (via `imuxsock`) et les pousse vers l'extérieur.
Le module de sortie (**O**utput **M**odule) agit comme un
entonnoir d'émission : sa fonction est de faire sortir ce qui a été
généré localement, vers la destination définie dans `action()`.
