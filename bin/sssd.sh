#!/bin/bash

installSssd() {
    printHeading "INSTALL SSSD"
    if [[ "$AUTH_PROVIDER" = "openldap" ]]; then
        installSssdPackagesForOpenldap
        configSssdForOpenldap
    elif [[ "$AUTH_PROVIDER" = "ad" && "$SOLUTION" = "open-source" ]]; then
        installSssdPackagesForAd
        joinRealm
    fi
    configSshdForSssd
    restartSssdRelatedServices
}

# -----------------------------------------    SSSD for AD Operations   ----------------------------------------- #

installSssdPackagesForOpenldap() {
    for node in $(getEmrClusterNodes); do
        ssh -o StrictHostKeyChecking=no -i $SSH_KEY -T hadoop@$node \
        sudo yum -y install openldap-clients sssd sssd-client sssd-ldap sssd-tools authconfig nss-pam-ldapd oddjob-mkhomedir
    done
}

configSssdForOpenldap() {
    for node in $(getEmrClusterNodes); do
        ssh -o StrictHostKeyChecking=no -i $SSH_KEY -T hadoop@$node <<EOSSH
        # first, config with authconfig
        sudo authconfig --enablesssd --enablesssdauth --enablemkhomedir --enablerfc2307bis \
            --enableldap --enableldapauth --disableldaptls --disableforcelegacy --disablekrb5 \
            --ldapserver ldap://$OPENLDAP_HOST --ldapbasedn "dc=example,dc=com" --updateall
        # second, append more config items in sssd.conf
        sudo tee /etc/sssd/sssd.conf<<EOF
[sssd]
services = nss, pam, autofs
domains = default
[domain/default]
autofs_provider = ldap
ldap_schema = rfc2307bis
ldap_search_base = $OPENLDAP_BASE_DN
id_provider = ldap
auth_provider = ldap
chpass_provider = ldap
ldap_uri = ldap://$OPENLDAP_HOST
ldap_id_use_start_tls = False
cache_credentials = True
ldap_tls_reqcert = never
ldap_tls_cacertdir = /etc/openldap/cacerts
ldap_default_bind_dn = $SSSD_BIND_DN
ldap_default_authtok_type = password
ldap_default_authtok = $SSSD_BIND_PASSWORD
override_homedir = /home/%u
default_shell = /bin/bash
[nss]
homedir_substring = /home
[pam]
[autofs]
EOF
    sudo chmod 600 /etc/sssd/sssd.conf
EOSSH
    done
}

# --------------------------------------------    SSSD for AD Operations   ------------------------------------------- #

installSssdPackagesForAd() {
    for node in $(getEmrClusterNodes); do
        ssh -o StrictHostKeyChecking=no -i $SSH_KEY -T hadoop@$node <<EOSSH
        sudo yum -y install oddjob oddjob-mkhomedir sssd samba-common-tools adcli krb5-workstation openldap-clients policycoreutils-python realmd
EOSSH
    done
}

joinRealm() {
    if [[ "$AD_DOMAIN_ADMIN" = "" || "$AD_DOMAIN_ADMIN_PASSWORD" = "" ]]; then
        echo "ERROR! --ad-domain-admin or --ad-domain-admin-password is not provided!"
        exit 1
    fi
    for node in $(getEmrClusterNodes); do
        echo "Start to join [ $node] to Windows AD domain, this may take several minutes..."
        ssh -o StrictHostKeyChecking=no -i $SSH_KEY -T hadoop@$node <<EOSSH
        # we need disable output by &>/dev/null, otherwise there will be a prompt: "Password for domain-admin: "
        # this is will deliver error message to users. Actually, the password is input by echo command already!
        echo $AD_DOMAIN_ADMIN_PASSWORD | sudo realm join -U "$AD_DOMAIN_ADMIN" "$AD_DOMAIN" &>/dev/null
EOSSH
    done
}

configSshdForSssd() {
    # making a local shell script snippet and distribute to remote,
    # this is required, because ssh can't take local vars to remote.
    cat > /tmp/sshd-sssd-snippet.sh <<'EOF'
        cp -f /etc/ssh/sshd_config /etc/ssh/sshd_config.$(date +%s)
        items=(UsePAM PasswordAuthentication)
        for item in "${items[@]}"; do
            searchExp="^\s*[#]\?\s*${item}\s*\(yes\|no\)$"
            # all line numbers to be removed
            lineNums=($(grep -n -e "$searchExp" /etc/ssh/sshd_config | cut -d: -f1))
            # generate sed line numbers expr
            printf -v linesExp "%sd;" "${lineNums[@]}"
            # remove target lines
            sudo sed -i -e "$linesExp" /etc/ssh/sshd_config
            # insert at 1st matched line number ( to keep related config items co-located )
            sed "${lineNums[0]}i ${item} yes" -i /etc/ssh/sshd_config
        done
EOF
    for node in $(getEmrClusterNodes); do
        scp -o StrictHostKeyChecking=no -i $SSH_KEY /tmp/sshd-sssd-snippet.sh hadoop@$node:/tmp/sshd-sssd-snippet.sh
        ssh -o StrictHostKeyChecking=no -i $SSH_KEY -T hadoop@$node sudo sh /tmp/sshd-sssd-snippet.sh
    done
}

restartSssdRelatedServices() {
    for node in $(getEmrClusterNodes); do
        ssh -o StrictHostKeyChecking=no -i $SSH_KEY -T hadoop@$node <<EOSSH
        sudo systemctl enable sssd oddjobd
        sudo systemctl restart sssd oddjobd sshd
        sudo systemctl status sssd oddjobd sshd
EOSSH
    done
}