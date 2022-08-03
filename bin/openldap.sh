#!/bin/bash

installOpenldap() {
    printHeading "INSTALL OPENLDAP"
    testOpenldapSshConnectivity
    distributeInstaller "ec2-user" "$OPENLDAP_HOST"
    ssh -o StrictHostKeyChecking=no -i $SSH_KEY -T ec2-user@$OPENLDAP_HOST \
        sudo sh $APP_REMOTE_HOME/bin/setup.sh install-openldap-on-local \
            --region $REGION \
            --access-key-id $ACCESS_KEY_ID \
            --secret-access-key $SECRET_ACCESS_KEY \
            --solution $SOLUTION \
            --auth-provider $AUTH_PROVIDER \
            --openldap-host $OPENLDAP_HOST \
            --openldap-base-dn $OPENLDAP_BASE_DN \
            --openldap-root-cn $OPENLDAP_ROOT_CN \
            --openldap-root-password $OPENLDAP_ROOT_PASSWORD
}

installOpenldapOnLocal() {
    initEc2
    installOpenldapPackages
    enableOpenldap
    restartOpenldap
    initOpenldap
    enableMemberOf
    disableAnonymousAccess
    createOu
    createServiceAccounts
    # for OpenLDAP + EMR Native Ranger solution, need import kerberos schema
    if [[ "$AUTH_PROVIDER" = "openldap" && "$SOLUTION" = "emr-native" ]]; then
        importKerberosSchema
        addOpenldapKrbIndex
    fi
}

testOpenldapSshConnectivity() {
    printHeading "TEST OPENLDAP SSH CONNECTIVITY"
    if [[ -f $SSH_KEY && "$OPENLDAP_HOST" != "" ]]; then
        ssh -o StrictHostKeyChecking=no -i $SSH_KEY -T ec2-user@$OPENLDAP_HOST sudo whoami &>/dev/null
        if [ ! "$?" = "0" ]; then
            echo "ERROR!! ssh connection to [ $OPENLDAP_HOST ] failed!"
            exit 1
        fi
    else
        echo "ERROR!! --ssh-key or --openldap-host is not provided!"
        exit 1
    fi
}

installOpenldapPackages() {
    yum -y install openldap openldap-clients openldap-servers compat-openldap openldap-devel migrationtools
}

enableOpenldap() {
    systemctl enable slapd
}

restartOpenldap() {
    systemctl restart slapd
    systemctl status slapd
}

initOpenldap() {
    cat << EOF | ldapadd -Y EXTERNAL -H ldapi:///
dn: olcDatabase={1}monitor,cn=config
changetype: modify
replace: olcAccess
olcAccess: {0}to * by dn.base="gidNumber=0+uidNumber=0,cn=peercred,cn=external,cn=auth" read by dn.base="$OPENLDAP_ROOT_DN" read by * none

dn: olcDatabase={2}hdb,cn=config
changetype: modify
add: olcRootPW
olcRootPW: $(slappasswd -s $OPENLDAP_ROOT_PASSWORD)
-
replace: olcRootDN
olcRootDN: $OPENLDAP_ROOT_DN
-
replace: olcSuffix
olcSuffix: $OPENLDAP_BASE_DN
-
add: olcAccess
olcAccess: {0}to attrs=userPassword by self write by dn.base="$OPENLDAP_ROOT_DN" write by anonymous auth by * none
olcAccess: {1}to * by dn.base="$OPENLDAP_ROOT_DN" write by self write by * read
EOF
    # import regular schemas
    ldapadd -Y EXTERNAL -H ldapi:/// -f /etc/openldap/schema/core.ldif
    ldapadd -Y EXTERNAL -H ldapi:/// -f /etc/openldap/schema/cosine.ldif
    ldapadd -Y EXTERNAL -H ldapi:/// -f /etc/openldap/schema/nis.ldif
    ldapadd -Y EXTERNAL -H ldapi:/// -f /etc/openldap/schema/inetorgperson.ldif
}

enableMemberOf() {
    cat << EOF | ldapadd -Y EXTERNAL -H ldapi:///
dn: cn=module,cn=config
cn: module
objectClass: olcModuleList
olcModuleLoad: memberof
olcModulePath: /usr/lib64/openldap

dn: olcOverlay={0}memberof,olcDatabase={2}hdb,cn=config
objectClass: olcConfig
objectClass: olcMemberOf
objectClass: olcOverlayConfig
objectClass: top
olcOverlay: memberof
olcMemberOfDangling: ignore
olcMemberOfRefInt: TRUE
olcMemberOfGroupOC: groupOfNames
olcMemberOfMemberAD: member
olcMemberOfMemberOfAD: memberOf
EOF
    cat << EOF | ldapmodify -Y EXTERNAL -H ldapi:///
dn: cn=module{0},cn=config
add: olcmoduleload
olcmoduleload: refint
EOF
    cat << EOF | ldapadd -Y EXTERNAL -H ldapi:///
dn: olcOverlay={1}refint,olcDatabase={2}hdb,cn=config
objectClass: olcConfig
objectClass: olcOverlayConfig
objectClass: olcRefintConfig
objectClass: top
olcOverlay: {1}refint
olcRefintAttribute: memberof member manager owner
EOF
}

disableAnonymousAccess() {
    cat << EOF | ldapmodify -Y EXTERNAL -H ldapi:///
dn: cn=config
changetype: modify
add: olcDisallows
olcDisallows: bind_anon

dn: cn=config
changetype: modify
add: olcRequires
olcRequires: authc

dn: olcDatabase={-1}frontend,cn=config
changetype: modify
add: olcRequires
olcRequires: authc
EOF
}

createOu() {
    cat << EOF | ldapadd -D "$OPENLDAP_ROOT_DN" -w $OPENLDAP_ROOT_PASSWORD
dn: $OPENLDAP_BASE_DN
objectClass: dcObject
objectClass: organization
dc: $ORG_DC
o: $ORG_DC

dn: $OPENLDAP_USERS_BASE_DN
objectclass: top
objectclass: organizationalUnit
ou: users
description: OU for user accounts

dn: ou=groups,$OPENLDAP_BASE_DN
objectclass: top
objectclass: organizationalUnit
ou: groups
description: OU for user groups

dn: ou=services,$OPENLDAP_BASE_DN
objectclass: top
objectclass: organizationalUnit
ou: services
description: OU for service accounts
EOF
}

createServiceAccounts() {
    # sssd bind user
    cat << EOF | ldapadd -D "$OPENLDAP_ROOT_DN" -w $OPENLDAP_ROOT_PASSWORD
dn: $SSSD_BIND_DN
sn: sssd
cn: sssd
objectClass: top
objectclass: person
userPassword: $SSSD_BIND_PASSWORD
EOF
    # ranger bind user
    cat << EOF | ldapadd -D "$OPENLDAP_ROOT_DN" -w $OPENLDAP_ROOT_PASSWORD
dn: $OPENLDAP_RANGER_BIND_DN
sn: ranger
cn: ranger
objectClass: top
objectclass: person
userPassword: $OPENLDAP_RANGER_BIND_PASSWORD
EOF
    # hue bind user
    cat << EOF | ldapadd -D "$OPENLDAP_ROOT_DN" -w $OPENLDAP_ROOT_PASSWORD
dn: $OPENLDAP_HUE_BIND_DN
sn: hue
cn: hue
objectClass: top
objectclass: person
userPassword: $OPENLDAP_HUE_BIND_PASSWORD
EOF
}

importKerberosSchema() {
    cp $APP_HOME/conf/kerberos/kerberos.openldap.ldif /etc/openldap/schema/kerberos.openldap.ldif
    ldapadd -Y EXTERNAL -H ldapi:/// -f /etc/openldap/schema/kerberos.openldap.ldif
}

addOpenldapKrbIndex() {
    cat << EOF | ldapmodify -Y EXTERNAL -H ldapi:///
dn: olcDatabase={2}hdb,cn=config
changetype: modify
add: olcDbIndex
olcDbIndex: krbPrincipalName eq,pres,sub

dn: olcDatabase={2}hdb,cn=config
changetype: modify
add: olcDbIndex
olcDbIndex: krbPwdPolicyReference eq
EOF
}
