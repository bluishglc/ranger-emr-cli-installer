#!/bin/bash

# --------------------------------------    Migrating Kerberos DB Operations   --------------------------------------- #

# be careful, migrating kerberos db is ONE-TIME operation,
# it can NOT run twice!
migrateKerberosDb() {
    testKerberosKdcConnectivity
    distributeInstaller "hadoop" "$KERBEROS_KDC_HOST"
    ssh -o StrictHostKeyChecking=no -i $SSH_KEY -T hadoop@$KERBEROS_KDC_HOST \
        sudo sh $APP_REMOTE_HOME/bin/setup.sh migrate-kerberos-db-on-kdc-local \
        --region $REGION \
        --kerberos-realm $KERBEROS_REALM \
        --kerberos-kdc-host $KERBEROS_KDC_HOST \
        --openldap-host $OPENLDAP_HOST \
        --openldap-base-dn $OPENLDAP_BASE_DN \
        --openldap-root-cn $OPENLDAP_ROOT_CN \
        --openldap-root-password $OPENLDAP_ROOT_PASSWORD
}

migrateKerberosDbOnKdcLocal() {
    dumpKrbDb
    installKrbLdapPackages
    makePasswordFile
    configKdc
    createKrbDb
    restartKrb
    restoreKrbDb
}

testKerberosKdcConnectivity() {
    printHeading "TEST KERBEROS_KDC SSH CONNECTIVITY"
    if [[ -f $SSH_KEY && "$KERBEROS_KDC_HOST" != "" ]]; then
        ssh -o StrictHostKeyChecking=no -i $SSH_KEY -T hadoop@$KERBEROS_KDC_HOST sudo whoami &>/dev/null
        if [ ! "$?" = "0" ]; then
            echo "ERROR!! ssh connection to [ $KERBEROS_KDC_HOST ] failed!"
            exit 1
        fi
    else
        echo "ERROR!! --ssh-key or --kerberos-kdc-host is not provided!"
        exit 1
    fi
    nc -vz $KERBEROS_KDC_HOST 88 &>/dev/null
    if [ "$?" = "0" ]; then
        echo "Connecting to kerberos kdc [ $KERBEROS_KDC_HOST ] is SUCCESSFUL!!"
    else
        echo "Connecting to kerberos kdc [ $KERBEROS_KDC_HOST ] is FAILED!!"
        exit 1
    fi
}

dumpKrbDb() {
    # print all principals to text file as a reference when restore data
    kadmin.local -q "listprincs" | tee /tmp/principals.txt
    # dump db to dump file
    kdb5_util dump /tmp/kdc-db.dump
}

installKrbLdapPackages() {
    yum -y install krb5-server-ldap expect
}

makePasswordFile() {
    /usr/bin/expect <<EOF
    spawn kdb5_ldap_util stashsrvpw -f /etc/openldap-admin.keyfile "$OPENLDAP_ROOT_DN"
    expect {
        "Password for *" {
            send "$OPENLDAP_ROOT_PASSWORD\r"
            expect "Re-enter password for *" { send "$OPENLDAP_ROOT_PASSWORD\r" }
        }
    }
	expect eof
EOF
}

configKdc() {
    # The puppet of EMR will always revert all manual changes on kdc.conf when update emr configuration!
    # we can both modify /var/kerberos/krb5kdc/kdc.conf & /var/aws/emr/bigtop-deploy/puppet/modules/kerberos/templates/kdc.conf
    # if so, we need NOT explicitly trigger updating emr configuration, and also can be sure current version of kdc.conf
    # will keep if an emr configuration update triggered by other operation!
    configFiles=("/var/kerberos/krb5kdc/kdc.conf" "/var/aws/emr/bigtop-deploy/puppet/modules/kerberos/templates/kdc.conf")
    for configFile in "${configFiles[@]}"; do
        # the second conf file is puppet template, it may NOT exist on non-emr dedicate kdc.
        if [ -f $configFile ]; then
            cp $configFile $configFile.$(date +%s)
            # find "database_name", comment out, then insert "database_module = openldap_ldapconf"
            sed -i 's/\(^\s*\)database_name\(.*\)/\1#database_name\2\n\1database_module = openldap_ldapconf/g' $configFile
            # insert moudle [dbmodules]
            tee -a $configFile &>/dev/null <<EOF
        [dbmodules]
            openldap_ldapconf = {
                db_library = kldap
                ldap_servers = ldap://$OPENLDAP_HOST
                ldap_kerberos_container_dn = cn=kerberos,$OPENLDAP_BASE_DN
                ldap_kdc_dn = $OPENLDAP_ROOT_DN
                ldap_kadmind_dn = $OPENLDAP_ROOT_DN
                ldap_service_password_file = /etc/openldap-admin.keyfile
                ldap_conns_per_server = 5
           }
EOF
        fi
   done
}

createKrbDb() {
    /usr/bin/expect <<EOF
    spawn kdb5_ldap_util -D $OPENLDAP_ROOT_DN -w $OPENLDAP_ROOT_PASSWORD \
        -H ldap://$OPENLDAP_HOST create \
        -r $KERBEROS_REALM -subtrees $OPENLDAP_BASE_DN
    expect {
        "Enter KDC database master key*" {
            send "$KERBEROS_KADMIN_PASSWORD\r"
            expect "Re-enter KDC database master key*" { send "$KERBEROS_KADMIN_PASSWORD\r" }
        }
    }
	expect eof
EOF
}

restartKrb() {
    systemctl restart krb5kdc kadmin
    systemctl status krb5kdc kadmin
}

restoreKrbDb() {
    kdb5_util load -update /tmp/kdc-db.dump
}

