CREATE DATABASE /*!32312 IF NOT EXISTS*/ `migrate` /*!40100 DEFAULT CHARACTER SET latin1 */;

USE `migrate`;

--
-- Table structure for table `usermap`
--

DROP TABLE IF EXISTS `usermap`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `usermap` (
  `broken` tinyint(1) NOT NULL DEFAULT '0',
  `switch` tinyint(1) NOT NULL DEFAULT '0',
  `switched` tinyint(1) NOT NULL DEFAULT '0',
  `manual` tinyint(1) NOT NULL DEFAULT '0',
  `migrate` tinyint(1) NOT NULL DEFAULT '0',
  `migration_complete` tinyint(1) NOT NULL DEFAULT '0',
  `fromuser` varchar(255) COLLATE utf8_unicode_ci NOT NULL,
  `fromfolder` text COLLATE utf8_unicode_ci NOT NULL,
  `touser` varchar(255) COLLATE utf8_unicode_ci NOT NULL,
  `topassword` varchar(255) COLLATE utf8_unicode_ci DEFAULT NULL,
  `recursive` tinyint(1) NOT NULL DEFAULT '0',
  `migrating` varchar(255) COLLATE utf8_unicode_ci NOT NULL DEFAULT '0',
  `migrated` int(11) NOT NULL DEFAULT '0',
  `time_migrated` timestamp NULL DEFAULT NULL,
  `duration` int(11) NOT NULL DEFAULT '0',
  `percent_complete` int(11) NOT NULL DEFAULT '0',
  `fc_folder_count` int(11) NOT NULL DEFAULT '0',
  `destination_folder_count` int(11) NOT NULL DEFAULT '0',
  `fc_fcuid_count` int(11) NOT NULL DEFAULT '0',
  `destination_fcuid_count` int(11) NOT NULL DEFAULT '0',
  `missed_folders_count` int(11) NOT NULL DEFAULT '0',
  `missed_fcuids_count` int(11) NOT NULL DEFAULT '0',
  `account_size` int(11) NOT NULL DEFAULT '0'
) ENGINE=MyISAM DEFAULT CHARSET=utf8 COLLATE=utf8_unicode_ci;

CREATE USER 'migrate'@'localhost' IDENTIFIED BY 'password';
GRANT SELECT, INSERT, UPDATE, DELETE ON *.* TO 'migrate'@'localhost' IDENTIFIED BY 'password';
