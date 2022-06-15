#BI Utility Server Role
- - - -

This performs standard setup items for BI Utility Server Role.
It performs the following task.

- Ensures Chocolatey is installed
- Sets system time zone to Central Standard Time
- Installs the following software via Chocolately

  - winmerge
  - notepadplusplus
  - visualstudio2017community
  - sql-server-management-studio
  - git
  - vcredist2017
  - msvisualcplusplus2013-redist
  - sql2016-clrtypes
  - sqlserver-odbcdriver
  - sql2012.nativeclient
  - ssdt17
  - visualstudio2017sql
  - microsoft-build-tools
  - install ssms-tools-pack
  - sqlserach
  - redshift-odbc
  - tsqlflex
  

- Adds the following user(s) and group(s) to the local administrators group.

  - CORP\BI_Admins
  - CORP\BI_Dev_Server_Admin
  - CORP\ITSQLAdmins

__Note:__ Additional Groups can be defined under the __vars/serversetup.yml__ file.

Requirements
------------

The System must be a domain joined server with a Windows Operating system

Role Variables
--------------

The following files are used for role variables.

- vars/serversetup.yml

  - Sets the list of user(s) and group(s) who will be defined as local administrators.
  - Sets the list of software to be installed via Chocolatey.

Dependencies
------------

N/A

Example Playbook
----------------

Including an example of how to use your role (for instance, with variables passed in as parameters) is always nice for users too:

    - hosts: servers
      roles:
         - { role: bi-utility-sever }

License
-------

BSD

Author Information
------------------

- Name:Matthew Badali
- Date Created: 5/10/2021