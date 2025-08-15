#!/bin/bash
init() {
    echo "Digite a senha do administrador do LDAP:"
    read -s pass
    export DEBIAN_FRONTEND=noninteractive
    sudo debconf-set-selections <<EOF
slapd slapd/internal/generated_adminpw password $pass
slapd slapd/password2 password $pass
slapd slapd/internal/adminpw password $pass
slapd slapd/password1 password $pass
slapd slapd/domain string pine.local.br
slapd shared/organization string pine.local.br
EOF
    sudo apt -y install slapd ldap-utils
}

unit() {
    printf 'dn: ou=Users,dc=pine,dc=local,dc=br
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
ou: Notebook' > /tmp/base.ldif
    ldapadd -x -D "cn=admin,dc=pine,dc=local,dc=br" -W -f /tmp/base.ldif
}

gsudo() {
    printf 'dn: cn=sudo,ou=Groups,dc=pine,dc=local,dc=br
objectClass: top
objectClass: posixGroup
cn: sudo
gidNumber: 1000' > /tmp/gsudo.ldif
ldapadd -x -D "cn=admin,dc=pine,dc=local,dc=br" -W -f /tmp/gsudo.ldif
}

uemperor() {
    echo "Digite a nova senha para o usuário emperor:"
    read -s pass
    hash=$(slappasswd -s "$pass")
    printf 'dn: uid=emperor,ou=Users,dc=pine,dc=local,dc=br
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
userPassword: %s' "$hash" > /tmp/uemperor.ldif
    ldapadd -x -D "cn=admin,dc=pine,dc=local,dc=br" -W -f /tmp/uemperor.ldif
}

gsudomembers() {
    printf 'dn: cn=sudo,ou=Groups,dc=pine,dc=local,dc=br
changetype: modify
add: memberUid
memberUid: emperor' > /tmp/gsudomembers.ldif
ldapadd -x -D "cn=admin,dc=pine,dc=local,dc=br" -W -f /tmp/gsudomembers.ldif
}

# Sequence
init
unit
gsudo
uemperor
gsudomembers


ldapadd -x -D "cn=admin,dc=pine,dc=local,dc=br" -w "$pass" -f hosts.ldif