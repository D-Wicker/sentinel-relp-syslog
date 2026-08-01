#!/bin/bash
set -e               # stop le script si une commande échoue

# Exécuté SUR LOG-FRONT-01 (exemple de nommage sur ma VM a créatoin du LAB, 
# là où se trouve ca-key.pem, jamais copiée vers les clients). A relancer une fois par VM cliente
# (BASTION-FRONT-01, SQL-FRONT-01, PBX-FRONT-01, ZAB-FRONT-01, ici a titre d'exemple...).
# Usage : ./generate-client-cert.sh <NOM_DE_LA_MACHINE>
# Exemple : ./generate-client-cert.sh BASTION-FRONT-01

CERTS_DIR="$(dirname "$0")/../server/certs"
CN="$1"

# Vérifie qu'un CN a bien été fourni en argument. Sans ça, on
# retomberait dans le piège du CN générique identique pour tous
# les clients, ce qui empêcherait de les distinguer/révoquer
# individuellement.
if [ -z "$CN" ]; then
  echo "Usage: $0 <CN_DE_LA_MACHINE_CLIENTE>"
  echo "Exemple: $0 BASTION-FRONT-01"
  exit 1
fi

# Vérifie que la CA existe bien avant de continuer (le script
# generate-ca-and-server.sh doit avoir tourné avant, une seule fois).
if [ ! -f "$CERTS_DIR/ca-key.pem" ]; then
  echo "Erreur : ca-key.pem introuvable. Lance d'abord generate-ca-and-server.sh"
  exit 1
fi

echo "=== Génération clé + CSR client pour $CN ==="
# Génère la clé privée du client et sa CSR, avec un CN unique par
# machine — utile pour distinguer les connexions dans les logs et
# pour pouvoir révoquer ce seul certificat en cas de compromission
# de cette VM précise, sans impacter les autres clients.
openssl req -newkey rsa:4096 \
  -keyout "$CERTS_DIR/${CN}-key.pem" \
  -out "$CERTS_DIR/${CN}-req.pem" \
  -nodes -subj "/CN=${CN}"

echo "=== Signature du certificat client pour $CN ==="
# La CA signe la CSR du client avec sa clé privée locale, qui ne
# quitte jamais cette machine.
openssl x509 -req \
  -in "$CERTS_DIR/${CN}-req.pem" \
  -CA "$CERTS_DIR/ca-cert.pem" -CAkey "$CERTS_DIR/ca-key.pem" \
  -CAcreateserial -out "$CERTS_DIR/${CN}-cert.pem" -days 365

chmod 600 "$CERTS_DIR/${CN}-key.pem"
# Restreint la clé privée du client en lecture/écriture au seul
# propriétaire du fichier : c'est le matériel cryptographique qui
# prouve l'identité de cette machine auprès du serveur RELP (mTLS).
# Si un autre utilisateur du système pouvait la lire, il pourrait
# usurper l'identité de ce client — même principe de moindre
# privilège que pour ca-key.pem, à l'échelle d'une seule machine.

echo "=== Terminé pour $CN ==="
echo "Fichiers à transférer vers $CN : ${CN}-key.pem, ${CN}-cert.pem, ca-cert.pem"
echo "(ca-key.pem NE DOIT JAMAIS être transféré)"
