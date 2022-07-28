#!/bin/bash

createIamRoles() {
    # create iam roles if not exists
    aws cloudformation get-template --region $REGION --stack-name emr-ranger-iam-roles &> /dev/null
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
        echo "The cfn stack: [ emr-ranger-iam-roles ] is EXISTING, skip creating job. "
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