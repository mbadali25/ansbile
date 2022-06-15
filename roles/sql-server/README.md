# SQL-Server Role

- - - -

This ansible role will install SQL Server on to the Windows Server.
It will determine the needs from the following factors:

- AWS Owner Tag
- AWS Environment Tag
- Server Name

## SQL Server Role setup

The Server will install any of these 4 SQL Server roles depending on the server name

- DatabaseServer
- AnalysisServer
- IntegrationsServer
- ReportingServer

## Server Configuration

- Provisions the SQL Data Disk
  - Initialize disk as GPT
  - Creates partitions
  - Formats partitions
  - Assigns drive letter and label
    - Based on AWS tags
- Sets system time zone to Central Standard Time
- Configures and installs the package manager
- Installs required software via the package manager
  - This might vary depending on environment and server owner- 
- Assigned Active Directory security groups based on owner and environment

### Security Groups

#### All Environments

- CORP\ITSQLAdmins

#### Owner: Data and Analytics

##### Environment: Development

- CORP\BI_DEV_Server_Admin

##### Environment: QA

- CORP\BI_QA_Server_Admin

__Note:__ Additional Groups can be defined under the __default/main.yml__ file.

#### Installed Software

#### Owner: Data and Analyitcs

The below software is installed for all environments

- Git command line
- WinMerge
- Notepad++
- Microsoft Build Tools
- Pragmatic Workbench
- SQL 2012 Native Client
- SQL Server 2016 CLR Types
- SQL Sever Database Tools for Visual Studio 2017
- SQL Server Management Studio
- SQL Server ODBC Driver
- SSMS Tool Pack
- Redgate SQL Search
- Redshift ODBC Drivers
- TaskFactory
- T-SQL Flex
- Visual C++ Redistributable 2013
- Visual C++ Redistributable 2015-2019
- Visual Studio 2017 Community Edition

## Requirements

- - - -

The System must be a domain joined server with a Windows Operating system

## Role Variables

- - - -

The following files are used for role variables.

- vars/db_servers.yml

  - This variable file is set on runtime
    - It pulls the server names and IPs of the nodes for the cluster to be used in the role

### Dependencies

- - - -

- The AWS Server Disk need to have the following Tags'
  - DriveLabel
  - DriveLetter

- The AWS EC2 instance needs to have the following Tags'
  - Environment
  - Owner

- The Ansible facts script must be present and run
  - Location: C:\etc\ansible\facts.d
  - ScriptName: system_info.ps1

### Example Playbook

- - - -

Including an example of how to use your role (for instance, with variables passed in as parameters) is always nice for users too:

    - hosts: servers #Host Group or Server Name
      roles:
         - { role: sql-server }

#### License

- - - -

BSD

#### Author Information

- - - -

- Name:Matthew Badali
- Date Created: 08/02/2021
