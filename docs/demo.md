# Scénario de démonstration — Serveur syslog - RELP + mTLS natif

**Objectif** : démontrer que les logs envoyés par un client vers LOG-FRONT-01 sont bien transmis via RELP **et** chiffrés en TLS mutuel, avec une preuve technique (capture réseau) et non une simple absence d'erreur.

**Durée estimée** : 5 à 7 minutes
**Machines nécessaires** : LOG-FRONT-01 (serveur) + un client déjà déployé (ex: BASTION-FRONT-01)
**Deux terminaux ouverts en parallèle** : un sur LOG-FRONT-01, un sur le client

---

## Préparation

Vérifier que les deux services tournent :

```
# Sur LOG-FRONT-01
sudo systemctl status rsyslog --no-pager

# Sur le client
sudo systemctl status rsyslog --no-pager

```

Les deux doivent afficher `active (running)`.

---

## Étape 1 — Montrer l'état initial (rien de suspect)

**Sur LOG-FRONT-01**, montrer que le serveur écoute bien sur le port dédié RELP, distinct du flux syslog classique en clair :

```
ss -tulnp | grep -E ':514|:6514'

```

**Résultat attendu** :
```
tcp   LISTEN 0  100   0.0.0.0:514    0.0.0.0:*   (flux imtcp existant, en clair)
tcp   LISTEN 0  55    0.0.0.0:6514   0.0.0.0:*   (flux RELP+mTLS, notre ajout)

```

> **Point oral** : "Le port 514 correspond au flux syslog historique de l'infrastructure, en clair. Le port 6514 est le nouveau flux RELP que nous avons ajouté, chiffré et authentifié par certificat, sans toucher à l'existant."

---

## Étape 2 — Lancer la capture réseau AVANT d'envoyer le message

**Sur LOG-FRONT-01**, lancer la capture en la limitant dans le temps pour ne pas avoir à l'arrêter manuellement devant le jury :

```
sudo timeout 20 tcpdump -i any port 6514 -X -w /tmp/demo-capture.pcap

```

Cette commande :
- capture tout le trafic sur le port 6514 pendant 20 secondes
- `-X` affiche chaque paquet en hexadécimal **et** en ASCII à l'écran, en direct
- `-w` enregistre en parallèle dans un fichier, pour l'analyse a posteriori

Le terminal reste bloqué pendant 20 secondes, en attente de paquets — c'est le moment de basculer sur le second terminal.

---

## Étape 3 — Envoyer un message de test bien identifiable

**Sur le client (BASTION-FRONT-01)**, dans les 20 secondes de la capture :

```
logger "DEMO-JURY-$(date +%H%M%S) - Ceci est un message secret en clair"

```

Le message inclut volontairement une chaîne lisible et un timestamp unique, pour prouver ensuite qu'elle n'apparaît nulle part dans la capture.

---

## Étape 4 — Lire la capture en direct

Revenir sur le terminal LOG-FRONT-01. La capture affiche des paquets de ce type :

```
16:06:42.371674 eth0 In IP 172.16.1.10.36514 > LOG-FRONT-01.lan.syslog-tls: Flags [P.], length 171
    0x0000:  4500 00df 6f03 4000 4006 70b1 ac10 0132  E...o.@.@.p....2
    0x0010:  ac10 0112 8ea2 1972 b054 7431 5039 a1d1  .......r.Tt1P9..
    0x0020:  8018 0270 5b36 0000 0101 080a 038e 20d7  ...p[6..........
    0x0030:  da4d c7cd 1703 0300 a690 a11a 11a5 2ea7  .M..............
    0x0040:  aab2 4c42 3902 f9f8 d94c 39a2 14c4 7670  ..LB9....L9...vp
```

> **Point à montrer** : à l'offset `0x0030`, la séquence `17 03 03` est la signature d'un enregistrement TLS 1.2 de type "Application Data". Tout ce qui suit est du binaire chiffré illisible — c'est visible à l'œil nu dans la colonne ASCII de droite, qui n'affiche que des points (caractères non imprimables), aucune lettre du message envoyé.

---

## Étape 5 — Preuve négative : chercher le message en clair dans la capture

C'est l'étape la plus parlante : prouver par la négative que le message n'existe nulle part en clair.

```
sudo tcpdump -r /tmp/demo-capture.pcap -A | grep -i "DEMO-JURY"

```

**Résultat attendu : aucune ligne affichée.**

> **Point à dire** : "Si le trafic n'était pas réellement chiffré — TLS mal configuré, ou désactivé silencieusement — cette commande aurait retrouvé le texte du message que nous venons d'envoyer. Le fait qu'elle ne retourne rien est la preuve que le contenu a bien transité chiffré sur le réseau, et pas seulement que la configuration l'affirme."

---

## Étape 6 — Preuve positive : le message est bien arrivé côté serveur

Pour clore la démonstration, montrer que le message a malgré tout été reçu et traité correctement — le chiffrement n'empêche pas la livraison, il protège juste le contenu en transit :

```
sudo tail -1 /var/log/remote-relp/BASTION-FRONT-01.log

```

**Résultat attendu** :

```
2026-07-13T16:06:42.xxxxxx+00:00 BASTION-FRONT-01 kasgrunt: DEMO-JURY-160642 - Ceci est un message secret en clair

```

> **Point de conclusion** : "Le message est arrivé en clair dans le fichier de log, parce que c'est bien rsyslog côté serveur qui l'a déchiffré après authentification mutuelle du client — pas parce que le réseau l'a laissé passer en clair. La preuve du chiffrement se situe au niveau du transport (étape 5), pas du stockage final."

---

## Résumé du scénario (aide-mémoire rapide)

| # | Terminal | Commande | Ce que ça prouve |
|---|----------|----------|-------------------|
| 1 | LOG-FRONT-01 | `ss -tulnp \| grep -E ':514\|:6514'`                                    | Le flux RELP est isolé du flux existant |
| 2 | LOG-FRONT-01 | `sudo timeout 20 tcpdump -i any port 6514 -X -w /tmp/demo-capture.pcap` | Lance la capture |
| 3 | Client       | `logger "DEMO-JURY-$(date +%H%M%S) - ..."`                              | Génère un message identifiable |
| 4 | LOG-FRONT-01 | *(lecture directe de la sortie tcpdump)*                                | En-tête TLS visible, contenu illisible |
| 5 | LOG-FRONT-01 | `sudo tcpdump -r /tmp/demo-capture.pcap -A \| grep -i "DEMO-JURY"`      | Aucun résultat = chiffrement prouvé |
| 6 | LOG-FRONT-01 | `sudo tail -1 /var/log/remote-relp/BASTION-FRONT-01.log`                | Le message est bien arrivé et déchiffré côté serveur |

---

## Variante — si le jury demande de voir plusieurs clients

Répéter les étapes 3 à 6 pour un second client (ex: SQL-FRONT-01), en changeant simplement le nom de fichier consulté à l'étape 6 :

```
sudo tail -1 /var/log/remote-relp/SQL-FRONT-01.log

```

Cela permet de montrer que le tri par `%HOSTNAME%` fonctionne correctement et que chaque client dispose de sa propre identité (certificat CN unique), sans confusion entre les flux.
