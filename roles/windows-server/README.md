# Windows Server Role
- - - -

This performs standard setup items for Windows Server.
It performs the following task.

- Ensures Chocolatey is installed
- Sets system time zone to Central Standard Time
- Installs the following software via Chocolately

  - Powershell Core version 7
  - AWS CLI
  - WGET
  - CURL
  - Microsoft Edge
  - Rapid7 Agent
  
- Ensures that the follow Windows Features are installed

  - Telnet Client
  - Built-in Version of Adobe Flash

- Ensure that the following Windows Features are removed

  - SMB version 1.0

- Adds the following user(s) and group(s) to the local administrators group.

  - CORP\ServerAdmins
  - CORP\SVCRapid7

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
         - { role: windows-sever }

License
-------

BSD

Author Information
------------------

- Name:Matthew Badali
- Date Created: 5/10/2021