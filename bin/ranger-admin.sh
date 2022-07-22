#!/bin/bash

# --------------------------------------------   Ranger-Admin Operations   ------------------------------------------- #

initRangerAdminDb() {
    printHeading "INIT RANGER DB"
    cp $APP_HOME/sql/init-ranger-db.sql $APP_HOME/sql/.init-ranger-db.sql
    sed -i "s|@DB_HOST@|$MYSQL_HOST|g" $APP_HOME/sql/.init-ranger-db.sql
    sed -i "s|@MYSQL_RANGER_DB_USER_PASSWORD@|$MYSQL_RANGER_DB_USER_PASSWORD|g" $APP_HOME/sql/.init-ranger-db.sql
    mysql -h$MYSQL_HOST -uroot -p$MYSQL_ROOT_PASSWORD -s --prompt=nowarning --connect-expired-password <$APP_HOME/sql/.init-ranger-db.sql
}

configRangerAdminCommonProps() {
    confFile="$1"
    sed -i "s|@DB_HOST@|$MYSQL_HOST|g" $confFile
    sed -i "s|@DB_ROOT_PASSWORD@|$MYSQL_ROOT_PASSWORD|g" $confFile
    sed -i "s|@SOLR_HOST@|$SOLR_HOST|g" $confFile
    sed -i "s|@DB_PASSWORD@|$MYSQL_RANGER_DB_USER_PASSWORD|g" $confFile
    sed -i "s|@RANGER_VERSION@|$RANGER_VERSION|g" $confFile
}

configRangerAdminAdProps() {
    confFile="$1"
    sed -i "s|@AD_DOMAIN@|$AD_DOMAIN|g" $confFile
    sed -i "s|@AD_URL@|$AD_URL|g" $confFile
    sed -i "s|@AD_BASE_DN@|$AD_BASE_DN|g" $confFile
    sed -i "s|@AD_RANGER_BIND_DN@|$AD_RANGER_BIND_DN|g" $confFile
    sed -i "s|@AD_RANGER_BIND_PASSWORD@|$AD_RANGER_BIND_PASSWORD|g" $confFile
    sed -i "s|@AD_USER_OBJECT_CLASS@|$AD_USER_OBJECT_CLASS|g" $confFile
}

configRangerAdminOpenldapProps() {
    confFile="$1"
    sed -i "s|@OPENLDAP_URL@|$OPENLDAP_URL|g" $confFile
    sed -i "s|@OPENLDAP_USER_DN_PATTERN@|$OPENLDAP_USER_DN_PATTERN|g" $confFile
    sed -i "s|@OPENLDAP_GROUP_SEARCH_FILTER@|$OPENLDAP_GROUP_SEARCH_FILTER|g" $confFile
    sed -i "s|@OPENLDAP_BASE_DN@|$OPENLDAP_BASE_DN|g" $confFile
    sed -i "s|@OPENLDAP_RANGER_BIND_DN@|$OPENLDAP_RANGER_BIND_DN|g" $confFile
    sed -i "s|@OPENLDAP_RANGER_BIND_PASSWORD@|$OPENLDAP_RANGER_BIND_PASSWORD|g" $confFile
    sed -i "s|@OPENLDAP_USER_OBJECT_CLASS@|$OPENLDAP_USER_OBJECT_CLASS|g" $confFile
}

configRangerAdminHttpProps() {
    confFile="$1"
    sed -i "s|@POLICYMGR_EXTERNAL_URL@|$RANGER_URL|g" $confFile
    sed -i "s|@POLICYMGR_HTTP_ENABLED@|true|g" $confFile
    sed -i "s|@POLICYMGR_HTTPS_KEYSTORE_FILE@||g" $confFile
    sed -i "s|@POLICYMGR_HTTPS_KEYSTORE_KEYALIAS@||g" $confFile
    sed -i "s|@POLICYMGR_HTTPS_KEYSTORE_PASSWORD@||g" $confFile
}

configRangerAdminHttpsProps() {
    confFile="$1"
    sed -i "s|@POLICYMGR_EXTERNAL_URL@|$RANGER_URL|g" $confFile
    sed -i "s|@POLICYMGR_HTTP_ENABLED@|false|g" $confFile
    sed -i "s|@POLICYMGR_HTTPS_KEYSTORE_FILE@|$RANGER_SECRETS_DIR/ranger-admin-keystore.jks|g" $confFile
    sed -i "s|@POLICYMGR_HTTPS_KEYSTORE_KEYALIAS@|ranger-admin|g" $confFile
    sed -i "s|@POLICYMGR_HTTPS_KEYSTORE_PASSWORD@|changeit|g" $confFile
}

configRangerAdminKrbProps() {
    confFile="$1"
    sed -i "s|@RANGER_HOST@|$RANGER_HOST|g" $confFile
    sed -i "s|@KERBEROS_REALM@|$KERBEROS_REALM|g" $confFile
    sed -i "s|@RANGER_SECRETS_DIR@|$RANGER_SECRETS_DIR|g" $confFile
}

makeUserHomeOnHdfs() {

    user=ad-user-1

    # MUST create user on all nodes!!
    sudo groupadd $user
    sudo useradd -g $user $user

    user=ad-user-1
    hdfs dfs -mkdir /user/$user
    hdfs dfs -chown $user:$user /user/$user
    hdfs dfs -chmod 777 /user/$user
    hdfs dfs -ls /user

    sudo kadmin.local -q "addprinc ad-user-1@EXAMPLE.COM"
}

installRangerAdmin() {
    printHeading "INSTALL RANGER ADMIN FOR AD"
    # remove all existing files
    rm -rf /opt/ranger-$RANGER_VERSION-admin
    rm -rf /etc/ranger/admin
    rm -rf /var/log/ranger/admin
    tar -zxvf /tmp/ranger-repo/ranger-$RANGER_VERSION-admin.tar.gz -C /opt/ &>/dev/null
    installHome=/opt/ranger-$RANGER_VERSION-admin

    confFile=$installHome/install.properties
    # backup existing version of install.properties
    cp $confFile $confFile.$(date +%s)
    # copy a new version from template file
    cp -f $APP_HOME/conf/ranger-admin/$AUTH_PROVIDER-template.properties $confFile
    # ad or ldap configs
    if [ "$AUTH_PROVIDER" = "ad" ]; then
        configRangerAdminAdProps $confFile
    elif [ "$AUTH_PROVIDER" = "openldap" ]; then
        configRangerAdminOpenldapProps $confFile
    else
        echo "Invalid authentication type, only AD and LDAP are supported!"
        exit 1
    fi
    # common configs
    configRangerAdminCommonProps $confFile
    # https or http configs
    if [ "$SOLUTION" = "emr-native" ]; then
        # it's NOT required to add ranger into kerberos
        # configRangerAdminKrbProps $confFile
        configRangerAdminHttpsProps $confFile
    elif [ "$SOLUTION" = "open-source" ]; then
        configRangerAdminHttpProps $confFile
    else
        echo "Invalid --solution option value, only true or false are allowed!"
        exit 1
    fi

    curDir=$(pwd)
    # must run under project root dir.
    cd $installHome
    export JAVA_HOME=$JAVA_HOME
    sh setup.sh
    sh set_globals.sh
    cd $curDir
    installXmlstarletIfNotExists
    # Ranger installation scripts have BUG!!
    # although, for the sake of security, ranger write password to a key store file,
    # however, it does not work, and at the same time, it removes password in xml conf file with "_",
    # so, it can't login after installation! here, write password back to conf xml file!!
#    adminConfFile=/etc/ranger/admin/conf/ranger-admin-site.xml
#    cp $adminConfFile $adminConfFile.$(date +%s)
    # xmlstarlet edit -L -u "/configuration/property/name[.='ranger.jpa.jdbc.password']/../value" -v "$MYSQL_RANGER_DB_USER_PASSWORD" $adminConfFile
    # ranger.service.https.attrib.keystore.pass 这个也得改
    # 上面这个BUG有可能和cred_keystore_filename=$app_home/WEB-INF/classes/conf/.jceks/rangeradmin.jceks这个配置有管！$app_home得改！
    ranger-admin stop || true
    sleep $RESTART_INTERVAL
    ranger-admin start
    # waiting for staring, this is required!
    sleep $RESTART_INTERVAL
}

testRangerAdminConnectivity() {
    printHeading "TEST RANGER CONNECTIVITY"
    nc -vz $RANGER_HOST $RANGER_PORT
    if [ "$?" = "0" ]; then
        echo "Connecting to ranger server is SUCCESSFUL!!"
    else
        echo "Connecting to ranger server is FAILED!!"
        exit 1
    fi
}

removeRangerAdmin() {
    echo "Stop Ranger Admin Service..."
    ranger-admin stop
    echo "Drop Ranger DB..."
    mysql -h$MYSQL_HOST -uroot -p$MYSQL_ROOT_PASSWORD -s --prompt=nowarning --connect-expired-password -e "drop database if exists ranger;"
    echo "Remove Ranger Admin..."
    rm -rf /opt/ranger-$RANGER_VERSION-admin
    rm -rf /etc/ranger/admin
    rm -rf /var/log/ranger/admin
    echo "BE CAREFUL: The following ranger files will be DELETED!"
    find /etc -name "*ranger-admin*"
    find /etc -name "*ranger-admin*" -exec rm -rf {} \;
    userdel -r ranger
    groupdel ranger
}

downloadRangerRepo() {
    # repo dir plays a download flag file, if exists, skip download again.
    if [ ! -d /tmp/ranger-repo ]; then
        printHeading "DOWNLOAD RANGER"
        curl --connect-timeout 5 -I $RANGER_REPO_FILE_URL &>/dev/null
        if [ ! "$?" = "0" ]; then
            echo "Given Ranger Repo URL: $RANGER_REPO_FILE_URL is inaccessible, please check network and security group settings!"
            exit 1
        fi
#        wget --recursive --no-parent --no-directories --no-host-directories $RANGER_REPO_FILE_URL -P /tmp/ranger-repo &>/dev/null
        wget $RANGER_REPO_FILE_URL -O /tmp/ranger-repo.zip
        unzip -o /tmp/ranger-repo.zip -d /tmp/
    fi
}

# Because of file size limiting (<100MB) of GitHub, ranger installation files are splitted to 10 files,
# So have to combine them before unpackage
downloadRangerRepoFromGithub() {
    # README.md play a download flag file, if exists, skip download again.
    # Too many downloads from an IP will be blocked by GitHub!
    if [ ! -f /tmp/ranger-repo/README.md ]; then
        printHeading "DOWNLOAD RANGER"
        wget https://github.com/bluishglc/ranger-repo/archive/v$RANGER_VERSION.tar.gz -O /tmp/ranger-repo.tar.gz
        tar -zxvf /tmp/ranger-repo.tar.gz -C /tmp &>/dev/null
        cat /tmp/ranger-repo/ranger-repo.tar.gz.* >/tmp/ranger-repo/ranger-repo.tar.gz
        tar -zxvf /tmp/ranger-repo/ranger-repo.tar.gz -C /tmp &>/dev/null
        rm -rf /tmp/ranger-repo.tar.gz
        rm -rf /tmp/ranger-repo/ranger-repo.tar.gz*
    fi
}
