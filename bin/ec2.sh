#!/bin/bash

initEc2() {
    # In most cases, init ec2 is a one-time job, no need to run duplicatly,
    # however, sometimes, when first run, users may enter wrong region or access keys,
    # then all following actions will fail, and this is hard to find root cause,
    # so finally, let's remove installed flag checking, let init-ec2 job always run!

#    if [ -f "$INIT_EC2_FLAG_FILE" ]; then
#        echo "This ec2 instance has been initialized, nothing to do!"
#        echo "If you want to force re-init this ec2, please execute force-init-ec2 command"
#    else
        if [[ "$REGION" = "" || "$ACCESS_KEY_ID" = "" || "$SECRET_ACCESS_KEY" = "" ]]; then
            echo "ERROR! --region or --access-key-id or --secret-access-key is not provided!"
            exit 1
        fi
        installTools
        configSsh
        installAwsCli
        installJdk8IfNotExists
        touch "$INIT_EC2_FLAG_FILE"
#    fi
}

forceInitEc2() {
    rm -f "$INIT_EC2_FLAG_FILE"
    initEc2
}

installTools() {
    printHeading "INSTALL COMMON TOOLS ON EC2"
    yum -y update
    # install common tools
    yum -y install https://dl.fedoraproject.org/pub/epel/epel-release-latest-$(rpm -E '%{rhel}').noarch.rpm
    yum -y install lrzsz vim wget zip unzip expect tree htop iotop nc telnet jq

    # change timezone
    cp /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
}

configSsh() {
    printHeading "CONFIG SSH"
    # enable ssh login with password
    sed -i "s/PasswordAuthentication no/PasswordAuthentication yes/g" /etc/ssh/sshd_config
    echo "PermitRootLogin yes" | tee -a  /etc/ssh/sshd_config
    echo "RSAAuthentication yes" | tee -a  /etc/ssh/sshd_config
    systemctl restart sshd

    # overwrite authorized_keys of root, because it blocks root login with: "no-port-forwarding, ... echo;sleep 10""
    # if user: hadoop exists, this is a node of EMR, otherwise, this is a normal EC2 instance!
    egrep "^hadoop\:" /etc/passwd >& /dev/null
    if [ "$?" == "0" ]; then
        cat /home/hadoop/.ssh/authorized_keys > /root/.ssh/authorized_keys
    else
        cat /home/ec2-user/.ssh/authorized_keys > /root/.ssh/authorized_keys
    fi
}

installAwsCli() {
    printHeading "INSTALL AWS CLI V2"
    # aws cli is very stupid!
    # for v1, it is installed via rpm/yum, so with 'yum list installed awscli', we can't get version
    # for v2, it is installed via zip Packages, it does NOT work with 'yum list installed awscli', only 'aws --version' works
    # but for v1, 'aws --version' does not work, it DO print version message, but does NOT return string value!
    # if let message=$(aws --version), it prints message on console, but $message is empty!
    # so, it is REQUIRED to append '2>&1', the following is right way to get version:
    # awscliVer=$(aws --version 2>&1 | grep -o '[0-9]*\.[0-9]*\.[0-9]*' | head -n1)
    rm /tmp/awscli -rf
    echo "Remove awscli v1 if exists ..."
    yum -y remove awscli

    echo "Remove awscli v2 if exists in case not latest version ..."
    rm /usr/bin/aws &> /dev/null
    rm /usr/local/bin/aws &> /dev/null
    rm /usr/bin/aws_completer &> /dev/null
    rm /usr/local/bin/aws_completer &> /dev/null
    rm -rf /usr/local/aws-cli &> /dev/null

    echo "Install latest awscli v2 ..."
    wget "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -P "/tmp/awscli/"  &> /dev/null
    unzip /tmp/awscli/awscli-exe-linux-x86_64.zip -d /tmp/awscli/ &> /dev/null
    /tmp/awscli/aws/install
    ln -s /usr/local/bin/aws /usr/bin/aws

    echo "Create credentials for awscli ..."
    tee /tmp/config <<EOF
[default]
region = $REGION
EOF
    tee /tmp/credentials <<EOF
[default]
aws_access_key_id = $ACCESS_KEY_ID
aws_secret_access_key = $SECRET_ACCESS_KEY
EOF
    # for non-root users
    users=(ec2-user hadoop)
    for user in "${users[@]}"; do
        # if user exists, add awscli credentials
        egrep "^$user\:" /etc/passwd >& /dev/null
        if [ "$?" == "0" ]; then
            rm -rf /home/$user/.aws
            mkdir /home/$user/.aws
            cp /tmp/config /home/$user/.aws/
            cp /tmp/credentials /home/$user/.aws/
            chown -R $user:$user /home/$user/.aws
        fi
    done
    # for root user
    rm -rf /root/.aws
    mkdir /root/.aws
    cp /tmp/config /root/.aws/
    cp /tmp/credentials /root/.aws/
    chown -R root:root /root/.aws

    rm -f /tmp/config /tmp/credentials
}

installJdk8IfNotExists() {
    rpm -q java-1.8.0-openjdk-devel &>/dev/null
    if [ ! "$?" = "0" ]; then
        printHeading "INSTALL OPEN JDK8"
        yum -y install java-1.8.0-openjdk-devel
        printHeading "MAKE AND EXPORT JAVA ENV VARS"
        echo "export JAVA_HOME=$JAVA_HOME;export PATH=$JAVA_HOME/bin:$PATH" > /etc/profile.d/java.sh
        source /etc/profile.d/java.sh
        # make sure ec2-user also set JAVA_HOME, only works after re-login as ec2-user
        # not work for current ssh session!
        sudo -i -u ec2-user source /etc/profile.d/java.sh
    fi
}