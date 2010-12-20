package switch_users;

use warnings;
use strict;

use DBI;
use Data::Dumper;

use Email::Send;

use List::Compare;
use Date::Manip;

my $dataDir = "/home/migrate/ba-rcvd/new/";
my $timeout = 300;
my $searchString = "BA Migrate Script: ";
my $max_export_script_size = 20000;
my $migrate_email_address = 'migrate@migrate.schoolname.edu';
my $fc_admin_email_address = 'administrator@schoolname.edu';
my $domain = 'schoolname.edu';
my $fc_ip_address = '192.168.1.24';
my $migrate_ip_address = '192.168.1.6';

sub initialize {
	my ($my_dataDir, $my_timeout, $my_searchString, $my_max_export_script_size, $my_migrate_email_address, $my_fc_admin_email_address, $my_fc_ip_address, $my_migrate_ip_address, $my_domain) = @_;

	$dataDir = $my_dataDir;
	$timeout = $my_timeout;
	$searchString = $my_searchString;
	$max_export_script_size = $my_max_export_script_size;
	$migrate_email_address = $my_migrate_email_address;
	$fc_admin_email_address = $my_fc_admin_email_address;
	$fc_ip_address = $my_fc_ip_address;
	$migrate_ip_address = $my_migrate_ip_address;
	$domain = $my_domain;
}

sub switch_user_to_destination {
	my($fromuser, $touser) = @_;

        my($ba_script_subject) = $searchString . "Disable User Account: $fromuser";

        my @ba_script_body = "";

        # the following Batch Admin script adds the user to the "Migrated_To_Destination" group in First Class
	# this group's permissions are very restricted effectively allowing the user to access their First Class account
	# and receive email but disabling their ability to create anything
	# This script also creates a redirect mail rule that redirects any incoming email to their new destination email address
        push (@ba_script_body, "REPLY\n");
        push (@ba_script_body, "PUT USER $fromuser 1216 6 0\n");
        push (@ba_script_body, "PGADD $fromuser Migrated_To_Destination\n");
        push (@ba_script_body, "SetBase desktop $fromuser \"Mailbox\"\n");
        push (@ba_script_body, "SetRelative FromBase Path \"\"\n");
        push (@ba_script_body, "New Relative \"\" \"Migration Rule\" \"\" FormDoc 23047 0 0 23 23 -U+X\n");
        push (@ba_script_body, "Put Previous 8120 7 10000 8140 0 8141 0 9 \"\"\n");
        push (@ba_script_body, "Put Previous 13810.0 7 33 13830.0 7 7 13832.0 0 \"$touser\@$domain\" 13830.1 7 3\n");
        push (@ba_script_body, "Put Item Previous  13830 7 7\n");
        push (@ba_script_body, "Compile Relative \"\"\n");

        email_to_batch_admin ($ba_script_subject, \@ba_script_body);

        my ($matching_file_arrived, $matching_filename) = wait_for_matching_file_arrival ($dataDir, $searchString, $timeout);

	if ($matching_file_arrived) {
		open (FH, $matching_filename);
		my @script_reply = <FH>;
		close(FH);

        	my($ba_script_subject) = $searchString . "Enable User Account: $fromuser";

	        my @ba_script_body = "";
	        push (@ba_script_body, "REPLY\n");
	        push (@ba_script_body, "PUT USER $fromuser 1216 6 2\n");
	        
		email_to_batch_admin ($ba_script_subject, \@ba_script_body);

        	my ($matching_file_arrived, $matching_filename) = wait_for_matching_file_arrival ($dataDir, $searchString, $timeout);

		if (grep(/PGAdd\: User \'$fromuser\' updated/, @script_reply)) {
			print print_timestamp() . " : Restricted the user: \"$fromuser\" in First Class\n";
			return 1;
		}
		else {
			print print_timestamp() . " : Failed to restrict the user: \"$fromuser\" in First Class\n";
			return 0;
		}
	}
	else {
		print print_timestamp() . " : Failed to determine whether the user: \"$fromuser\" was restricted in First Class\n";
		return 0;
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
	$sender->mailer_args([Host => $fc_ip_address]);
	$sender->send($content);

        $send_to = "To: $migrate_email_address\n";

	@test = ($reply_to, $subject, $send_to, $content_type, @{$ba_script_body});

	$content = join( "", @test ) . "\n";

	$sender->mailer_args([Host => $migrate_ip_address]);
	$sender->send($content);
}

sub wait_for_matching_file_arrival {
        my ($dataDir, $searchString, $timeout) = @_;

        my @original_file_set = glob($dataDir . "*");

        my $filename = eval {
                local $SIG{ALRM} = sub { die "Timedout\n" }; # \n required
                alarm $timeout;

                while () {
                        my @current_file_set = glob($dataDir . "*");

                        my $lc = List::Compare->new(\@original_file_set, \@current_file_set);

                        foreach my $new_filename ($lc->get_Ronly) {
                                open (FH, $new_filename);

                                while (<FH>) {
                                        if ( /$searchString/ ) {
                                                alarm 0;
                                                return $new_filename;
                                        }
                                }
                        }
                }
        };
        return (0, "") if ($@ eq "Timedout\n");
        return (1, $filename);
}

sub print_timestamp {
	return UnixDate(ParseDateString("epoch " . time()),'%Y-%m-%d %T');
}

1;
