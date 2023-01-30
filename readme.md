# An Installer for Apache Ranger and AWS EMR Automated Installation and Integration with OpenLDAP & Windows AD

This is a powerful cli tool for Apache Ranger and AWS EMR automated installation & integration with OpenLDAP & Windows AD. It supports Open-Source Ranger and EMR-Native Ranger both, supports OpenLDAP & Windows AD both, and works in all AWS regions (also including China regions). Especially, for Open-Source Ranger, it can install ranger on an existing cluster and supports multi-master cluster and single-master cluster both. On each step, this installer always checks connectivity first then decides whether to go for the next steps, this is very helpful to identify network issues or service failure, i.e., when Ranger or OpenLDAP is not up. Finally, the actual installation job is a trial-and-error process. Users always need to try different parameter values to find the one that works in users' environment. The installer allows users to rerun an all-in-one installation anytime without side effects and users can also do a step-by-step run for debugging. The following is a key features summary:

![](https://dz2cdn1.dzone.com/storage/temp/16538007-25-feature-list.jpg)

The following is detailed documents for solutions overview and scenario 1,2,3,4. No matter which one you selected, please read solutions overview first so as to get a full picture, then pick one from 4 scenarios according to your environments and requirements. 

## Solutions Overview

[Apache Ranger and AWS EMR Automated Installation Series (1): Solutions Overview](https://dzone.com/articles/apache-ranger-aws-emr-automated-installation-1)

## Scenario 1: OpenLDAP + EMR-Native Ranger

[Apache Ranger and AWS EMR Automated Installation Series (2): OpenLDAP + EMR-Native Ranger](https://dzone.com/articles/apache-ranger-aws-emr-automated-installation-2)

## Scenario 2: Windows AD + EMR-Native Ranger

[Apache Ranger and AWS EMR Automated Installation Series (3): Windows AD + EMR-Native Ranger](https://dzone.com/articles/apache-ranger-aws-emr-automated-installation-3)

## Scenario 3: OpenLDAP + Open-Source Ranger

[Apache Ranger and AWS EMR Automated Installation Series (4): OpenLDAP + Open-Source Ranger](https://dzone.com/articles/apache-ranger-aws-emr-automated-installation-4)

## Scenario 4: Windows AD + Open-Source Ranger

[Apache Ranger and AWS EMR Automated Installation Series (5): Windows AD + Open-Source Ranger](https://dzone.com/articles/apache-ranger-aws-emr-automated-installation-5)

