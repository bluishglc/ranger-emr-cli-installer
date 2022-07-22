#!/bin/bash

# -----------------------------------------------   MySQL Operations   ----------------------------------------------- #

installMySqlIfNotExists() {
    systemctl --type=service --state=running | grep mysqld
    if [ ! "$?" = "0" ]; then
        printHeading "INSTALL MYSQL"
#        installMySqlViaYum
        # switch to rpm installing in case the bind width of mysql yum repo site is poor
        installMySqlViaRpm
        systemctl enable mysqld
        systemctl start mysqld
        systemctl status mysqld
        # filter message that contains temp password
        tmpPasswdMsg=$(grep 'temporary password' /var/log/mysqld.log)
        # split from last space, get temp password
        tmpPasswd="${tmpPasswdMsg##* }"
        echo "get mysql initial password: $tmpPasswd"
        cp $APP_HOME/sql/init-mysql.sql $APP_HOME/sql/.init-mysql.sql
        sed -i "s|@MYSQL_ROOT_PASSWORD@|$MYSQL_ROOT_PASSWORD|g" "$APP_HOME/sql/.init-mysql.sql"
        # -h must be "localhost", not host IP!
        mysql -hlocalhost -uroot -p"$tmpPasswd" -s --prompt=nowarning --connect-expired-password <"$APP_HOME/sql/.init-mysql.sql"
    fi
}

installMySqlViaYum() {
    if [ ! -f /tmp/mysql57-community-release-el7-11.noarch.rpm ]; then
        wget https://dev.mysql.com/get/mysql57-community-release-el7-11.noarch.rpm -P /tmp/
    fi
    rpm -ivh /tmp/mysql57-community-release-el7-11.noarch.rpm
    # update gpg key, this is required after 2022
    rpm --import https://repo.mysql.com/RPM-GPG-KEY-mysql-2022
    yum -y install mysql-community-server
}

installMySqlViaRpm() {
    yum -y remove mariadb-libs
    yum -y install ncurses-compat-libs
    # note: only provide x86_64 rpm packages
    rpm -ivh /tmp/ranger-repo/mysql-community-common-5.7.38-1.el7.x86_64.rpm
    rpm -ivh /tmp/ranger-repo/mysql-community-libs-5.7.38-1.el7.x86_64.rpm
    rpm -ivh /tmp/ranger-repo/mysql-community-libs-compat-5.7.38-1.el7.x86_64.rpm
    rpm -ivh /tmp/ranger-repo/mysql-community-client-5.7.38-1.el7.x86_64.rpm
    rpm -ivh /tmp/ranger-repo/mysql-community-server-5.7.38-1.el7.x86_64.rpm
}

installMySqlCliIfNotExists() {
    mysql -V &>/dev/null
    if [ ! "$?" = "0" ]; then
        printHeading "INSTALL MYSQL CLI CLIENT FOR CONNECTIVITY TESTING"
        echo "MySQL client has not been installed yet, will install right now!"
        yum -y install mysql-community-server
        if [ ! -f /tmp/mysql57-community-release-el7-11.noarch.rpm ]; then
            wget https://dev.mysql.com/get/mysql57-community-release-el7-11.noarch.rpm -P /tmp/
        fi
        rpm -ivh /tmp/mysql57-community-release-el7-11.noarch.rpm
        yum -y install mysql-community-client
    fi
}

testMySqlConnectivity() {
    printHeading "TEST MYSQL CONNECTIVITY"
    installMySqlCliIfNotExists
    mysql -h$MYSQL_HOST -uroot -p$MYSQL_ROOT_PASSWORD -e "select 1;" &>/dev/null
    if [ "$?" = "0" ]; then
        echo "Connecting to mysql server is SUCCESSFUL!!"
    else
        echo "Connecting to mysql server is FAILED!!"
        exit 1
    fi
}

installMySqlJdbcDriverIfNotExists() {
    if [ ! -f /usr/share/java/mysql-connector-java.jar ]; then
        printHeading "INSTALL MYSQL JDBC DRIVER"
        wget https://dev.mysql.com/get/Downloads/Connector-J/mysql-connector-java-5.1.48.tar.gz -P /tmp/
        tar -zxvf /tmp/mysql-connector-java-5.1.48.tar.gz -C /tmp &>/dev/null
        mkdir -p /usr/share/java/
        cp /tmp/mysql-connector-java-5.1.48/mysql-connector-java-5.1.48-bin.jar /usr/share/java/mysql-connector-java.jar
        echo "Mysql JDBC Driver is installed!"
    fi
}