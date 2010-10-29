
SET SQL_MODE="NO_AUTO_VALUE_ON_ZERO";

--
-- Database: `migrate`
--

-- --------------------------------------------------------

--
-- Table structure for table `usermap`
--

CREATE TABLE IF NOT EXISTS `usermap` (
  `broken` tinyint(1) NOT NULL default '0',
  `switch` tinyint(1) NOT NULL default '0',
  `switched` tinyint(1) NOT NULL default '0',
  `manual` tinyint(1) NOT NULL default '0',
  `migrate` tinyint(1) NOT NULL default '0',
  `migration_complete` tinyint(1) NOT NULL default '0',
  `fromhost` varchar(255) collate utf8_unicode_ci NOT NULL,
  `fromuser` varchar(255) collate utf8_unicode_ci NOT NULL,
  `fromfolder` text collate utf8_unicode_ci NOT NULL,
  `tohost` varchar(255) collate utf8_unicode_ci NOT NULL,
  `touser` varchar(255) collate utf8_unicode_ci NOT NULL,
  `topassword` varchar(255) collate utf8_unicode_ci default NULL,
  `tofolder` text collate utf8_unicode_ci NOT NULL,
  `recursive` tinyint(1) NOT NULL default '0',
  `migrating` tinyint(1) NOT NULL default '0',
  `migrated` int(11) NOT NULL default '0',
  `time_migrated` timestamp NULL default NULL,
  `duration` int(11) NOT NULL default '0',
  `fc_folder_count` int(11) NOT NULL default '0',
  `zimbra_folder_count` int(11) NOT NULL default '0',
  `fc_fcuid_count` int(11) NOT NULL default '0',
  `zimbra_fcuid_count` int(11) NOT NULL default '0',
  `missed_folders_count` int(11) NOT NULL default '0',
  `missed_fcuids_count` int(11) NOT NULL default '0',
  `account_size` int(11) NOT NULL default '0'
) ENGINE=MyISAM DEFAULT CHARSET=utf8 COLLATE=utf8_unicode_ci;