#!/bin/bash

################################################################################
# 
# WARNING: This script is not ready to be executed in non-interactive mode.
# My advice is to copy and paste each command separately.
#
# For this POC, I'm using ldap.madeof.glass as the LDAP server's FQDN, and
# dc=madeof,dc=glass as the domain components.
#
################################################################################


# Let's pretend to use an actual URL, but actually redirect it back to localhost.

sudo tee -a /etc/hosts <<-EOF
127.0.0.1 ldap.madeof.glass
EOF

ping -c 1 ldap.madeof.glass

# Install and configure ldap and slapd

sudo apt install -y gnutls-bin ssl-cert ldap-utils ldap-server ldapscripts # actually, probably don't need gnutls-bin or ldapscripts
sudo dpkg-reconfigure slapd

# Create our ldap.conf

sudo tee /etc/ldap/ldap.conf <<-EOF
BASE dc=madeof,dc=glass
URI ldap://ldap.madeof.glass
TLS_CIPHER_SUITE SECURE256
EOF

sudo adduser openldap ssl-cert

# Verify (insecure) access to ldap

ldapwhoami -D cn=admin,dc=madeof,dc=glass -W

ldapwhoami -Y EXTERNAL -H ldapi:/// -Q # should return uid=1000
sudo ldapwhoami -Y EXTERNAL -H ldapi:/// -Q # should return uid=0

# Create a demo user

sudo useradd john

sudo tee ~/demo_data.ldif <<-EOF
dn: ou=People,dc=madeof,dc=glass
objectClass: organizationalUnit
ou: People

dn: ou=Groups,dc=madeof,dc=glass
objectClass: organizationalUnit
ou: Groups

dn: cn=miners,ou=Groups,dc=madeof,dc=glass
objectClass: posixGroup
cn: miners
gidNumber: 5000

dn: uid=john,ou=People,dc=madeof,dc=glass
objectClass: inetOrgPerson
objectClass: posixAccount
objectClass: shadowAccount
uid: john
sn: Doe
givenName: John
cn: John Doe
displayName: John Doe
uidNumber: 10000
gidNumber: 5000
userPassword: {CRYPT}x
gecos: John Doe
loginShell: /bin/bash
homeDirectory: /home/john
EOF

ldapadd -x -D cn=admin,dc=madeof,dc=glass -W -f demo_data.ldif
ldapsearch -x -LLL -b dc=madeof,dc=glass '(uid=john)' cn gidNumber

################################################################################
# 
# Magic TLS Config Section
#
# The following code block generates three files used by LDAP: ldap.crt, ldap.csr, ldap.key
# One file that must be distributed to your LDAP clients and trusted: glassCA.crt
# And one file that must be kept top secret: glassCA.key
#
################################################################################

# Generate Private CA Key
openssl genrsa -des3 -out glassCA.key 4096

# Generate Root Certificate
openssl req -x509 -new -nodes -key glassCA.key -sha256 -days 3650 -out glassCA.pem

# Copy Root Certificate to ca-certificates folder and update
sudo cp glassCA.pem /usr/local/share/ca-certificates/glassCA.crt
sudo update-ca-certificates

# Create a Private Key for LDAP
openssl genrsa -out ldap.key 4096

# Create a CSR
openssl req -new -key ldap.key -out ldap.csr

# Create the Certificate using our CSR, CA Private Key, and the CA Certificate
openssl x509 -req -in ldap.csr -CA glassCA.pem -CAkey glassCA.key -CAcreateserial -out ldap.crt -days 3650 -sha256

# Let's store our LDAP files somewhere safe:
sudo mkdir -p /etc/ldap/certs
sudo cp ldap.crt /etc/ldap/certs/ldapcrt.pem
sudo cp ldap.key /etc/ldap/certs/ldapkey.pem
sudo chown -R openldap:openldap /etc/ldap/certs/

# Now we provide these files to the LDAP server:

sudo tee ~/tls_config.ldif <<-EOF
dn: cn=config
add: olcTLSCACertificateFile
olcTLSCACertificateFile: /etc/ssl/certs/glassCA.pem
-
add: olcTLSCertificateKeyFile
olcTLSCertificateKeyFile: /etc/ldap/certs/ldapkey.pem
-
add: olcTLSCertificateFile
olcTLSCertificateFile: /etc/ldap/certs/ldapcrt.pem
EOF

sudo ldapmodify -Y EXTERNAL -H ldapi:/// -f tls_config.ldif

# Update slapd to use ldaps
sudo sed -i -e 's/SLAPD_SERVICES="ldap:\/\/\/ ldapi:\/\/\/"/SLAPD_SERVICES="ldap:\/\/\/ ldapi:\/\/\/ ldaps:\/\/\/"/g' /etc/default/slapd
sudo systemctl restart slapd

# Tell ldap.conf to use the ldaps URI and point to the correct cacert

sudo tee /etc/ldap/ldap.conf <<-EOF
BASE dc=madeof,dc=glass
URI ldaps://ldap.madeof.glass
TLS_CACERT /etc/ssl/certs/glassCA.pem
TLS_CIPHER_SUITE SECURE256
EOF

################################################################################
# 
# Test StartTLS and LDAPS Connectivity
#
################################################################################

# Test StartTLS
ldapwhoami -D cn=admin,dc=madeof,dc=glass -W -H ldap://ldap.madeof.glass -v

# Test LDAPS
ldapwhoami -D cn=admin,dc=madeof,dc=glass -W -H ldaps://ldap.madeof.glass -v

# Test default
ldapwhoami -D cn=admin,dc=madeof,dc=glass -W -v
