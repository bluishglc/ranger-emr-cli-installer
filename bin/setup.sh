#!/bin/sh

# Run the below commands as root
if [ "$(whoami)" != "root" ]; then
    echo "Run me as [ root ] user!"
    exit 1
fi

export APP_HOME="$(
    cd "$(dirname $(readlink -nf "$0"))"/..
    pwd -P
)"

# It should NOT be a compile-phase var, otherwise it may miss var replacement when copy from maven project directly
# It should be a dynamic var based on APP_HOME
# export APP_REMOTE_HOME="/opt/ranger-emr-cli-installer"
export APP_REMOTE_HOME="/opt/${APP_HOME##*/}"

export AWS_PAGER=""

OPT_KEYS=(
    REGION ARN_ROOT SSH_KEY ACCESS_KEY_ID SECRET_ACCESS_KEY SOLUTION ENABLE_CROSS_REALM_TRUST TRUSTING_REALM TRUSTING_DOMAIN TRUSTING_HOST RANGER_SECRETS_DIR
    AUTH_PROVIDER AD_DOMAIN AD_URL AD_BASE_DN RANGER_BIND_DN RANGER_BIND_PASSWORD HUE_BIND_DN HUE_BIND_PASSWORD AD_USER_OBJECT_CLASS
    SKIP_INSTALL_OPENLDAP OPENLDAP_URL OPENLDAP_USER_DN_PATTERN OPENLDAP_GROUP_SEARCH_FILTER OPENLDAP_BASE_DN RANGER_BIND_DN RANGER_BIND_PASSWORD HUE_BIND_DN HUE_BIND_PASSWORD OPENLDAP_USER_OBJECT_CLASS
    OPENLDAP_BASE_DN OPENLDAP_ROOT_CN OPENLDAP_ROOT_DN OPENLDAP_ROOT_PASSWORD OPENLDAP_USERS_BASE_DN
    JAVA_HOME SKIP_INSTALL_MYSQL MYSQL_HOST MYSQL_ROOT_PASSWORD MYSQL_RANGER_DB_USER_PASSWORD
    SKIP_INSTALL_SOLR SOLR_HOST RANGER_HOST RANGER_PORT RANGER_REPO_URL RANGER_VERSION RANGER_PLUGINS
    KERBEROS_KDC_HOST SKIP_MIGRATE_KERBEROS_DB OPENLDAP_HOST
    EMR_CLUSTER_ID MASTER_INSTANCE_GROUP_ID SLAVE_INSTANCE_GROUP_IDS EMR_MASTER_NODES EMR_SLAVE_NODES EMR_CLUSTER_NODES EMR_ZK_QUORUM EMR_HDFS_URL EMR_FIRST_MASTER_NODE
    EXAMPLE_GROUP EXAMPLE_USERS SKIP_CONFIGURE_HUE RESTART_INTERVAL
)

source "$APP_HOME/bin/utils.sh"
source "$APP_HOME/bin/ec2.sh"
source "$APP_HOME/bin/emr.sh"
source "$APP_HOME/bin/iam.sh"
source "$APP_HOME/bin/crt.sh"
source "$APP_HOME/bin/kerberos.sh"
source "$APP_HOME/bin/mysql.sh"
source "$APP_HOME/bin/openldap.sh"
source "$APP_HOME/bin/ranger-admin.sh"
source "$APP_HOME/bin/ranger-solr.sh"
source "$APP_HOME/bin/ranger-usersync.sh"
source "$APP_HOME/bin/ranger-plugins.sh"
source "$APP_HOME/bin/sasl-gssapi.sh"
source "$APP_HOME/bin/sssd.sh"
source "$APP_HOME/bin/user.sh"

install() {
    printHeading "ALL-IN-ONE INSTALL"
    initEc2
    # emr-native required operations
    if [ "$SOLUTION" = "emr-native" ]; then
        createIamRoles
        createRangerSecrets
        createEmrSecurityConfiguration
    fi

    # it is supported to install an openldap server
    if [[ "$AUTH_PROVIDER" = "openldap" && "$SKIP_INSTALL_MYSQL" = "false" ]]; then
        installOpenldap
    fi

    installRanger
    # because of circular dependency between ranger and emr installation for openldap + emr-native solution
    # the installation progress need pending for creating emr cluster
#    if [[ "$AUTH_PROVIDER" = "openldap" && "$SOLUTION" = "emr-native" ]]; then
    waitForCreatingEmrCluster
    testEmrSshConnectivity
#    fi

    # If for ad, only need pending and waiting for input cluster id

    # for OpenLDAP + EMR Native Ranger solution, need enable sasl/gssapi and migrate kerberos db
    if [[ "$AUTH_PROVIDER" = "openldap" && "$SOLUTION" = "emr-native" ]]; then
        enableSaslGssapi
        if [[ "$SKIP_MIGRATE_KERBEROS_DB" = "false" ]]; then
            testKerberosKdcConnectivity
            # BE CAREFUL!!
            # the puppet of EMR will always revert changes of kdc.conf
            # so will disable migrating kerberos db job, this does NOT block other functions.
            # but, please remeber to remove -x parameter of addprinc when creating kerberos principal!
            migrateKerberosDb
        fi
    fi

    # if AUTH_PROVIDER is openldap and SOLUTION is open-source,
    # an EMR cluster should be available, the EMR_CLUSTER_ID is provided,
    # so it is time to install sssd on each node of EMR cluster.
    # if SOLUTION is emr-native, the EMR cluster can ONLY create after ranger installed
    # so, at this time point, no EMR cluster is available, installing sssd has to defer to EMR cluster is up.
    # Only AD + EMR Native Ranger solution need NOT install sssd, because this job will complete automatically
    # when create emr cluster by enable cross-realm trust, for all the other 3 solutions, this job is required
    if [[ "$AUTH_PROVIDER" != "ad" || "$SOLUTION" != "emr-native" ]]; then
        installSssd
    fi

#    # updating hue configuration also need an EMR cluster is ready,
#    # so only open-source can do now, for emr-native, need  defer to EMR cluster is up.
#    if [ "$SOLUTION" = "open-source" ]; then

    # Because emr configuration is an all-in-one json, so be careful to perform
    # updating hue configuration action unless your emr cluster's configuration is empty.
    # by default, we will update it to achieve completed installation, if you have other
    # configurations, please set "--skip-configure-hue true".
    if [ "$SKIP_CONFIGURE_HUE" = "false" ]; then
        configHue
    fi
#    fi
    # add example users if --example-users provided
    if [[ "$AUTH_PROVIDER" = "openldap" && "${EXAMPLE_USERS[*]}" != "" ]]; then
        addExampleUsers
    fi

    installRangerPlugins
    installRangerPlugins

    printHeading "ALL DONE!!"
}

waitForCreatingEmrCluster() {
    printHeading "CREATE EMR CLUSTER"
    num=1

    if [[ "$SOLUTION" = "emr-native" ]]; then
        confirmed="false"
        while [[ "$confirmed" != "true" ]]; do
            echo -ne "$((num++)). Create an emr cluster from emr web console. \n\n"
            echo -ne ">> Be sure to select this ec2 instance profile: \E[33m[ EMR_EC2_RangerRole ]\n\n\E[0m"
            echo -ne ">> Be sure to select this security configuration: \E[33m[ ranger@$RANGER_HOST ]\n\n\E[0m"
            confirmed=$(askForConfirmation "Have you created the cluster?")
            echo ""
        done
    fi

    confirmed="false"
    while [[ ! "$confirmed" = "true" ]]; do
        read -p "$((num++)). Enter the emr cluster id: " EMR_CLUSTER_ID
        echo -ne "\n>> Accepted the emr cluster id: \E[33m[ $EMR_CLUSTER_ID ]\E[0m\n\n"

        if [[ "$AUTH_PROVIDER" = "openldap" && "$SOLUTION" = "emr-native" ]]; then
            read -p "$((num++)). Enter the emr cluster kerberos realm: " KERBEROS_REALM
            echo -ne "\n>> Accepted the emr cluster kerberos realm: \E[33m[ $KERBEROS_REALM ]\E[0m\n\n"

            read -p "$((num++)). Enter the emr cluster kerberos kadmin password: " KERBEROS_KADMIN_PASSWORD
            echo -ne "\n>> Accepted the emr cluster kerberos kadmin password: \E[33m[ $KERBEROS_KADMIN_PASSWORD ]\E[0m\n\n"

            read -p "$((num++)). Enter the private DNS (FQDN) of emr cluster kerberos KDC host: " KERBEROS_KDC_HOST
            echo -ne "\n>> Accepted the private DNS (FQDN) of emr cluster kerberos KDC host: \E[33m[ $KERBEROS_KDC_HOST ]\E[0m\n\n"
            askHueAndLdapIntegration "$((num++))"
        else
            askHueAndLdapIntegration "$((num++))"
        fi

        confirmed=$(askForConfirmation "Do you confirm all above?")
        echo ""
    done

    echo -ne "Waiting for emr cluster creating...\n\n"

    now=$(date +%s)sec
    while true; do
        emrClusterStatus="$(getEmrClusterStatus)"
        if [ "$emrClusterStatus" == "STARTING" ] || [ "$emrClusterStatus" == "RUNNING" ]; then
            for i in {0..5}; do
                echo -ne "\E[33;5m>> The emr cluster [ $EMR_CLUSTER_ID ] state is [ $emrClusterStatus ], duration [ $(TZ=UTC date --date now-$now +%H:%M:%S) ] ....\r\E[0m"
                sleep 1
            done
        else
            echo -ne "\e[0A\e[KThe emr cluster [ $EMR_CLUSTER_ID ] is [ $emrClusterStatus ]\n\n"
            if [ "$emrClusterStatus" == "TERMINATED_WITH_ERRORS" ] || [ "$emrClusterStatus" == "TERMINATED" ]; then
                exit 1
            else
                break
            fi
        fi
    done
}

askHueAndLdapIntegration() {
    num="$1"
    integrateHueAndLdap=$(askForConfirmation "$num. Do you want Hue to integrate with LDAP? (Be careful! if yes, emr existing configuration will be overwritten!)")
    if [[ "$integrateHueAndLdap" = "true" ]]; then
        SKIP_CONFIGURE_HUE="false"
        echo -ne "\n>> You selected: \E[33m[ Yes ]\E[0m\n\n"
    elif [[ "$integrateHueAndLdap" = "false" ]]; then
        SKIP_CONFIGURE_HUE="true"
        echo -ne "\n>> You selected: \E[33m[ No ]\E[0m\n\n"
    fi
}

installRanger() {
    printHeading "INSTALL RANGER"
    testLdapConnectivity
    downloadRangerRepo
    if [ "$SKIP_INSTALL_MYSQL" = "false" ]; then
        installMySqlIfNotExists
    fi
    testMySqlConnectivity
    installMySqlJdbcDriverIfNotExists
    installJdk8IfNotExists
    # If skip installing solr, please perform initSolrAsRangerAuditStore
    # operation on remote solr server mannually! this is required!
    if [ "$SKIP_INSTALL_SOLR" = "false" ]; then
        installSolrIfNotExists
        initSolrAsRangerAuditStore
    fi
    testSolrConnectivity
    initRangerAdminDb
    installRangerAdmin
    testRangerAdminConnectivity
    installRangerUsersync
    printHeading "RANGER HAS STARTED!"
}

remove() {
    printHeading "REMOVE ALL IF EXISTING"
    # removeRangerPlugins
    removeRangerUsersync
    removeRangerAdmin
    removeSolr
    removeEmrSecurityConfigurationIfExists
    removeRangerSecrets
}

installRangerPlugins() {
    printHeading "INSTALL RANGER PLUGINS"
    testRangerAdminConnectivity
    # open-source solution assume emr cluster is existing,
    # so it supports to test connectivity.
    if [ "$SOLUTION" = "open-source" ]; then
        testEmrSshConnectivity
        testEmrNamenodeConnectivity
        testSolrConnectivityFromEmrNodes
        testRangerAdminConnectivityFromEmrNodes
    fi
    for plugin in "${RANGER_PLUGINS[@]}"; do
        case $plugin in
        emr-native-emrfs)
            installRangerEmrNativeEmrfsPlugin
            ;;
        emr-native-spark)
            installRangerEmrNativeSparkPlugin
            ;;
        emr-native-hive)
            installRangerEmrNativeHivePlugin
            ;;
        emr-native-trino)
            installRangerEmrNativeTrinoPlugin
            ;;
        open-source-hdfs)
            installRangerOpenSourceHdfsPlugin
            ;;
        open-source-hive)
            installRangerOpenSourceHivePlugin
            ;;
        open-source-hbase)
            installRangerOpenSourceHbasePlugin
            ;;
        *)
            if [ "$plugin" = "" ]; then
                echo "ERROR! Please provide plugins to be installed via option: --ranger-plugins."
            else
                echo "ERROR! No such plugin(s): [$plugin] or it is UNSUPPORTED in $SOLUTION solution."
            fi
            exit 1
            ;;
        esac
    done
}

parseArgs() {
    # reset all config items first.
    resetAllOpts

    optString="\
        region:,ssh-key:,access-key-id:,secret-access-key:,java-home:,\
        skip-migrate-kerberos-db:,kerberos-realm:,kerberos-kdc-host:,kerberos-kadmin-password:,\
        solution:,enable-cross-realm-trust:,trusting-realm:,trusting-domain:,trusting-host:,ranger-version:,ranger-repo-url:,restart-interval:,ranger-host:,ranger-secrets-dir:,ranger-plugins:,\
        auth-provider:,ad-host:,ad-domain:,ad-base-dn:,ad-user-object-class:,\
        openldap-host:,openldap-base-dn:,openldap-root-cn:,openldap-root-password:,example-users:,\
        sssd-bind-dn:,sssd-bind-password:,\
        skip-install-openldap:,openldap-user-dn-pattern:,openldap-group-search-filter:,openldap-base-dn:,ranger-bind-dn:,ranger-bind-password:,hue-bind-dn:,hue-bind-password:,openldap-user-object-class:,\
        skip-install-mysql:,mysql-host:,mysql-root-password:,mysql-ranger-db-user-password:,skip-install-solr:,solr-host:,\
        emr-cluster-id:,skip-configure-hue:\
    "
    # IMPORTANT!! -o option can not be omitted, even there are no any short options!
    # otherwise, parsing will go wrong!
    OPTS=$(getopt -o "" -l "$optString" -- "$@")
    exitCode=$?
    if [ $exitCode -ne 0 ]; then
        echo "".
#        printUsage
        exit 1
    fi
    eval set -- "$OPTS"
    while true; do
        case "$1" in
            --region)
                REGION="${2}"

                # 1. ec2.internal for us-east-1
                # 2. compute.internal for other regions
                if [ "$REGION" = "us-east-1" ]; then
                    CERTIFICATE_CN="*.ec2.internal"
                else
                    # BE CAREFUL:
                    # SSL: certificate subject name '*.compute.internal' does not match target host name 'ip-x-x-x-x.cn-north-1.compute.internal'
                    # I don't know why emr native plugin can work with cn "*.compute.internal", it seems emr native does NOT sync policies via https.
                    # BUT for opensource plugins, "*.compute.internal"??? testing!!!
                    # CERTIFICATE_CN="*.${REGION}.compute.internal"
                    CERTIFICATE_CN="*.compute.internal"
                fi
                # 1. for china, arn root is aws-cn
                # 2. for others, arn root is aws
                if [ "$REGION" = "cn-north-1" -o "$REGION" = "cn-northwest-1" ]; then
                    ARN_ROOT="aws-cn"
                    SERVICE_POSTFIX="com.cn"
                else
                    ARN_ROOT="aws"
                    SERVICE_POSTFIX="com"
                fi
                shift 2
                ;;
            --access-key-id)
                ACCESS_KEY_ID="${2}"
                shift 2
                ;;
            --secret-access-key)
                SECRET_ACCESS_KEY="${2}"
                shift 2
                ;;
            --solution)
                SOLUTION="${2}"
                if [ "$SOLUTION" = "open-source" ]; then
                    RANGER_PROTOCOL="http"
                    RANGER_PORT="6080"
                # for emr-native solution, https is required!
                elif [ "$SOLUTION" = "emr-native" ]; then
                    RANGER_PROTOCOL="https"
                    RANGER_PORT="6182"
                else
                    echo "For --solution option, only 'open-source' or 'emr-native' is acceptable!"
                    exit 1
                fi
                shift 2
                ;;
            --auth-provider)
                AUTH_PROVIDER="${2,,}"
                shift 2
                ;;
            --skip-migrate-kerberos-db)
                if [ "$2" != "true" -a "$2" != "false" ]; then
                    echo "For --skip-migrate-kerberos-db option, only 'true' or 'false' is acceptable!"
                    exit 1
                fi
                SKIP_MIGRATE_KERBEROS_DB="$2"
                shift 2
                ;;
            --kerberos-realm)
                KERBEROS_REALM="${2}"
                shift 2
                ;;
            --kerberos-kdc-host)
                KERBEROS_KDC_HOST="${2}"
                shift 2
                ;;
            --kerberos-kadmin-password)
                KERBEROS_KADMIN_PASSWORD="${2}"
                shift 2
                ;;
            --enable-cross-realm-trust)
                if [ "$2" != "true" -a "$2" != "false" ]; then
                    echo "For --enable-cross-realm-trust option, only 'true' or 'false' is acceptable!"
                    exit 1
                fi
                ENABLE_CROSS_REALM_TRUST="$2"
                shift 2
                ;;
            --trusting-realm)
                TRUSTING_REALM="${2}"
                shift 2
                ;;
            --trusting-domain)
                TRUSTING_DOMAIN="${2}"
                shift 2
                ;;
            --trusting-host)
                TRUSTING_HOST="${2}"
                shift 2
                ;;
            --ad-host)
                AD_HOST="$2"
                AD_URL="ldap://$AD_HOST"
                shift 2
                ;;
            --ad-domain)
                AD_DOMAIN="$2"
                shift 2
                ;;
            --ad-base-dn)
                AD_BASE_DN="$2"
                shift 2
                ;;
            --ad-user-object-class)
                AD_USER_OBJECT_CLASS="$2"
                shift 2
                ;;
            --openldap-user-dn-pattern)
                OPENLDAP_USER_DN_PATTERN="$2"
                shift 2
                ;;
            --openldap-group-search-filter)
                OPENLDAP_GROUP_SEARCH_FILTER="$2"
                shift 2
                ;;
            --openldap-base-dn)
                OPENLDAP_BASE_DN="$2"
                shift 2
                ;;
            --ranger-bind-dn)
                RANGER_BIND_DN="$2"
                shift 2
                ;;
            --ranger-bind-password)
                RANGER_BIND_PASSWORD="$2"
                shift 2
                ;;
            --hue-bind-dn)
                HUE_BIND_DN="$2"
                shift 2
                ;;
            --hue-bind-password)
                HUE_BIND_PASSWORD="$2"
                shift 2
                ;;
            --openldap-user-object-class)
                OPENLDAP_USER_OBJECT_CLASS="$2"
                shift 2
                ;;
            --java-home)
                JAVA_HOME="$2"
                shift 2
                ;;
            --skip-install-mysql)
                if [ "$2" != "true" -a "$2" != "false" ]; then
                    echo "For --skip-install-mysql option, only 'true' or 'false' is acceptable!"
                    exit 1
                fi
                SKIP_INSTALL_MYSQL="$2"
                shift 2
                ;;
            --ranger-host)
                RANGER_HOST="$2"
                shift 2
                ;;
            --mysql-host)
                MYSQL_HOST="$2"
                shift 2
                ;;
            --mysql-root-password)
                MYSQL_ROOT_PASSWORD="$2"
                shift 2
                ;;
            --mysql-ranger-db-user-password)
                MYSQL_RANGER_DB_USER_PASSWORD="$2"
                shift 2
                ;;
            --skip-install-solr)
                if [ "$2" != "true" -a "$2" != "false" ]; then
                    echo "For --skip-install-solr option, only 'true' or 'false' is acceptable!"
                    exit 1
                fi
                SKIP_INSTALL_SOLR="$2"
                shift 2
                ;;
            --solr-host)
                SOLR_HOST="$2"
                shift 2
                ;;
            --ranger-version)
                RANGER_VERSION="$2"
                shift 2
                ;;
            --ranger-repo-url)
                RANGER_REPO_URL="$2"
                shift 2
                ;;
            --ranger-secrets-dir)
                RANGER_SECRETS_DIR="$2"
                shift 2
                ;;
            --ranger-plugins)
                IFS=', ' read -r -a RANGER_PLUGINS <<< "${2,,}"
                shift 2
                ;;
            --emr-cluster-id)
                # resolving emr cluster information MUST put off to init-ec2 done
                # because resolving emr cluster nodes vars need jq & aws cli
                EMR_CLUSTER_ID="$2"
                # it is REQUIRED to postpone the initialization of following vars!
#                EMR_MASTER_NODES=($(getEmrMasterNodes))
#                EMR_SLAVE_NODES=($(getEmrSlaveNodes))
#                EMR_CLUSTER_NODES=("${EMR_MASTER_NODES[@]}" "${EMR_SLAVE_NODES[@]}")

#                # EMR_ZK_QUORUM looks like 'node1,node2,node3'
#                EMR_ZK_QUORUM=$(IFS=,; echo "${EMR_MASTER_NODES[*]}")
#                # add hdfs:// prefix and :8020 postfix, EMR_HDFS_URL looks like 'hdfs://node1:8020,hdfs://node2:8020,hdfs://node3:8020'
#                EMR_HDFS_URL=$(echo $EMR_ZK_QUORUM | sed -E 's/([^,]+)/hdfs:\/\/\1:8020/g')
#                # NOTE: ranger hive plugin will use hiveserver2 address, for single master node EMR cluster,
#                # it is master node, for multi masters EMR cluster, all 3 master nodes will install hiverserver2
#                # usually, there should be a virtual IP play hiverserver2 role, but EMR has no such config.
#                # here, we pick first master node as hiveserver2
#                EMR_FIRST_MASTER_NODE=${EMR_MASTER_NODES[0]}

                shift 2
                ;;
            --ssh-key)
                SSH_KEY="$2"
                # chmod in case its mod is not 600
                chmod 600 $SSH_KEY
                shift 2
                ;;
            --skip-install-openldap)
                if [ "$2" != "true" -a "$2" != "false" ]; then
                    echo "For --skip-install-openldap option, only 'true' or 'false' is acceptable!"
                    exit 1
                fi
                SKIP_INSTALL_OPENLDAP="$2"
                shift 2
                ;;
            --openldap-host)
                OPENLDAP_HOST="$2"
                OPENLDAP_URL="ldap://$OPENLDAP_HOST"
                shift 2
                ;;
            --openldap-base-dn)
                OPENLDAP_BASE_DN="$2"
                shift 2
                ;;
            --openldap-root-cn)
                OPENLDAP_ROOT_CN="$2"
                shift 2
                ;;
            --openldap-root-password)
                OPENLDAP_ROOT_PASSWORD="$2"
                shift 2
                ;;
             --sssd-bind-dn)
                SSSD_BIND_DN="$2"
                shift 2
                ;;
            --sssd-bind-password)
                SSSD_BIND_PASSWORD="$2"
                shift 2
                ;;
            --skip-configure-hue)
                if [ "$2" != "true" -a "$2" != "false" ]; then
                    echo "For --skip-configure-hue option, only 'true' or 'false' is acceptable!"
                    exit 1
                fi
                SKIP_CONFIGURE_HUE="$2"
                shift 2
                ;;
            --example-users)
                IFS=', ' read -r -a EXAMPLE_USERS <<< "${2,,}"
                shift 2
                ;;
            --restart-interval)
                RESTART_INTERVAL="$2"
                shift 2
                ;;
            --) # No more arguments
                shift
                break
                ;;
            *)
                echo ""
                echo "Invalid option $1." >&2
                printUsage
                exit 1
                ;;
        esac
    done
    shift $((OPTIND-1))
    additionalOpts=$*
    # build ranger repo file url
    RANGER_REPO_FILE_URL="$RANGER_REPO_URL/$RANGER_VERSION/ranger-repo.zip"
    # build ranger admin url
    RANGER_URL="${RANGER_PROTOCOL}://${RANGER_HOST}:${RANGER_PORT}"

    # OpenLDAP-Specific vars bassed on base dn
    OPENLDAP_ROOT_DN="cn=${OPENLDAP_ROOT_CN},${OPENLDAP_BASE_DN}"
    OPENLDAP_USERS_BASE_DN="ou=users,$OPENLDAP_BASE_DN"
    ORG_NAME=$(echo $OPENLDAP_BASE_DN | sed 's/dc=//g' | sed 's/,/./g')
    ORG_DC=${ORG_NAME%%.*}

    if [ "$AUTH_PROVIDER" = "ad" ]; then
        # check if all required config items are set
        adKeys=(AD_DOMAIN AD_URL AD_BASE_DN RANGER_BIND_DN RANGER_BIND_PASSWORD)
#        for key in "${adKeys[@]}"; do
#            if [ "$(eval echo \$$key)" = "" ]; then
#                echo "ERROR: [ $key ] is NOT set, it is required for Windows AD config."
#                exit 1
#            fi
#        done
        if [ "$AD_USER_OBJECT_CLASS" = "" ]; then
            # set default value if not set
            AD_USER_OBJECT_CLASS="person"
        fi
    elif [ "$AUTH_PROVIDER" = "openldap" ]; then
#        ldapKeys=(LDAP_URL LDAP_BASE_DN LDAP_RANGER_BIND_DN LDAP_RANGER_BIND_PASSWORD)
#        for key in "${ldapKeys[@]}"; do
#            if [ "$(eval echo \$$key)" = "" ]; then
#                echo "ERROR: [ $key ] is NOT set, it is required for OpenLDAP config."
#                exit 1
#            fi
#        done

        # If not set, assign default value
        if [ "$OPENLDAP_USER_DN_PATTERN" = "" ]; then
            OPENLDAP_USER_DN_PATTERN="uid={0},$OPENLDAP_BASE_DN"
        fi
        if [ "$OPENLDAP_GROUP_SEARCH_FILTER" = "" ]; then
            OPENLDAP_GROUP_SEARCH_FILTER="(member=uid={0},$OPENLDAP_BASE_DN)"
        fi
        if [ "$OPENLDAP_USER_OBJECT_CLASS" = "" ]; then
            OPENLDAP_USER_OBJECT_CLASS="inetOrgPerson"
        fi
    fi

    if [ "$RANGER_BIND_DN" = "" ]; then
        RANGER_BIND_DN="cn=ranger,ou=services,$OPENLDAP_BASE_DN"
    fi
    if [ "$RANGER_BIND_PASSWORD" = "" ]; then
        RANGER_BIND_PASSWORD="$COMMON_DEFAULT_PASSWORD"
    fi
    if [ "$HUE_BIND_DN" = "" ]; then
        HUE_BIND_DN="cn=hue,ou=services,$OPENLDAP_BASE_DN"
    fi
    if [ "$HUE_BIND_PASSWORD" = "" ]; then
        HUE_BIND_PASSWORD="$COMMON_DEFAULT_PASSWORD"
    fi
    if [ "$SSSD_BIND_DN" = "" ]; then
        SSSD_BIND_DN="cn=sssd,ou=services,$OPENLDAP_BASE_DN"
    fi
    if [ "$SSSD_BIND_PASSWORD" = "" ]; then
        SSSD_BIND_PASSWORD="$COMMON_DEFAULT_PASSWORD"
    fi
    # print all resolved options
    printAllOpts
}

resetAllOpts() {
    # unset vars which has no default values
    for key in "${OPT_KEYS[@]}"; do
        eval unset $key
    done
    # Set default value for some configs if there are not set in command line.
    INIT_EC2_FLAG_FILE='/tmp/init-ec2.flag'
    MIGRATE_KERBEROS_DB_FLAG='/tmp/migrate-kerberos-db.flag'
    JAVA_HOME='/usr/lib/jvm/java'
    COMMON_DEFAULT_PASSWORD='Admin1234!'
    RANGER_VERSION='2.1.0'
    RANGER_REPO_URL="https://github.com/bluishglc/ranger-repo/releases/download"
    RANGER_SECRETS_DIR="/opt/ranger-$RANGER_VERSION-secrets"
    AUDIT_EVENTS_LOG_GROUP="/aws-emr/audit-events"
    RANGER_HOST=$(hostname -f)
    KERBEROS_KADMIN_PASSWORD=$COMMON_DEFAULT_PASSWORD
    OLKB_EXAMPLE_USER_PASSWORD=$COMMON_DEFAULT_PASSWORD
    MYSQL_HOST=$RANGER_HOST
    MYSQL_ROOT_PASSWORD=$COMMON_DEFAULT_PASSWORD
    MYSQL_RANGER_DB_USER_PASSWORD=$COMMON_DEFAULT_PASSWORD
    SOLR_HOST=$RANGER_HOST
    RESTART_INTERVAL=30
    SKIP_INSTALL_MYSQL=false
    SKIP_INSTALL_SOLR=false
    SKIP_INSTALL_OPENLDAP=false
    SKIP_CONFIGURE_HUE=false
    SKIP_MIGRATE_KERBEROS_DB=false
    OPENLDAP_BASE_DN='dc=example,dc=com'
    OPENLDAP_ROOT_CN='admin'
    OPENLDAP_ROOT_PASSWORD=$COMMON_DEFAULT_PASSWORD
    EXAMPLE_GROUP="example-group"
}

printAllOpts() {
    printHeading "CONFIGURATION ITEMS"
    for key in "${OPT_KEYS[@]}"; do
        case $key in
        EMR_CLUSTER_NODES|EMR_MASTER_NODES|EMR_SLAVE_NODES|RANGER_PLUGINS)
            val=$(eval echo \${${key}[@]})
            echo "$key = $val"
            ;;
        *)
            val=$(eval echo \$$key)
            echo "$key = $val"
            ;;
        esac
    done
}

validateConfigs() {
    for key in "${OPT_KEYS[@]}"; do
        val=$(eval echo \$$key)
        if [ "$val" = "" ]; then
            echo "Required config item [ $key ] is not set, installing process will exit!"
            exit 1
        fi
    done
}

printUsage() {
    echo ""
    printHeading "RANGER-EMR-CLI-INSTALLER USAGE"
    echo ""
    echo "Actions:"
    echo ""
    echo "install                               Install all components"
    echo "install-ranger                        Install ranger only"
    echo "install-ranger-plugins                Install ranger plugin only"
    echo "test-emr-ssh-connectivity             Test EMR ssh connectivity"
    echo "test-emr-namenode-connectivity        Test EMR namenode connectivity"
    echo "test-ldap-connectivity                Test LDAP connectivity"
    echo "install-mysql                         Install MySQL"
    echo "test-mysql-connectivity               Test MySQL connectivity"
    echo "install-mysql-jdbc-driver             Install MySQL JDBC driver"
    echo "install-jdk                           Install JDK8"
    echo "download-ranger-repo                       Download ranger"
    echo "install-solr                          Install solr"
    echo "test-solr-connectivity                Test solr connectivity"
    echo "init-solr-as-ranger-audit-store       Test solr connectivity"
    echo "init-ranger-admin-db                  Init ranger admin db"
    echo "install-ranger-admin                  Install ranger admin"
    echo "install-ranger-usersync               Install ranger usersync"
    echo "help                                  Print help"
    echo ""
    echo "Options:"
    echo ""
    echo "--auth-provider [ad|ldap]                 Authentication type, optional value: ad or ldap"
    echo "--ad-domain                           Specify the domain name of windows ad server"
    echo "--ad-base-dn                          Specify the base dn of windows ad server"
    echo "--ad-user-object-class                Specify the user object class of windows ad server"
    echo "--openldap-url                            Specify the ldap url of Open LDAP, i.e. ldap://10.0.0.1"
    echo "--openldap-user-dn-pattern                Specify the user dn pattern of Open LDAP"
    echo "--openldap-group-search-filter            Specify the group search filter of Open LDAP"
    echo "--openldap-base-dn                        Specify the base dn of Open LDAP"
    echo "--ranger-bind-dn                        Specify the bind dn of Open LDAP"
    echo "--ranger-bind-password                  Specify the bind password of Open LDAP"
    echo "--openldap-user-object-class              Specify the user object class of Open LDAP"
    echo "--java-home                           Specify the JAVA_HOME path, default value is /usr/lib/jvm/java"
    echo "--skip-install-mysql [true|false]     Specify If skip mysql installing or not, default value is 'false'"
    echo "--mysql-host                          Specify the mysql server hostname or IP, default value is current host IP"
    echo "--mysql-root-password                 Specify the root password of mysql"
    echo "--mysql-ranger-db-user-password       Specify the ranger db user password of mysql"
    echo "--solr-host                           Specify the solr server hostname or IP, default value is current host IP"
    echo "--skip-install-solr [true|false]      Specify If skip solr installing or not, default value is 'false'"
    echo "--ranger-host                         Specify the ranger server hostname or IP, default value is current host IP"
    echo "--ranger-version [2.1.0]              Specify the ranger version, now only Ranger 2.1.0 is supported"
    echo "--ranger-repo-url                     Specify the ranger repository url"
    echo "--ranger-plugins [hdfs|hive|hbase]    Specify what plugins will be installed(accept multiple comma-separated values), now support hdfs, hive and hbase"
    echo "--emr-master-nodes                    Specify master nodes list of EMR cluster(accept multiple comma-separated values), i.e. 10.0.0.1,10.0.0.2,10.0.0.3"
    echo "--emr-core-nodes                      Specify core nodes list of EMR cluster(accept multiple comma-separated values), i.e. 10.0.0.4,10.0.0.5,10.0.0.6"
    echo "--ssh-key                         Specify the path of ssh key to connect EMR nodes"
    echo "--restart-interval                    Specify the restart interval"
    echo ""
    echo "Samples:"
    echo ""
    echo "1. All-In-One install, install Ranger, then integrate to a Windows AD server and a multi-master EMR cluster"
    echo ""
    cat << EOF | sed 's/^ *//'
    sudo ranger-emr-cli-installer/bin/setup.sh install \\
    --ranger-host $(hostname -f) \\
    --java-home /usr/lib/jvm/java \\
    --skip-install-mysql false \\
    --mysql-host $(hostname -f) \\
    --mysql-root-password 'Admin1234!' \\
    --mysql-ranger-db-user-password 'Admin1234!' \\
    --skip-install-solr false \\
    --solr-host $(hostname -f) \\
    --auth-provider ad \\
    --ad-domain example.com \\
    --ad-base-dn 'cn=users,dc=example,dc=com' \\
    --ad-ranger-bind-dn 'cn=ranger-binder,ou=service accounts,dc=example,dc=com' \\
    --ad-ranger-bind-password 'Admin1234!' \\
    --ad-user-object-class 'person' \\
    --ranger-version 2.1.0 \\
    --ranger-repo-url 'http://52.80.56.214:7080/ranger-repo/' \\
    --ranger-plugins hdfs,hive,hbase \\
    --emr-master-nodes 10.0.0.177,10.0.0.199,10.0.0.21 \\
    --emr-core-nodes 10.0.0.114,10.0.0.136 \\
    --ssh-key /home/ec2-user/key.pem \\
    --restart-interval 30
EOF
    echo ""
    echo "2. All-In-One install, install Ranger, then integrate to a Open LDAP server and a multi-master EMR cluster"
    echo ""
    cat << EOF | sed 's/^ *//'
    sudo ranger-emr-cli-installer/bin/setup.sh install \\
    --ranger-host $(hostname -f) \\
    --java-home /usr/lib/jvm/java \\
    --skip-install-mysql false \\
    --mysql-host $(hostname -f) \\
    --mysql-root-password 'Admin1234!' \\
    --mysql-ranger-db-user-password 'Admin1234!' \\
    --skip-install-solr false \\
    --solr-host $(hostname -f) \\
    --auth-provider openldap \\
    --openldap-url ldap://10.0.0.41 \\
    --openldap-base-dn 'dc=example,dc=com' \\
    --ranger-bind-dn 'cn=ranger-binder,ou=service accounts,dc=example,dc=com' \\
    --ranger-bind-password 'Admin1234!' \\
    --openldap-user-dn-pattern 'uid={0},dc=example,dc=com' \\
    --openldap-group-search-filter '(member=uid={0},dc=example,dc=com)' \\
    --openldap-user-object-class inetOrgPerson \\
    --ranger-version 2.1.0 \\
    --ranger-repo-url 'http://52.80.56.214:7080/ranger-repo/' \\
    --ranger-plugins hdfs,hive,hbase \\
    --emr-master-nodes 10.0.0.177,10.0.0.199,10.0.0.21 \\
    --emr-core-nodes 10.0.0.114,10.0.0.136 \\
    --ssh-key /home/ec2-user/key.pem \\
    --restart-interval 30
EOF
    echo ""
    echo "3. Integrate second EMR cluster"
    echo ""
    cat << EOF | sed 's/^ *//'
    sudo ranger-emr-cli-installer/bin/setup.sh install-ranger-plugins \\
    --ranger-host $(hostname -f) \\
    --solr-host $(hostname -f) \\
    --ranger-version 2.1.0 \\
    --ranger-plugins hdfs,hive,hbase \\
    --emr-master-nodes 10.0.0.18 \\
    --emr-core-nodes 10.0.0.69 \\
    --ssh-key /home/ec2-user/key.pem \\
    --restart-interval 30
EOF
    echo ""
}

# ----------------------------------------------    Scripts Entrance    ---------------------------------------------- #

ACTION="$1"

shift

# BE CAREFUL: parseArgs depends on aws cli installed by initEc2 to query emr cluster nodes
# initEc2 depends on parseArgs to parse --access-key-id and --secret-access-key, so???
parseArgs "$@"

# If --emr-cluster-id set, the program need resolve emr cluster information (i.e. EMR_CLUSTER_NODES)
# by given id, but this job requires current ec2 instance must be initialised ( installed & configured aws cli )。
# however, initEc2 depends on parseArgs to parse --access-key-id and --secret-access-key, so we can simply
# let program always check if current ec2 instance is initialised, if not, prevent any other actions
# except init-ec2. but this will also block all-in-one install, because for all-in-one install,
# --emr-cluster-id, --access-key-id and --secret-access-key are given at the same time, and initEc2 may not
# executing yet for a brand new ec2 instance. so, a better way is to defer resolving emr cluster information
# at a proper time point. but it is hard to find a proper time point to resolving
# emr cluster information, because multiple actions need this resolving job, i.e. install-ranger-plugins,
# install-sssd or enable-sasl-gssapi, so it is impossible to control these actions' executing order, because
# this is up to end users. so, the last option is to resolve emr cluster information as late as possible.
# this is similar to LAZY LOADING variable in other programming languages, but shell has no such feature.
# so, we have to simulate via a function, i.e. getEmrMasterNodes()

case $ACTION in
    init-ec2)
        initEc2
    ;;
    force-init-ec2)
        forceInitEc2
    ;;
    install)
        install
    ;;
    wait)
        waitForCreatingEmrCluster
    ;;
    # --- Ranger Operations --- #

    install-ranger)
        installRanger
    ;;
    install-ranger-plugins)
        installRangerPlugins
    ;;
    remove)
        remove
    ;;
    create-iam-roles)
        createIamRoles
    ;;
    remove-iam-roles)
        removeIamRoles
    ;;
    create-ranger-secrets)
        createRangerSecrets
    ;;
    create-emr-security-configuration)
        createEmrSecurityConfiguration
    ;;
    test-emr-ssh-connectivity)
        testEmrSshConnectivity
    ;;
    test-emr-namenode-connectivity)
        testEmrNamenodeConnectivity
    ;;
    test-ldap-connectivity)
        testLdapConnectivity
    ;;
    install-mysql)
        installMySqlIfNotExists
    ;;
    test-mysql-connectivity)
        testMySqlConnectivity
    ;;
    install-mysql-jdbc-driver)
        installMySqlJdbcDriverIfNotExists
    ;;
    install-jdk)
        installJdk8IfNotExists
    ;;
    download-ranger-repo)
        downloadRangerRepo
    ;;
    install-solr)
        installSolrIfNotExists
    ;;
    test-solr-connectivity)
        testSolrConnectivity
    ;;
    init-solr-as-ranger-audit-store)
        initSolrAsRangerAuditStore
    ;;
    init-ranger-admin-db)
        initRangerAdminDb
    ;;
    install-ranger-admin)
        initRangerAdminDb
        installRangerAdmin
    ;;
    install-ranger-usersync)
        installRangerUsersync
    ;;
    configure-hue)
        configHue
    ;;

    # --- EMR Operations --- #

    get-emr-latest-cluster-id)
        getEmrLatestClusterId
    ;;
    print-emr-cluster-nodes)
        printEmrClusterNodes
    ;;
    find-emr-log-errors)
        findLogErrors
    ;;

    # --- OpenLDAP Operations --- #

    install-openldap)
        installOpenldap
    ;;

    install-openldap-on-local)
        installOpenldapOnLocal
    ;;

    # --- Kerberos Operations --- #

    # be careful, migrating kerberos db is ONE-TIME operation,
    # it can NOT run twice!
    migrate-kerberos-db)
        migrateKerberosDb
    ;;

    migrate-kerberos-db-on-kdc-local)
        migrateKerberosDbOnKdcLocal
    ;;

    # -- SASL/GSSAPI Operations -- #

    enable-sasl-gssapi)
        enableSaslGssapi
    ;;

    enable-sasl-gssapi-on-openldap-local)
        enableSaslGssapiOnOpenldapLocal
    ;;

    # ----- SSSD Operations ----- #

    install-sssd)
        installSssd
    ;;

    # ----- Example Users Operations ----- #

    add-example-users)
        addExampleUsers
    ;;
    add-example-users-on-kdc-local)
        addExampleUsersOnKdcLocal
    ;;
    add-example-users-on-openldap-local)
        addExampleUsersOnOpenldapLocal
    ;;
    help)
#        printUsage
    ;;
    *)
#        printUsage
    ;;
esac

