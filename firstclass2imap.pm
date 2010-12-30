package firstclass2imap;

use warnings;
use strict;

use DBI;
use Data::Dumper;
use File::Copy;
use File::Basename;

use Email::Send;

use Mail::Message;
use Mail::Box::Manager;
use Mail::IMAPClient;
use MIME::Base64;
use MIME::Types;
use List::Compare;
use Date::Parse;
use Date::Manip;

my $dry_run = 0;
my $debugimap = 0;
my $to_imaps = 1;
my $to_authuser = 'admin';
my $to_authuser_password = 'password';
my $dataDir = "/home/migrate/Maildir/.ba_rcvd_1/";
my $timeout = 300;
my $searchString = "BA Migrate Script 1: ";
my $max_export_script_size = 20000;
my $migrate_user = "migrate";
my $migrate_password = "migrate";
my $migrate_email_address = 'migrate@migrate.schoolname.edu';
my $fc_admin_email_address = 'administrator@schoolname.edu';
my $fromhost = '192.168.1.24';
my $migratehost = '192.168.1.6';

sub initialize {
	my ($my_dataDir, $my_timeout, $my_searchString, $my_migrate_user, $my_migrate_password, $my_max_export_script_size, $my_dry_run, $my_debugimap, $my_to_imaps, $my_to_authuser, $my_to_authuser_password, $my_migrate_email_address, $my_fc_admin_email_address, $my_fromhost, $my_migratehost) = @_;

	$dataDir = $my_dataDir;
	$timeout = $my_timeout;
	$searchString = $my_searchString;
	$max_export_script_size = $my_max_export_script_size;
	$dry_run = $my_dry_run;
	$debugimap = $my_debugimap;
	$to_imaps = $my_to_imaps;
	$to_authuser = $my_to_authuser;
	$to_authuser_password = $my_to_authuser_password;
	$migrate_user = $my_migrate_user;
	$migrate_password = $my_migrate_password;
	$migrate_email_address = $my_migrate_email_address;
	$fc_admin_email_address = $my_fc_admin_email_address;
	$fromhost = $my_fromhost;
	$migratehost = $my_migratehost;
}

sub migrate_folder_structure {
	my($fromuser, $fromfolder, $tohost, $touser, $topassword, $tofolder, $recursive, $delete_from_destination) = @_;

	print print_timestamp() . " : Start Migrating Folder Structure for Account: $fromuser with" . ($delete_from_destination?" ":"out ") . "deletion from destination\n";

	my($fc_total_folders, $imap_created_folders, $imap_deleted_folders, $imap_total_folders) = (0, 0, 0, 0);
	
	my $starttime = time();
	my $lasttime = $starttime;
	my $elapsed_time = "";

	my @from_folders_list;

	my($successful, $fc_folder_exists) = fc_folder_exists($fromuser, $fromfolder);

	if (!$successful) {
		($elapsed_time, $lasttime) = elapsed_time($starttime);
		print print_timestamp() . " : Failed to Determine Whether Folder: $fromfolder exists in Account: $fromuser\n";
		print print_timestamp() . " : Failed to Migrate Folder Structure for Account: $fromuser\n";
		return 0;
	}
	if (!$fc_folder_exists) {
		($elapsed_time, $lasttime) = elapsed_time($starttime);
		print print_timestamp() . " : Folder: $fromfolder does NOT exist in Account: $fromuser\n";
		print print_timestamp() . " : Failed to Migrate Folder Structure for Account: $fromuser\n";
		return 0;
	}
	push (@from_folders_list, $fromfolder);
	if ($recursive) {
		my($failed, @temp_from_folders) = get_fixed_fc_subfolders($fromuser, $fromfolder);
		if ($failed) {
			($elapsed_time, $lasttime) = elapsed_time($starttime);
			print print_timestamp() . " : Failed to get subfolders for Account: $fromuser\n";
			print print_timestamp() . " : Failed to Migrate Folder Structure for Account: $fromuser\n";
			return 0;
		}
		push(@from_folders_list, @temp_from_folders);
	}
        # this code is capable of removing folders from the list of folders to be migrated
        # we don't really need this now but the code will be kept in case of future need
#        @from_folders_list = grep(!/^mailbox$/i, @from_folders_list);

	my(@from_folders_list_converted);
	foreach my $from_folder (@from_folders_list) {
		push (@from_folders_list_converted, convert_folder_names_fc_to_imap($from_folder));
	}

	my(@to_folders_list) = get_imap_folders_list($tohost, $touser, $topassword, $tofolder, $recursive);

	if (!@to_folders_list) {
		print print_timestamp() . " : Failed to get list of destination folders for Account: $touser\n";
		print print_timestamp() . " : Failed to Migrate Folder Structure for Account: $fromuser\n";
		return 0;
	}

	my($lc) = List::Compare->new('-i', \@from_folders_list_converted, \@to_folders_list);

        my $imap = create_imap_client($tohost, $touser, $topassword, $debugimap);

	foreach my $imap_folder (sort({ lc($a) cmp lc($b) } $lc->get_Lonly)) {
		print print_timestamp() . " : Creating Folder: $imap_folder\n";

		if ($dry_run) { next; }

		if ($imap->create($imap_folder)) {
			$imap_created_folders++;
			print print_timestamp() . " : Created Folder: $imap_folder\n";
		}
		else {
			($elapsed_time, $lasttime) = elapsed_time($starttime);
			print print_timestamp() . " : Failed to Create Folder: $imap_folder\n";
			print print_timestamp() . " : Failed to Migrate Folder Structure for Account: $fromuser\n";
			return 0;
		}
	} 

	if ($delete_from_destination) {
		foreach my $imap_folder (sort({ lc($b) cmp lc($a) } $lc->get_Ronly)) {
			print print_timestamp() . " : Deleting Folder: $imap_folder\n";

			if ($dry_run) { next; }

			if ($imap->delete($imap_folder)) {
				$imap_deleted_folders++;
				print print_timestamp() . " : Deleted Folder: $imap_folder\n";
			}
			else {
				print print_timestamp() . " : Failed to Delete Folder: $imap_folder\n";
			}
		}
	}

	$imap->close();

	$fc_total_folders = @from_folders_list;

	@to_folders_list = get_imap_folders_list($tohost, $touser, $topassword, $tofolder, $recursive);
	$imap_total_folders = @to_folders_list;

	$lc = List::Compare->new('-i', \@from_folders_list_converted, \@to_folders_list);
	my @missed_folders = $lc->get_Lonly;
	my $missed_folders_count = @missed_folders;

        print print_timestamp() . " : Sync Report for $fromuser\'s Folder Structure: \n";
        print "\t\t\t FC    \t  IMAP\n";
        print "Created Folders: \t\t    " . $imap_created_folders . "\n";
        print "Deleted Folders: \t\t    " . $imap_deleted_folders . "\n";
        print "Total Folders: \t\t " . $fc_total_folders . "\t   " . $imap_total_folders . "\n";

	if ($missed_folders_count) {
		print $missed_folders_count . " FirstClass folder(s) did NOT successfully migrate to destination\n";
	}
	else {
		print "All of FirstClass's folder structure has successfully been migrated to destination\n";
	}

	($elapsed_time, $lasttime) = elapsed_time($starttime);
	print print_timestamp() . " : Finished Migrating Folder Structure for Account: $fromuser in $elapsed_time\n";

	return (1, $fc_total_folders, $imap_total_folders, \@missed_folders);
}

sub migrate_folders {
	my($fromuser, $fromfolder, $tohost, $touser, $topassword, $tofolder, $recursive, $delete_from_destination, $force_update_all_email) = @_;

	print print_timestamp() . " : Start Migrating Folders for Account: $fromuser\n";

	my $starttime = time();
	my $lasttime = $starttime;
	my $elapsed_time = "";

	my($account_missed_fcuids_count, $dir_account_skip, $dir_account_append, $dir_account_delete, $dir_account_update, $dir_account_total_fcuids) = (0, 0, 0, 0, 0, 0);
	my($imap_account_skip, $imap_account_append, $imap_account_delete, $imap_account_update, $imap_account_total_fcuids) = (0, 0, 0, 0, 0);
	my($account_total_size, $account_total_size_to_be_migrated) = (0, 0);
	my %missed_fcuids;

	my @from_folders_list;

	my($successful, $fc_folder_exists) = fc_folder_exists($fromuser, $fromfolder);

	if (!$successful) {
		($elapsed_time, $lasttime) = elapsed_time($starttime);
		print print_timestamp() . " : Failed to Determine Whether Folder: $fromfolder exists in Account: $fromuser\n";
		print print_timestamp() . " : Failed to Migrate Folders for Account: $fromuser\n";
		return (0, $dir_account_total_fcuids, $imap_account_total_fcuids);
	}
	if (!$fc_folder_exists) {
		($elapsed_time, $lasttime) = elapsed_time($starttime);
		print print_timestamp() . " : Folder: $fromfolder does NOT exist in Account: $fromuser\n";
		print print_timestamp() . " : Failed to Migrate Folders for Account: $fromuser\n";
		return (0, $dir_account_total_fcuids, $imap_account_total_fcuids);
	}
	push (@from_folders_list, $fromfolder);
	if ($recursive) {
		my($failed, @temp_from_folders) = get_fixed_fc_subfolders($fromuser, $fromfolder);
		if ($failed) {
			($elapsed_time, $lasttime) = elapsed_time($starttime);
			print print_timestamp() . " : Failed to get subfolders for Account: $fromuser\n";
			print print_timestamp() . " : Failed to Migrate Folders for Account: $fromuser\n";
			return (0, $dir_account_total_fcuids, $imap_account_total_fcuids);
		}
		push(@from_folders_list, @temp_from_folders);
	}
        # this code is capable of removing folders from the list of folders to be migrated
        # we don't really need this now but the code will be kept in case of future need
#        @from_folders_list = grep(!/^mailbox$/i, @from_folders_list);

	($elapsed_time, $lasttime) = elapsed_time($lasttime);
	print print_timestamp() . " : Elapsed Time: $elapsed_time\n";

	foreach my $fc_folder (@from_folders_list) {
		my $imap_folder = convert_folder_names_fc_to_imap($fc_folder);

		print print_timestamp() . " : Start Migrating Folder: $imap_folder with" . ($delete_from_destination?" ":"out ") . "deletion from destination\n";

		my($folder_missed_fcuids_count, $dir_folder_skip, $dir_folder_append, $dir_folder_delete, $dir_folder_update, $dir_folder_total_fcuids) = (0, 0, 0, 0, 0, 0);
		my($imap_folder_skip, $imap_folder_append, $imap_folder_delete, $imap_folder_update, $imap_folder_total_fcuids) = (0, 0, 0, 0, 0);

                # create a list @imap_fcuid_list of FC-UNIQUE-ID's and Message-ID's for
                # each message in user's destination IMAP folder
		my $imap_fcuid_msgid = get_imap_fcuid_msgid_hash($tohost, $touser, $topassword, $imap_folder);

		my ($successful, $export_filter_date_ranges, $days_skipped, $folder_total_size, $folder_total_size_to_be_migrated, $sync_fcuids) =
			get_export_filter_date_ranges($max_export_script_size, $fromuser, $fc_folder, $tohost, $touser, $topassword, $imap_folder, $imap_fcuid_msgid, $force_update_all_email);

		if (!$successful) {
			($elapsed_time, $lasttime) = elapsed_time($starttime);
			print print_timestamp() . " : Failed to Migrate Folders for Account: $fromuser\n";
			return (0, $dir_account_total_fcuids, $imap_account_total_fcuids);
		}

		$account_total_size += $folder_total_size;
		$account_total_size_to_be_migrated += $folder_total_size_to_be_migrated;

		my @dir_fcuids = ();
		foreach my $fcuid (keys(%$sync_fcuids)) {
			$dir_folder_skip++ if ($sync_fcuids->{$fcuid}->{'action'} eq "skip");
			$dir_folder_append++ if ($sync_fcuids->{$fcuid}->{'action'} eq "append");
			$dir_folder_delete++ if ( $delete_from_destination && ($sync_fcuids->{$fcuid}->{'action'} eq "delete") );
			$dir_folder_update++ if ($sync_fcuids->{$fcuid}->{'action'} eq "update");
			push(@dir_fcuids, $fcuid);
		}

		$dir_folder_total_fcuids = $dir_folder_skip + $dir_folder_append + $dir_folder_update;

	    if ($dir_folder_append || $dir_folder_delete || $dir_folder_update) {

#		Make sure all email in the migrate account's inbox is deleted
		print print_timestamp() . " : Deleting all email from the temporary $migrate_user account.\n";

		my $mgr  = Mail::Box::Manager->new;
		my $pop_mailbox = $mgr->open(type => 'pop3', username => $migrate_user, password => $migrate_password, server_name => $fromhost);
		foreach my $msg ($pop_mailbox->messages) {
			$msg->delete;
			print ".";
		}
		my($pop_mailbox_size) = $pop_mailbox->size || 0;
		$pop_mailbox->close(write => 'NEVER');

		print "\n" . print_timestamp() . " : Finished Deleting all email from the temporary $migrate_user account.\n";

		if ($pop_mailbox_size == 0) {
			my $attachments = {};
			foreach my $daterange (@$export_filter_date_ranges) {
				my ($startdate, $enddate, $size) = @$daterange;

				print print_timestamp() . " : Start populating the migrate's inbox with email from Folder: \"$imap_folder\" for Date Range: \"$startdate\" to \"$enddate\" with Size: $size KB.\n";

				my($matching_file_arrived, $matching_filename) = request_ba_import_script($fromuser, $fc_folder, $startdate, $enddate);

				if (!$matching_file_arrived) {
					print print_timestamp() . " : Did NOT receive the emailed results of the request_ba_import_script.\n";
					next;
				}
				else {
					my($content_type, $processed_ba_import_script);
					($content_type, $processed_ba_import_script, $attachments) = process_ba_import_script($matching_filename);

					my($ba_script_subject) = $searchString . "Processed Import Script for User: $fromuser for Folder: $fc_folder for Date Range:  $startdate - $enddate";

					email_to_batch_admin($ba_script_subject, $processed_ba_import_script, $content_type);

				        my ($matching_file_arrived, $matching_filename) = wait_for_matching_file_arrival ($dataDir, $searchString, $timeout);

					if (!$matching_file_arrived) {
						print print_timestamp() . " : Did NOT receive the completion notice for populating the migrate's inbox with email from Folder: \"$imap_folder\" for Date Range: \"$startdate\" to \"$enddate\" with Size: $size KB.\n";
						next;
					}
					else {
						print print_timestamp() . " : Finished populating the migrate's inbox with email from Folder: \"$imap_folder\" for Date Range: \"$startdate\" to \"$enddate\" with Size: $size KB.\n";
					}
				}
			}
			print print_timestamp() . " : Start syncing email.\n";
			($imap_folder_skip, $imap_folder_append, $imap_folder_delete, $imap_folder_update) = dir_imap_sync($fromuser, $tohost, $touser, $topassword, $imap_folder, $sync_fcuids, $imap_fcuid_msgid, $attachments, $delete_from_destination);
			print print_timestamp() . " : Finished syncing email.\n";
		}
	    }

		my $imap = create_imap_client($tohost, $touser, $topassword, $debugimap);

		$imap->select($imap_folder);

		my $hash_ref = $imap->fetch_hash("BODY[HEADER.FIELDS (FC-UNIQUE-ID)]");

		my @imap_fcuids = ();
        	foreach my $uid (keys(%$hash_ref)) {
                        if ( $hash_ref->{$uid}->{"BODY[HEADER.FIELDS (FC-UNIQUE-ID)]"} =~ /FC-UNIQUE-ID:\s*(.*?)\s*$/ ) {
                                push(@imap_fcuids, $1);
                                $imap_folder_total_fcuids++;
                        }
	        }
		$imap->close;

		my($lc) = List::Compare->new(\@dir_fcuids, \@imap_fcuids);
		$folder_missed_fcuids_count = $lc->get_Lonly;

		my @folder_missed_fcuids = ();
		foreach my $fcuid ($lc->get_Lonly) {
			if ( ($sync_fcuids->{$fcuid}->{'date'} ne "") && ($sync_fcuids->{$fcuid}->{'time'} ne "") ) {

				# chat transcripts in First Class are handled strangely by batch admin commands which causes the migration process to
				# expect them to be migrated but the actual migration is impossible
				# batch admin dir command lists a chat transcript as a leaf item but in the dir command's summary it seems that it might be seeing it as a folder
				# batch admin export command does not include chat transcripts at all for some reason which is why it is impossible for them to be migrated
				# the following line of code allows the migration report to ignore the chat transcripts so we can report 100% successful migration
				# this is done here because the only way to test for a chat transcript is to see if it's subject line matches "Private Chat transcript"
				# since other legitimate items might have that subject line I decided to attempt the migration first and then ignore any unsuccessfully migrated items with "Private Chat transcript" as the subject line
				if ($sync_fcuids->{$fcuid}->{'subject'} eq "Private Chat transcript") {next;}

				push( @folder_missed_fcuids, $sync_fcuids->{$fcuid});
			}
		}
		if (@folder_missed_fcuids) { $missed_fcuids{$fc_folder} = \@folder_missed_fcuids; }

		$account_missed_fcuids_count += $folder_missed_fcuids_count;
		$dir_account_skip += $dir_folder_skip;
		$dir_account_append += $dir_folder_append;
		$dir_account_delete += $dir_folder_delete;
		$dir_account_update += $dir_folder_update;
		$dir_account_total_fcuids += $dir_folder_total_fcuids;

		$imap_account_skip += $imap_folder_skip;
		$imap_account_append += $imap_folder_append;
		$imap_account_delete += $imap_folder_delete;
		$imap_account_update += $imap_folder_update;
		$imap_account_total_fcuids += $imap_folder_total_fcuids;

		print print_timestamp() . " : Sync Report for $fromuser\'s \"$imap_folder\" folder: \n";
		print "Total size of Folder: \"$imap_folder\" content is: $folder_total_size KB.\n";
		print "Total size of Folder: \"$imap_folder\" content to be migrated is: $folder_total_size_to_be_migrated KB.\n";
		print "\t\t\tFC-DIR \t  IMAP\n";
		print "Skip: \t\t\t $dir_folder_skip\n";
		print "Append: \t\t $dir_folder_append \t    $imap_folder_append\n";
		print "Delete: \t\t $dir_folder_delete \t    $imap_folder_delete\n";
		print "Update: \t\t $dir_folder_update \t    $imap_folder_update\n";
		print "Total FC-UID's: \t $dir_folder_total_fcuids \t    $imap_folder_total_fcuids\n";

		if ( $folder_missed_fcuids_count ) {
			print $folder_missed_fcuids_count . " FC-UNIQUE-ID('s) in FC's folder did NOT successfully migrate to the destination folder.\n";
		}
		foreach my $daterange (@$days_skipped) {
			my ($skippeddate, $size) = @$daterange;
			print "Skipped email in Folder: \"$imap_folder\" from: $skippeddate because the size $size KB is too large.\n";
		}
		print "End of Report for $fromuser\'s \"$imap_folder\" folder.\n";

		($elapsed_time, $lasttime) = elapsed_time($lasttime);
		print print_timestamp() . " : Finished Migrating Folder: $imap_folder in $elapsed_time\n";
	}

	print print_timestamp() . " : Sync Report for all of $fromuser\'s folders: \n";
	print "Total size of $fromuser\'s account is: $account_total_size KB.\n";
	print "Total size of $fromuser\'s account content to be migrated is: $account_total_size_to_be_migrated KB.\n";
	print "\t\t\tFC-DIR \t  IMAP\n";
	print "Skip: \t\t\t $dir_account_skip \n";
	print "Append: \t\t $dir_account_append \t    $imap_account_append\n";
	print "Delete: \t\t $dir_account_delete \t    $imap_account_delete\n";
	print "Update: \t\t $dir_account_update \t    $imap_account_update\n";
	print "Total FC-UID's: \t $dir_account_total_fcuids \t    $imap_account_total_fcuids\n";

	if ( $account_missed_fcuids_count ) {
		print $account_missed_fcuids_count . " FC-UNIQUE-ID('s) in FC's account did NOT successfully migrate to the destination account.\n";
	}
	print "End of Report for all of $fromuser\'s folders.\n";

	($elapsed_time, $lasttime) = elapsed_time($starttime);
	print print_timestamp() . " : Finished Migrating Folders for Account: $fromuser in $elapsed_time\n";

	return (1, $dir_account_total_fcuids, $imap_account_total_fcuids, \%missed_fcuids);
}

sub dir_imap_sync {
	my ($fromuser, $tohost, $touser, $topassword, $tofolder, $sync_fcuids, $imap_fcuid_msgid, $attachments, $delete_from_destination) = @_;

	my($imap_folder_skip, $imap_folder_append, $imap_folder_delete, $imap_folder_update) = (0, 0, 0, 0);

	my $imap = create_imap_client($tohost, $touser, $topassword, $debugimap);
	my $mgr  = Mail::Box::Manager->new;

	my $pop_mailbox = $mgr->open(type => 'pop3', username => $migrate_user, password => $migrate_password, server_name => $fromhost);

	my $imap_mailbox = $mgr->open(type => 'imap', imap_client => $imap, folder => $tofolder, access => 'rw');

        my(%pop_fcuids_msgids_hash);
        foreach my $msg ($pop_mailbox->messages) {
                if ( $msg->get('FC-UNIQUE-ID') ) {
                        $pop_fcuids_msgids_hash{$msg->get('FC-UNIQUE-ID')}{'msgid'} = $msg->messageId;
                        $pop_fcuids_msgids_hash{$msg->get('FC-UNIQUE-ID')}{'date'} = $msg->get('Date');
                }
        }

	foreach my $fcuid (sort { if (($sync_fcuids->{$a}->{'action'} ne "delete") && ($sync_fcuids->{$b}->{'action'} ne "delete")) {str2time($sync_fcuids->{$a}->{'date'} . " " . $sync_fcuids->{$a}->{'time'}) <=> str2time($sync_fcuids->{$b}->{'date'} . " " . $sync_fcuids->{$b}->{'time'})} } (keys(%$sync_fcuids))) {

		if ($delete_from_destination && ($sync_fcuids->{$fcuid}->{'action'} eq "delete") ) {
			print print_timestamp() . " : IMAP Deleting from Folder: \"$tofolder\" \t Email: " . $fcuid . "\t" . $imap_fcuid_msgid->{$fcuid}->{'datetime'} . "\n";

			if ($dry_run) { next; }

			foreach my $msg ($imap_mailbox->messages) {
				if ($msg->messageId eq $imap_fcuid_msgid->{$fcuid}->{'msgid'}) {
					$msg->delete;
					$imap_folder_delete++;
					print print_timestamp() . " : IMAP Deleted from Folder: \"$tofolder\" \t Email: " . $fcuid . "\t" . $imap_fcuid_msgid->{$fcuid}->{'datetime'} . "\n";
				}
			}
		}
		if ($sync_fcuids->{$fcuid}->{'action'} eq "append") {
			print print_timestamp() . " : IMAP Appending to Folder: \"$tofolder\" \t Email: " . $fcuid . "\t" . $sync_fcuids->{$fcuid}->{'date'} . " " . $sync_fcuids->{$fcuid}->{'time'} . "\n";

			if ($dry_run) { next; }

			if (defined($pop_fcuids_msgids_hash{$fcuid}) && $pop_mailbox->find($pop_fcuids_msgids_hash{$fcuid}{"msgid"})) {
				my $pop_msg = $pop_mailbox->find($pop_fcuids_msgids_hash{$fcuid}{"msgid"})->string;

				# First Class's POP3 implementation truncates the name of any email attachment if the attachment's name length exceeds 31 characters
				# the following 'if' block makes sure that all email attachments are properly named
				foreach my $attachment_number ( keys %{$attachments->{ $fcuid }} ) {
					my $attachment_name = qq|$attachments->{ $fcuid }{ $attachment_number }|;

					# At some point when First Class generates the import script and emails the script
					# to the migration server some of the attachments lose their appropriate mime types
					# the following code makes sure the best available mime type is chosen
					my ($mediatype, $encoding) = MIME::Types::by_suffix($attachment_name);
					if ($mediatype eq "") {
						if ( ($pop_msg =~ /Content-Type:\s*(\S*)\s*name="$attachment_number"/) && ($1 ne "") ) {
							$mediatype = $1;
						}
						else {
							$mediatype = "application/octet-stream";
						}
					}

					# the MIME::Type module returns "x-msword" for ".doc" attachments but destination won't recognize that and
					# put the appropriate icon next to the attachment so we substitute "msword" for "x-msword"
					$mediatype =~ s/\/x-msword$/\/msword/g;

                                        if ( $pop_msg =~ s/Content-Type:\s*(\S*)\s*name="$attachment_number"(.*)/Content-Type: $mediatype; "$attachment_name"$2/g ) {
                                                $pop_msg =~ s/(Content-Disposition:.*filename=")$attachment_number"/$1$attachment_name"/g;
                                        }
				}

				if ($imap->append_string("$tofolder", 
					$pop_msg, '\Seen', 
					UnixDate(ParseDateString("epoch " . str2time($sync_fcuids->{$fcuid}->{'date'} . " " . $sync_fcuids->{$fcuid}->{'time'})),'%d-%b-%Y %T %z'))) {

					$imap_folder_append++;
					print print_timestamp() . " : IMAP Appended to Folder: \"$tofolder\" \t Email: " . $fcuid . "\t" . $sync_fcuids->{$fcuid}->{'date'} . " " . $sync_fcuids->{$fcuid}->{'time'} . "\n";
				}
				else {
					print print_timestamp() . " : IMAP Failed to Append to Folder: \"$tofolder\" \t Email: " . $fcuid . "\t" . $sync_fcuids->{$fcuid}->{'date'} . " " . $sync_fcuids->{$fcuid}->{'time'} . "\n";
				}
			}
		}
		if ($sync_fcuids->{$fcuid}->{'action'} eq "update") {
			print print_timestamp() . " : IMAP Updating in Folder: \"$tofolder\" \t Email: " . $fcuid . "\t" . $sync_fcuids->{$fcuid}->{'date'} . " " . $sync_fcuids->{$fcuid}->{'time'} . "\t" . $imap_fcuid_msgid->{$fcuid}->{'datetime'} . "\n";

			if ($dry_run) { next; }

			if (defined($pop_fcuids_msgids_hash{$fcuid}) && $pop_mailbox->find($pop_fcuids_msgids_hash{$fcuid}{"msgid"})) {
				if (defined($imap_fcuid_msgid->{$fcuid}->{"msgid"})) {
					foreach my $msg ($imap_mailbox->messages) {
						if ($msg->messageId eq $imap_fcuid_msgid->{$fcuid}->{"msgid"}) {
							$msg->delete;
							last;
						}
					}
				}
				my $pop_msg = $pop_mailbox->find($pop_fcuids_msgids_hash{$fcuid}{"msgid"})->string;

				# First Class's POP3 implementation truncates the name of any email attachment if the attachment's name length exceeds 31 characters
				# the following 'if' block makes sure that all email attachments are properly named
				foreach my $attachment_number ( keys %{$attachments->{ $fcuid }} ) {
					my $attachment_name = qq|$attachments->{ $fcuid }{ $attachment_number }|;

					# At some point when First Class generates the import script and emails the script
					# to the migration server some of the attachments lose their appropriate mime types
					# the following code makes sure the best available mime type is chosen
					my ($mediatype, $encoding) = MIME::Types::by_suffix($attachment_name);
					if ($mediatype eq "") {
						if ( ($pop_msg =~ /Content-Type:\s*(\S*)\s*name="$attachment_number"/) && ($1 ne "") ) {
							$mediatype = $1;
						}
						else {
							$mediatype = "application/octet-stream";
						}
					}

					# the MIME::Type module returns "x-msword" for ".doc" attachments but destination won't recognize that and
					# put the appropriate icon next to the attachment so we substitute "msword" for "x-msword"
					$mediatype =~ s/\/x-msword$/\/msword/g;

                                        if ( $pop_msg =~ s/Content-Type:\s*(\S*)\s*name="$attachment_number"(.*)/Content-Type: $mediatype; "$attachment_name"$2/g ) {
                                                $pop_msg =~ s/(Content-Disposition:.*filename=")$attachment_number"/$1$attachment_name"/g;
                                        }
				}

				if ($imap->append_string("$tofolder", 
					$pop_msg, '\Seen',
					UnixDate(ParseDateString("epoch " . str2time($sync_fcuids->{$fcuid}->{'date'} . " " . $sync_fcuids->{$fcuid}->{'time'})),'%d-%b-%Y %T %z'))) {

					$imap_folder_update++;
					print print_timestamp() . " : IMAP Updated in Folder: \"$tofolder\" \t Email: " . $fcuid . "\t" . $sync_fcuids->{$fcuid}->{'date'} . " " . $sync_fcuids->{$fcuid}->{'time'} . "\t" . $imap_fcuid_msgid->{$fcuid}->{'datetime'} . "\n";
				}
				else {
					print print_timestamp() . " : IMAP Failed to Update in Folder: \"$tofolder\" \t Email: " . $fcuid . "\t" . $sync_fcuids->{$fcuid}->{'date'} . " " . $sync_fcuids->{$fcuid}->{'time'} . "\t" . $imap_fcuid_msgid->{$fcuid}->{'datetime'} . "\n";
				}
			}
		}
	}
	$pop_mailbox->close;
	$imap_mailbox->close;

	return ($imap_folder_skip, $imap_folder_append, $imap_folder_delete, $imap_folder_update);
}

#---------------------------Actual Processing of Batch Admin Scripts-----------------------------------

sub fc_folder_exists {
	my ($fromuser, $fromfolder) = @_;

        my($ba_script_subject) = $searchString . "Does User: $fromuser Folder: $fromfolder exist?";

        my @ba_script_body = "REPLY\n";

        push (@ba_script_body, "IF OBJECT DESKTOP $fromuser \"$fromfolder\" EXISTS\n");
	push (@ba_script_body, "\tWRITE $fromfolder EXISTS: True\nELSE\n\tWRITE $fromfolder EXISTS: False\nENDIF\n");

        email_to_batch_admin ($ba_script_subject, \@ba_script_body);

        my ($matching_file_arrived, $matching_filename) = wait_for_matching_file_arrival ($dataDir, $searchString, $timeout);

        if ($matching_file_arrived) {
                open(FH, $matching_filename);
                my @exists = <FH>;
                close(FH);

		if (grep(/$fromfolder EXISTS: True/, @exists)) {
			return (1, 1);
		}
		else {
			return (1, 0);
		}
	}
	else {
		return (0, 0);
	}
}

sub convert_folder_names_fc_to_imap {
        my($fc_folder) = @_;

        $fc_folder =~ s/:\s+/:/;                # remove leading whitespace in a first class folder's name since destination folder names don't allow for it
        $fc_folder =~ s/^\s+//;                 # remove leading whitespace in a first class folder's name since destination folder names don't allow for it
        $fc_folder =~ s/\s+:/:/;                # remove trailing whitespace in a first class folder's name since destination folder names don't allow for it
        $fc_folder =~ s/\s+$//;                 # remove trailing whitespace in a first class folder's name since destination folder names don't allow for it
        $fc_folder =~ s/\s{2,}/ /g;             # this just collapses multiple whitespace characters down to a single space since some (or all) imap doesn't like multiple spaces in a folder name

        $fc_folder =~ s/&/&-/g;                 # enables &'s to be used in folder names
        $fc_folder =~ s/\//\\/g;
        $fc_folder =~ s/:/\//g;                 # First Class uses ':' in a folder path but destination uses '/' so we make the conversion here
        $fc_folder =~ s/\/\\/\//g;
#        $fc_folder =~ s/\\/\\\\/g;
        $fc_folder =~ s/\?/\|/g;

       # FC folder 'Mailbox' maps to imap folder 'INBOX'

        $fc_folder =~ s/^.*?(?=\/)|.*/INBOX/;  # replace the first folder name with "INBOX"

       # FC folder subfolder 'Mailbox:AAA' maps to imap folder 'AAA' a subfolder of root
       # FC folder subfolder 'Mailbox:AAA:BBB' maps to imap folder 'AAA/BBB'

        $fc_folder =~ s/^INBOX\///i;

        return $fc_folder;
}

sub get_fixed_fc_subfolders {
	my ($fromuser, $fromfolder) = @_;
	my %item_names;
	my %aliases;
	my @folders;
	my $failed = 0;

        my($ba_script_subject) = $searchString . "DIR of User: $fromuser Folder: $fromfolder";

        my @ba_script_body = "REPLY\n";

        push (@ba_script_body, "DIR DESKTOP $fromuser \"$fromfolder\" +lbpsdr\n");

        email_to_batch_admin ($ba_script_subject, \@ba_script_body);

        my ($matching_file_arrived, $matching_filename) = wait_for_matching_file_arrival ($dataDir, $searchString, $timeout);

        if ($matching_file_arrived) {
#      	        print print_timestamp() . " : Found: $matching_filename\n";

		open(FH, $matching_filename);
		my @dir = <FH>;
		close(FH);

		@ba_script_body = "REPLY\n";

		foreach my $dir (@dir) {
			if ( ($dir =~ /\[B:(\d+)\]/) && ($1 ne "") ) {
				push (@ba_script_body, "WRITE FC-INDEX: $1\n");
				push (@ba_script_body, "get properties byindex $1 desktop $fromuser \"$fromfolder\" 1020\n");
			}
		}

	        email_to_batch_admin ($ba_script_subject, \@ba_script_body);
	        my ($matching_file_arrived, $matching_filename) = wait_for_matching_file_arrival ($dataDir, $searchString, $timeout);

        	if ($matching_file_arrived) {
			open(FH, $matching_filename);
			while (<FH>) {
				if ( (/FC-INDEX: (\d+)/) && ($1 ne "") ) {
					my $idx = $1;
					if ( (<FH> =~ /1020 \d+ \"\[.*\] $fromuser.*\"/i) ) {
						$aliases{$idx} = 0;
					}
					else {
						$aliases{$idx} = 1;
					}
				}
			}
			close(FH);
		}
		else {
			print print_timestamp() . " : Failed to Get Aliases Report for $fromuser\'s Folder: $fromfolder\n";
			$failed = 1;
			return $failed;
		}

		foreach my $dir (@dir) {
			if ( ($dir =~ /\[(\w):(\d+)\] "(.*)" ".*".*/) && ($1 ne "") && ($2 ne "") && ($3 ne "") ) {
				my $item_index = $2;
				my $original_item_name = $3;
				my $item_name = $3;

				if ( ($1 eq "B") && !$aliases{$item_index} ) {
					# if a First Class folder has a ':' in its name then batch admin scripts will get messed up since First Class uses the ':' in a folder's path
					# the same way destination uses the '/' in a folder's path so we substitute the ':' with a '|' and rename the First Class folder
					# destination does not allow a ':' in its folder names anyway so this fixes that too
					$item_name =~ s/:/\|/g;

					# if a First Class folder has a '"' in its name then batch admin scripts will get messed up so we substitute '"' with a ''' and rename the First Class folder
					# destination does not allow a '"' in its folder names anyway so this fixes that too
					$item_name =~ s/"/'/g;

					# the following code makes sure that all folder names at a given level in a First Class mailbox are unique
					my $temp_item_name = $item_name;
					$temp_item_name =~ s/([\^.$|()\[\]])/\\$1/g;

					if (grep(/^$temp_item_name$/i, values(%item_names))) {
						my $i = 1;

						while (grep(/^$temp_item_name$i$/i, values(%item_names))) {
							$i++;
						}
						$item_name .= $i;
					}
					if ($item_name ne $original_item_name) {
					        my($ba_script_subject) = $searchString . "Rename: $fromuser Folder: $fromfolder:$original_item_name to $fromfolder:$item_name";

					        my @ba_script_body = "REPLY\n";

					        push (@ba_script_body, "PUT PROPERTIES BYINDEX $item_index DESKTOP $fromuser \"$fromfolder\" 1017 0 \"$item_name\"\n");

					        email_to_batch_admin ($ba_script_subject, \@ba_script_body);

					        my ($matching_file_arrived, $matching_filename) = wait_for_matching_file_arrival ($dataDir, $searchString, $timeout);

					        if ($matching_file_arrived) {
				                        open(FH, $matching_filename);
				                        my @renamed_results = <FH>;
							close(FH);

							if (grep(/error/i, @renamed_results)) {
								print print_timestamp() . " : Failed to Rename $fromuser\'s Folder: $fromfolder:$original_item_name to $fromfolder:$item_name\n";
								$failed = 1;
								return $failed;
							}
							else {
								print print_timestamp() . " : Renamed $fromuser\'s Folder: $fromfolder:$original_item_name to $fromfolder:$item_name\n";
							}
						}
						else {
							print print_timestamp() . " : Failed to Detemine if Renaming $fromuser\'s Folder: $fromfolder:$3 to $fromfolder:$item_name was successful\n";
							$failed = 1;
							return $failed;
						}
					}
				}
				$item_names{$item_index} = $item_name;
			}
		}
	}
	else {
		print print_timestamp() . " : Failed to Get DIR Report for $fromuser\'s Folder: $fromfolder\n";
		$failed = 1;
		return ($failed);
	}
	foreach my $idx (keys(%item_names)) {
		if ( exists($aliases{$idx}) && ($aliases{$idx} == 0) ) {
			push (@folders, "$fromfolder:" . $item_names{$idx});
		}
	}
	my @subfolders;
	foreach my $folder (@folders) {
		my ($temp_failed, @temp_subfolders) = get_fixed_fc_subfolders($fromuser, $folder);
		if ($temp_failed) {
			$failed = $temp_failed;
		}
		push (@subfolders, @temp_subfolders);
	}
	push (@folders, @subfolders);

	return ($failed, sort({ lc($a) cmp lc($b) } @folders));
}

sub request_ba_import_script {
        my ($fromuser, $fromfolder, $startdate, $enddate) = @_;

        my($ba_script_subject) = $searchString . "Request Import Script for User: $fromuser for Folder: $fromfolder for Date Range: $startdate - $enddate";

        my @ba_script_body = "";

        # the following Batch Admin command returns an import script for the user's folder
        # this import script will only import a specified number of days worth of email
        # in order to not overwhelm the servers which would basically prevent us from migrating
        if ( $enddate eq "" ) {
               push (@ba_script_body, "SETEXPORTFILTERS MODIFIED AFTER $startdate 00:00:00 +d\n");
        }
        else {
               push (@ba_script_body, "SETEXPORTFILTERS MODIFIED BEFORE $enddate 00:00:00 MODIFIED AFTER $startdate 00:00:00 +d\n");
        }
        push (@ba_script_body, "EXPORT DESKTOP $fromuser \"$fromfolder\"\n");

        email_to_batch_admin ($ba_script_subject, \@ba_script_body);

        my ($matching_file_arrived, $matching_filename) = wait_for_matching_file_arrival ($dataDir, $searchString, $timeout);

	return ($matching_file_arrived, $matching_filename);
}

sub process_ba_import_script {
        my ($filename) = @_;

        my @msg;

        my $is_body = 0;
        my $content_type = "";
        my $boundary = "";

        my $is_item = 0;
        my @item;
	my $is_sent_item = 0;
	my $last_cc_index = -1;
        my @internet_header_buffer;

	my %attachments = ();
	my %attachment_names = ();
	my $uploaded_file_name = "";

	my $keep = 0;
	my $subject = "";

        my $fc_unique_id = "";
	my $fcuid = "";

        open (FH, $filename);

        foreach my $line (<FH>) {
           if (!$is_body) {
		if ( ($content_type eq "") && ( $line =~ /Content-Type: .*/ ) ) {
			$content_type = $line . "\n";

			if (( $line =~ /Content-Type: .*boundary="(.+)"/) && ($1 ne "" )) {
				$boundary = $1;
			}

                        if ($boundary eq "") {
				$is_body = 1;
			}

			next;
                }
                if ( ($boundary ne "") && ( $line =~ /(.*?)($boundary)/ ) ) {
                        $is_body = 1;

			push (@msg, "MIME-Version: 1.0\n");
			push (@msg, "This is a multi-part message in MIME format.\n");
                        push (@msg, $line);
                }
           }
           else {
		$line =~ s/<ObjDesc>/DESKTOP $migrate_user \"Mailbox\"/;
                if ( $line =~ /^\/\/ This script was generated by FirstClass Server/ ) {
			push (@msg, "REPLY\n");
		}
                if ( $line =~ /^\/\/ Reference: (-?\d{2,}:\S+$)/ ) {
                        $is_item = 1;
                        $fc_unique_id = $1;
                }
                if ( $line =~ /^New Relative ".*" ".*" ".*" \w+ \d+ -?\d+ -?\d+ -?\d*\s?.*-U\+S/ ) {
			$is_sent_item = 1;
		}
                if ( $line =~ /^New Relative "(.*)" "(.*)" "(.*)" (\w+) \d+ -?\d+ -?\d+ -?\d*\s?(.*-U)/ ) {
			$keep = 1;

			$line = "New Relative \"$1\" \"$2\" \"$3\" Message 23032 0 0 0 $5+R\n";

			$subject = $3;

			if ($4 eq "Document") {
				$subject = $2;

				$line = "New Relative \"$1\" \"$2\" \"$2\" Message 23032 0 0 0 $5+R\n";

				push (@item, $line);
        	                push (@item, "Put Previous 8 \"Document from First Class <noreply\@noreply.com>\" -V\n");
                	        push (@item, "Put Previous 4 0 \"Document from First Class <noreply\@noreply.com>\" -V\n");

				next;
			}
			if ($4 eq "FCF") {
				$subject = $2;

				$uploaded_file_name = $2;

				push (@item, $line);
        	                push (@item, "Put Previous 8 \"Uploaded File from First Class <noreply\@noreply.com>\" -V\n");
                	        push (@item, "Put Previous 4 0 \"Uploaded File from First Class <noreply\@noreply.com>\" -V\n");

				next;
			}
		}

###	I commented the following out on 12/10/08 to wait until i got the problems again so i can work on this more
###	This next stuff tries to address an issue with To and CC fields
###	Sometimes there is a long address without an @ symbol which causes First Class to choke on import
###	The only problem is the following code messes normal To CC fields up so something needs to get fixed
		# make sure any To/CC addresses have an @ symbol in them
###		if ( $line !~ /^Put Previous [45] \d+ ".*\@.*"/ ) {
###	                $line =~ s/(^Put Previous [45] \d+ ")(.*)(".*)/$1$2\@$3/;
###		}

                if ( $line =~ /^Put Previous 8120 .*/ ) {next;}

		# if there are any BCC addresses in a sent email we need to change them to CC addresses because otherwise they will get lost
		# this means we have to keep track of the count of original CC addresses so we can index the BCC addresses correctly
                if ( $is_sent_item && ($line =~ /^Put Previous 5 (\d+) ".*" -V/) ) {$last_cc_index = $1;}
                if ( $is_sent_item && ($line =~ /^Put Previous 14 \d+ "\s*(.*)" -V/) ) {
			$line = "Put Previous 5 " . ++$last_cc_index . " \"$1\" -V\n";
                }

                if (( $line =~ /^(Upload Previous ".+?")/ ) && ( $uploaded_file_name ne "" )) {
			$line = $1 . " \"$uploaded_file_name\"\n";
		}

		# First Class's POP3 implementation truncates the name of any email attachment if the attachment's name length exceeds 31 characters
		# the following 'if' block makes sure that all email attachment names are captured so they can be used later to fix the names
                if ( $line =~ /^Upload Previous "(.+)" "(.+)"/ ) {
			$attachment_names{$1} = $2;

			$line = "Upload Previous \"$1\"\n";
		}

		# save the internet headers for later clean up
                if ( $line =~ /^Put Previous 8014.0 0 "(.*)"/ ) {
			push (@internet_header_buffer, $1);
			next;
                }

                if ( $line =~ /^Put Properties Previous 1018 14 (.*)$/ ) {
			$fcuid = $fc_unique_id . "|" . $1;

			# First Class's POP3 implementation truncates the name of any email attachment if the attachment's name length exceeds 31 characters
			# this saves the email attachment names for later so they can be used later to fix the names
			foreach my $attachment_number (keys(%attachment_names)) {
				$attachments{$fcuid}{$attachment_number} = $attachment_names{$attachment_number};
			}

			push (@item, "Put Previous 8120 7 1252 8140 0 8141 0 8126 $1 9 \"$subject\"\n\n");

                        # For some reason when using the pop3 interface to get this header, some messages were concatenating other headers causing syncing to fail
                        # So put the FC-UNIQUE-ID header before the FC-UNIQUE-ID-Description so we can guarantee that we will only get the ID when we get the header
                        push (@item, "Put Previous 8014.0 0 \"FC-UNIQUE-ID: $fcuid\\rFC-UNIQUE-ID-Description: This is for migration purposes only\\r\"\n");

			# Sometimes First Class email has malformed internet headers so this cleans up all First Class email internet headers
			foreach my $internet_header_line ( split( /\\r/, join("", @internet_header_buffer) ) ) {

				# make sure the $internet_header_line is a properly formed internet header that either starts with 'field:' or whitespace and then the rest of the value
				if ( ($internet_header_line !~ /^\S+:/) && ($internet_header_line !~ /^\s+\S+/) ) {last;}

				# batch admin script lines must be less than about 500 characters otherwise batch admin messes up the import process
				# this is probably most likely to happen with internet headers so the next bit of code chops up internet headers into 100 character blocks
				my @internet_header_line_pieces = $internet_header_line =~ /.{1,100}/g;

				my $count = 0;
				foreach my $internet_header_line_piece (@internet_header_line_pieces) {
					$count++;

					if ($count == @internet_header_line_pieces) {$internet_header_line_piece .= "\\r";}

					push (@item, "Put Previous 8014.0 0 \"$internet_header_line_piece\" +A\n");
				}
			}

                        push (@item, "\n");
                        push (@item, $line);

			if ($keep) {push (@msg, @item);}

                        $is_item = 0;
                        @item = ();
			$is_sent_item = 0;
			$last_cc_index = -1;
                        @internet_header_buffer = ();

			$keep = 0;
			$subject = "";

			%attachment_names = ();
			$uploaded_file_name = "";

                        $fc_unique_id = "";
			$fcuid = "";

                        next;
                }
                if ($is_item) {push (@item, $line);}
                else          {push (@msg, $line);}
           }
        }
        return ($content_type, \@msg, \%attachments);
}

sub get_export_filter_date_ranges {
        my ($max_export_script_size, $fromuser, $fromfolder, $tohost, $touser, $topassword, $tofolder, $imap_fcuid_msgid, $force_update_all_email) = @_;

        my %date;
	my %sync_fcuids;
	my $folder_total_size = 0;
        my @imap_fcuid = keys(%$imap_fcuid_msgid);
	my $enddate = "";
	my @export_filter_date_ranges;
	my @days_skipped;
	my $folder_total_size_to_be_migrated = 0;

        my($ba_script_subject) = $searchString . "DIR of User: $fromuser Folder: $fromfolder";

        my @ba_script_body = "REPLY\n";

        # the following Batch Admin command returns a DIR list of the contents of a First Class user's folder
        # this will be used to create Batch Admin export script filters for a folder so we don't end up trying to
        # email massive messages that will just fail to transmit

        push (@ba_script_body, "DIR DESKTOP $fromuser \"$fromfolder\" +lbpsdr\n");

        email_to_batch_admin ($ba_script_subject, \@ba_script_body);

        my ($matching_file_arrived, $matching_filename) = wait_for_matching_file_arrival ($dataDir, $searchString, $timeout);

        if ($matching_file_arrived) {
#               print print_timestamp() . " : Found: $matching_filename\n";

		print print_timestamp() . " : Evaluating Batch Admin DIR script results for Folder: \"$fromfolder\"\n";

                open (FH, $matching_filename);
                foreach my $line (<FH>) {
                        if ($line =~ /\[L:\d+\]\s+"(.*)"\s+"(.*)"\s+(\d{4}\/\d{2}\/\d{2})\s+(\d{2}:\d{2}:\d{2})\s+(\d+)\s+kb\s+(\S+)$/) {

                                my $item_name = $1;
                                my $item_subject = $2;
                                my $item_date = $3;
                                my $item_time = $4;
                                my $item_size = $5;
                                my $fcuid = $6;

                                my $calcdate = new Date::Manip::Date;
                                $calcdate->parse($item_date . " " . $item_time);

                                # 2212122496 is the UTC time offset in seconds that FirstClass uses
                                my $fc_timestamp = -2212122496 + $calcdate->secs_since_1970_GMT();

                                # adjust timestamp to the timezone of the firstclass server
                                $fc_timestamp -= ( 7 * 3600 );

                                # adjust timestamp for daylight savings timezone if needed
                                $fc_timestamp += ( $calcdate->printf('%Z') =~ /\w+D/ ) ? 3600 : 0; 

                                $fcuid .= "|$fc_timestamp";

                                $date{$item_date}{'size'} += $item_size;
                                $folder_total_size += $item_size;
                                $date{$item_date}{'migrate'} = 0;
                                $sync_fcuids{$fcuid}{'folder'} = $fromfolder;
                                $sync_fcuids{$fcuid}{'name'} = $item_name;
                                $sync_fcuids{$fcuid}{'subject'} = $item_subject;
                                $sync_fcuids{$fcuid}{'date'} = $item_date;
                                $sync_fcuids{$fcuid}{'time'} = $item_time;
                                $sync_fcuids{$fcuid}{'action'} = "skip";
                        }
                }
		close (FH);

		my(@fc_fcuid) = keys(%sync_fcuids);

		if ($force_update_all_email) {
			foreach my $fcuid (@fc_fcuid) {
				print print_timestamp() . " : Force Update in Folder: \"$tofolder\" \t Email: " . $fcuid . "\t" . $sync_fcuids{$fcuid}{'date'} . " " . $sync_fcuids{$fcuid}{'time'} . "\n";
				$date{$sync_fcuids{$fcuid}{'date'}}{'migrate'} = 1;
				$sync_fcuids{$fcuid}{'action'} = "update";
			}
		}
		else {
			my($lc) = List::Compare->new(\@fc_fcuid, \@imap_fcuid);

			foreach my $fcuid ($lc->get_Ronly) {
				print print_timestamp() . " : Delete from Folder: \"$tofolder\" \t Email: " . $fcuid . "\t" . $imap_fcuid_msgid->{$fcuid}->{'datetime'} . "\n";
				$sync_fcuids{$fcuid}{'action'} = "delete";
			}
			foreach my $fcuid ($lc->get_Lonly) {
				print print_timestamp() . " : Append to Folder: \"$tofolder\" \t Email: " . $fcuid . "\t" . $sync_fcuids{$fcuid}{'date'} . " " . $sync_fcuids{$fcuid}{'time'} . "\n";
				$date{$sync_fcuids{$fcuid}{'date'}}{'migrate'} = 1;
				$sync_fcuids{$fcuid}{'action'} = "append";
			}
			foreach my $fcuid ($lc->get_intersection) {
				if ( str2time($sync_fcuids{$fcuid}{'date'} . " " . $sync_fcuids{$fcuid}{'time'}) > str2time($imap_fcuid_msgid->{$fcuid}->{'datetime'}) ) {
					print print_timestamp() . " : Update in Folder: \"$tofolder\" \t Email: " . $fcuid . "\t" . $sync_fcuids{$fcuid}{'date'} . " " . $sync_fcuids{$fcuid}{'time'} . 
							"\t" . $imap_fcuid_msgid->{$fcuid}->{'datetime'} . "\n";
					$date{$sync_fcuids{$fcuid}{'date'}}{'migrate'} = 1;	
					$sync_fcuids{$fcuid}{'action'} = "update";
				}
			}
		}

                my $startdate = "";

		foreach my $date (sort(keys(%date))) {
			if ($date{$date}{'migrate'}) {
				if ($startdate eq "") {
					$startdate = $date;
					next;
				}
				if (($date{$startdate}{'size'} + $date{$date}{'size'}) < $max_export_script_size) {
					$date{$startdate}{'size'} += $date{$date}{'size'};
					delete($date{$date});
				}
				else {
					$startdate = $date;
				}
       	                }
               	        else {
				$startdate = "";
                        }
		}

	        my @dates = sort(keys(%date));

                for (my $i=0; $i < scalar(@dates); $i++) {
			$startdate = "";
			$enddate = "";

			if ($date{$dates[$i]}{'migrate'}) {
	                        my $size = $date{$dates[$i]}{'size'};
	                        $folder_total_size_to_be_migrated += $size;

	                        if ($size < $max_export_script_size) {
		                        $startdate = $dates[$i];
        	                        $enddate = $dates[$i+1] if ($i != (scalar(@dates)-1));

                	                push (@export_filter_date_ranges, [$startdate, $enddate, $size]);
	                       	        print print_timestamp() . " : Migrate email from Folder: \"$fromfolder\" in Date Range: \"$startdate\" to \"$enddate\" with a size of $size KB.\n";
	                        }
        	                else {
                	                push (@days_skipped, [$dates[$i], $size]);
	                       	        print print_timestamp() . " : Skip email in Folder: \"$fromfolder\" from $dates[$i] because the size $size KB is too large.\n";
	                        }
        	        }
			else {
#				print print_timestamp() . " : Skip email in Folder: \"$fromfolder\" from $dates[$i] because the email has already been migrated.\n";
			}
		}
		print print_timestamp() . " : Finished evaluating Batch Admin DIR script results for Folder: \"$fromfolder\"\n";
                return (1, \@export_filter_date_ranges, \@days_skipped, $folder_total_size, $folder_total_size_to_be_migrated, \%sync_fcuids);
        }
        else {
		print print_timestamp() . " : Failed to Get DIR Report for $fromuser\'s Folder: $fromfolder\n";
                return (0, \@export_filter_date_ranges, \@days_skipped, $folder_total_size, $folder_total_size_to_be_migrated, \%sync_fcuids);
        }
}

#-----------------Sending and Receiving Batch Admin Scripts-----------------------

sub email_to_batch_admin {
        my ($ba_script_subject, $ba_script_body, $content_type) = @_;

        if ( (!defined($content_type)) || ($content_type eq "") ) {$content_type = "Content-type: text/plain\n\n";}

        my $reply_to = "From: $migrate_email_address\n";
        my $subject = "Subject: $ba_script_subject\n";
        my $send_to = "To: $fc_admin_email_address\n";

	my @test = ($reply_to, $subject, $send_to, $content_type, @{$ba_script_body});

	my $content = join( "", @test ) . "\n";

	my $sender = Email::Send->new({mailer => 'SMTP'});
	$sender->mailer_args([Host => $fromhost]);
	$sender->send($content);

        $send_to = "To: $migrate_email_address\n";

	@test = ($reply_to, $subject, $send_to, $content_type, @{$ba_script_body});

	$content = join( "", @test ) . "\n";

	$sender->mailer_args([Host => $migratehost]);
	$sender->send($content);
}

sub wait_for_matching_file_arrival {
        my ($dataDir, $searchString, $timeout) = @_;

        my $dataDirNew = $dataDir . 'new/';
        my $dataDirCur = $dataDir . 'cur/';

        my @original_file_set = glob($dataDirNew . "*");

        my $filename = eval {
                local $SIG{ALRM} = sub { die "Timedout\n" }; # \n required
                alarm $timeout;

                while () {
                        my @current_file_set = glob($dataDirNew . "*");

                        my $lc = List::Compare->new(\@original_file_set, \@current_file_set);

                        foreach my $new_filename ($lc->get_Ronly) {
                                open (FH, $new_filename);

                                while (<FH>) {
                                        if ( /$searchString/ ) {
                                                alarm 0;
                                                return basename($new_filename);
                                        }
                                }
                        }
                }
        };
        return (0, "") if ($@ eq "Timedout\n");

        # remove html part from body

        open (FH, $dataDirNew . $filename);
        my $msg = Mail::Message->read(\*FH);
        close FH;

        if ( $msg->isMultipart ) {
            foreach my $part ( $msg->parts('RECURSE') ) {
                if ( $part->contentType eq 'text/html' ) {
                    $part->delete;
#                    print print_timestamp() . " : Removed the HTML part of the emailed batch admin response.\n";
                }
            }
        }

        open(FH,'>', $dataDirNew . $filename);
        $msg->print(\*FH);
        close FH;

        move($dataDirNew . $filename, $dataDirCur);

        return (1, $dataDirCur . $filename);
}

#--------------------IMAP Stuff-----------------------------------------------------

sub get_imap_fcuid_msgid_hash {
        my ($tohost, $touser, $topassword, $tofolder) = @_;

        my %imap_fcuid_msgid_hash;
        my $imap = create_imap_client($tohost, $touser, $topassword, $debugimap);

	$imap->select($tofolder);

	my $hash_ref = $imap->fetch_hash('INTERNALDATE');

	foreach my $uid (keys(%$hash_ref)) {
		if ($imap->get_header($uid, "FC-UNIQUE-ID")) {
			$imap_fcuid_msgid_hash{$imap->get_header($uid, "FC-UNIQUE-ID")}{'msgid'} = $imap->get_header($uid, "Message-Id");
			$imap_fcuid_msgid_hash{$imap->get_header($uid, "FC-UNIQUE-ID")}{'msgid'} =~ s/\<|\>//g;

			$imap_fcuid_msgid_hash{$imap->get_header($uid, "FC-UNIQUE-ID")}{'datetime'} = $hash_ref->{$uid}->{'INTERNALDATE'};
		}
	}
        $imap->close;

	return \%imap_fcuid_msgid_hash;
}

# sub get_imap_folders_list returns a cleaned up list of all subfolders of the root_folder recursively
sub get_imap_folders_list {
        my ($host, $user, $password, $folder, $recursive) = @_;

	my $imap = create_imap_client($host, $user, $password);

        my @imap_folders_list;

       foreach ($imap->folders) {
               next if ( /^Follow up$|^Misc$|^Priority$|^\[Gmail\]/ );
               s/\\\\/\\/g;
               if ( /^"?(.+?)\/?"?$/ && ($1 ne "") ) {
                       push(@imap_folders_list, $1);
		}
	}
	$imap->close;

        return sort({ lc($a) cmp lc($b) } @imap_folders_list);
}

sub create_imap_client {
        my ($host, $user, $password, $debugimap) = @_;

        my $imap;

        my $port = $to_imaps ? "993" : "143";
        my $authuser = $user;

        # gmail does not allow PLAIN mechanism so use LOGIN
        my $authmech = "LOGIN";

# if the imap server allows for admin access to user accounts then set $authuser and $password to an imap account with admin rights
        if ($to_authuser && $to_authuser_password) {
                $authuser = $to_authuser;
                $password = $to_authuser_password;
        }

###$debugimap = 1;
        $imap = Mail::IMAPClient->new(
                    Clear => (20),
                    Server => ($host),
                    Port => ($port),
                    Uid => (1),
                    Peek => (1),
                    Debug => ($debugimap),
                    Buffer => (4096),
                    Ssl => ($to_imaps)
                );

        $debugimap && print print_timestamp() . " : IMAP Connected: " . ($imap->IsConnected ? "True" : "False") . "\n";

        $imap->Authmechanism($authmech);
        $imap->Authcallback(\&plainauth) if $authmech eq "PLAIN";

        $imap->User($user);
        $imap->{AUTHUSER} = $authuser;
        $imap->Password($password);

        $imap->login();
        $debugimap && print print_timestamp() . " : IMAP Authenticated: " . ($imap->IsAuthenticated ? "True" : "False") . "\n";

        return $imap;
}

sub plainauth() {
        my($code, $imap) = @_;

        my $string = sprintf("%s\x00%s\x00%s", $imap->User, $imap->{AUTHUSER}, $imap->Password);
        return encode_base64("$string", "");
}

sub email_user_notification {
        my ($from_address, $tohost, $to_address, $msg_subject, @body) = @_;

        my $reply_to = "From: " . $from_address . "\n";
        my $send_to = "To: " . $to_address . "\n";
        my $subject = "Subject: $msg_subject\n";
	my $content_type = "Content-type: text/plain\n\n";

	my @test = ($reply_to, $subject, $send_to, $content_type, @body);

	my $content = join( "", @test ) . "\n";

	my $sender = Email::Send->new({mailer => 'SMTP'});

	$sender->send($content);
}

sub elapsed_time {
	my $lasttime = shift;
	my $timenow = time();
	my $elapsed_time = Delta_Format(DateCalc(ParseDateString("epoch " . $lasttime), ParseDateString("epoch " . $timenow)), , 0, "%dvd %hvh %mvm %svs");
	$lasttime = $timenow;
	return($elapsed_time, $lasttime);
}

sub print_timestamp {
	return UnixDate(ParseDateString("epoch " . time()),'%Y-%m-%d %T');
}

1;
