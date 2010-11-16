package build_usermap;

use warnings;
use strict;

use DBI;
use Data::Dumper;

use Email::Send;

use List::Compare;
use Date::Parse;
use Date::Manip;

my $list_of_users_filename = "";
my $dataDir = "/home/migrate/ba-rcvd/new/";
my $timeout = 300;
my $searchString = "BA Migrate Script: ";
my $max_export_script_size = 20000;
my $migrate_email_address = 'migrate@migrate.schoolname.edu';
my $fc_admin_email_address = 'administrator@schoolname.edu';
my $fc_ip_address = '192.168.1.24';
my $migrate_ip_address = '192.168.1.6';
my $to_ip_address = "192.168.1.26";

sub initialize {
	my ($my_list_of_users_filename, $my_dataDir, $my_timeout, $my_searchString, $my_max_export_script_size, $my_migrate_email_address, $my_fc_admin_email_address, $my_fc_ip_address, $my_migrate_ip_address, $my_to_ip_address) = @_;

	$list_of_users_filename = $my_list_of_users_filename;
	$dataDir = $my_dataDir;
	$timeout = $my_timeout;
	$searchString = $my_searchString;
	$max_export_script_size = $my_max_export_script_size;
	$migrate_email_address = $my_migrate_email_address;
	$fc_admin_email_address = $my_fc_admin_email_address;
	$fc_ip_address = $my_fc_ip_address;
	$migrate_ip_address = $my_migrate_ip_address;
	$to_ip_address = $my_to_ip_address;
}

sub build_usermap {
	# MySQL CONFIG VARIABLES
	my($mysqldb, $mysqluser, $mysqlpassword) = ("migrate", "migrate", "test");

	# PERL MYSQL CONNECT
	my($dbh2) = DBI->connect("DBI:mysql:$mysqldb", $mysqluser, $mysqlpassword) or die "Couldn't connect to database: " . DBI->errstr;

        my(%fromuser_hash);
        my($ba_script_subject) = $searchString . "Get Passwords";
        my(@ba_script_body) = "REPLY\n";

        open (FH, $list_of_users_filename);

        my($fromuser, $touser);

	# create a batch admin script that will get a list that
	# verifies the existence of a set of users in Firstclass as well as the size of each user's account and their passwords
        foreach my $line (<FH>) {
		$line  =~ /(.*),(.*)/;
		($fromuser, $touser) = ($1, $2);

                $fromuser_hash{$fromuser}{'tohost'} = $to_ip_address;
                $fromuser_hash{$fromuser}{'touser'} = $touser;
		$fromuser_hash{$fromuser}{'exists_in_fc'} = 0;

                # the following Batch Admin command will return a First Class clientid's userid and password
                # this will be used to match userid's and passwords to their corresponding userid's in our local database
	        push (@ba_script_body, "GET USER $fromuser 1500 1201 1217 1258\n" );

#		print "$old_username \t $fromuser_hash{$fromuser}{'touser'}\n";
#		print "fromuser: \"$fromuser\" \t touser: \"$touser\"\n";
        }

        email_to_batch_admin ($ba_script_subject, \@ba_script_body);

        my ($matching_file_arrived, $matching_filename) = wait_for_matching_file_arrival ($dataDir, $searchString, $timeout);

	if ($matching_file_arrived) {
#	        print print_timestamp() . " : Found: $matching_filename\n";

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
				my($sth2) = $dbh2->prepare("SELECT COUNT(*) FROM usermap WHERE fromuser = ? AND touser = ? AND manual = 1");
				$sth2->execute($fromuser, $fromuser_hash{$fromuser}{'touser'})
					or die "Couldn't execute SELECT statement: " . $sth2->errstr;

				my($row_exists) = $sth2->fetch;

				if ( @$row_exists[0] ) {next;}

				$sth2 = $dbh2->prepare("SELECT COUNT(*) FROM usermap WHERE fromuser = ? AND touser = ? AND manual = 0");
				$sth2->execute($fromuser, $fromuser_hash{$fromuser}{'touser'})
					or die "Couldn't execute SELECT statement: " . $sth2->errstr;

				$row_exists = $sth2->fetch;

				# if a row already exists for this user then update the row
				if ( @$row_exists[0] ) {
	                	        $sth2 = $dbh2->prepare ("UPDATE usermap SET tohost = ?, topassword = ?, account_size = ? WHERE fromuser = ? AND touser = ? AND manual = 0");
	        	                $sth2->execute( $fromuser_hash{$fromuser}{'tohost'}, $fromuser_hash{$fromuser}{'topassword'}, $fromuser_hash{$fromuser}{'size'}, $fromuser, $fromuser_hash{$fromuser}{'touser'} )
						or die "Couldn't execute UPDATE statement: " . $sth2->errstr;
		                        print print_timestamp() . " : Updated fromuser: $fromuser\n";
				}
				# if row does not already exist for this user then create a new row
				else {
		                        $sth2 = $dbh2->prepare("INSERT INTO usermap ( switched, manual, migrate, fromhost, fromuser, fromfolder, tohost, touser, topassword, tofolder, recursive, account_size ) VALUE ( 1, 0, 1, ?, ?, ?, ?, ?, ?, ?, ?, ? )");
		                        $sth2->execute( $fromhost, $fromuser, $fromfolder, $fromuser_hash{$fromuser}{"tohost"}, $fromuser_hash{$fromuser}{'touser'}, $fromuser_hash{$fromuser}{'topassword'}, $tofolder, $recursive, $fromuser_hash{$fromuser}{'size'}) 
						or die "Couldn't execute INSERT statement: " . $sth2->errstr;
		                        print print_timestamp() . " : Inserted fromuser: $fromuser \t touser: $fromuser_hash{$fromuser}{'touser'}\n";
				}
			}
		}

	        my($sth2) = $dbh2->prepare("SELECT fromuser, touser, tohost FROM usermap WHERE manual = 0") or warn $dbh2->errstr();

	        $sth2->execute or die "Couldn't execute SELECT statement: " . $sth2->errstr;

		my $tohost = "";

	        $sth2->bind_columns (\$fromuser, \$touser, \$tohost);

	        my(%usermap_hash);

		# now that the mysql database has been updated with information from FirstClass we delete any rows in mysql that have invalid/old information
	        while ($sth2->fetchrow_hashref) {
#	                $usermap_hash{$fromuser}{'touser'} = $touser;
#	                $usermap_hash{$fromuser}{'tohost'} = $tohost;

	                if ( ! exists($fromuser_hash{$fromuser}{'touser'}) || ( ($touser ne $fromuser_hash{$fromuser}{'touser'}) &&  ($tohost ne $fromuser_hash{$fromuser}{'tohost'}) ) ) {
                        	my $sth3 = $dbh2->prepare("DELETE FROM usermap WHERE fromuser = ? AND touser = ? AND manual = 0");
                	        $sth3->execute($fromuser, $touser)
        	                        or die "Couldn't execute DELETE statement: " . $sth3->errstr;
				print print_timestamp() . " : Deleted fromuser: $fromuser \t touser: $touser\n";
			}
	        }
#	        foreach $fromuser (sort(keys(%usermap_hash))) {
#	                if ( ! exists($fromuser_hash{$fromuser}{'touser'}) || ( ($usermap_hash{$fromuser}{'touser'} ne $fromuser_hash{$fromuser}{'touser'}) &&  ($usermap_hash{$fromuser}{'tohost'} ne $fromuser_hash{$fromuser}{'tohost'}) ) ) {
#                        	$sth2 = $dbh2->prepare("DELETE FROM usermap WHERE fromuser = ? AND touser = ? AND manual = 0");
#                	        $sth2->execute($fromuser, $usermap_hash{$fromuser}{'touser'})
#        	                        or die "Couldn't execute DELETE statement: " . $sth2->errstr;
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