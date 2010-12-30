package switch_users;

use warnings;
use strict;

use DBI;
use Data::Dumper;
use File::Copy;
use File::Basename;
use YAML::Tiny;

use Email::Send;
use Mail::Message;

use List::Compare;
use Date::Manip;

my $rcvdDir = "/home/migrate/Maildir/.switched_user_rcvd/";
my $timeout = 300;
my $searchString = "BA Migrate Script switched_user: ";
my $max_export_script_size = 20000;
my $migrate_email_address = 'migrate@migrate.schoolname.edu';
my $fc_admin_email_address = 'administrator@schoolname.edu';
my $domain = 'schoolname.edu';
my $fromhost = '192.168.1.24';
my $migratehost = '192.168.1.6';

sub initialize {
	# Create a YAML file
	my $yaml = YAML::Tiny->new;

	# Open the config
	$yaml = YAML::Tiny->read( 'migration.cfg' );

	$rcvdDir = $yaml->[0]->{rcvdDir} . ".switched_user_rcvd/";
	$timeout = $yaml->[0]->{timeout};
	$searchString = $yaml->[0]->{searchString} . " switched_user: ";
	$max_export_script_size = $yaml->[0]->{max_export_script_size};
	$migrate_email_address = $yaml->[0]->{migrate_email_address};
	$fc_admin_email_address = $yaml->[0]->{fc_admin_email_address};
	$fromhost = $yaml->[0]->{fromhost};
	$migratehost = $yaml->[0]->{migratehost};
	$domain = $yaml->[0]->{domain};
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

        my ($matching_file_arrived, $matching_filename) = wait_for_matching_file_arrival ($rcvdDir, $searchString, $timeout);

	if ($matching_file_arrived) {
		open (FH, $matching_filename);
		my @script_reply = <FH>;
		close(FH);

        	my($ba_script_subject) = $searchString . "Enable User Account: $fromuser";

	        my @ba_script_body = "";
	        push (@ba_script_body, "REPLY\n");
	        push (@ba_script_body, "PUT USER $fromuser 1216 6 2\n");
	        
		email_to_batch_admin ($ba_script_subject, \@ba_script_body);

        	my ($matching_file_arrived, $matching_filename) = wait_for_matching_file_arrival ($rcvdDir, $searchString, $timeout);

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
	$sender->mailer_args([Host => $fromhost]);
	$sender->send($content);

        $send_to = "To: $migrate_email_address\n";

	@test = ($reply_to, $subject, $send_to, $content_type, @{$ba_script_body});

	$content = join( "", @test ) . "\n";

	$sender->mailer_args([Host => $migratehost]);
	$sender->send($content);
}

sub wait_for_matching_file_arrival {
        my ($rcvdDir, $searchString, $timeout) = @_;

        my $rcvdDirNew = $rcvdDir . 'new/';
        my $rcvdDirCur = $rcvdDir . 'cur/';

        my @original_file_set = glob($rcvdDirNew . "*");

        my $filename = eval {
                local $SIG{ALRM} = sub { die "Timedout\n" }; # \n required
                alarm $timeout;

                while () {
                        my @current_file_set = glob($rcvdDirNew . "*");

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

        open (FH, $rcvdDirNew . $filename);
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

        open(FH,'>', $rcvdDirNew . $filename);
        $msg->print(\*FH);
        close FH;

        move($rcvdDirNew . $filename, $rcvdDirCur);

        return (1, $rcvdDirCur . $filename);
}

sub print_timestamp {
	return UnixDate(ParseDateString("epoch " . time()),'%Y-%m-%d %T');
}

1;
