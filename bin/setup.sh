#!/bin/sh

# Run the below commands as root
if [ "$(whoami)" != "root" ]; then
    echo "Run me as [ root ] user!"
    exit 1
fi

APP_HOME="$(
    cd "$(dirname $(readlink -nf "$0"))"/..
    pwd -P
)"

DEFAULT_RANGER_REPO_URL='http://52.81.173.97:7080/ranger-repo/'
DEFAULT_JAVA_HOME='/usr/lib/jvm/java'
DEFAULT_DB_PASSWORD='Admin1234!'
DEFAULT_HOSTNAME=$(hostname -i)
DEFAULT_RANGER_VERSION='2.1.0'
DEFAULT_RESTART_INTERVAL=30

OPT_KEYS=(
    AUTH_TYPE
    AD_DOMAIN AD_URL AD_BASE_DN AD_BIND_DN AD_BIND_PASSWORD AD_USER_OBJECT_CLASS
    LDAP_URL LDAP_USER_DN_PATTERN LDAP_GROUP_SEARCH_FILTER LDAP_BASE_DN LDAP_BIND_DN LDAP_BIND_PASSWORD LDAP_USER_OBJECT_CLASS
    JAVA_HOME SKIP_INSTALL_MYSQL MYSQL_HOST MYSQL_ROOT_PASSWORD MYSQL_RANGER_DB_USER_PASSWORD
    SKIP_INSTALL_SOLR SOLR_HOST RANGER_REPO_URL RANGER_VERSION RANGER_PLUGINS
    EMR_NODES EMR_MASTER_NODES EMR_CORE_NODES EMR_HDFS_URL EMR_ZK_QUORUM EMR_HIVE_SERVER2 EMR_SSH_KEY RESTART_INTERVAL
)

source "$APP_HOME/bin/utils.sh"
source "$APP_HOME/bin/funcs.sh"

# ----------------------------------------------    Scripts Entrance    ---------------------------------------------- #

case $1 in
install)
    shift
    resetConfigs
    parseArgs "$@"
    printConfigs
    testEmrSshConnectivity
    testEmrNamenodeConnectivity
    testLdapConnectivity
    if [ "$SKIP_INSTALL_MYSQL" = "false" ]; then
        installMySqlIfNotExists
    fi
    testMySqlConnectivity
    installMySqlJdbcDriverIfNotExists
    installJdk8IfNotExists
    downloadRanger
    # If skip installing solr, please perform initSolrAsRangerAuditStore
    # operation on remote solr server mannually! this is required!
    if [ "$SKIP_INSTALL_SOLR" = "false" ]; then
        installSolrIfNotExists
        initSolrAsRangerAuditStore
    fi
    testSolrConnectivity
    initRangerAdminDb
    installRangerAdmin
    testRangerConnectivity
    installRangerUsersync
    testSolrConnectivityFromEmrNodes
    testRangerConnectivityFromEmrNodes
    installRangerPlugins
    printHeading "ALL DONE!!"
    ;;
install-ranger)
    printHeading "STARTING SETUP!!"
    shift
    resetConfigs
    parseArgs "$@"
    printConfigs
    testLdapConnectivity
    if [ "$SKIP_INSTALL_MYSQL" = "false" ]; then
        installMySqlIfNotExists
    fi
    testMySqlConnectivity
    installMySqlJdbcDriverIfNotExists
    installJdk8IfNotExists
    downloadRanger
    # If skip installing solr, please perform initSolrAsRangerAuditStore
    # operation on remote solr server mannually! this is required!
    if [ "$SKIP_INSTALL_SOLR" = "false" ]; then
        installSolrIfNotExists
        initSolrAsRangerAuditStore
    fi
    testSolrConnectivity
    initRangerAdminDb
    installRangerAdmin
    testRangerConnectivity
    installRangerUsersync
    printHeading "ALL DONE!!"
    ;;
install-ranger-plugins)
    shift
    resetConfigs
    parseArgs "$@"
    printConfigs
    testEmrSshConnectivity
    testEmrNamenodeConnectivity
    testSolrConnectivityFromEmrNodes
    testRangerConnectivityFromEmrNodes
    installRangerPlugins
    printHeading "ALL DONE!!"
    ;;
test-emr-ssh-connectivity)
    shift
    resetConfigs
    parseArgs "$@"
    testEmrSshConnectivity
    ;;
test-emr-namenode-connectivity)
    shift
    resetConfigs
    parseArgs "$@"
    testEmrNamenodeConnectivity
    ;;
test-ldap-connectivity)
    shift
    resetConfigs
    parseArgs "$@"
    testLdapConnectivity
    ;;
install-mysql)
    shift
    resetConfigs
    parseArgs "$@"
    installMySqlIfNotExists
    ;;
test-mysql-connectivity)
    shift
    resetConfigs
    parseArgs "$@"
    testMySqlConnectivity
    ;;
install-mysql-jdbc-driver)
    installMySqlJdbcDriverIfNotExists
    ;;
install-jdk)
    shift
    resetConfigs
    parseArgs "$@"
    installJdk8IfNotExists
    ;;
download-ranger)
    shift
    resetConfigs
    parseArgs "$@"
    downloadRanger
    ;;
install-solr)
    shift
    resetConfigs
    parseArgs "$@"
    installSolrIfNotExists
    ;;
test-solr-connectivity)
    shift
    resetConfigs
    parseArgs "$@"
    testSolrConnectivity
    ;;
init-solr-as-ranger-audit-store)
    shift
    resetConfigs
    parseArgs "$@"
    initSolrAsRangerAuditStore
    ;;
init-ranger-admin-db)
    shift
    resetConfigs
    parseArgs "$@"
    initRangerAdminDb
    ;;
install-ranger-admin)
    shift
    resetConfigs
    parseArgs "$@"
    initRangerAdminDb
    installRangerAdmin
    ;;
install-ranger-usersync)
    shift
    resetConfigs
    parseArgs "$@"
    installRangerUsersync
    ;;
help)
    printUsage
    ;;
*)
    printUsage
    ;;
esac

