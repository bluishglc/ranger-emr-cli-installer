#!/usr/bin/env bash

#
# This script apply follow naming role:
# for a principal, i.e. ranger-admin, its:
# 1. private key: ranger-admin.key
# 2. certificate: ranger-admin.crt
# 3. pcks12 file: ranger-admin.p12
# 4. keystore:    ranger-admin-keystore.jks
# 5. truststore:  ranger-admin-truststore.jks
#

createRangerSecrets() {
    printHeading "CREATE KEY, CRT, KEYSTORE & TRUSTSTORE FOR RANGER"

    rm -rf $RANGER_SECRETS_DIR
    mkdir -p $RANGER_SECRETS_DIR

    # ranger-admin
    printHeading "CREATE KEY, CRT, KEYSTORE FOR [ ranger-admin ]"
    createKeyCertPair "ranger-admin"
    createKeystore "ranger-admin"

    # ranger-plugin
    #   it is NOT possible to use ranger-plugin certs, because they will be generated & managed by EMR
    #   but for other open-source plugins, i.e. HBase, Presto, these certs will be required if ranger admin https enabled!
    printHeading "CREATE KEY, CRT, KEYSTORE FOR [ ranger-plugin ]"
    createKeyCertPair "ranger-plugin"
    createKeystore "ranger-plugin"

    # build truststore file used by ranger admin, be careful, this file NOT USED!
    # instead, plugins crts will install to JVM cacerts file.
    createOrImportToTruststore "ranger-admin" "ranger-admin"# trust self
    createOrImportToTruststore "ranger-admin" "ranger-plugin" # trust plugin

    # build truststore file used by ranger open-source plugins.
    # for emr-native plugins, EMR will regenerate truststore with key & certs from secrets manager.
    createOrImportToTruststore "ranger-plugin" "ranger-plugin" # trust self
    createOrImportToTruststore "ranger-plugin" "ranger-admin" # trust admin

    # NOTE: because there is explicit truststore config items in ranger admin,
    # there is no way to set the path of 'ranger-admin-truststore.jks',
    # so, we HAVE TO add all trusted crts to JAVA default crts store: $JAVA_HOME/jre/lib/security/cacerts
    removeFromJavaDefaultTruststore "ranger-admin"
    importToJavaDefaultTruststore "ranger-admin" # trust self
    removeFromJavaDefaultTruststore "ranger-plugin"
    importToJavaDefaultTruststore "ranger-plugin" # trust self

    listCerts "ranger-admin"
    listCerts "ranger-plugin"

    removeSecretsOnSecretsManager
    uploadRangerSecretsToSecretsManager
}

removeRangerSecrets() {
    removeSecretsOnSecretsManager
    removeFromJavaDefaultTruststore "ranger-admin"
    removeFromJavaDefaultTruststore "ranger-plugin"
    rm -rf $RANGER_SECRETS_DIR
}

createKeyCertPair() {
    principal="$1"
    openssl req -x509 -newkey rsa:2048 -nodes -keyout $RANGER_SECRETS_DIR/${principal}.key -out $RANGER_SECRETS_DIR/${principal}.crt -days 3650  -subj "/C=CN/ST=SHANGHAI/L=SHANGHAI/O=EXAMPLE/OU=IT/CN=$CERTIFICATE_CN"
}

createKeystore() {
    principal="$1"
    openssl pkcs12 -export -in $RANGER_SECRETS_DIR/${principal}.crt -inkey $RANGER_SECRETS_DIR/${principal}.key -chain -CAfile $RANGER_SECRETS_DIR/${principal}.crt -name ${principal} -out $RANGER_SECRETS_DIR/${principal}.p12 -password pass:changeit
    keytool -importkeystore -deststorepass changeit -destkeystore $RANGER_SECRETS_DIR/${principal}-keystore.jks -srckeystore $RANGER_SECRETS_DIR/${principal}.p12 -srcstoretype PKCS12 -srcstorepass changeit
}

createOrImportToTruststore() {
    trustingPrincipal="$1"
    trustedPrincipal="$2"
    keytool -import -file $RANGER_SECRETS_DIR/${trustedPrincipal}.crt -alias $trustedPrincipal -keystore $RANGER_SECRETS_DIR/${trustingPrincipal}-truststore.jks -storepass changeit -noprompt
}

removeFromJavaDefaultTruststore() {
    trustedPrincipal="$1"
    keytool -delete -alias $trustedPrincipal -keystore $JAVA_HOME/jre/lib/security/cacerts -storepass changeit
}

importToJavaDefaultTruststore() {
    trustedPrincipal="$1"
    keytool -import -file $RANGER_SECRETS_DIR/${trustedPrincipal}.crt -alias $trustedPrincipal -keystore $JAVA_HOME/jre/lib/security/cacerts -storepass changeit -noprompt
}

listCerts() {
    principal="$1"
    echo "${principal}-keystore.jks contains following certificates:"
    keytool -list -v -keystore $RANGER_SECRETS_DIR/${principal}-keystore.jks -storepass changeit|grep Alias.*
    echo "${principal}-truststore.jks contains following certificates:"
    keytool -list -v -keystore $RANGER_SECRETS_DIR/${principal}-truststore.jks -storepass changeit|grep Alias.*
}

uploadRangerSecretsToSecretsManager() {
    printHeading "UPLOAD SECRETS TO SECRETSMANAGER"
    # append postfix for secret id in case there are multiple clusters to be created!
    aws secretsmanager create-secret --name "ranger-admin@${RANGER_HOST}" --description "Ranger Admin Certificate" --secret-string file://$RANGER_SECRETS_DIR/ranger-admin.crt --region $REGION
    # EMR Security Configuration need a secret file contains plugin key and cert both.
    cat $RANGER_SECRETS_DIR/ranger-plugin.key $RANGER_SECRETS_DIR/ranger-plugin.crt >  $RANGER_SECRETS_DIR/ranger-plugin.key+crt
    aws secretsmanager create-secret --name "ranger-plugin@${RANGER_HOST}" --description "Ranger Admin Private Key & Certificate" --secret-string file://$RANGER_SECRETS_DIR/ranger-plugin.key+crt --region $REGION
}

removeSecretsOnSecretsManager() {
    printHeading "REMOVE SECRETS FROM SECRETSMANAGER"
    aws secretsmanager delete-secret --secret-id "ranger-admin@${RANGER_HOST}" --force-delete-without-recovery --region $REGION --cli-read-timeout 10 --cli-connect-timeout 10
    aws secretsmanager delete-secret --secret-id "ranger-plugin@${RANGER_HOST}" --force-delete-without-recovery --region $REGION --cli-read-timeout 10 --cli-connect-timeout 10

    # deleting secrets is async job, have to wait for a while...
    sleep 30
}

