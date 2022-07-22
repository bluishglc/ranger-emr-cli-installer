#!/usr/bin/env bash

printHeading()
{
    title="$1"
    if [ "$TERM" = "dumb" -o "$TERM" = "unknown" ]; then
        paddingWidth=60
    else
        paddingWidth=$((($(tput cols)-${#title})/2-5))
    fi
    printf "\n%${paddingWidth}s"|tr ' ' '='
    printf "    $title    "
    printf "%${paddingWidth}s\n\n"|tr ' ' '='
}

validateTime()
{
    if [ "$1" = "" ]
    then
        echo "Time is missing!"
        exit 1
    fi
    TIME=$1
    date -d "$TIME" >/dev/null 2>&1
    if [ "$?" != "0" ]
    then
        echo "Invalid Time: $TIME"
        exit 1
    fi
}

installXmlstarletIfNotExists() {
    if ! xmlstarlet --version &>/dev/null; then
        yum -y install https://dl.fedoraproject.org/pub/epel/epel-release-latest-$(rpm -E '%{rhel}').noarch.rpm &>/dev/null
        yum -y install xmlstarlet &>/dev/null
    fi
}

distributeInstaller() {
    user="$1"
    host="$2"
    installer=ranger-emr-cli-installer
    ssh -o StrictHostKeyChecking=no -i $SSH_KEY -T $user@$host sudo rm -rf /tmp/$installer
    scp -o StrictHostKeyChecking=no -i $SSH_KEY -r $APP_HOME $user@$host:/tmp/$installer &>/dev/null
    ssh -o StrictHostKeyChecking=no -i $SSH_KEY -T $user@$host <<EOSSH
        sudo rm -rf $APP_REMOTE_HOME
        sudo mv /tmp/$installer $APP_REMOTE_HOME
EOSSH
}