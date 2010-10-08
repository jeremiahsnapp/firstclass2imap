package switch_users;

use warnings;
use strict;

use DBI;
use Data::Dumper;

use Email::Send;

use Mail::Box::Manager;
use Mail::IMAPClient;
use MIME::Base64;
use MIME::Types;
use List::Compare;
use Date::Parse;
use Date::Manip;

my $dry_run = 0;
my $debugimap = 0;
my $dataDir = "/home/migrate/ba-rcvd/new/";
my $timeout = 300;
my $searchString = "BA Migrate Script: ";
my $max_export_script_size = 20000;
my $migrate_user = "migrate";
my $migrate_password = "migrate";

sub initialize {
	my ($my_dataDir, $my_timeout, $my_searchString, $my_migrate_user, $my_migrate_password, $my_max_export_script_size, $my_dry_run, $my_debugimap) = @_;

	$dataDir = $my_dataDir;
	$timeout = $my_timeout;
	$searchString = $my_searchString;
	$max_export_script_size = $my_max_export_script_size;
	$dry_run = $my_dry_run;
	$debugimap = $my_debugimap;
	$migrate_user = $my_migrate_user;
	$migrate_password = $my_migrate_password;
}

sub switch_user_to_zimbra {
	my($fromuser, $touser) = @_;

        my($ba_script_subject) = $searchString . "Disable User Account: $fromuser";

        my @ba_script_body = "";

        # the following Batch Admin script adds the user to the "Migrated_To_Zimbra" group in First Class
	# this group's permissions are very restricted effectively allowing the user to access their First Class account
	# and receive email but disabling their ability to create anything
	# This script also creates a redirect mail rule that redirects any incoming email to their new Zimbra email address
        push (@ba_script_body, "REPLY\n");
        push (@ba_script_body, "PUT USER $fromuser 1216 6 0\n");
        push (@ba_script_body, "PGADD $fromuser Migrated_To_Zimbra\n");
        push (@ba_script_body, "SetBase desktop $fromuser \"Mailbox\"\n");
        push (@ba_script_body, "SetRelative FromBase Path \"\"\n");
        push (@ba_script_body, "New Relative \"\" \"Migration Rule\" \"\" FormDoc 23047 0 0 23 23 -U+X\n");
        push (@ba_script_body, "Put Previous 8120 7 10000 8140 0 8141 0 9 \"\"\n");
        push (@ba_script_body, "Put Previous 13810.0 7 33 13830.0 7 7 13832.0 0 \"$touser\@schoolname.edu\" 13830.1 7 3\n");
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

        my $reply_to = "From: migrate\@migrate.schoolname.edu\n";
        my $subject = "Subject: $ba_script_subject\n";
        my $send_to = "To: administrator\@schoolname.edu\n";

	my @test = ($reply_to, $subject, $send_to, $content_type, @{$ba_script_body});

	my $content = join( "", @test ) . "\n";

	my $sender = Email::Send->new({mailer => 'SMTP'});
	$sender->mailer_args([Host => '192.168.1.24']);
	$sender->send($content);

        $send_to = "To: migrate\@migrate.schoolname.edu\n";

	@test = ($reply_to, $subject, $send_to, $content_type, @{$ba_script_body});

	$content = join( "", @test ) . "\n";

	$sender->mailer_args([Host => '192.168.1.6']);
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
	return UnixDate(ParseDate("epoch" . time()),'%Y-%m-%d %T');
}

1;
