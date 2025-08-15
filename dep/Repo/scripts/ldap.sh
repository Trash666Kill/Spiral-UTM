#!/bin/bash

# Função de inicialização
init() {
    printf "\e[32m**ENTER THE LDAP ADMINISTRATOR PASSWORD:**\e[0m\n"
    read -s PASS
    export DEBIAN_FRONTEND=noninteractive
    debconf-set-selections <<EOF
slapd slapd/internal/generated_adminpw password $PASS
slapd slapd/password2 password $PASS
slapd slapd/internal/adminpw password $PASS
slapd slapd/password1 password $PASS
slapd slapd/domain string pine.local.br
slapd shared/organization string pine.local.br
EOF
    apt update && apt -y install slapd ldap-utils
    if [[ $? -ne 0 ]]; then
        printf "\e[31mError installing slapd or ldap-utils.\e[0m\n"
        exit 1
    fi
}

# Criação de unidades organizacionais
unit() {
    BASE=$(cat <<EOF
dn: ou=Users,dc=pine,dc=local,dc=br
objectClass: top
objectClass: organizationalUnit
ou: Users

dn: ou=Groups,dc=pine,dc=local,dc=br
objectClass: top
objectClass: organizationalUnit
ou: Groups

dn: ou=Hosts,dc=pine,dc=local,dc=br
objectClass: top
objectClass: organizationalUnit
ou: Hosts

dn: ou=Unknown,ou=Hosts,dc=pine,dc=local,dc=br
objectClass: top
objectClass: organizationalUnit
ou: Unknown

dn: ou=Server,ou=Hosts,dc=pine,dc=local,dc=br
objectClass: top
objectClass: organizationalUnit
ou: Server

dn: ou=Firewall,ou=Hosts,dc=pine,dc=local,dc=br
objectClass: top
objectClass: organizationalUnit
ou: Firewall

dn: ou=Container,ou=Hosts,dc=pine,dc=local,dc=br
objectClass: top
objectClass: organizationalUnit
ou: Container

dn: ou=Virtual Machine,ou=Hosts,dc=pine,dc=local,dc=br
objectClass: top
objectClass: organizationalUnit
ou: Virtual Machine

dn: ou=Desktop,ou=Hosts,dc=pine,dc=local,dc=br
objectClass: top
objectClass: organizationalUnit
ou: Desktop

dn: ou=Notebook,ou=Hosts,dc=pine,dc=local,dc=br
objectClass: top
objectClass: organizationalUnit
ou: Notebook"
EOF
    )
    echo "$BASE" | ldapadd -x -D "cn=admin,dc=pine,dc=local,dc=br" -w "$PASS"
}

# Criação do grupo sudo
gsudo() {
    GSUDO=$(cat <<EOF
dn: cn=sudo,ou=Groups,dc=pine,dc=local,dc=br
objectClass: top
objectClass: posixGroup
cn: sudo
gidNumber: 1000
EOF
    )
    echo "$GSUDO" | ldapadd -x -D "cn=admin,dc=pine,dc=local,dc=br" -w "$PASS"
}

# Criação do usuário Emperor
uemperor() {
    printf "\e[32m**ENTER NEW PASSWORD FOR EMPEROR USER:**\e[0m\n"
    read -s EMPASS
    HASH=$(slappasswd -s "$EMPASS")
    UEMPEROR=$(cat <<EOF
dn: uid=emperor,ou=Users,dc=pine,dc=local,dc=br
objectClass: inetOrgPerson
objectClass: posixAccount
objectClass: shadowAccount
cn: Emperor
sn: User
uid: emperor
uidNumber: 1001
gidNumber: 1000
homeDirectory: /home/emperor
loginShell: /bin/bash
userPassword: $HASH
EOF
    )
    echo "$UEMPEROR" | ldapadd -x -D "cn=admin,dc=pine,dc=local,dc=br" -w "$PASS"
}

# Adição do usuário ao grupo sudo
gsudomembers() {
    GSUDOMEMBERS=$(cat <<EOF
dn: cn=sudo,ou=Groups,dc=pine,dc=local,dc=br
changetype: modify
add: memberUid
memberUid: emperor
EOF
    )
    echo "$GSUDOMEMBERS" | ldapadd -x -D "cn=admin,dc=pine,dc=local,dc=br" -w "$PASS"
}

# Sequência de execução
init
unit
gsudo
uemperor
gsudomembers