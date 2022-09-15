
# --------------------------------------    Migrating Kerberos DB Operations   --------------------------------------- #

# be careful, migrating kerberos db is ONE-TIME operation,
# it can NOT run twice!
addExampleUsers() {
    printHeading "ADD EXAMPLE USER"
    testOpenldapSshConnectivity
    distributeInstaller "ec2-user" "$OPENLDAP_HOST"
    ssh -o StrictHostKeyChecking=no -i $SSH_KEY -T ec2-user@$OPENLDAP_HOST \
        sudo sh $APP_REMOTE_HOME/bin/setup.sh add-example-users-on-openldap-local \
        --region $REGION \
        --solution $SOLUTION \
        --auth-provider $AUTH_PROVIDER \
        --openldap-host $OPENLDAP_HOST \
        --openldap-base-dn $OPENLDAP_BASE_DN \
        --openldap-root-cn $OPENLDAP_ROOT_CN \
        --openldap-root-password $OPENLDAP_ROOT_PASSWORD \
        --example-users "$(echo ${EXAMPLE_USERS[*]} | sed -E 's/[[:blank:]]+/,/g')"

    # for emr-native, kerberos is required, so it is also required to
    # create kerberos mapping principals against openldap accounts.
    if [[ "$SOLUTION" = "emr-native" ]]; then
        testKerberosKdcConnectivity
        distributeInstaller "hadoop" "$KERBEROS_KDC_HOST"
        ssh -o StrictHostKeyChecking=no -i $SSH_KEY -T hadoop@$KERBEROS_KDC_HOST \
            sudo sh $APP_REMOTE_HOME/bin/setup.sh add-example-users-on-kdc-local \
            --region $REGION \
            --solution $SOLUTION \
            --auth-provider $AUTH_PROVIDER \
            --openldap-host $OPENLDAP_HOST \
            --openldap-base-dn $OPENLDAP_BASE_DN \
            --openldap-root-cn $OPENLDAP_ROOT_CN \
            --openldap-root-password $OPENLDAP_ROOT_PASSWORD \
            --example-users "$(echo ${EXAMPLE_USERS[*]} | sed -E 's/[[:blank:]]+/,/g')"
    fi
    # manually sync example user to ranger by restart ranger-usersync service
    # otherwise, ranger-usersync auto sync from ad/ldap every 360 minutes.
    # tips, this command should run on ranger server.
    ranger-usersync restart
}

addExampleUsersOnKdcLocal() {
    if [[ "$AUTH_PROVIDER" = "openldap" && "$SOLUTION" = "emr-native" ]]; then
        addKerberosUsers
    else
        echo "Nothing to do!"
        echo "add-example-users is a utility cli action, it ONLY works for openldap + open-source ranger or openldap + emr-native ranger solution!"
        echo "For Windows AD bases solution, please go to Windows AD server to create users!"
    fi
}

addExampleUsersOnOpenldapLocal() {
    if [[ "$AUTH_PROVIDER" = "openldap" ]]; then
        addOpenldapUsers
        # for emr-native, kerberos is required, so need unify password of ldap and kerberos
        if [[ "$SOLUTION" = "emr-native" ]]; then
            updateOpenldapUsersPasswordSetting
        fi
    fi
}

addOpenldapUsers() {
    for user in "${EXAMPLE_USERS[@]}"; do
        # add user
        cat << EOF | ldapadd -D "$OPENLDAP_ROOT_DN" -w $OPENLDAP_ROOT_PASSWORD
dn: uid=$user,$OPENLDAP_USERS_BASE_DN
objectClass: posixAccount
objectClass: top
objectClass: inetOrgPerson
uid: $user
displayName: $user
sn: $user
homeDirectory: /home/$user
cn: $user
uidNumber: $((1000+$RANDOM%9000))
gidNumber: 100
userPassword: $(slappasswd -s $COMMON_DEFAULT_PASSWORD)
EOF
        # add user to group
        ldapsearch -D "$OPENLDAP_ROOT_DN" -w $OPENLDAP_ROOT_PASSWORD -b "cn=$EXAMPLE_GROUP,ou=groups,$OPENLDAP_BASE_DN" >& /dev/null
        # if group not exists, use ldapadd, otherwise ldapmodify
        # the root cause of this augly design is ldap coupled group's creating with users!
        if [ "$?" != "0" ]; then
            cat << EOF | ldapadd -D "$OPENLDAP_ROOT_DN" -w $OPENLDAP_ROOT_PASSWORD
dn: cn=$EXAMPLE_GROUP,ou=groups,$OPENLDAP_BASE_DN
cn: $EXAMPLE_GROUP
objectclass: top
objectclass: groupofnames
member: uid=$user,$OPENLDAP_USERS_BASE_DN
EOF
        else
            cat << EOF | ldapmodify -D "$OPENLDAP_ROOT_DN" -w $OPENLDAP_ROOT_PASSWORD
dn: cn=$EXAMPLE_GROUP,ou=groups,$OPENLDAP_BASE_DN
changetype: modify
add: member
member: uid=$user,$OPENLDAP_USERS_BASE_DN
EOF
        fi
    done
}

addKerberosUsers() {
    # install expect in case not installed
    yum -y install expect
    # if kerberos db is migrated to openldap, -x parameter would be required
    if [ -f "$MIGRATE_KERBEROS_DB_FLAG" ]; then
       for user in "${EXAMPLE_USERS[@]}"; do
            /usr/bin/expect <<EOF
                spawn kadmin.local -q "addprinc -x dn=uid=$user,$OPENLDAP_USERS_BASE_DN $user"
                expect {
                    "Enter password*" {
                        send "$COMMON_DEFAULT_PASSWORD\r"
                        expect "Re-enter password*" { send "$COMMON_DEFAULT_PASSWORD\r" }
                    }
                }
                expect eof
EOF
        done
    else
       for user in "${EXAMPLE_USERS[@]}"; do
            /usr/bin/expect <<EOF
                spawn kadmin.local -q "addprinc $user"
                expect {
                    "Enter password*" {
                        send "$COMMON_DEFAULT_PASSWORD\r"
                        expect "Re-enter password*" { send "$COMMON_DEFAULT_PASSWORD\r" }
                    }
                }
                expect eof
EOF
        done
    fi
}

updateOpenldapUsersPasswordSetting() {
    for user in "${EXAMPLE_USERS[@]}"; do
        cat << EOF | ldapadd -D "$OPENLDAP_ROOT_DN" -w $OPENLDAP_ROOT_PASSWORD
dn: uid=$user,$OPENLDAP_USERS_BASE_DN
changetype: modify
replace: userPassword
userPassword: {SASL}$user@$KERBEROS_REALM
EOF
    done
}
