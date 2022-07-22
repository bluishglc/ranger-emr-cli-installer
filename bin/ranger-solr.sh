#!/bin/bash

installSolrIfNotExists() {
    if [ ! -f /etc/init.d/solr ]; then
        printHeading "INSTALL SOLR"
        # download from offical site, but sometimes, it's slow, so disable it.
        # the private ranger repo had provided solr, it's available at /tmp/ranger-repo/solr-8.6.2.tgz
        # wget https://archive.apache.org/dist/lucene/solr/8.6.2/solr-8.6.2.tgz -P /tmp/ranger-repo
        tar -zxvf /tmp/ranger-repo/solr-8.6.2.tgz -C /tmp &>/dev/null
        # install but do NOT star solr
        /tmp/solr-8.6.2/bin/install_solr_service.sh /tmp/ranger-repo/solr-8.6.2.tgz -n

    fi
}

removeSolr() {
    echo "Stop Ranger AuditStore Service..."
    sudo -u solr /opt/solr/ranger_audit_server/scripts/stop_solr.sh
    rm -r /var/solr
    rm -r /opt/solr
    rm -r /opt/solr-8.6.2
    userdel -r solr
    groupdel solr
    echo "BE CAREFUL: The following solr files will be DELETED!"
    find /etc -name "*solr*"
    find /etc -name "*solr*" -exec rm -rf {} \;
}

initSolrAsRangerAuditStore() {
    printHeading "INIT SOLR AS RANGER AUDIT STORE"
    tar -zxvf /tmp/ranger-repo/ranger-$RANGER_VERSION-solr_for_audit_setup.tar.gz -C /tmp &>/dev/null
    confFile=/tmp/solr_for_audit_setup/install.properties
    # backup confFile
    cp $confFile $confFile.$(date +%s)
    cp $APP_HOME/conf/ranger-audit/solr-template.properties $confFile
    sed -i "s|@JAVA_HOME@|$JAVA_HOME|g" $confFile
    curDir=$(pwd)
    # must run under project root dir.
    cd /tmp/solr_for_audit_setup
    sh setup.sh
    cd $curDir
    # stop first in case it is already started.
    sudo -u solr /opt/solr/ranger_audit_server/scripts/stop_solr.sh || true
    sudo -u solr /opt/solr/ranger_audit_server/scripts/start_solr.sh
    # waiting for staring, this is required!
    sleep $RESTART_INTERVAL
}

testSolrConnectivity() {
    printHeading "TEST SOLR CONNECTIVITY"
    nc -vz $SOLR_HOST 8983
    if [ "$?" = "0" ]; then
        echo "Connecting to solr server is SUCCESSFUL!!"
    else
        echo "Connecting to solr server is FAILED!!"
        exit 1
    fi
}
