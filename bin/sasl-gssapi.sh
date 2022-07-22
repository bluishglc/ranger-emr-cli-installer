#!/bin/bash

enableSaslGssapi() {
    printHeading "ENABLE SASL/GSSAPI"
    provisionKrb5Conf
    provisionOpenldapServiceKeytab
    provisionOpenldapHostKeytab
    enableSaslGssapiOnOpenldap
    enableSaslGssapiOnEmrCluster
}

provisionKrb5Conf() {
    scp -o StrictHostKeyChecking=no -i $SSH_KEY hadoop@$KERBEROS_KDC_HOST:/etc/krb5.conf /tmp/krb5.conf
    scp -o StrictHostKeyChecking=no -i $SSH_KEY /tmp/krb5.conf ec2-user@$OPENLDAP_HOST:/tmp/krb5.conf
    ssh -o StrictHostKeyChecking=no -i $SSH_KEY -T ec2-user@$OPENLDAP_HOST sudo mv /tmp/krb5.conf /etc/krb5.conf
}

provisionOpenldapServiceKeytab() {
    ssh -o StrictHostKeyChecking=no -i $SSH_KEY -T hadoop@$KERBEROS_KDC_HOST <<EOSSH
        sudo kadmin.local -q "addprinc -randkey ldap/$OPENLDAP_HOST@$KERBEROS_REALM"
        sudo kadmin.local -q "ktadd -k /tmp/ldap.keytab ldap/$OPENLDAP_HOST@$KERBEROS_REALM"
        # add read permission, otherwise scp can't copy it
        sudo chmod a+r /tmp/ldap.keytab
EOSSH
    scp -o StrictHostKeyChecking=no -i $SSH_KEY hadoop@$KERBEROS_KDC_HOST:/tmp/ldap.keytab /tmp/ldap.keytab
    scp -o StrictHostKeyChecking=no -i $SSH_KEY /tmp/ldap.keytab ec2-user@$OPENLDAP_HOST:/tmp/ldap.keytab
}

provisionOpenldapHostKeytab() {
    ssh -o StrictHostKeyChecking=no -i $SSH_KEY -T hadoop@$KERBEROS_KDC_HOST <<EOSSH
        sudo kadmin.local -q "addprinc -randkey host/$OPENLDAP_HOST@$KERBEROS_REALM"
        sudo kadmin.local -q "ktadd -k /tmp/krb5.keytab host/$OPENLDAP_HOST@$KERBEROS_REALM"
        # add read permission, otherwise scp can't copy it
        sudo chmod a+r /tmp/krb5.keytab
EOSSH
    scp -o StrictHostKeyChecking=no -i $SSH_KEY hadoop@$KERBEROS_KDC_HOST:/tmp/krb5.keytab /tmp/krb5.keytab
    scp -o StrictHostKeyChecking=no -i $SSH_KEY /tmp/krb5.keytab ec2-user@$OPENLDAP_HOST:/tmp/krb5.keytab
}

# ------------------------------------    SASL/GSSAPI Operations on OpenLDAP   --------------------------------------- #

enableSaslGssapiOnOpenldap() {
    printHeading "ENABLE SASL/GSSAPI ON OPENLDAP"
    distributeInstaller "ec2-user" "$OPENLDAP_HOST"
    ssh -o StrictHostKeyChecking=no -i $SSH_KEY -T ec2-user@$OPENLDAP_HOST \
        sudo sh $APP_REMOTE_HOME/bin/setup.sh enable-sasl-gssapi-on-openldap-local \
            --region "$REGION" \
            --kerberos-realm $KERBEROS_REALM \
            --kerberos-kdc-host $KERBEROS_KDC_HOST \
            --openldap-host $OPENLDAP_HOST \
            --openldap-base-dn $OPENLDAP_BASE_DN \
            --openldap-root-cn $OPENLDAP_ROOT_CN \
            --openldap-root-password $OPENLDAP_ROOT_PASSWORD \
            --emr-cluster-id $EMR_CLUSTER_ID
}

enableSaslGssapiOnOpenldapLocal() {
    installSaslGssapiOnOpenldap
    addOpenldapServiceIntoKerberos
    addOpenldapHostIntoKerberos
    configKerberosAccountsMapping
    configSaslLib
    configSaslauthd
    enableSaslauthd
    # it's required to restart slapd
    # and this func in openldap.sh
    restartOpenldap
}

installSaslGssapiOnOpenldap() {
    yum -y install cyrus-sasl-lib cyrus-sasl-gssapi cyrus-sasl-devel krb5-workstation
}

addOpenldapServiceIntoKerberos() {
    # provision keytab file
    mv -f /tmp/ldap.keytab /etc/openldap/ldap.keytab
    chown ldap:ldap /etc/openldap/ldap.keytab
    chmod 600 /etc/openldap/ldap.keytab

    # config slapd refer to keytab file
    cp -f /etc/sysconfig/slapd /etc/sysconfig/slapd.$(date +%s)
    # comment out existing config items
    sed -i 's/^KRB5_KTNAME/#KRB5_KTNAME/g' /etc/sysconfig/slapd
    # add new config item
    echo 'KRB5_KTNAME="FILE:/etc/openldap/ldap.keytab"' >> /etc/sysconfig/slapd
    cat /etc/sysconfig/slapd
}

addOpenldapHostIntoKerberos() {
    # provision keytab file
    mv -f /tmp/krb5.keytab /etc/krb5.keytab
    chown root:root /etc/krb5.keytab
    chmod 600 /etc/krb5.keytab
    # configuring saslauthd refer to keytab file is merged with configuring saslauthd
    # please take a look function configSaslauthd
}

configKerberosAccountsMapping() {
    cat << EOF | ldapadd -Y EXTERNAL -H ldapi:///
dn: cn=config
changetype: modify
replace: olcAuthzRegexp
olcAuthzRegexp: uid=([^,]*),cn=gssapi,cn=auth uid=\$1,$OPENLDAP_USERS_BASE_DN
EOF
}

configSaslLib() {
    tee /etc/sasl2/slapd.conf <<EOF
pwcheck_method: saslauthd
saslauthd_path: /run/saslauthd/mux
EOF
}

configSaslauthd() {
    cp -f /etc/sysconfig/saslauthd /etc/sysconfig/saslauthd.$(date +%s)
    sed -i 's/^SOCKETDIR/#SOCKETDIR/g' /etc/sysconfig/saslauthd
    echo 'SOCKETDIR=/run/saslauthd' >> /etc/sysconfig/saslauthd
    sed -i 's/^MECH/#MECH/g' /etc/sysconfig/saslauthd
    echo 'MECH=kerberos5' >> /etc/sysconfig/saslauthd
    sed -i 's/^KRB5_KTNAME/#KRB5_KTNAME/g' /etc/sysconfig/saslauthd
    echo 'KRB5_KTNAME=/etc/krb5.keytab' >> /etc/sysconfig/saslauthd
}

enableSaslauthd() {
    systemctl enable saslauthd
    systemctl restart saslauthd
    systemctl status saslauthd
}

# -----------------------------------    SASL/GSSAPI Operations on EMR Cluster   ------------------------------------- #

enableSaslGssapiOnEmrCluster() {
    printHeading "ENABLE SASL/GSSAPI ON EMR CLUSTER"
    installSaslGssapiOnEmrCluster
    configSshdForGssapiOnEmrCluster
    restartSshdOnEmrCluster
}

installSaslGssapiOnEmrCluster() {
    # install on each node of EMR cluster
    for node in $(getEmrClusterNodes); do
        ssh -o StrictHostKeyChecking=no -i $SSH_KEY -T hadoop@$node \
        sudo yum -y install openldap-clients cyrus-sasl-lib cyrus-sasl-gssapi cyrus-sasl-devel krb5-workstation
    done
}

configSshdForGssapiOnEmrCluster() {
    # making a local shell script snippet and distribute to remote,
    # this is required, because ssh can't take local vars to remote.
    cat > /tmp/sshd-gssapi-snippet.sh <<'EOF'
        cp -f /etc/ssh/sshd_config /etc/ssh/sshd_config.$(date +%s)
        items=(KerberosAuthentication GSSAPIAuthentication)
        for item in ${items[@]}; do
            searchExp="^\s*[#]\?\s*${item}\s*\(yes\|no\)$"
            # all line numbers to be removed
            lineNums=($(grep -n -e "$searchExp" /etc/ssh/sshd_config | cut -d: -f1))
            # generate sed line numbers expr
            printf -v linesExp "%sd;" "${lineNums[@]}"
            # remove target lines
            sed -i -e "$linesExp" /etc/ssh/sshd_config
            # insert at 1st matched line number ( to keep related config items co-located )
            sed -i "${lineNums[0]}i ${item} yes" /etc/ssh/sshd_config
        done
EOF
    for node in $(getEmrClusterNodes); do
        scp -o StrictHostKeyChecking=no -i $SSH_KEY /tmp/sshd-gssapi-snippet.sh hadoop@$node:/tmp/sshd-gssapi-snippet.sh
        ssh -o StrictHostKeyChecking=no -i $SSH_KEY -T hadoop@$node sudo sh /tmp/sshd-gssapi-snippet.sh
    done
}

restartSshdOnEmrCluster() {
    for node in $(getEmrClusterNodes); do
        ssh -o StrictHostKeyChecking=no -i $SSH_KEY -T hadoop@$node <<EOSSH
        sudo systemctl restart sshd
        sudo systemctl status sshd
EOSSH
    done
}