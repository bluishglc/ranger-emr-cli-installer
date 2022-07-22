#!/bin/bash

createIamRoles() {
    # create iam roles if not exists
    aws cloudformation get-template --region $REGION --stack-name emr-ranger-iam-roles &> /dev/null
    if [ "$?" != "0" ]; then
        printHeading "CREATING CFN STACK: [ emr-ranger-iam-roles ]..."
        aws cloudformation deploy \
            --region "$REGION" \
            --stack-name emr-ranger-iam-roles \
            --no-fail-on-empty-changeset \
            --capabilities CAPABILITY_NAMED_IAM \
            --template-file $APP_HOME/conf/iam/emr-ranger-iam-roles.template && \
        echo "Creating cfn stack: [ emr-ranger-iam-roles ] is SUCCESSFUL!! "
    else
        echo "The cfn stack: [ emr-ranger-iam-roles ] is EXISTING, skip creating job. "
    fi
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