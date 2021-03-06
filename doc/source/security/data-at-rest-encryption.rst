.. _data_at_rest_encryption:

===============================================================================
Data at Rest Encryption
===============================================================================

.. contents::
   :local:

|Percona Server| enables data at rest encryption of the InnoDB (file-per-table) tablespace by encrypting the physical database files. The data is automatically encrypted prior to writing to storage and automatically decrypted when read.
If unauthorized users access the data files, they cannot read the contents. 

.. rubric:: Architecture

The data at rest encryption uses a two-tier architecture with the following components:

.. tabularcolumns:: |p{5cm}|p{11cm}|

.. list-table::
   :header-rows: 1
  
   * - Type
     - Description
   * - Master key
     - The Master key is used to encrypt or decrypt the tablespace keys.
   * - Tablespace key for each tablespace
     - The tablespace key encrypts the data pages and is written in the tablespace header. Rebuild the table to change the tablespace key.

When the server must access the data, the master key decrypts the tablespace key, the tablespace is decrypted and available for read or write operations.

The two separate keys architecture allows the master key to be rotated in a
minimal operation. During the master key rotation, each tablespace key is
re-encrypted with the new master key. Only the first page of the tablespace file
(.ibd) is read and written during the rotation. An encrypted page is decrypted
at the I/O layer, added to the buffer pool, and used to read and write the data.
A buffer pool page is not encrypted. The I/O layer encrypts the page before the
page is flushed to disk.

An encryption key in the tablespace header is required to encrypt or decrypt the tablespace. The Master key is stored in the keyring plugin.

.. note::

   |Percona XtraBackup| version 2.4 supports the backup of encrypted general
   tablespaces.

.. _keyring_plugin:

=======================================================
Keyring Plugins and Settings
=======================================================

To enable encryption, use either of the following plugins:

*  `keyring_file` stores the keyring data locally in a flat file

* `keyring_vault` provides an interface for the database with a HashiCorp Vault
  server to store key and secure encryption keys.

Enable only one keyring plugin at a time. Enabling multiple keyring plugins is not supported and may result in data loss.

.. note::

    The `keyring_file` plugin should not be used for regulatory compliance.

To install the selected plugin, follow the `installing and uninstalling plugins
<https://dev.mysql.com/doc/refman/8.0/en/plugin-loading.html>`_ instructions.

.. seealso::

    HashiCorp Documentation:

    `Installing Vault <https://www.vaultproject.io/docs/install/index.html>`_

    `KV Secrets Engine - Version 1 <https://www.vaultproject.io/docs/secrets/kv/kv-v1>`_

    `KV Secrets Engine - Version 2 <https://www.vaultproject.io/docs/secrets/kv/kv-v2>`_

    `Production Hardening <https://learn.hashicorp.com/vault/operations/production-hardening>`_

.. _keyring_vault_plugin:

Loading the Keyring Plugin
------------------------------------------------------------------------------

Load the plugin at server startup with the `early-plugin-load Option
<https://dev.mysql.com/doc/refman/8.0/en/server-options.html#option_mysqld_early-plugin-load>`_
to enable the keyring. To make encrypted table recovery more efficient,load the plugin with the configuration file. 

Run the following command to load the keyring_file plugin:

.. code-block:: bash

   $ mysqld --early-plugin-load="keyring_file=keyring_file.so"

.. note::

     To start a server with different early plugins to be loaded, the
     ``--early-plugin-load`` option can contain the plugin names in a
     double-quoted list with each plugin name separated by a semicolon. The
     use of double quotes ensures the semicolons do not create issues when
     the list is executed in a script.

.. _enabling-vault:

To enable Master key vault encryption, the user must have
`SUPER
<https://dev.mysql.com/doc/refman/5.7/en/privileges-provided.html#priv_super>`_
privileges.

The following statements loads the keyring_vault plugin and the `keyring_vault_config`. The second statement provides the location to the keyring_vault configuration file.

.. code-block:: guess

    [mysqld]
    early-plugin-load="keyring_vault=keyring_vault.so"
    loose-keyring_vault_config="/home/mysql/keyring_vault.conf"

Add the following statements to my.cnf:

.. code-block:: MySQL

    [mysqld]
    early-plugin-load="keyring_vault=keyring_vault.so"
    loose-keyring_value_config="/home/mysql/keyring_vault.conf"

Restart the server.

.. note::

    The keyring_vault extension, ".so", and the file location for the vault
    configuration should be changed to match your operating system's extension
    and operating system location.

.. seealso::

    `MySQL Using the HashiCorp Vault Keyring Plugin <https://dev.mysql.com/doc/mysql-security-excerpt/8.0/en/keyring-hashicorp-plugin.html>`_

Describing the keyring_vault_config file
-----------------------------------------

The `keyring_vault_config` file has the following information:

* ``vault_url`` - the Vault server address

* ``secret_mount_point`` - where the `keyring_vault` stores the keys

* ``secret_mount_point_version`` - the ``KV Secrets Engine version (kv or kv-v2)`` used. Implemented in |Percona Server| 5.7.33-36.

* ``token`` - a token generated by the Vault server

* ``vault_ca [optional]`` - if the machine does not trust the Vault's CA
  certificate, this variable points to the CA certificate used to sign the
  Vault's certificates.

The following is a configuration file example: ::

  vault_url = https://vault.public.com:8202
  secret_mount_point = secret
  secret_mount_point_version = AUTO
  token = 58a20c08-8001-fd5f-5192-7498a48eaf20
  vault_ca = /data/keyring_vault_confs/vault_ca.crt

.. warning::

    Each ``secret_mount_point`` must be used by only one server. Multiple
    servers using the same secret_mount_point may cause unpredictable behavior.

Create a backup of the keyring configuration file or data file immediately
after creating the encrypted tablespace. If you are using Master key encryption, backup before master key rotation and after master key rotation.

The first time a key is retrieved from a `keyring`, the `keyring_vault`
communicates with the Vault server to retrieve the key type and data.

secret_mount_point_version information
---------------------------------------

Implemented in |Percona Server| 5.7.33-36, the ``secret_mount_point_version`` can be either a ``1``, ``2``, ``AUTO``, or the ``secret_mount_point_version`` parameter is not listed in the configuration file. 

.. list-table::
  :widths: 10 40
  :header-rows: 1

  * - Value
    - Description
  * - 1
    - Works with ``KV Secrets Engine - Version 1 (kv)``. When forming key operation URLs, the ``secret_mount_point`` is always used without any transformations.

      For example, to return a key named ``skey``, the URL is <vault_url>/v1/<secret_mount_point>/skey
  * - 2
    - Works with ``KV Secrets Engine - Version 2 (kv)`` The initialization logic splits the ``secret_mount_point`` parameter into two parts: ``mount_point_path`` (the mount path under which the Vault Server secret was created), and ``directory_path`` (a virtual directory suffix that can be used to create virtual namespaces with the same real mount point).

      Both the ``mount_point_path`` and the ``directory_path`` are needed to form key access URLs. For example, <vault_url>/v1/<mount_point_path/data/<directory_path>/skey
  * - AUTO
    - An auto-detection mechanism probes and determines if the secrets engine version is ``kv`` or ``kv-v2`` and based on the outcome will either use the ``secret_mount_point`` as is, or split the ``secret_mount_point`` into two parts.
  * - None 
    - If the ``secret_mount_point_version`` is not set, the behavior is the same as if you had set the value to ``AUTO``. 

If you set the ``secret_mount_point_version`` to ``2`` but the path pointed by ``secret_mount_point`` is based on ``KV Secrets Engine - Version 1 (kv)``, an error is reported and the plugin fails to initialize. 

If you set the ``secret_mount_point_version`` to ``1`` but the path pointed by ``secret_mount_point`` is based on ``KV Secrets Engine - Version 2 (kv-v2)``, the plugin initialization succeeds but any MySQL keyring-related operations fail.


Upgrading from 5.7.32 or earlier to 5.7.33 or later
-----------------------------------------------------

The ``keyring_vault`` plugin configuration files created before |Percona Server| 5.7.33 work only with ``KV Secrets Engine - Version 1 (kv)`` and do not have the ``secret_mount_point_version`` parameter. After the upgrade to 5.7.33 or later, the ``secret_mount_point_version`` is implicitly considered ``AUTO`` and the information is probed and the secrets engine version is determined to ``1``.

Upgrading from Vault Secrets Engine Version 1 to Version 2 
-----------------------------------------------------------

You can upgrade from the Vault Secrets Engine Version 1 to Version 2, use either of the following methods:

* Set the ``secret_mount_point_version`` to ``AUTO`` or not set in the ``keyring_vault`` plugin configuration files in all Percona Servers. This setting ensures the auto-detection mechanism is invoked during the plugin initialization. 

* Set the ``secret_mount_point_version`` to ``2`` to ensure that plugins do not initialize unless the ``kv`` to ``kv-v2`` upgrade completes.

.. note:: the ``keyring_vault`` plugin that works with ``kv-v2`` secret engines do not use built-in key versioning capabilities. The keyring key versions are encoded into key names.

KV Secret Engine considerations for upgrading from 5.7 to 8.0 
---------------------------------------------------------------

When you upgrade from |Percona Server| 5.7.32 or older, you can only use ``KV Secrets Engine 1 (kv)``. You can upgrade to any version of |Percona Server| 8.0. Both the old ``keyring_vault`` plugin and new ``keyring_vault`` plugin work correctly with the existing Vault Server data under the existing ``keyring_vault`` plugin configuration file.

If you upgrade from |Percona Server| 5.7.33 or newer, you have the following options:

  * If you are using ``KV Secrets Engine 1 (kv)`` you can upgrade with any version of |Percona Server| 8.0.

  * If you are using ``KV Secrets Engine 2 (kv-v2)`` you can upgrade with |Percona Server| 8.0.23 or newer. |Percona Server| 8.0.23 is the first version of the 8.0 series which has the ``keyring_vault`` plugin that supports ``kv-v2``. 


System Variables
--------------------

.. variable:: keyring_vault_config

    :cli: ``--keyring-vault-config``
    :dyn: Yes
    :scope: Global
    :vartype: Text
    :default:

This variable is used to define the location of the :ref:`keyring_vault_plugin`
configuration file.

.. variable:: keyring_vault_timeout

  :cli: ``--keyring-vault-timeout``
  :dyn: Yes
  :scope: Global
  :vartype: Numeric
  :default: ``15``

Set the duration in seconds for the Vault server connection timeout. The
default value is ``15``. The allowed range is from ``0`` to ``86400``. To wait an infinite amount of time set the variable to ``0``.

Verifying the Keyring Plugin is Active
---------------------------------------

To verify the keyring plugin is active, run the `SHOW PLUGINS
<https://dev.mysql.com/doc/refman/8.0/en/show-plugins.html>`__ statement or
run a query on the `INFORMATION_SCHEMA.PLUGINS` table. You can also query the PLUGINS view.

.. code-block:: mysql

    mysql> SELECT plugin_name, plugin_status FROM INFORMATION_SCHEMA.PLUGINS WHERE plugin_name LIKE 'keyring%';

    +---------------+----------------+
    | plugin_name   | plugin_status  |
    +===============+================+
    | keyring_file  | ACTIVE         |
    +---------------+----------------+

Encrypting a File-Per-Table Tablespace
--------------------------------------

The `CREATE TABLESPACE <https://dev.mysql.com/doc/refman/5.7/en/create-tablespace.html>`_ statement is extended to allow the ``ENCRYPTION=['Y/N']`` option to encrypt a File-per-Table tablespace.

.. code-block:: mysql

    mysql> CREATE TABLE myexample (id INT mytext varchar(255)) ENCRYPTION='Y';

To enable encryption to an existing tablespace, add the ``ENCRYPTION`` option to the ``ALTER TABLE`` statement.

.. code-block:: mysql

    mysql> CREATE TABLE myexample ENCRYPTION='Y';

You must add the ``ENCRYPTION`` option to ``ALTER TABLE`` to change the table encryption state. Without the ``ENCRYPTION`` option, an encrypted table remains encrypted or an unencrypted table remains unencrypted.

Encrypting a General Tablespace
-------------------------------------------

As of :rn:`5.7.20-18`, |Percona Server| supports general tablespace encryption. You cannot partially encrypt the tables in a general tablespace. All of the tables must be encrypted or none of the tables are encrypted.

.. rubric:: Automatically Encrypting Tablespaces

Add the ``innodb_encrypt_tables`` variable to my.cnf to automatically encrypt general tablespaces. The possible values for the variable are:

.. list-table::
    :widths: 25 50
    :header-rows: 1

    * - Value
      - Description
    * - OFF
      - The default value which disables automatic encryption of new tables
    * - ON
      - Enables automatic encryption for new tables
    * - FORCE
      - New tables are automatically created with encryption. 

        Adding ``ENCRYPTION=NO`` to either a ``CREATE TABLE`` or ``ALTER TABLE`` statement results in a warning.

The `CREATE TABLESPACE <https://dev.mysql.com/doc/refman/5.7/en/create-tablespace.html>`_ statement is extended to allow the ``ENCRYPTION=['
Y/N']`` option.

.. code-block:: guess

    mysql> CREATE TABLE t1 (id INT) ENCRYPTION='Y';

To encrypt an existing table, add the `ENCRYPTION` option in the ``ALTER TABLE`` statement. 

.. code-block:: MySQL

    mysql> ALTER TABLE t1 ENCRYPTION='Y';

You can also disable encryption for a table, set the
encryption to `N`.

.. code-block:: MySQL

    mysql> ALTER TABLE t1 ENCRYPTION='N';

.. note::

    The ``ALTER TABLE`` statment modifies the current encryption mode only if
    the ``ENCRYPTION`` clause is explictily added.
    
.. rubric:: System Variables

.. variable:: innodb_encrypt_tables

   :version 5.7.21-21: Implemented
   :cli: ``--innodb-encrypt-tables``
   :dyn: Yes
   :scope: Global
   :vartype: Text
   :default: ``OFF``

:Availability: This variable is **Experimental** quality.

Encrypting Binary Logs
-----------------------

To start binlog encryption, start the server with ``-encrypt-binlog=1``. This state requires ``-master_verify_checksum`` and ``-binlog_checksum`` to be ``ON`` and one of the keyring plugins loaded.

.. note::

    These actions do not encrypt all binlogs in a replication schema. You must enable ``encrypt-binlog`` on each of the replica servers, even if they do not produce binlog files. Enabling encryption on replica servers enable relay log encryption.
    
You can rotate the encryption key used by |Percona Server| by running the
following statement:

.. code-block:: MySQL

    mysql> SELECT rotate_system_key("percona_binlog");

:Availability: The ``rotate_system_key("percona_binlog")`` command is **Experimental** quality.

This command creates a new binlog encryption key in the keyring. The new key
encrypts the next binlog file.

Temporary file encryption
-------------------------

|Percona Server| supports the encryption of temporary file storage. Users enable the encryption with ``encrypt-tmp_files``.  

The variable to enable this operation is the following:

..  code-block:: guess

    [mysqld]
    encrypt-tmp-files=ON

.. _verifying-encryption:

Verifying the Encryption Setting
----------------------------------

For single tablespaces, verify the ENCRYPTION option using
`INFORMATION_SCHEMA.TABLES` and the `CREATE OPTIONS` settings.

.. code-block:: MySQL

    mysql> SELECT TABLE_SCHEMA, TABLE_NAME, CREATE_OPTIONS FROM
           INFORMATION_SCHEMA.TABLES WHERE CREATE_OPTIONS LIKE '%ENCRYPTION%';

    +----------------------+-------------------+------------------------------+
    | TABLE_SCHEMA         | TABLE_NAME        | CREATE_OPTIONS               |
    +----------------------+-------------------+------------------------------+
    |sample                | t1                | ENCRYPTION="Y"               |
    +----------------------+-------------------+------------------------------+

A ``flag`` field in the ``INFORMATION_SCHEMA.INNODB_TABLESPACES`` has the bit
number 13 set if the tablespace is encrypted. This bit can be checked with the
``flag & 8192`` expression with the following method:

.. code-block:: mysql

    SELECT space, name, flag, (flag & 8192) != 0 AS encrypted FROM
    INFORMATION_SCHEMA.INNODB_TABLESPACES WHERE name in ('foo', 'test/t2', 'bar',
    'noencrypt');

      +-------+-----------+-------+-----------+
      | space | name      | flag  | encrypted |
      +-------+-----------+-------+-----------+
      |    29 | foo       | 10240 |      8192 |
      |    30 | test/t2   |  8225 |      8192 |
      |    31 | bar       | 10240 |      8192 |
      |    32 | noencrypt |  2048 |         0 |
      +-------+-----------+-------+-----------+
      4 rows in set (0.01 sec)

To allow for master Key rotation, you can encrypt an already encrypted InnoDB
system tablespace with a new master key by running the following ``ALTER
INSTANCE`` statement:

.. code-block:: guess

   mysql> ALTER INSTANCE ROTATE INNODB MASTER KEY;

.. seealso::

    `ALTER INSTANCE <https://dev.mysql.com/doc/refman/5.7/en/alter-instance.html>`_


Rotating the Master Key
-----------------------

For security, you should rotate the Master key in a timely manner. Use the ``ALTER INSTANCE`` statement. To rotate the key, you must have ``SUPER`` privilege. 

.. code-block:: mysql

    mysql> ALTER INSTANCE ROTATE INNODB MASTER KEY;

The statement cannot be run at the same time you run ``CREATE TABLE ... ENCRYPTION`` or ``ALTER TABLE ENCRYPTION`` statements. The ``ALTER INSTANCE`` statement uses locks to prevent conflicts. If a DML statement is running, that statement must complete before the ``ALTER INSTANCE`` statement begins.

When the Master key is rotated, the tablespace keys in that instance are re-encrypted. The operation does not re-encrypt the tablespace data. 

The re-encryption for the tablespace keys must succeed for the key rotation to be successful. If the rotation is interrupted, for example, if there is a server failure, the operation rolls forward when the server restarts. 


