#!/bin/bash

#!/usr/bin/env bash


# -------------------------------------------------   AD Operations   ------------------------------------------------ #

testLdapConnectivity() {
    printHeading "TEST Windows AD / OpenLDAP CONNECTIVITY"
    ldapsearch -VV &>/dev/null
    if [ ! "$?" = "0" ]; then
        echo "Install ldapsearch for Windows AD / OpenLDAP connectivity test"
        yum -y install openldap-clients &>/dev/null
    fi
    if [ "$AUTH_PROVIDER" = "ad" ]; then
        echo "Searched following dn from Windows AD server with given configs:"
        ldapsearch -x -LLL -D "$RANGER_BIND_DN" -w "$RANGER_BIND_PASSWORD" -H "$AD_URL" -b "$AD_BASE_DN" dn
    elif [ "$AUTH_PROVIDER" = "openldap" ]; then
        echo "Searched following dn from OpenLDAP server with given configs:"
        ldapsearch -x -LLL -D "$RANGER_BIND_DN" -w "$RANGER_BIND_PASSWORD" -H "$OPENLDAP_URL" -b "$OPENLDAP_BASE_DN" dn
    else
        echo "Invalid authentication type, only AD and LDAP are supported!"
        exit 1
    fi

    if [ "$?" = "0" ]; then
        echo "Connecting to Windows AD / OpenLDAP server is SUCCESSFUL!!"
    else
        echo "Connecting to Windows AD / OpenLDAP server is FAILED!!"
        exit 1
    fi
}

# -------------------------------------------   Ranger Plugin Operations   ------------------------------------------- #

testEmrSshConnectivity() {
    printHeading "TEST EMR SSH CONNECTIVITY"
    if [ -f $SSH_KEY ]; then
        for masterNode in $(getEmrMasterNodes); do
            printHeading "MASTER NODE [ $masterNode ]"
            ssh -o ConnectTimeout=5 -o ConnectionAttempts=1 -o StrictHostKeyChecking=no -i $SSH_KEY -T hadoop@$masterNode <<EOF
            systemctl --type=service --state=running|egrep '^(hadoop|hbase|hive|spark|hue|presto|oozie|zookeeper|flink)\S*'
EOF
            if [ ! "$?" = "0" ]; then
                echo "ERROR!! connection to [ $masterNode ] failed!"
                exit 1
            fi
        done
        for node in $(getEmrSlaveNodes); do
            printHeading "CORE NODE [ $node ]"
            ssh -o ConnectTimeout=5 -o ConnectionAttempts=1 -o StrictHostKeyChecking=no -i $SSH_KEY -T hadoop@$node <<EOF
            systemctl --type=service --state=running|egrep '^(hadoop|hbase|hive|spark|hue|presto|oozie|zookeeper|flink)\S*'
EOF
            if [ ! "$?" = "0" ]; then
                echo "ERROR!! connection to [ $node ] failed!"
                exit 1
            fi
        done
    else
        echo "ERROR!! The ssh key file to login EMR nodes dese NOT exist!"
        exit 1
    fi
}

testEmrNamenodeConnectivity() {
    printHeading "TEST NAMENODE CONNECTIVITY"
    for node in $(getEmrMasterNodes); do
        nc -vz $node 8020 &>/dev/null
        if [ "$?" = "0" ]; then
            echo "Connecting to namenode [ $node ] is SUCCESSFUL!!"
        else
            echo "Connecting to namenode [ $node ] is FAILED!!"
            exit 1
        fi
    done
}

testSolrConnectivityFromEmrNodes() {
    printHeading "TEST CONNECTIVITY FROM EMR NODES TO SOLR"
    for node in $(getEmrClusterNodes); do
        ssh -o StrictHostKeyChecking=no -i $SSH_KEY -T hadoop@$node <<EOF
        if ! nc --version &>/dev/null; then
            sudo yum -y install nc
        fi
EOF
        ssh -o StrictHostKeyChecking=no -i $SSH_KEY -T hadoop@$node nc -vz $SOLR_HOST 8983
        if [ "$?" = "0" ]; then
            echo "Connecting to solr server from [ $node ] is SUCCESSFUL!!"
        else
            echo "Connecting to solr server from [ $node ] is FAILED!!"
            exit 1
        fi
    done
}

testRangerAdminConnectivityFromEmrNodes() {
    printHeading "TEST CONNECTIVITY FROM EMR NODES TO RANGER"
    for node in $(getEmrClusterNodes); do
        ssh -o StrictHostKeyChecking=no -i $SSH_KEY -T hadoop@$node <<EOF
        if ! nc --version &>/dev/null; then
            sudo yum -y install nc
        fi
EOF
        ssh -o StrictHostKeyChecking=no -i $SSH_KEY -T hadoop@$node nc -vz $RANGER_HOST $RANGER_PORT
        if [ "$?" = "0" ]; then
            echo "Connecting to ranger server from [ $node ] is SUCCESSFUL!!"
        else
            echo "Connecting to ranger server from [ $node ] is FAILED!!"
            exit 1
        fi
    done
}

# --------------------------------------    EMR Native EMRFS PlugIn Operations    --------------------------------------- #

installRangerEmrNativeEmrfsPlugin() {
    printHeading "INSTALL EMR NATIVE RANGER EMRFS PLUGIN"
    installHome=/opt/ranger-$RANGER_VERSION-admin/ews/webapp/WEB-INF/classes/ranger-plugins/amazon-emr-emrfs
    rm -rf $installHome
    mkdir $installHome
    cp /tmp/ranger-repo/ranger-emr-emrfs-plugin-2.x.jar $installHome/
    echo "Create emrfs plugin servicedef..."
    curl -k -iv -u admin:admin -d @$APP_HOME/policy/emr-native-emrfs-servicedef.json -H "Content-Type: application/json" \
        -X POST $RANGER_URL/service/public/v2/api/servicedef
    echo "Create emrfs plugin repo..."
    cp $APP_HOME/policy/emr-native-emrfs-repo.json $APP_HOME/policy/.emr-native-emrfs-repo.json
    sed -i "s|@CERTIFICATE_CN@|$CERTIFICATE_CN|g" $APP_HOME/policy/.emr-native-emrfs-repo.json
    curl -k -iv -u admin:admin -d @$APP_HOME/policy/.emr-native-emrfs-repo.json -H "Content-Type: application/json" \
        -X POST $RANGER_URL/service/public/v2/api/service/
    echo ""
}

# ------------------------------------    EMR Native Spark PlugIn Operations    -------------------------------------- #

installRangerEmrNativeSparkPlugin() {
    printHeading "INSTALL EMR NATIVE RANGER SPARK PLUGIN"
    installHome=/opt/ranger-$RANGER_VERSION-admin/ews/webapp/WEB-INF/classes/ranger-plugins/amazon-emr-spark
    rm -rf $installHome
    mkdir $installHome
    cp /tmp/ranger-repo/ranger-spark-plugin-2.x.jar $installHome/
    echo "Create Spark plugin servicedef..."
    curl -k -iv -u admin:admin -d @$APP_HOME/policy/emr-native-spark-servicedef.json -H "Content-Type: application/json" \
        -X POST $RANGER_URL/service/public/v2/api/servicedef
    echo "Create Spark plugin repo..."
    cp $APP_HOME/policy/emr-native-spark-repo.json $APP_HOME/policy/.emr-native-spark-repo.json
    sed -i "s|@CERTIFICATE_CN@|$CERTIFICATE_CN|g" $APP_HOME/policy/.emr-native-spark-repo.json
    curl -k -iv -u admin:admin -d @$APP_HOME/policy/.emr-native-spark-repo.json -H "Content-Type: application/json" \
        -X POST $RANGER_URL/service/public/v2/api/service/
    echo ""
}

# --------------------------------------   EMR Native Hive PlugIn Operations   --------------------------------------- #

installRangerEmrNativeHivePlugin() {
    printHeading "INSTALL EMR NATIVE RANGER HIVE PLUGIN"
        cp $APP_HOME/policy/emr-native-hive-repo.json $APP_HOME/policy/.emr-native-hive-repo.json
    sed -i "s|@CERTIFICATE_CN@|$CERTIFICATE_CN|g" $APP_HOME/policy/.emr-native-hive-repo.json
    curl -k -iv -u admin:admin -d @$APP_HOME/policy/.emr-native-hive-repo.json -H "Content-Type: application/json" \
        -X POST $RANGER_URL/service/public/api/repository/
    echo ""
}

# --------------------------------------   EMR Native Trino PlugIn Operations   --------------------------------------- #

# Note: Trino is not supported yet by end of Jul. 2022, although official doc has added trino plugin!
installRangerEmrNativeTrinoPlugin() {
    printHeading "INSTALL EMR NATIVE RANGER TRINO PLUGIN"
    installHome=/opt/ranger-$RANGER_VERSION-admin/ews/webapp/WEB-INF/classes/ranger-plugins/amazon-emr-trino
    rm -rf $installHome
    mkdir $installHome
    echo "Create Trino plugin servicedef..."
    # remove if exists
    curl -k -iv -u admin:admin -X DELETE $RANGER_URL/service/public/v2/api/servicedef/name/amazon-emr-trino
    curl -k -iv -u admin:admin -d @$APP_HOME/policy/emr-native-trino-servicedef.json -H "Content-Type: application/json" \
        -X POST $RANGER_URL/service/public/v2/api/servicedef
    echo "Create Trino plugin repo..."
    cp $APP_HOME/policy/emr-native-trino-repo.json $APP_HOME/policy/.emr-native-trino-repo.json
    sed -i "s|@CERTIFICATE_CN@|$CERTIFICATE_CN|g" $APP_HOME/policy/.emr-native-trino-repo.json
    curl -k -iv -u admin:admin -d @$APP_HOME/policy/.emr-native-trino-repo.json -H "Content-Type: application/json" \
        -X POST $RANGER_URL/service/public/v2/api/service/
    echo ""
}

# --------------------------------------  Open Source HDFS PlugIn Operations   --------------------------------------- #

initRangerOpenSourceHdfsRepo() {
    printHeading "INIT RANGER HDFS REPO"
    cp $APP_HOME/policy/open-source-hdfs-repo.json $APP_HOME/policy/.open-source-hdfs-repo.json
    sed -i "s|@EMR_CLUSTER_ID@|$EMR_CLUSTER_ID|g" $APP_HOME/policy/.open-source-hdfs-repo.json
    sed -i "s|@EMR_HDFS_URL@|$(getEmrHdfsUrl)|g" $APP_HOME/policy/.open-source-hdfs-repo.json
    curl -iv -u admin:admin -d @$APP_HOME/policy/.open-source-hdfs-repo.json -H "Content-Type: application/json" \
        -X POST $RANGER_URL/service/public/api/repository/
    sleep 5 # sleep for a while, otherwise repo may be not available for policy to refer.
    # import user default policy is required, otherwise some services have no permission to r/w its data, i.e. hbase
    cp $APP_HOME/policy/open-source-hdfs-policy.json $APP_HOME/policy/.open-source-hdfs-policy.json
    sed -i "s|@EMR_CLUSTER_ID@|$EMR_CLUSTER_ID|g" $APP_HOME/policy/.open-source-hdfs-policy.json
    curl -iv -u admin:admin -d @$APP_HOME/policy/.open-source-hdfs-policy.json -H "Content-Type: application/json" \
        -X POST $RANGER_URL/service/public/api/policy/
    echo ""
}

installRangerOpenSourceHdfsPlugin() {
    # Must init repo first before install plugin
    initRangerOpenSourceHdfsRepo
    printHeading "INSTALL RANGER HDFS PLUGIN"
    tar -zxvf /tmp/ranger-repo/ranger-$RANGER_VERSION-hdfs-plugin.tar.gz -C /tmp &>/dev/null
    installFilesDir=/tmp/ranger-$RANGER_VERSION-hdfs-plugin
    confFile=$installFilesDir/install.properties
    # backup install.properties
    cp $confFile $confFile.$(date +%s)
    cp $APP_HOME/conf/ranger-plugin/hdfs-template.properties $confFile
    sed -i "s|@EMR_CLUSTER_ID@|$EMR_CLUSTER_ID|g" $confFile
    sed -i "s|@SOLR_HOST@|$SOLR_HOST|g" $confFile
    sed -i "s|@POLICY_MGR_URL@|$RANGER_URL|g" $confFile
    installHome=/opt/ranger-$RANGER_VERSION-hdfs-plugin
    for masterNode in $(getEmrMasterNodes); do
        printHeading "INSTALL RANGER HDFS PLUGIN ON MASTER NODE: [ $masterNode ]: "
        ssh -o StrictHostKeyChecking=no -i $SSH_KEY -T hadoop@$masterNode sudo rm -rf $installFilesDir $installHome
        # NOTE: we can't copy files from local /tmp/plugin-dir to remote /opt/plugin-dir,
        # because hadoop user has no write permission at /opt
        scp -o StrictHostKeyChecking=no -i $SSH_KEY -r $installFilesDir hadoop@$masterNode:$installFilesDir &>/dev/null
        ssh -o StrictHostKeyChecking=no -i $SSH_KEY -T hadoop@$masterNode <<EOF
            sudo cp -r $installFilesDir $installHome
            # the enable-hdfs-plugin.sh just work with open source version of hadoop,
            # for emr, we have to copy ranger jars to /usr/lib/hadoop-hdfs/lib/
            sudo find $installHome/lib -name *.jar -exec cp {} /usr/lib/hadoop-hdfs/lib/ \;
            sudo sh $installHome/enable-hdfs-plugin.sh
            # NOTE: from a certain version of EMR 6.x, a strange issue is: enable hdfs plugin does NOT work anymore
            # but if enable twice, it will work! both ranger and EMR are changing with version iteration.
            # I don't want to waste time on the stupid issue anymore, so just enable TWICE!!
            sudo sh $installHome/enable-hdfs-plugin.sh
EOF
    done
    restartNamenode
}

restartNamenode() {
    printHeading "RESTART NAMENODE"
    for masterNode in $(getEmrMasterNodes); do
        echo "STOP NAMENODE ON MASTER NODE: [ $masterNode ]"
        ssh -o StrictHostKeyChecking=no -i $SSH_KEY -T hadoop@$masterNode sudo systemctl stop hadoop-hdfs-namenode
        sleep $RESTART_INTERVAL
        echo "START NAMENODE ON MASTER NODE: [ $masterNode ]"
        ssh -o StrictHostKeyChecking=no -i $SSH_KEY -T hadoop@$masterNode sudo systemctl start hadoop-hdfs-namenode
        sleep $RESTART_INTERVAL
    done
}

# -------------------------------------   Open Source Hive PlugIn Operations   --------------------------------------- #

initRangerOpenSourceHiveRepo() {
    printHeading "INIT RANGER HIVE REPO"
    cp $APP_HOME/policy/open-source-hive-repo.json $APP_HOME/policy/.open-source-hive-repo.json
    sed -i "s|@EMR_CLUSTER_ID@|$EMR_CLUSTER_ID|g" $APP_HOME/policy/.open-source-hive-repo.json
    sed -i "s|@EMR_FIRST_MASTER_NODE@|$(getEmrFirstMasterNode)|g" $APP_HOME/policy/.open-source-hive-repo.json
    curl -iv -u admin:admin -d @$APP_HOME/policy/.open-source-hive-repo.json -H "Content-Type: application/json" \
        -X POST $RANGER_URL/service/public/api/repository/
    echo ""
}

installRangerOpenSourceHivePlugin() {
    # Must init repo first before install plugin
    initRangerOpenSourceHiveRepo
    printHeading "INSTALL RANGER HIVE PLUGIN"
    tar -zxvf /tmp/ranger-repo/ranger-$RANGER_VERSION-hive-plugin.tar.gz -C /tmp/ &>/dev/null
    installFilesDir=/tmp/ranger-$RANGER_VERSION-hive-plugin
    confFile=$installFilesDir/install.properties
    # backup install.properties
    cp $confFile $confFile.$(date +%s)
    cp $APP_HOME/conf/ranger-plugin/hive-template.properties $confFile
    sed -i "s|@EMR_CLUSTER_ID@|$EMR_CLUSTER_ID|g" $confFile
    sed -i "s|@SOLR_HOST@|$SOLR_HOST|g" $confFile
    sed -i "s|@RANGER_HOST@|$RANGER_HOST|g" $confFile
    installHome=/opt/ranger-$RANGER_VERSION-hive-plugin
    for masterNode in $(getEmrMasterNodes); do
        printHeading "INSTALL RANGER HIVE PLUGIN ON MASTER NODE: [ $masterNode ] "
        ssh -o StrictHostKeyChecking=no -i $SSH_KEY -T hadoop@$masterNode sudo rm -rf $installFilesDir $installHome
        # NOTE: we can't copy files from local /tmp/plugin-dir to remote /opt/plugin-dir,
        # because hadoop user has no write permission at /opt
        scp -o StrictHostKeyChecking=no -i $SSH_KEY -r $installFilesDir hadoop@$masterNode:$installFilesDir &>/dev/null
        ssh -o StrictHostKeyChecking=no -i $SSH_KEY -T hadoop@$masterNode <<EOF
            sudo cp -r $installFilesDir $installHome
            # the enable-hive-plugin.sh just work with open source version of hadoop,
            # for emr, we have to copy ranger jars to /usr/lib/hive/lib/
            sudo find $installHome/lib -name *.jar -exec cp {} /usr/lib/hive/lib/ \;
            sudo sh $installHome/enable-hive-plugin.sh
EOF
    done
    restartHiveServer2
}

restartHiveServer2() {
    printHeading "RESTART HIVESERVER2"
    for masterNode in $(getEmrMasterNodes); do
        echo "STOP HIVESERVER2 ON MASTER NODE: [ $masterNode ]"
        ssh -o StrictHostKeyChecking=no -i $SSH_KEY -T hadoop@$masterNode sudo systemctl stop hive-server2
        sleep $RESTART_INTERVAL
        echo "START HIVESERVER2 ON MASTER NODE: [ $masterNode ]"
        ssh -o StrictHostKeyChecking=no -i $SSH_KEY -T hadoop@$masterNode sudo systemctl start hive-server2
        sleep $RESTART_INTERVAL
    done
}

# -------------------------------------   Open Source HBase PlugIn Operations   -------------------------------------- #

initRangerOpenSourceHbaseRepo() {
    printHeading "INIT RANGER HBASE REPO"
    cp $APP_HOME/policy/open-source-hbase-repo.json $APP_HOME/policy/.open-source-hbase-repo.json
    sed -i "s|@EMR_CLUSTER_ID@|$EMR_CLUSTER_ID|g" $APP_HOME/policy/.open-source-hbase-repo.json
    sed -i "s|@EMR_ZK_QUORUM@|$(getEmrZkQuorum)|g" $APP_HOME/policy/.open-source-hbase-repo.json
    curl -iv -u admin:admin -d @$APP_HOME/policy/.open-source-hbase-repo.json -H "Content-Type: application/json" \
        -X POST $RANGER_URL/service/public/api/repository/
    echo ""
}

installRangerOpenSourceHbasePlugin() {
    # Must init repo first before install plugin
    initRangerOpenSourceHbaseRepo
    printHeading "INSTALL RANGER HBASE PLUGIN"
    tar -zxvf /tmp/ranger-repo/ranger-$RANGER_VERSION-hbase-plugin.tar.gz -C /tmp &>/dev/null
    installFilesDir=/tmp/ranger-$RANGER_VERSION-hbase-plugin
    confFile=$installFilesDir/install.properties
    # backup install.properties
    cp $confFile $confFile.$(date +%s)
    cp $APP_HOME/conf/ranger-plugin/hbase-template.properties $confFile
    sed -i "s|@EMR_CLUSTER_ID@|$EMR_CLUSTER_ID|g" $confFile
    sed -i "s|@SOLR_HOST@|$SOLR_HOST|g" $confFile
    sed -i "s|@RANGER_URL@|$RANGER_URL|g" $confFile
    for node in $(getEmrClusterNodes); do
        printHeading "INSTALL RANGER HBASE PLUGIN ON NODE: [ $masterNode ]: "
        installHome=/opt/ranger-$RANGER_VERSION-hbase-plugin
        ssh -o StrictHostKeyChecking=no -i $SSH_KEY -T hadoop@$node sudo rm -rf $installFilesDir $installHome
        # NOTE: we can't copy files from local /tmp/plugin-dir to remote /opt/plugin-dir,
        # because hadoop user has no write permission at /opt
        scp -o StrictHostKeyChecking=no -i $SSH_KEY -r $installFilesDir hadoop@$node:$installFilesDir &>/dev/null
        ssh -o StrictHostKeyChecking=no -i $SSH_KEY -T hadoop@$node <<EOF
        sudo cp -r $installFilesDir $installHome
        # the enable-hbase-plugin.sh just work with open source version of hadoop,
        # for emr, we have to copy ranger jars to /usr/lib/hbase/lib/
        sudo find $installHome/lib -name *.jar -exec cp {} /usr/lib/hbase/lib/ \;
        sudo sh $installHome/enable-hbase-plugin.sh
EOF
    done
    restartHbase
}

restartHbase() {
    printHeading "RESTART HBASE"
    for node in $(getEmrMasterNodes); do
        echo "STOP HBASE-MASTER ON MASTER NODE: [ $node ]"
        ssh -o StrictHostKeyChecking=no -i $SSH_KEY -T hadoop@$node sudo systemctl stop hbase-master
        sleep $RESTART_INTERVAL
        echo "START HBASE-MASTER ON MASTER NODE: [ $node ]"
        ssh -o StrictHostKeyChecking=no -i $SSH_KEY -T hadoop@$node sudo systemctl start hbase-master
        sleep $RESTART_INTERVAL
    done
    # stop regionserver first, then master
    for node in $(getEmrSlaveNodes); do
        echo "RESTART HBASE-REGIONSERVER ON CORE NODE: [ $node ]"
        # Get remote hostname (just hostname, not fqdn, only this value can trigger graceful_stop.sh work with hbase-daemon.sh
        # not hbase-daemons.sh, EMR has no this file.
        remoteHostname=$(ssh -o StrictHostKeyChecking=no -i $SSH_KEY -T hadoop@$node hostname)
        ssh -o StrictHostKeyChecking=no -i $SSH_KEY -T hadoop@$node sudo -u hbase /usr/lib/hbase/bin/graceful_stop.sh --restart --reload $remoteHostname &>/dev/null
        sleep $RESTART_INTERVAL
    done
}

