# An Installer for Apache Ranger and AWS EMR Automated Installation and Integration with OpenLDAP & Windows AD

---

Author：Laurence Geng　　｜　　Created Date：2020-11-21　　｜　　Updated Date：2023-01-30

---

This is a powerful cli tool for Apache Ranger and AWS EMR automated installation & integration with OpenLDAP & Windows AD. It can complete 3 major jobs automatically:

1. Install and integrate an authentication provider.
2. Setup Ranger server and its plugins on EMR cluster.
3. Configure all related components if Kerberos is enabled.

For authentication providers, Windows AD and OpenLDAP are most widely used. Their installation and integration are very different, so they should count as two separate jobs.

For Ranger installation, there are two options. The first is “open-source ranger server + EMR-native ranger plugins.” In the document, we will refer to it as an “EMR-native” ranger solution. The second is “open-source ranger server + open-source ranger plugins.” In the document, we will refer to it as an “open-source” ranger solution. Installing the two solutions will be two separate jobs.

For Kerberos, if enabled, it will bring a lot of changes to the above jobs, so enabling or disabling Kerberos is also two separate jobs.

In summary, based on the three factors above, there are eight possible scenarios (technology stacks) as follows:

![](https://dz2cdn1.dzone.com/storage/temp/16331443-1-8-scenarios-table-small.jpg)

This installer supports first 4 high-applicability scenarios, the following is detailed documents for overview and scenario 1,2,3,4. No matter which one you selected, please read solutions overview first to get a full picture.

No.|Documents
:---|:--------------
1|[Apache Ranger and AWS EMR Automated Installation and Integration Series (1): Solutions Overview](https://dzone.com/articles/apache-ranger-aws-emr-automated-installation-1)
2|[Apache Ranger and AWS EMR Automated Installation and Integration Series (2): OpenLDAP + EMR-Native Ranger](https://dzone.com/articles/apache-ranger-aws-emr-automated-installation-2)
3|[Apache Ranger and AWS EMR Automated Installation and Integration Series (3): Windows AD + EMR-Native Ranger](https://dzone.com/articles/apache-ranger-aws-emr-automated-installation-3)
4|[Apache Ranger and AWS EMR Automated Installation and Integration Series (4): OpenLDAP + Open-Source Ranger](https://dzone.com/articles/apache-ranger-aws-emr-automated-installation-4)
5|[Apache Ranger and AWS EMR Automated Installation and Integration Series (5): Windows AD + Open-Source Ranger](https://dzone.com/articles/apache-ranger-aws-emr-automated-installation-5)


This installer supports Windows AD and OpenLDAP and works in all AWS regions (including Chinese regions). Especially, for scenarios 3 & 4, it can install ranger on an existing cluster and supports multi-master cluster and single-master cluster both. For each step, this installer always checks connectivity first then decides whether to go for the next steps. This is very helpful to identify network issues or service failure, i.e., when Ranger or OpenLDAP is not up. Finally, the actual installation job is a trial-and-error process. Users always need to try different parameter values to find the one that works in users' environment. The installer allows users to rerun an all-in-one installation anytime without side effects and users can also do a step-by-step run for debugging. The following is a key features summary:

![](https://dz2cdn1.dzone.com/storage/temp/16538007-25-feature-list.jpg)

For scenarios 5 and 6, as of this writing, EMR is not yet supported. Since disabling Kerberos on EMR cluster is not a recommended practice, the AWS service team is working on a solution to meet the needs. For scenarios 7 and 8, considering few users pick them, we won't discuss them. 
