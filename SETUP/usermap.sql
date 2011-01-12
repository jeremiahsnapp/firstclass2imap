CREATE DATABASE /*!32312 IF NOT EXISTS*/ `migrate` /*!40100 DEFAULT CHARACTER SET latin1 */;

USE `migrate`;

--
-- Table structure for table `usermap`
--

DROP TABLE IF EXISTS `usermap`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `usermap` (
    `broken` tinyint(1) NOT NULL default '0',
        /*
        boolean value, manually set, identifies firstclass accounts that unavoidably break the migration process
        */
    `switch` tinyint(1) NOT NULL default '0',
        /*
        boolean value, manually set, identifies accounts that are ready for final switch over to new email system -
        this will trigger some firstclass batch admin commands that will restrict access to the firstclass account as well as
        create a redirect rule that redirects any incoming email to the new email system
        */
    `switched` tinyint(1) NOT NULL default '0',
        /*
        boolean value, automatically set, identifies accounts that have been switched over to new email system
        */
    `manual` tinyint(1) NOT NULL default '0',
        /*
        boolean value, manually set, identifies accounts that should not be automatically migrated by the migration script
        */
    `migrate` tinyint(1) NOT NULL default '0',
        /*
        boolean value, manually set, identifies accounts that should be migrated
        */
    `force_update_all_email` tinyint(1) NOT NULL default '0',
        /*
        boolean value, manually set, when set will force an update of all migrated email in the destination account
        Typically this should be left disabled
        */
    `migration_complete` tinyint(1) NOT NULL default '0',
        /*
        boolean value, automatically set, identifies accounts that have been migrated successfully
        */
    `fromuser` varchar(255) collate utf8_unicode_ci NOT NULL,
        /*
        firstclass username
        */
    `fromfolder` text collate utf8_unicode_ci NOT NULL,
        /*
        firstclass folder to be migrated, defaults to "Mailbox"
        */
    `touser` varchar(255) collate utf8_unicode_ci NOT NULL,
        /*
        new email system username
        */
    `topassword` varchar(255) collate utf8_unicode_ci default NULL,
        /*
        new email system password, defaults to empty string, shouldn't be needed in most migration scenarios
        */
    `recursive` tinyint(1) NOT NULL default '0',
        /*
        boolean value, identifies whether to migrate all subfolders
        */
    `migrating` varchar(255) collate utf8_unicode_ci default '0',
        /*
        identifies if this what FirstClass server IP address and script Instance is being used to migrate an account
        a NULL or zero value indicates the account is not being migrated
        this field is also used for the migration scripts to determine if a migration Instance is already in use
        */
    `status` text COLLATE utf8_unicode_ci,
        /*
        stores migration status message
        */
    `migrated` int(11) NOT NULL default '0',
        /*
        counts the number of times the migration process has been run for this account
        */
    `time_migrated` timestamp NULL default NULL,
        /*
        time stamp when this account was last migrated
        */
    `duration` int(11) NOT NULL default '0',
        /*
        total elapsed time in seconds spent migrating this account
        */
    `percent_complete` int(11) NOT NULL DEFAULT '0',
        /*
        percentage of total migration completed for this account
        */
    `fc_folder_count` int(11) NOT NULL default '0',
        /*
        number of folders this account has in firstclass
        */
    `destination_folder_count` int(11) NOT NULL default '0',
        /*
        number of corresponding folders this account has in new email system
        */
    `fc_fcuid_count` int(11) NOT NULL default '0',
        /*
        number of firstclass items (email, uploaded files, etc) on the firstclass server
        */
    `destination_fcuid_count` int(11) NOT NULL default '0',
        /*
        number of firstclass items (email, uploaded files, etc) found on the new email server
        */
    `missed_folders_count` int(11) NOT NULL default '0',
        /*
        number of firstclass folders that are missing on the new email server
        */
    `missed_fcuids_count` int(11) NOT NULL default '0',
        /*
        number of firstclass items (email, uploaded files, etc) that are missing on the new email server
        */
    `account_size` int(11) NOT NULL default '0'
        /*
        size of firstclass account in kb
        */
) ENGINE=MyISAM DEFAULT CHARSET=utf8 COLLATE=utf8_unicode_ci;

CREATE USER 'migrate'@'localhost' IDENTIFIED BY 'password';
GRANT SELECT, INSERT, UPDATE, DELETE ON *.* TO 'migrate'@'localhost' IDENTIFIED BY 'password';

