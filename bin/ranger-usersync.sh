#!/bin/bash

# ------------------------------------------   Ranger-UserSync Operations   ------------------------------------------ #

configRangerUsersyncCommonProps() {
    confFile="$1"
    sed -i "s|@RANGER_VERSION@|$RANGER_VERSION|g" $confFile
    sed -i "s|@RANGER_URL@|$RANGER_URL|g" $confFile
}

configRangerUsersyncAdProps() {
    confFile="$1"
    sed -i "s|@AD_URL@|$AD_URL|g" $confFile
    sed -i "s|@AD_BASE_DN@|$AD_BASE_DN|g" $confFile
    sed -i "s|@AD_RANGER_BIND_DN@|$AD_RANGER_BIND_DN|g" $confFile
    sed -i "s|@AD_RANGER_BIND_PASSWORD@|$AD_RANGER_BIND_PASSWORD|g" $confFile
    sed -i "s|@AD_USER_OBJECT_CLASS@|$AD_USER_OBJECT_CLASS|g" $confFile
}

configRangerUsersyncOpenldapProps() {
    confFile="$1"
    sed -i "s|@OPENLDAP_URL@|$OPENLDAP_URL|g" $confFile
    sed -i "s|@OPENLDAP_BASE_DN@|$OPENLDAP_BASE_DN|g" $confFile
    sed -i "s|@RANGER_BIND_DN@|$RANGER_BIND_DN|g" $confFile
    sed -i "s|@RANGER_BIND_PASSWORD@|$RANGER_BIND_PASSWORD|g" $confFile
    sed -i "s|@OPENLDAP_USER_OBJECT_CLASS@|$OPENLDAP_USER_OBJECT_CLASS|g" $confFile
}

configRangerUsersyncHttpProps() {
    confFile="$1"
    sed -i "s|@RANGER_URL@|$RANGER_URL|g" $confFile
}

configRangerUsersyncHttpsProps() {
    confFile="$1"
    sed -i "s|@RANGER_URL@|$RANGER_URL|g" $confFile
#    sed -i "s|@AUTH_SSL_TRUSTSTORE_FILE@|$RANGER_SECRETS_DIR/ranger-admin-truststore.jks|g" $confFile
#    sed -i "s|@AUTH_SSL_TRUSTSTORE_PASSWORD@|changeit|g" $confFile
}

installRangerUsersync() {
    printHeading "INSTALL RANGER USERSYNC"
    tar -zxvf /tmp/ranger-repo/ranger-$RANGER_VERSION-usersync.tar.gz -C /opt/ &>/dev/null
    installHome=/opt/ranger-$RANGER_VERSION-usersync
    confFile=$installHome/install.properties
    # backup existing version of install.properties
    cp $confFile $confFile.$(date +%s)
    # copy a new version from template file
    cp -f $APP_HOME/conf/ranger-usersync/$AUTH_PROVIDER-template.properties $confFile
    # ad or ldap configs
    if [ "$AUTH_PROVIDER" = "ad" ]; then
        configRangerUsersyncAdProps $confFile
    elif [ "$AUTH_PROVIDER" = "openldap" ]; then
        configRangerUsersyncOpenldapProps $confFile
    else
        echo "Invalid authentication type, only AD and LDAP are supported!"
        exit 1
    fi
    configRangerUsersyncCommonProps $confFile
    # https or http configs
#    if [ "$SOLUTION" = "emr-native" ]; then
#        configRangerUsersyncHttpsProps $confFile
#    elif [ "$SOLUTION" = "open-source" ]; then
#        configRangerUsersyncHttpProps $confFile
#    else
#        echo "Invalid --solution option value, only true or false are allowed!"
#        exit 1
#    fi
    curDir=$(pwd)
    # must run under project root dir.
    cd $installHome
    export JAVA_HOME=$JAVA_HOME
    sh setup.sh
    sh set_globals.sh
    cd $curDir
    # IMPORTANT! must enable usersync in ranger-ugsync-site.xml, by default, it is disabled!
    ugsyncConfFile=/etc/ranger/usersync/conf/ranger-ugsync-site.xml
    cp $ugsyncConfFile $ugsyncConfFile.$(date +%s)
    installXmlstarletIfNotExists
    xmlstarlet edit -L -u "/configuration/property/name[.='ranger.usersync.enabled']/../value" -v "true" $ugsyncConfFile
    ranger-usersync start
}

removeRangerUsersync() {
    echo "Stop Ranger UserSync Service..."
    ranger-usersync stop
    echo "Remove Ranger UserSync..."
    rm -rf /opt/ranger-$RANGER_VERSION-usersync
    rm -rf /etc/ranger/usersync
    rm -rf /var/log/ranger/usersync
    echo "BE CAREFUL: The following ranger files will be DELETED!"
    find /etc -name "*ranger-usersync*"
    find /etc -name "*ranger-usersync*" -exec rm -rf {} \;
}