# A CLI Tool for Ranger Self Installing and Ingerating with AWS EMR Cluster and AD/LDAP

---

Author：Laurence Geng　　｜　　Created Date：2020-11-21　　｜　　Updated Date：2020-11-21

---

This is a command line tool which is used to install ranger and integrate a AWS EMR cluster and a windows AD or Open LDAP server as authentication channel. There is another closely related project: **[ranger-emr-cfn-installer](https://github.com/bluishglc/ranger-emr-cfn-installer)** which does the same job via aws cloudformation. The two projects are very close, but can work independently，you can pick anyone as you wish.

## 1. Ranger Introduction

Let’s check out Ranger's architecture:

![ranger-architecture](https://user-images.githubusercontent.com/5539582/99872048-f0c24480-2c19-11eb-8c0f-43df2552837c.png)

Ranger has 5 parts:

1. Ranger Admin Service
2. Ranger UserSync Service
3. A Backend RDB for Storing User's Authorization
4. A Solr Server for Storing Audit Log
5. A Series of Plugins for Big Data Components/Services

Besides above, there are 2 external dependencies For Ranger to integrate:

6. A Windows AD or Open LDAD Server as Authentication Channel
7. A Hadoop (AWS EMR) Cluster to Be Managed by Ranger

So, a fully Ranger installation will cover following jobs:

1. Install JDK (Required by Ranger Admin and Solr)
2. Install MySQL (As Ranger Backend RDB)
3. Install Solr (As Ranger Audit Store)
4. Install Ranger Admin (and Integrate with AD/LDAP Server)
5. Install Ranger UserSync (and Integrate with AD/LDAP Server)
6. Install Ranger Plugins (i.e. HDFS, Hive, HBase and so on)

## 2. Download

1. First all, setup a clean Linux server, login and switch to root user.

2. Install Git and check out this tool.

```bash
yum -y install git
git clone https://github.com/bluishglc/ranger-emr-cli-installer.git /home/ec2-user/ranger-emr-cli-installer
```

## 3. Usage

After downloaded, let's print usage to check if the cli tool is ready to use.

```bash
sh /home/ec2-user/ranger-emr-cli-installer/bin/setup.sh help
```
then, the console will print all actions and options supported by this CLI tool:

```
=============================    RANGER-EMR-CLI-INSTALLER USAGE    =============================

Actions:

install                               Install all components
install-ranger                        Install ranger only
install-ranger-plugins                Install ranger plugin only
test-emr-ssh-connectivity             Test EMR ssh connectivity
test-emr-namenode-connectivity        Test EMR namenode connectivity
test-ldap-connectivity                Test LDAP connectivity
install-mysql                         Install MySQL
test-mysql-connectivity               Test MySQL connectivity
install-mysql-jdbc-driver             Install MySQL JDBC driver
install-jdk                           Install JDK8
download-ranger                       Download ranger
install-solr                          Install solr
test-solr-connectivity                Test solr connectivity
init-solr-as-ranger-audit-store       Test solr connectivity
init-ranger-admin-db                  Init ranger admin db
install-ranger-admin                  Install ranger admin
install-ranger-usersync               Install ranger usersync
help                                  Print help

Options:

--auth-type [ad|ldap]                 Authentication type, optional value: ad or ldap
--ad-domain                           Specify the domain name of windows ad server
--ad-url                              Specify the ldap url of windows ad server, i.e. ldap://10.0.0.1
--ad-base-dn                          Specify the base dn of windows ad server
--ad-bind-dn                          Specify the bind dn of windows ad server
--ad-bind-password                    Specify the bind password of windows ad server
--ad-user-object-class                Specify the user object class of windows ad server
--ldap-url                            Specify the ldap url of Open LDAP, i.e. ldap://10.0.0.1
--ldap-user-dn-pattern                Specify the user dn pattern of Open LDAP
--ldap-group-search-filter            Specify the group search filter of Open LDAP
--ldap-base-dn                        Specify the base dn of Open LDAP
--ldap-bind-dn                        Specify the bind dn of Open LDAP
--ldap-bind-password                  Specify the bind password of Open LDAP
--ldap-user-object-class              Specify the user object class of Open LDAP
--java-home                           Specify the JAVA_HOME path, default value is /usr/lib/jvm/java
--skip-install-mysql [true|false]     Specify If skip mysql installing or not, default value is 'false'
--mysql-host                          Specify the mysql server hostname or IP, default value is current host IP
--mysql-root-password                 Specify the root password of mysql
--mysql-ranger-db-user-password       Specify the ranger db user password of mysql
--solr-host                           Specify the solr server hostname or IP, default value is current host IP
--skip-install-solr [true|false]      Specify If skip solr installing or not, default value is 'false'
--ranger-host                         Specify the ranger server hostname or IP, default value is current host IP
--ranger-version [2.1.0]              Specify the ranger version, now only Ranger 2.1.0 is supported
--ranger-repo-url                     Specify the ranger repository url
--ranger-plugins [hdfs|hive|hbase]    Specify what plugins will be installed(accept multiple comma-separated values), now support hdfs, hive and hbase
--emr-master-nodes                    Specify master nodes list of EMR cluster(accept multiple comma-separated values), i.e. 10.0.0.1,10.0.0.2,10.0.0.3
--emr-core-nodes                      Specify core nodes list of EMR cluster(accept multiple comma-separated values), i.e. 10.0.0.4,10.0.0.5,10.0.0.6
--emr-ssh-key                         Specify the path of ssh key to connect EMR nodes
--restart-interval                    Specify the restart interval

```

## 4. Examples

To illustrate how to use this cli tool, let's assume we have a following environment:

**A Windows AD Server**

Info Item Key|Info Item Value
---------|-----
IP|10.0.0.194
Domain Name|corp.emr.local
Base DN|cn=users,dc=corp,dc=emr,dc=local
Bind DN|cn=ranger,ou=service accounts,dc=example,dc=com
Bind DN Password|Admin1234!
User Object Class|person


**An Open LDAP Server**

Info Item Key|Info Item Value
---------|-----
IP|10.0.0.41
Base DN|dc=example,dc=com
Bind DN|cn=ranger,ou=service accounts,dc=example,dc=com
Bind DN Password|Admin1234!
User DN Pattern|uid={0},dc=example,dc=com
Bind Group Search Filter|(member=uid={0},dc=example,dc=com)
User Object Class|inetOrgPerson


**A Multi-Master EMR Cluster**

Node|IP
---|---
Master Nodes|10.0.0.177,10.0.0.199,10.0.0.21
Core Nodes|10.0.0.114,10.0.0.136


**A Normal EMR Cluster**

Node|IP
---|---
Master Nodes|10.0.0.177,10.0.0.199,10.0.0.21
Core Nodes|10.0.0.114,10.0.0.136

### 4.1. Install Ranger + Integrate a Window AD Server + Integrate A Multi-Master EMR Cluster

The following diagram illustrates what this example will do:

![example1](https://user-images.githubusercontent.com/5539582/99872053-fc157000-2c19-11eb-94c4-ee36ed30ce14.png)

The following command line will finish this job:

```bash
sudo sh ranger-emr-cli-installer/bin/setup.sh install \
--ranger-host $(hostname -i) \
--java-home /usr/lib/jvm/java \
--skip-install-mysql false \
--mysql-host $(hostname -i) \
--mysql-root-password 'Admin1234!' \
--mysql-ranger-db-user-password 'Admin1234!' \
--skip-install-solr false \
--solr-host $(hostname -i) \
--auth-type ad \
--ad-domain corp.emr.local \
--ad-url ldap://10.0.0.194 \
--ad-base-dn 'cn=users,dc=corp,dc=emr,dc=local' \
--ad-bind-dn 'cn=ranger,ou=service accounts,dc=corp,dc=emr,dc=local' \
--ad-bind-password 'Admin1234!' \
--ad-user-object-class person \
--ranger-version 2.1.0 \
--ranger-repo-url 'http://52.81.173.97:7080/ranger-repo/' \
--ranger-plugins hdfs,hive,hbase \
--emr-master-nodes 10.0.0.177,10.0.0.199,10.0.0.21 \
--emr-core-nodes 10.0.0.114,10.0.0.136 \
--emr-ssh-key /home/ec2-user/key.pem \
--restart-interval 30
```

### 4.2. Integrate The Second Normal EMR Cluster

The following diagram illustrates what this example will do:

![example2](https://user-images.githubusercontent.com/5539582/99872056-0172ba80-2c1a-11eb-9087-ea8e5ef353b7.png)

The following command line will finish this job:

```bash
sudo sh ranger-emr-cli-installer/bin/setup.sh install-ranger-plugins \
--ranger-host $(hostname -i) \
--solr-host $(hostname -i) \
--ranger-version 2.1.0 \
--ranger-plugins hdfs,hive,hbase \
--emr-master-nodes 10.0.0.18 \
--emr-core-nodes 10.0.0.69 \
--emr-ssh-key /home/ec2-user/key.pem \
--restart-interval 30
```

### 4.3. Install Ranger + Integrate a Open LDAP Server + Integrate A Multi-Master EMR Cluster

The following diagram illustrates what this example will do:

![example3](https://user-images.githubusercontent.com/5539582/99872059-059ed800-2c1a-11eb-82e7-da5e21949d44.png)

The following command line will finish this job:

```bash
sudo sh ranger-emr-cli-installer/bin/setup.sh install \
--ranger-host $(hostname -i) \
--java-home /usr/lib/jvm/java \
--skip-install-mysql false \
--mysql-host $(hostname -i) \
--mysql-root-password 'Admin1234!' \
--mysql-ranger-db-user-password 'Admin1234!' \
--skip-install-solr false \
--solr-host $(hostname -i) \
--auth-type ldap \
--ldap-url ldap://10.0.0.41 \
--ldap-base-dn 'dc=example,dc=com' \
--ldap-bind-dn 'cn=ranger,ou=service accounts,dc=example,dc=com' \
--ldap-bind-password 'Admin1234!' \
--ldap-user-dn-pattern 'uid={0},dc=example,dc=com' \
--ldap-group-search-filter '(member=uid={0},dc=example,dc=com)' \
--ldap-user-object-class inetOrgPerson \
--ranger-version 2.1.0 \
--ranger-repo-url 'http://52.81.173.97:7080/ranger-repo/' \
--ranger-plugins hdfs,hive,hbase \
--emr-master-nodes 10.0.0.177,10.0.0.199,10.0.0.21 \
--emr-core-nodes 10.0.0.114,10.0.0.136 \
--emr-ssh-key /home/ec2-user/key.pem \
--restart-interval 30
```

## 5. Versions & Compatibility

The following is Ranger and EMR version compatibility form:

&nbsp;|Ranger 1.X|Ranger 2.x
---|---|---
EMR 5.X|Y|N
EMR 6.X|N|Y

for Ranger 1, it works with Hadoop 2, for Ranger 2, it works with Hadoop 3, This tool is developed against Ranger 2.1.0, so it can only integrate EMR 6.X by now. For Ranger 1.2 + EMR 5.X, it is to be developed in next.

