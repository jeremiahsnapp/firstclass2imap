#!/usr/bin/perl

use warnings;
use strict;
use POSIX qw(ceil floor);

use DBI;

use firstclass2imap;
use Date::Manip;

if (@ARGV != 3) {
        print "Usage: ./single_firstclass2imap.pl <instance> <threshold> <destination_email_address>\n\n";
        print "Where <instance> is a number representing the migration account in First Class that will be used.\n\n";
        print "<threshold> is the maximum size of a batch admin email in kB\n\n";
        print "<fc_user> is the firstclass user you want to migrate.\n\n";
        print "Example: ./single_firstclass2imap.pl 1 20000 fc_user\n\n";

        exit;
}

my $instance = shift(@ARGV);
my $threshold = shift(@ARGV);
my $fc_user = shift(@ARGV);

my @procs = `ps ax`;
if ( grep(/firstclass2imap.pl\s+$instance/, @procs) > 1 ) {
    print "Instance $instance is already running.\n";
    print "Choose a different value for 'instance'.\n";
    exit();
}

my $my_timeout = 3600;
my $my_rcvdDir = "/home/migrate/Maildir/.ba_rcvd_$instance/";
my $my_sentDir = "/home/migrate/Maildir/.ba_sent_$instance/";
my $my_searchString = "BA Migrate Script $instance: ";
my $my_migrate_user = "migrate" . $instance;
my $my_migrate_password = "migrate" . $instance;
my $my_max_export_script_size = $threshold;
my $my_dry_run = 0;
my $my_debugimap = 0;
my $my_to_imaps = 1;
my $my_to_authuser = 'admin';
my $my_to_authuser_password = 'password';
my $my_migrate_email_address = 'migrate@migrate.schoolname.edu';
my $my_fc_admin_email_address = 'administrator@schoolname.edu';
my $my_fc_ip_address = '192.168.1.24';
my $my_migrate_ip_address = '192.168.1.6';
my $force_update_all_email = 0;
my $domain = 'schoolname.edu';
my $migration_notification_email_address = 'admin@schoolname.edu';

firstclass2imap::initialize($my_rcvdDir, $my_timeout, $my_searchString, $my_migrate_user, $my_migrate_password, $my_max_export_script_size, $my_dry_run, $my_debugimap, $my_to_imaps, $my_to_authuser, $my_to_authuser_password, $my_migrate_email_address, $my_fc_admin_email_address, $my_fc_ip_address, $my_migrate_ip_address);

# MySQL CONFIG VARIABLES
my($mysqldb, $mysqluser, $mysqlpassword) = ("migrate", "migrate", "test");

# PERL MYSQL CONNECT
my($dbh) = DBI->connect("DBI:mysql:$mysqldb", $mysqluser, $mysqlpassword) or die "Couldn't connect to database: " . DBI->errstr;

$dbh->{mysql_auto_reconnect} = 1;

my $count = 0;

# you can use $count to limit the number of accounts you want to migrate
# it can be helpful during testing to limit the number to a single account
while ($count < 1) {

# when you are ready to migrate all accounts you can remove the "while" condition
###while () {

	my $starttime = time();
	my $lasttime = $starttime;
	my $elapsed_time = "";
	my $elapsed_time_secs = "";

	my ($switched, $fromhost, $fromuser, $fromfolder, $tohost, $touser, $topassword, $tofolder, $recursive, $migrated, $migrating) = 
		(0, "", "", "", "", "", "", "", 0, 0, 0);

# this query is helpful during testing ... it limits the migration to a specific account
	my($sth) = $dbh->prepare("SELECT switched, fromhost, fromuser, fromfolder, tohost, touser, topassword, tofolder, recursive, migrated, migrating FROM usermap WHERE fromuser = '$fc_user'");

	$sth->execute() or die "Couldn't execute SELECT statement: " . $sth->errstr;

	$sth->bind_columns (\$switched, \$fromhost, \$fromuser, \$fromfolder, \$tohost, \$touser, \$topassword, \$tofolder, \$recursive, \$migrated, \$migrating);

	$sth->fetchrow_hashref;

        $sth->finish;

        if ( $fromuser eq "" ) {
            print "Unable to find an account in the database to migrate.\n";
            exit;
        }
        if ( $migrating == 1 ) {
            print "The user $fc_user is already being migrated.\n";
            exit;
        }

###	# you can override recursive migration here
###	$recursive = 0;


        open(FH, '>>', "/var/log/migration/instance.$instance");
        print FH print_timestamp() . " $fromuser\n";
        close FH;

        $migrated++;

        unless ( -e "/var/log/migration/$fromuser") {
               system("mkdir /var/log/migration/$fromuser");
        }

        open(STDOUT, '>', "/var/log/migration/$fromuser/$fromuser." . $migrated) or die "Can't redirect STDOUT: $!";
        open(STDERR, ">&STDOUT")                  or die "Can't dup STDOUT: $!";

	system("rm -rf $my_rcvdDir");
	system("rm -rf $my_sentDir");

	$sth = $dbh->prepare ("UPDATE usermap SET time_migrated = NOW(), migrating = 1, migrated = ? WHERE fromuser = ? AND touser = ? AND fromfolder = ? AND tofolder = ? LIMIT 1");
	if ($sth->execute( $migrated, $fromuser, $touser, $fromfolder, $tofolder )) {
                $sth->finish;
		my($migrated_folder_structure, $migrated_folders, $fc_folder_count, $destination_folder_count, $dir_account_total_fcuids, $imap_account_total_fcuids) = (0, 0, 0, 0, 0, 0);
		my ($missed_folders_count, $missed_fcuids_count) = (0, 0);
		my $missed_folders;
		my $missed_fcuids;

		my $delete_from_destination = 0;
###		$delete_from_destination = 1 if (!$switched);

		($migrated_folder_structure, $fc_folder_count, $destination_folder_count, $missed_folders) = firstclass2imap::migrate_folder_structure($fromhost, $fromuser, $fromfolder, $tohost, $touser, $topassword, $tofolder, $recursive, $delete_from_destination);

		if (!$migrated_folder_structure) {
			$sth = $dbh->prepare ("UPDATE usermap SET migrating = 0, broken = 1 WHERE fromuser = ? AND touser = ? AND fromfolder = ? AND tofolder = ? LIMIT 1");
                        $sth->execute( $fromuser, $touser, $fromfolder, $tofolder );
                        $sth->finish;

			$count++;
			next;
		}

		($migrated_folders, $dir_account_total_fcuids, $imap_account_total_fcuids, $missed_fcuids) = firstclass2imap::migrate_folders($fromhost, $fromuser, $fromfolder, $tohost, $touser, $topassword, $tofolder, $recursive, $delete_from_destination, $force_update_all_email);

		if ($migrated_folder_structure && $migrated_folders) {
			$missed_folders_count = @$missed_folders;
			foreach my $folder (keys(%{$missed_fcuids})) {
				foreach my $fcuid (@{$missed_fcuids->{$folder}} ) {
					$missed_fcuids_count++;
				}
			}

			($elapsed_time, $lasttime, $elapsed_time_secs) = elapsed_time($starttime);

                        my $percent_complete = 0;
                        if ( ($fc_folder_count + $dir_account_total_fcuids) != 0 ) {
                          $percent_complete = floor(
                                                      (
                                                        ( ($fc_folder_count - $missed_folders_count) + ($dir_account_total_fcuids - $missed_fcuids_count) )
                                                        / ($fc_folder_count + $dir_account_total_fcuids)
                                                      )
                                                      * 100
                                                  );
                        }
                        else {
                          $percent_complete = 100;
                        }

                        $sth = $dbh->prepare ("UPDATE usermap SET duration = ?, percent_complete = ?, fc_folder_count = ?, destination_folder_count = ?, fc_fcuid_count = ?, destination_fcuid_count = ?, missed_folders_count = ?, missed_fcuids_count = ? WHERE fromuser = ? AND touser = ? AND fromfolder = ? AND tofolder = ? LIMIT 1");
                        $sth->execute( $elapsed_time_secs, $percent_complete, $fc_folder_count, $destination_folder_count, $dir_account_total_fcuids, $imap_account_total_fcuids, $missed_folders_count, $missed_fcuids_count, $fromuser, $touser, $fromfolder, $tofolder );
                        $sth->finish;

			if ( ($missed_folders_count == 0) && ($missed_fcuids_count == 0) ) {
				$sth = $dbh->prepare ("UPDATE usermap SET migration_complete = 1 WHERE fromuser = ? AND touser = ? AND fromfolder = ? AND tofolder = ? LIMIT 1");
				$sth->execute( $fromuser, $touser, $fromfolder, $tofolder );
                                $sth->finish;
			}
		}

		$sth = $dbh->prepare ("UPDATE usermap SET migrating = 0 WHERE fromuser = ? AND touser = ? AND fromfolder = ? AND tofolder = ? LIMIT 1");
		$sth->execute( $fromuser, $touser, $fromfolder, $tofolder );
                $sth->finish;

                if (0) {
###             this is commented out because we don't want email notifications at this point since there would be so many
###             if ($migrated_folder_structure && $migrated_folders) {
			my $from_address = "$migration_notification_email_address";

			my $to_address = "$migration_notification_email_address";

			if ( $migrated_folder_structure && $migrated_folders && ($missed_folders_count == 0) && ($missed_fcuids_count == 0) ) {
				$to_address .= ',' . $touser . '@' . $domain;
			}

			my $subject = "";
			if ( ($dir_account_total_fcuids == 0) && $migrated_folder_structure && $migrated_folders ) {
				$subject = "$touser\'s Email Migration Report:    100% Successful";
			}
			if ($dir_account_total_fcuids != 0) {
				$subject = "$touser\'s Email Migration Report:    " . 
					sprintf("%d", 
						floor(
						    ( 
							( ($fc_folder_count - $missed_folders_count) + ($dir_account_total_fcuids - $missed_fcuids_count) )
							/ ($fc_folder_count + $dir_account_total_fcuids)
						    ) 
						    * 100
						)
					) . "% Successful";
			}

			my @body = ();

			push(@body, "This is the Email Migration Report for your FirstClass account.\n\n");

			push(@body, "Number of FirstClass Folders Migrated: " . ($fc_folder_count - $missed_folders_count) . "\n");
			push(@body, "Number of FirstClass Items Migrated:   " . ($dir_account_total_fcuids - $missed_fcuids_count) . "\n\n");

			if (($fc_folder_count - $missed_folders_count) > 1) {
				push(@body, "You can find your migrated folders by clicking on the little arrow next to your \"Inbox\" folder.\n\n");
			}

			push(@body, pretty_print($missed_folders, $missed_fcuids));

			firstclass2imap::email_user_notification($from_address, $tohost, $to_address, $subject, @body);
		}
	}
        $sth->finish;
	$count++;
}

sub pretty_print {
	my($missed_folders, $missed_fcuids) = @_;

	my @pretty = ();

	my ($missed_folders_count, $missed_fcuids_count) = (0, 0);

	if (defined($missed_folders)) { $missed_folders_count = @$missed_folders; }
	if (defined($missed_fcuids)) {
		foreach my $folder (keys(%{$missed_fcuids})) {
			foreach my $fcuid (@{$missed_fcuids->{$folder}} ) {
				$missed_fcuids_count++;
			}
		}
	}

	if ( ($missed_folders_count == 0) && ($missed_fcuids_count == 0) ) {
		push(@pretty, "Our records indicate that all of your FirstClass folders and their content were successfully migrated to your new destination account.\n\n");
		push(@pretty, "If you have any questions please reply to this email.\n\n");
		push(@pretty, "Thank you.\n\n");

		return @pretty;
	}

	push(@pretty, "Our records indicate that the following FirstClass folders and their content were NOT successfully migrated to your new destination account.\n\n");
	push(@pretty, "If you have any questions please reply to this email.\n\n");
	push(@pretty, "Thank you.\n\n");

	push(@pretty, "\nThe following folders were not migrated:\n") if (@$missed_folders);
	foreach my $folder (sort({ lc($a) cmp lc($b) } @$missed_folders)) {
		push(@pretty, "\tFolder: " . $folder . "\n");
	}

	push(@pretty, "\nThe following items were NOT migrated:\n") if (keys(%{$missed_fcuids}));
	foreach my $folder (keys(%{$missed_fcuids})) {
		push(@pretty, "\nFolder: " . $folder . "\n");

		foreach my $fcuid (sort( { $a->{'name'} cmp $b->{'name'} } @{$missed_fcuids->{$folder}} ) ) {
			my($date, $time, $name, $subject) = ("", "", "", "");
			($date, $time, $name, $subject) = ($fcuid->{'date'}, $fcuid->{'time'}, $fcuid->{'name'}, $fcuid->{'subject'});

			my $item_string = "";

			$item_string .= "   " . $date;
			$item_string .= "   " . $time;
			$item_string .= "    Name: "    . sprintf("%-30.30s", $name);
			$item_string .= "    Subject: " . sprintf("%-30.30s", $subject);
			$item_string .= "\n";
	
			push(@pretty, $item_string);
		}
	}
	return @pretty;
}
sub elapsed_time {
        my $lasttime = shift;
        my $timenow = time();
        my $elapsed_time = Delta_Format(DateCalc(ParseDateString("epoch " . $lasttime), ParseDateString("epoch " . $timenow)), , 0, "%dvd %hvh %mvm %svs");
        my $elapsed_time_secs = Delta_Format(DateCalc(ParseDateString("epoch " . $lasttime), ParseDateString("epoch " . $timenow)), , 0, "%sh");
        $lasttime = $timenow;
        return($elapsed_time, $lasttime, $elapsed_time_secs);
}

sub print_timestamp {
        return UnixDate(ParseDateString("epoch " . time()),'%Y-%m-%d %T');
}
