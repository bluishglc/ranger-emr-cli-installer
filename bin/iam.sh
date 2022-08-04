#!/bin/bash

createIamRoles() {
    # create iam roles if not exists
    # it is NOT a good idea to identify if roles are created by checking if its cfn is created,
    # because cfn is region-specific, however, roles are NOT, so if install cfn on a region,
    # the cfn is invisible in other regions, at this moment, if we run this tool on other region,
    # it will re-install the cfn, but this job will fail, because the roles are global, they are already existing.
    # so we should change to check if roles existing not cfn.
    # aws cloudformation get-template --region $REGION --stack-name emr-ranger-iam-roles &> /dev/null
    aws iam get-role --role-name EMR_EC2_RangerRole &> /dev/null && \
    aws iam get-role --role-name EMR_RANGER_PluginRole &> /dev/null && \
    aws iam get-role --role-name EMR_RANGER_OthersRole &> /dev/null

    if [ "$?" != "0" ]; then
        printHeading "CREATING CFN STACK: [ emr-ranger-iam-roles ]..."
        templateFile=$APP_HOME/conf/iam/emr-ranger-iam-roles.template
        # backup existing version of template file if exists
        if [ -f "$templateFile" ]; then
            cp $templateFile $templateFile.$(date +%s)
        fi
        # copy a new version from template file
        cp -f $APP_HOME/conf/iam/emr-ranger-iam-roles-template.template $templateFile
        configIamRolesTemplate $templateFile
        aws cloudformation deploy \
            --region "$REGION" \
            --stack-name emr-ranger-iam-roles \
            --no-fail-on-empty-changeset \
            --capabilities CAPABILITY_NAMED_IAM \
            --template-file $templateFile && \
        echo "Creating cfn stack: [ emr-ranger-iam-roles ] is SUCCESSFUL!! "
    else
        echo "Roles: EMR_EC2_RangerRole, EMR_RANGER_PluginRole and EMR_RANGER_OthersRole are existing, skip creating job. "
    fi
}

configIamRolesTemplate() {
    templateFile="$1"
    sed -i "s|@ARN_ROOT@|$ARN_ROOT|g" $templateFile
    sed -i "s|@SERVICE_POSTFIX@|$SERVICE_POSTFIX|g" $templateFile
}

removeIamRoles() {
    # delete iam roles if exists
    aws cloudformation get-template --region $REGION --stack-name emr-ranger-iam-roles &> /dev/null
    if [ "$?" == "0" ]; then
        printHeading "DELETING CFN STACK: [ emr-ranger-iam-roles ]..."
        aws cloudformation delete-stack --region $REGION --stack-name emr-ranger-iam-roles && \
        echo "Deleting cfn stack: [ emr-ranger-iam-roles ] is SUCCESSFUL!! "
    fi
}