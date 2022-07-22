#!/bin/bash

createAuditEventsLogGroupIfNotExists() {
    if [ "$(aws logs describe-log-groups --region $REGION --log-group-name-prefix $AUDIT_EVENTS_LOG_GROUP --output text)" = "" ]; then
        aws logs create-log-group --region $REGION --log-group-name $AUDIT_EVENTS_LOG_GROUP
    fi
}

configSecurityConfigurationProps() {
    confFile="$1"
    awsAccountId="$(aws sts get-caller-identity --query Account --output text)"
    rangerAdminSecretArn="$(aws secretsmanager get-secret-value --secret-id "ranger-admin@$RANGER_HOST" --query ARN --output text)"
    rangerPluginSecretArn="$(aws secretsmanager get-secret-value --secret-id "ranger-plugin@$RANGER_HOST" --query ARN --output text)"
    auditEventsLogGroupArn="$(aws logs describe-log-groups --log-group-name-prefix /aws-emr/audit-events --query 'logGroups[0].arn' --output text)"
    sed -i "s|@TRUSTING_REALM@|$TRUSTING_REALM|g" $confFile
    sed -i "s|@TRUSTING_DOMAIN@|$TRUSTING_DOMAIN|g" $confFile
    sed -i "s|@TRUSTING_HOST@|$TRUSTING_HOST|g" $confFile
    sed -i "s|@RANGER_URL@|$RANGER_URL|g" $confFile
    sed -i "s|@ARN_ROOT@|$ARN_ROOT|g" $confFile
    sed -i "s|@AWS_ACCOUNT_ID@|$awsAccountId|g" $confFile
    sed -i "s|@RANGER_ADMIN_SECRET_ARN@|$rangerAdminSecretArn|g" $confFile
    sed -i "s|@RANGER_PLUGIN_SECRET_ARN@|$rangerPluginSecretArn|g" $confFile
    sed -i "s|@AUDIT_EVENTS_LOG_GROUP_ARN@|$auditEventsLogGroupArn|g" $confFile
}

createEmrSecurityConfiguration() {
    printHeading "CREATE EMR SECURITY CONFIGURATION"
    # emr security configuration is dedicated for emr-native solution
    if [ "$SOLUTION" = "emr-native" ]; then
    #    removeEmrSecurityConfigurationIfExists
        createAuditEventsLogGroupIfNotExists
        confFile=$APP_HOME/conf/emr/security-configuration.json
        # backup existing version of conf file if exists
        if [ -f "$confFile" ]; then
            cp $confFile $confFile.$(date +%s)
        fi

        if [ "$AUTH_PROVIDER" = "ad" ]; then
            # for ad, copy a new version from template file, including CrossRealmTrustConfiguration
            cp -f $APP_HOME/conf/emr/security-configuration-template.json $confFile
        elif [ "$AUTH_PROVIDER" = "openldap" ]; then
            # for ad, copy a new version from template file, but remove CrossRealmTrustConfiguration
            jq 'del(.AuthenticationConfiguration.KerberosConfiguration.ClusterDedicatedKdcConfiguration.CrossRealmTrustConfiguration)' \
            $APP_HOME/conf/emr/security-configuration-template.json > $confFile
        else
            echo "Invalid authentication type, only AD and LDAP are supported!"
            exit 1
        fi
        # configs props
        configSecurityConfigurationProps $confFile
        aws emr create-security-configuration --region $REGION --name "ranger@${RANGER_HOST}" --security-configuration file://$confFile
    else
        echo "the emr security configuration is dedicated for emr-native solution, it is useless to open-source solution!"
        exit 1
    fi
}

removeEmrSecurityConfigurationIfExists() {
    output=$(aws emr delete-security-configuration --region $REGION --name "ranger@${RANGER_HOST}" 2>&1)
    echo $output
    if [ "$(echo $output|grep 'cannot be deleted because it is in use by active clusters')" = "0" ]; then
        echo "ERROR! The security configuration [ ranger@${RANGER_HOST} ] is in use!"
        exit 1
    fi
}

configHueAdProps() {
    confFile="$1"
    sed -i "s|@MASTER_INSTANCE_GROUP_ID@|$(getMasterInstanceGroupId)|g" $confFile
    sed -i "s|@MASTER_PRIVATE_FQDN@|$(getEmrMasterNodes)|g" $confFile
    sed -i "s|@AD_DOMAIN@|$AD_DOMAIN|g" $confFile
    sed -i "s|@AD_URL@|$AD_URL|g" $confFile
    sed -i "s|@AD_BASE_DN@|$AD_BASE_DN|g" $confFile
    sed -i "s|@AD_HUE_BIND_DN@|$AD_HUE_BIND_DN|g" $confFile
    sed -i "s|@AD_HUE_PASSWORD@|$AD_HUE_PASSWORD|g" $confFile
}

configHueOpenldapProps() {
    confFile="$1"
    sed -i "s|@MASTER_INSTANCE_GROUP_ID@|$(getMasterInstanceGroupId)|g" $confFile
    sed -i "s|@MASTER_PRIVATE_FQDN@|$(getEmrMasterNodes)|g" $confFile
    sed -i "s|@ORG_NAME@|$ORG_NAME|g" $confFile
    sed -i "s|@OPENLDAP_HOST@|$OPENLDAP_HOST|g" $confFile
    sed -i "s|@OPENLDAP_BASE_DN@|$OPENLDAP_BASE_DN|g" $confFile
    sed -i "s|@OPENLDAP_USER_OBJECT_CLASS@|$OPENLDAP_USER_OBJECT_CLASS|g" $confFile
    sed -i "s|@OPENLDAP_HUE_BIND_DN@|$OPENLDAP_HUE_BIND_DN|g" $confFile
    sed -i "s|@OPENLDAP_HUE_BIND_PASSWORD@|$OPENLDAP_HUE_BIND_PASSWORD|g" $confFile
}

updateHueConfiguration() {
    printHeading "UPDATE HUE CONFIGURATION"
    confFile=$APP_HOME/conf/emr/hue-$AUTH_PROVIDER.json
    # backup existing version of conf file if exists
    if [ -f "$confFile" ]; then
        cp $confFile $confFile.$(date +%s)
    fi
    # copy a new version from template file
    cp -f $APP_HOME/conf/emr/hue-$AUTH_PROVIDER-template.json $confFile

    if [ "$AUTH_PROVIDER" = "ad" ]; then
        configHueAdProps $confFile
    elif [ "$AUTH_PROVIDER" = "openldap" ]; then
        configHueOpenldapProps $confFile
    else
        echo "Invalid authentication type, only AD and LDAP are supported!"
        exit 1
    fi

    aws emr modify-instance-groups --cluster-id $EMR_CLUSTER_ID \
        --instance-groups file://$confFile
}

# ----------------------------------------    Query Cluster Info Operations   ---------------------------------------- #

# An emr cluster has only one master instance group
getMasterInstanceGroupId() {
    if [ -f $INIT_EC2_FLAG_FILE ]; then
        if [ "$EMR_CLUSTER_ID" = "" ]; then
            echo "ERROR!! --emr-cluster-id is not provided, it is required to solve emr cluster info."
            exit 1
        fi
        if [ "$MASTER_INSTANCE_GROUP_ID" = "" ]; then
            MASTER_INSTANCE_GROUP_ID=$(aws emr describe-cluster --region $REGION --cluster-id $EMR_CLUSTER_ID | \
                jq -r '.Cluster.InstanceGroups[] | select(.InstanceGroupType == "MASTER") | .Id' | tr -s ' ')
        fi
        echo $MASTER_INSTANCE_GROUP_ID
    else
        echo "This EC2 instance has NOT been initialized yet, can't query emr cluster info with aws cli! Please run init-ec2 first!"
        exit 1
    fi
}

# slave instance groups is core + task groups, may return multiple values!
# be careful, return string is just word-split (iterable) literal, not an array!
getSlaveInstanceGroupIds() {
    if [ -f $INIT_EC2_FLAG_FILE ]; then
        if [ "$EMR_CLUSTER_ID" = "" ]; then
            echo "ERROR!! --emr-cluster-id is not provided, it is required to solve emr cluster info."
            exit 1
        fi
        if [ "$SLAVE_INSTANCE_GROUP_IDS" = "" ]; then
            SLAVE_INSTANCE_GROUP_IDS=$(aws emr describe-cluster --region $REGION --cluster-id $EMR_CLUSTER_ID | \
                jq -r '.Cluster.InstanceGroups[] | select((.InstanceGroupType == "CORE") or (.InstanceGroupType == "SLAVE")) | .Id' | tr -s ' ')
        fi
        echo $SLAVE_INSTANCE_GROUP_IDS
    else
        echo "This EC2 instance has NOT been initialized yet, can't query emr cluster info with aws cli! Please run init-ec2 first!"
        exit 1
    fi
}

getNodes() {
    instanceGroupIds="$1"
    # be careful, instanceGroupIds is word-split (iterable) literal, don't quote with “”
    for instanceGroupId in ${instanceGroupIds}; do
        # convert to an array
        nodes+=($(aws emr list-instances --region $REGION --cluster-id $EMR_CLUSTER_ID | \
            jq -r --arg instanceGroupId "$instanceGroupId" '.Instances[] | select(.InstanceGroupId == $instanceGroupId) | .PrivateDnsName' | tr -s ' '))
    done
    echo "${nodes[@]}"
}

getEmrMasterNodes() {
    if [[ "${EMR_MASTER_NODES[*]}" = "" ]]; then
        masterInstanceGroupId=$(getMasterInstanceGroupId)
        EMR_MASTER_NODES=($(getNodes "$masterInstanceGroupId"))
    fi
    echo "${EMR_MASTER_NODES[@]}"
}

getEmrSlaveNodes() {
    if [[ "${EMR_SLAVE_NODES[*]}" = "" ]]; then
        slaveInstanceGroupIds=$(getSlaveInstanceGroupIds)
        EMR_SLAVE_NODES=($(getNodes "$slaveInstanceGroupIds"))
    fi
    echo "${EMR_SLAVE_NODES[@]}"
}

getEmrClusterNodes() {
    if [[ "${EMR_CLUSTER_NODES[*]}" = "" ]]; then
        EMR_CLUSTER_NODES=($(getEmrMasterNodes) $(getEmrSlaveNodes))
    fi
    echo "${EMR_CLUSTER_NODES[@]}"
}

getEmrZkQuorum() {
    if [[ "$EMR_ZK_QUORUM" = "" ]]; then
        # EMR_ZK_QUORUM looks like 'node1,node2,node3'
        EMR_ZK_QUORUM=$(getEmrMasterNodes | sed -E 's/[[:blank:]]+/,/g')
    fi
    echo "$EMR_ZK_QUORUM"
}

getEmrHdfsUrl() {
    if [[ "$EMR_HDFS_URL" = "" ]]; then
        # add hdfs:// prefix and :8020 postfix, EMR_HDFS_URL looks like
        # hdfs://node1:8020,hdfs://node2:8020,hdfs://node3:8020
        EMR_HDFS_URL=$(getEmrZkQuorum | sed -E 's/([^,]+)/hdfs:\/\/\1:8020/g')
    fi
    echo "$EMR_HDFS_URL"
}

getEmrFirstMasterNode() {
    if [[ "$EMR_FIRST_MASTER_NODE" = "" ]]; then
        # NOTE: ranger hive plugin will use hiveserver2 address, for single master node EMR cluster,
        # it is master node, for multi masters EMR cluster, all 3 master nodes will install hiverserver2
        # usually, there should be a virtual IP play hiverserver2 role, but EMR has no such config.
        # here, we pick first master node as hiveserver2
        EMR_FIRST_MASTER_NODE=$(getEmrClusterNodes | cut -d ' ' -f 1)
    fi
    echo "$EMR_FIRST_MASTER_NODE"
}

printEmrClusterNodes() {
    echo "Master Nodes:"
    for node in $(getEmrMasterNodes); do
        echo $node
    done
    echo "Slave Nodes:"
    for node in $(getEmrSlaveNodes); do
        echo $node
    done
}

# -----------------------------------------    EMR Cluster Util Operations   ----------------------------------------- #

getEmrLatestClusterId() {
    latestCreationTime=$(aws emr list-clusters --region $REGION | jq -r '.Clusters[].Status.Timeline.CreationDateTime' | sort -r | head -n 1)
    aws emr list-clusters --active | jq -r --arg  latestCreationTime "$latestCreationTime" '.Clusters[] | select (.Status.Timeline.CreationDateTime == $latestCreationTime) | .Id'
}

getEmrClusterStatus() {
    aws emr describe-cluster --region $REGION --cluster-id $EMR_CLUSTER_ID | jq -r '.Cluster.Status.State'
}

getClusterIps() {
    # all nodes
    aws emr list-instances --region $REGION --cluster-id j-TO4FE32NLGPF | jq -r .Instances[].PrivateDnsName
    # master instance group id
    aws emr describe-cluster --region $REGION --cluster-id j-TO4FE32NLGPF | jq -r '.Cluster.InstanceGroups[] | select(.InstanceGroupType == "MASTER") | .Id'

    # all master node
    aws emr list-instances --region $REGION --cluster-id j-TO4FE32NLGPF | jq -r '.Instances[] | select(.InstanceGroupId == "ig-3RBRQ0UXGP2YL") | .PrivateDnsName'
}

findLogErrors() {
    accountId=$(aws sts get-caller-identity --query Account --output text)
    region=$(aws configure get region)
    rm -rf /tmp/$EMR_CLUSTER_ID
    aws s3 cp --recursive s3://aws-logs-${accountId}-${region}/elasticmapreduce/$EMR_CLUSTER_ID /tmp/$EMR_CLUSTER_ID >& /dev/null
    # try zgrep to replace gzip and grep!
    gzip -d -r /tmp/$EMR_CLUSTER_ID >& /dev/null
    grep --color=always -r --exclude="*.yaml" -i -E 'error|failed|exception' /tmp/$EMR_CLUSTER_ID
}
