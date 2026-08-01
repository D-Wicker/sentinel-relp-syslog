#!/bin/bash
# Active le mode strict : le script s'arrête immédiatement si une commande échoue
set -e

# A EXECUTER UNE SEULE FOIS, UNIQUEMENT SUR LOG-FRONT-01.
# La clé privée de la CA (ca-key.pem) ne doit JAMAIS quitter cette
# machine : quiconque la possède peut signer un certificat pour
# n'importe quelle identité et donc usurper n'importe quel membre
# de l'infrastructure (client OU serveur).

# Définit le dossier de stockage des certificats (crée un dossier
# "certs" là où se trouve le script)
CERTS_DIR="$(dirname "$0")/certs"
mkdir -p "$CERTS_DIR"

# Nettoyage préalable : supprime d'éventuels certificats d'une
# exécution précédente. ATTENTION : régénérer la CA ici invaliderait
# TOUS les certificats clients déjà signés (nouvelle CA = nouvelle
# racine de confiance) — ne relancer que si tout doit être re-signé.
echo "=== Nettoyage des anciens certificats CA/serveur ==="
sudo rm -f "$CERTS_DIR"/ca-*.pem "$CERTS_DIR"/ca-*.srl "$CERTS_DIR"/server-*.pem

echo "=== Génération de la CA ==="
# Génère une CA auto-signée (certificat public + clé privée de
# l'autorité racine). -nodes : pas de passphrase, pour automatisation.
openssl req -x509 -newkey rsa:4096 \
  -keyout "$CERTS_DIR/ca-key.pem" \
  -out "$CERTS_DIR/ca-cert.pem" \
  -days 365 -nodes -subj "/CN=KASGRUNT-LOG-CA"

# Verrouille immédiatement les permissions de la clé privée de la
# CA — le fichier le plus critique de toute cette PKI.
chmod 600 "$CERTS_DIR/ca-key.pem"

echo "=== Génération clé + CSR serveur ==="
# Le CN correspond au hostname réel du serveur RELP, pour cohérence
# avec le template %HOSTNAME% et pour faciliter l'audit.
openssl req -newkey rsa:4096 \
  -keyout "$CERTS_DIR/server-key.pem" \
  -out "$CERTS_DIR/server-req.pem" \
  -nodes -subj "/CN=LOG-FRONT-01"

echo "=== Signature du certificat serveur ==="
# La CA utilise sa clé privée pour signer la CSR et générer le
# certificat officiel du serveur.
openssl x509 -req \
  -in "$CERTS_DIR/server-req.pem" \
  -CA "$CERTS_DIR/ca-cert.pem" -CAkey "$CERTS_DIR/ca-key.pem" \
  -CAcreateserial -out "$CERTS_DIR/server-cert.pem" -days 365

chmod 600 "$CERTS_DIR/server-key.pem"

echo "=== Déploiement vers /etc/rsyslog.d/certs/ ==="
sudo mkdir -p /etc/rsyslog.d/certs
sudo cp "$CERTS_DIR/ca-cert.pem" "$CERTS_DIR/server-cert.pem" "$CERTS_DIR/server-key.pem" /etc/rsyslog.d/certs/

# rsyslog-svc doit pouvoir lire ces fichiers APRES le drop de
# privilèges ($PrivDropToUser, en fin de relp-server.conf).
sudo chown rsyslog-svc:rsyslog-svc /etc/rsyslog.d/certs/server-key.pem
sudo chmod 600 /etc/rsyslog.d/certs/server-key.pem
sudo chown root:rsyslog-svc /etc/rsyslog.d/certs/ca-cert.pem /etc/rsyslog.d/certs/server-cert.pem
sudo chmod 640 /etc/rsyslog.d/certs/ca-cert.pem /etc/rsyslog.d/certs/server-cert.pem

echo "=== Terminé. ca-key.pem NE DOIT JAMAIS quitter cette machine. ==="
ls -la "$CERTS_DIR"
