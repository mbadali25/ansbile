# Print Server Role
- - - -

This performs standard setup items for Windows Print Server.
It performs the following task.

- Ensures that the follow Windows Features are installed

  - Print-Server

    - Including all management tools for it

- Adds the following user(s) and group(s) to the local administrators group.

  - CORP\PrinterAdmins

__Note:__ Additional Groups can be defined under the __vars/serversetup.yml__ file.

Requirements
------------

The System must be a domain joined server with a Windows Operating System

Role Variables
--------------

The following files are used for role variables.

- vars/serversetup.yml

  - Sets the list of user(s) and group(s) who will be defined as local administrators.

Dependencies
------------

N/A

Example Playbook
----------------

Including an example of how to use your role (for instance, with variables passed in as parameters) is always nice for users too:

    - hosts: servers
      roles:
         - { role: print-sever }

License
-------

BSD

Author Information
------------------

- Name:Matthew Badali
- Date Created: 5/10/2021