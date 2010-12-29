package build_usermap;

use warnings;
use strict;

use DBI;
use Data::Dumper;
use File::Copy;
use File::Basename;

use Email::Send;
use Mail::Message;

use List::Compare;
use Date::Manip;

my $list_of_users_filename = "";
my $dataDir = "/home/migrate/Maildir/.build_usermap_rcvd/";
my $timeout = 300;
my $searchString = "BA Migrate Script Usermap: ";
my $max_export_script_size = 20000;
my $migrate_email_address = 'migrate@migrate.schoolname.edu';
my $fc_admin_email_address = 'administrator@schoolname.edu';
my $fc_ip_address = '192.168.1.24';
my $migrate_ip_address = '192.168.1.6';
my $tohost = 'imap.gmail.com';

sub initialize {
       my ($my_list_of_users_filename, $my_dataDir, $my_timeout, $my_searchString, $my_max_export_script_size, $my_migrate_email_address, $my_fc_admin_email_address, $my_fc_ip_address, $my_migrate_ip_address, $my_tohost) = @_;

	$list_of_users_filename = $my_list_of_users_filename;
	$dataDir = $my_dataDir;
	$timeout = $my_timeout;
	$searchString = $my_searchString;
	$max_export_script_size = $my_max_export_script_size;
	$migrate_email_address = $my_migrate_email_address;
	$fc_admin_email_address = $my_fc_admin_email_address;
	$fc_ip_address = $my_fc_ip_address;
	$migrate_ip_address = $my_migrate_ip_address;
       $tohost = $my_tohost;
}

sub build_usermap {
	# MySQL CONFIG VARIABLES
	my($mysqldb, $mysqluser, $mysqlpassword) = ("migrate", "migrate", "test");

	# PERL MYSQL CONNECT
	my($dbh) = DBI->connect("DBI:mysql:$mysqldb", $mysqluser, $mysqlpassword) or die "Couldn't connect to database: " . DBI->errstr;

        $dbh->{mysql_auto_reconnect} = 1;

        my(%fromuser_hash);
        my($ba_script_subject) = $searchString . "Get Passwords";
        my(@ba_script_body) = "REPLY\n";

        open (FH, $list_of_users_filename);

        my($fromuser, $touser);

	# create a batch admin script that will get a list that
	# verifies the existence of a set of users in Firstclass as well as the size of each user's account and their passwords
        foreach my $line (<FH>) {
		$line  =~ /(.*),(.*)/;
		($fromuser, $touser) = (lc($1), lc($2));

                $fromuser_hash{$fromuser}{'tohost'} = $tohost;
                $fromuser_hash{$fromuser}{'touser'} = $touser;
		$fromuser_hash{$fromuser}{'exists_in_fc'} = 0;

                # the following Batch Admin command will return a First Class clientid's userid and password
                # this will be used to match userid's and passwords to their corresponding userid's in our local database
	        push (@ba_script_body, "GET USER $fromuser 1500 1201 1217 1258\n" );

		print "Added '$fromuser' to the 'GET USER' batch admin script.\n";
        }

        email_to_batch_admin ($ba_script_subject, \@ba_script_body);

        print print_timestamp() . " : Batch Admin script has been emailed to the FirstClass server ... Waiting for response from the FirstClass server.\n";

        my ($matching_file_arrived, $matching_filename) = wait_for_matching_file_arrival ($dataDir, $searchString, $timeout);

	if ($matching_file_arrived) {
	        print print_timestamp() . " : Found: $matching_filename ... Response received from the FirstClass server.\n";

	        open (FH, $matching_filename);

	        # capture the userid field from the Batch Admin Reply Email
	        while (<FH>) {
	                if ( /^1500 \d+ (\d+) 1201 \d+ "(.*)" 1217 \d+ "(.*)" 1258 \d+ (\d+)/ && ($1 != 0) && ($2 ne "") && ($3 ne "") && ($4 ne "") ) {
				$fromuser_hash{lc($2)}{'size'} = $4;
				$fromuser_hash{lc($2)}{'exists_in_fc'} = 1;

				# we probably don't need the password so this is set to an empty string
				# if you do want to capture the password then replace the double quotes with $3
				$fromuser_hash{lc($2)}{'topassword'} = "";
	                }
	        }
	        close FH;

		my($fromhost, $fromfolder, $tofolder, $recursive) = ($fc_ip_address, "Mailbox", "INBOX", "1");

		foreach $fromuser (sort(keys(%fromuser_hash))) {
			if ( $fromuser_hash{$fromuser}{'exists_in_fc'} ) {
				# do not migrate the admin user account
				if ($fromuser_hash{$fromuser}{'touser'} =~ /.*admin.*/i) { next; }

				# check if this user is to be configured manually ... if they are then skip the user
				my($sth) = $dbh->prepare("SELECT COUNT(*) FROM usermap WHERE fromuser = ? AND touser = ? AND manual = 1");
				$sth->execute($fromuser, $fromuser_hash{$fromuser}{'touser'})
					or die "Couldn't execute SELECT statement: " . $sth->errstr;

				my($row_exists) = $sth->fetch;

                                $sth->finish;

				if ( @$row_exists[0] ) {
                                        print print_timestamp() . " : fromuser: $fromuser is a 'manual' entry in the database so don't modify the record.\n";
                                        next;
                                }

				$sth = $dbh->prepare("SELECT COUNT(*) FROM usermap WHERE fromuser = ? AND touser = ? AND manual = 0");
				$sth->execute($fromuser, $fromuser_hash{$fromuser}{'touser'})
					or die "Couldn't execute SELECT statement: " . $sth->errstr;

				$row_exists = $sth->fetch;

                                $sth->finish;

				# if a row already exists for this user then update the row
				if ( @$row_exists[0] ) {
                                       $sth = $dbh->prepare ("UPDATE usermap SET topassword = ?, account_size = ? WHERE fromuser = ? AND touser = ? AND manual = 0");
                                       $sth->execute( $fromuser_hash{$fromuser}{'topassword'}, $fromuser_hash{$fromuser}{'size'}, $fromuser, $fromuser_hash{$fromuser}{'touser'} )
						or die "Couldn't execute UPDATE statement: " . $sth->errstr;

                                        $sth->finish;

					print print_timestamp() . " : Updated fromuser: $fromuser in the database\n";
				}
				# if row does not already exist for this user then create a new row
				else {
                                       $sth = $dbh->prepare("INSERT INTO usermap ( switched, manual, migrate, fromhost, fromuser, fromfolder, touser, topassword, tofolder, recursive, account_size ) VALUE ( 0, 0, 0, ?, ?, ?, ?, ?, ?, ?, ?, ? )");
                                       $sth->execute( $fromhost, $fromuser, $fromfolder, $fromuser_hash{$fromuser}{'touser'}, $fromuser_hash{$fromuser}{'topassword'}, $tofolder, $recursive, $fromuser_hash{$fromuser}{'size'})
						or die "Couldn't execute INSERT statement: " . $sth->errstr;

                                        $sth->finish;

					print print_timestamp() . " : Inserted fromuser: $fromuser \t touser: $fromuser_hash{$fromuser}{'touser'} in the database\n";
				}
			}
                        else {
                                print print_timestamp() . " : fromuser: $fromuser does not exist in the FirstClass server so skip the user.\n";
                        }
		}

               my($sth) = $dbh->prepare("SELECT fromuser, touser FROM usermap WHERE manual = 0") or warn $dbh->errstr();

	        $sth->execute or die "Couldn't execute SELECT statement: " . $sth->errstr;

               $sth->bind_columns (\$fromuser, \$touser);

	        my(%usermap_hash);

		# now that the mysql database has been updated with information from FirstClass we delete any rows in mysql that have invalid/old information
	        while ($sth->fetchrow_hashref) {
#	                $usermap_hash{$fromuser}{'touser'} = $touser;

                       if ( ! exists($fromuser_hash{$fromuser}{'touser'}) || ($touser ne $fromuser_hash{$fromuser}{'touser'}) ) {
### disable deletion of accounts from the database until we determine that this is a feature we want
###                        	my $sth2 = $dbh->prepare("DELETE FROM usermap WHERE fromuser = ? AND touser = ? AND manual = 0");
###                	        $sth2->execute($fromuser, $touser)
###        	                        or die "Couldn't execute DELETE statement: " . $sth2->errstr;
				print print_timestamp() . " : Deleted fromuser: $fromuser \t touser: $touser in the database\n";
			}
	        }
                $sth->finish;
#	        foreach $fromuser (sort(keys(%usermap_hash))) {
#                      if ( ! exists($fromuser_hash{$fromuser}{'touser'}) || ($usermap_hash{$fromuser}{'touser'} ne $fromuser_hash{$fromuser}{'touser'}) ) {
#                        	$sth = $dbh->prepare("DELETE FROM usermap WHERE fromuser = ? AND touser = ? AND manual = 0");
#                	        $sth->execute($fromuser, $usermap_hash{$fromuser}{'touser'})
#        	                        or die "Couldn't execute DELETE statement: " . $sth->errstr;
#                                $sth->finish;
#				print print_timestamp() . " : Deleted fromuser: $fromuser \t touser: $usermap_hash{$fromuser}{'touser'}\n";
#	                }
#	        }
	}
	else {
		print print_timestamp() . " : Did NOT receive the emailed results of the \"GET USER\" Batch Admin Script.\n";
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

sub print_timestamp {
	return UnixDate(ParseDateString("epoch " . time()),'%Y-%m-%d %T');
}

1;
