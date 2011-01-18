#!/usr/bin/perl

use warnings;
use strict;
use POSIX qw(ceil floor);

use DBI;
use YAML::Tiny;

use firstclass2imap;
use Date::Manip;

if ( @ARGV < 1 ) {
    print "Usage: ./firstclass2imap.pl <instance> [fc_user]\n\n";
    print "Where <instance> is a number representing the migration account in First Class that will be used.\n\n";
    print "[fc_user] is optional but when set will cause the script to only migrate the firstclass user specified.\n\n";
    print "Example: ./firstclass2imap.pl 1 [fc_user]\n\n";

    exit;
}

my $instance = shift(@ARGV);
my $fc_user  = shift(@ARGV);

my $from_date_string = '';
my $to_date_string   = '';

# Create a YAML file
my $yaml = YAML::Tiny->new;

# Open the config
$yaml = YAML::Tiny->read('migration.cfg');

my $rcvdDir                = $yaml->[0]->{mailDir} . ".ba_rcvd_$instance/";
my $sentDir                = $yaml->[0]->{mailDir} . ".ba_sent_$instance/";
my $domain                 = $yaml->[0]->{domain};
my $migration_notification_email_address = $yaml->[0]->{migration_notification_email_address};
my $fromhost   = $yaml->[0]->{fromhost};
my $dbname     = $yaml->[0]->{dbname};
my $dbhost     = $yaml->[0]->{dbhost};
my $dbuser     = $yaml->[0]->{dbuser};
my $dbpassword = $yaml->[0]->{dbpassword};

firstclass2imap::initialize($instance, $from_date_string, $to_date_string);

# PERL Database CONNECT
my ($dbh) = DBI->connect( "DBI:mysql:$dbname:$dbhost", $dbuser, $dbpassword ) or die "Couldn't connect to database: " . DBI->errstr;

$dbh->{mysql_auto_reconnect} = 1;

my ($sth) = $dbh->prepare("SELECT migrating FROM usermap WHERE migrating = '$fromhost:$instance'");
$sth->execute() or die "Couldn't execute SELECT statement: " . $sth->errstr;

my ($row_exists) = $sth->fetch;

$sth->finish;

if ( @$row_exists[0] ) {
    print "Instance $instance is already running against the FirstClass server $fromhost.\n";
    print "Choose a different value for 'instance'.\n";
    exit();
}

$SIG{'INT'}  = 'exit_gracefully';
$SIG{'TERM'} = 'exit_gracefully';

my $count = 0;
my ( $switched, $force_update_all_email, $fromuser, $fromfolder, $touser, $topassword, $recursive, $migrated, $migrating );

# you can use $count to limit the number of accounts you want to migrate
# it can be helpful during testing to limit the number to a single account
#while ($count < 20) {

# when you are ready to migrate all accounts you can remove the "while" condition
while () {

    my $starttime         = time();
    my $lasttime          = $starttime;
    my $elapsed_time      = "";
    my $elapsed_time_secs = "";

    ( $switched, $force_update_all_email, $fromuser, $fromfolder, $touser, $topassword, $recursive, $migrated, $migrating ) =
      ( 0, 0, "", "", "", "", 0, 0, 0 );

    my $sth;
    if ($fc_user) {
        # this query is helpful during testing ... it limits the migration to a specific account
        $sth = $dbh->prepare("SELECT switched, force_update_all_email, fromuser, fromfolder, touser, topassword, recursive, migrated, migrating FROM usermap WHERE fromuser = '$fc_user'");
    }
    else {
        # this query is for when you are ready to migrate all accounts
        $sth = $dbh->prepare("SELECT switched, force_update_all_email, fromuser, fromfolder, touser, topassword, recursive, migrated, migrating FROM usermap WHERE broken = 0 AND migration_complete = 0 AND migrating = 0 AND migrate = 1 ORDER BY migrated ASC, account_size ASC");
    }

    $sth->execute() or die "Couldn't execute SELECT statement: " . $sth->errstr;

    $sth->bind_columns( \$switched, \$force_update_all_email, \$fromuser, \$fromfolder, \$touser, \$topassword, \$recursive, \$migrated, \$migrating );

    $sth->fetchrow_hashref;

    $sth->finish;

    if ( !$fromuser ) {
        print "Unable to find an account in the database to migrate.\n";
        exit;
    }
    if ($migrating) {
        print "The user $fc_user is already being migrated.\n";
        exit;
    }

    ###	# you can override recursive migration here
    ###	$recursive = 0;

    open( FH, '>>', "/var/log/migration/instance.$instance" );
    print FH print_timestamp() . " $fromuser\n";
    close FH;

    $migrated++;

    unless ( -e "/var/log/migration/$fromuser" ) {
        system("mkdir /var/log/migration/$fromuser");
    }

    my $ulog_counter = 1;
    while ( -e "/var/log/migration/$fromuser/$fromuser.$ulog_counter" ) {
        $ulog_counter++;
    }

    open( STDOUT, '>', "/var/log/migration/$fromuser/$fromuser.$ulog_counter" ) or die "Can't redirect STDOUT: $!";
    open( STDERR, ">&STDOUT" ) or die "Can't dup STDOUT: $!";

    system("rm -rf $rcvdDir");
    system("rm -rf $sentDir");

    $sth = $dbh->prepare("UPDATE usermap SET time_migrated = NOW(), migrating = ?, status = ?, migrated = ? WHERE fromuser = ? AND touser = ? AND fromfolder = ? LIMIT 1");
    if ( $sth->execute( "$fromhost:$instance", '', $migrated, $fromuser, $touser, $fromfolder ) ) {
        $sth->finish;
        my ( $migrated_folder_structure, $migrated_folders, $fc_folder_count, $destination_folder_count, $dir_account_total_fcuids, $imap_account_total_fcuids ) = ( 0, 0, 0, 0, 0, 0 );
        my ( $missed_folders_count, $missed_fcuids_count ) = ( 0, 0 );
        my $missed_folders;
        my $missed_fcuids;

        ( $migrated_folder_structure, $fc_folder_count, $destination_folder_count, $missed_folders ) = firstclass2imap::migrate_folder_structure( $fromuser, $fromfolder, $touser, $topassword, $recursive );

        if ( !$migrated_folder_structure ) {
            $sth = $dbh->prepare("UPDATE usermap SET migrating = 0, broken = 1 WHERE fromuser = ? AND touser = ? AND fromfolder = ? LIMIT 1");
            $sth->execute( $fromuser, $touser, $fromfolder );
            $sth->finish;

            $count++;
            last if ($fc_user);
            next;
        }

        ( $migrated_folders, $dir_account_total_fcuids, $imap_account_total_fcuids, $missed_fcuids ) = firstclass2imap::migrate_folders( $fromuser, $fromfolder, $touser, $topassword, $recursive, $force_update_all_email );

        if ( $migrated_folder_structure && $migrated_folders ) {
            $missed_folders_count = @$missed_folders;
            foreach my $folder ( keys( %{$missed_fcuids} ) ) {
                foreach my $fcuid ( @{ $missed_fcuids->{$folder} } ) {
                    $missed_fcuids_count++;
                }
            }

            ( $elapsed_time, $lasttime, $elapsed_time_secs ) = elapsed_time($starttime);

            my $percent_complete = 0;
            if ( ( $fc_folder_count + $dir_account_total_fcuids ) != 0 ) {
                $percent_complete = floor(
                    (
                        ( ( $fc_folder_count - $missed_folders_count ) + ( $dir_account_total_fcuids - $missed_fcuids_count ) )
                        / ( $fc_folder_count + $dir_account_total_fcuids )
                    )
                    * 100
                );
            }
            else {
                $percent_complete = 100;
            }

            $sth = $dbh->prepare("UPDATE usermap SET duration = ?, percent_complete = ?, fc_folder_count = ?, destination_folder_count = ?, fc_fcuid_count = ?, destination_fcuid_count = ?, missed_folders_count = ?, missed_fcuids_count = ? WHERE fromuser = ? AND touser = ? AND fromfolder = ? LIMIT 1");
            $sth->execute( $elapsed_time_secs, $percent_complete, $fc_folder_count, $destination_folder_count, $dir_account_total_fcuids, $imap_account_total_fcuids, $missed_folders_count, $missed_fcuids_count, $fromuser, $touser, $fromfolder );
            $sth->finish;

            if ( ( $missed_folders_count == 0 ) && ( $missed_fcuids_count == 0 ) ) {
                $sth = $dbh->prepare("UPDATE usermap SET migration_complete = 1 WHERE fromuser = ? AND touser = ? AND fromfolder = ? LIMIT 1");
                $sth->execute( $fromuser, $touser, $fromfolder );
                $sth->finish;
            }
        }

        $sth = $dbh->prepare("UPDATE usermap SET migrating = 0 WHERE fromuser = ? AND touser = ? AND fromfolder = ? LIMIT 1");
        $sth->execute( $fromuser, $touser, $fromfolder );
        $sth->finish;

        if (0) {
            ###             this is commented out because we don't want email notifications at this point since there would be so many
            ###             if ($migrated_folder_structure && $migrated_folders) {
            my $from_address = "$migration_notification_email_address";

            my $to_address = "$migration_notification_email_address";

            if ( $migrated_folder_structure && $migrated_folders && ( $missed_folders_count == 0 ) && ( $missed_fcuids_count == 0 ) ) {
                $to_address .= ',' . $touser . '@' . $domain;
            }

            my $subject = "";
            if ( ( $dir_account_total_fcuids == 0 ) && $migrated_folder_structure && $migrated_folders ) {
                $subject = "$touser\'s Email Migration Report:    100% Successful";
            }
            if ( $dir_account_total_fcuids != 0 ) {
                $subject = "$touser\'s Email Migration Report:    " .
                  sprintf( "%d",
                    floor(
                        (
                            ( ( $fc_folder_count - $missed_folders_count ) + ( $dir_account_total_fcuids - $missed_fcuids_count ) )
                            / ( $fc_folder_count + $dir_account_total_fcuids )
                        )
                        * 100
                      )
                  ) . "% Successful";
            }

            my @body = ();

            push( @body, "This is the Email Migration Report for your FirstClass account.\n\n" );

            push( @body, "Number of FirstClass Folders Migrated: " . ( $fc_folder_count - $missed_folders_count ) . "\n" );
            push( @body, "Number of FirstClass Items Migrated:   " . ( $dir_account_total_fcuids - $missed_fcuids_count ) . "\n\n" );

            if ( ( $fc_folder_count - $missed_folders_count ) > 1 ) {
                push( @body, "You can find your migrated folders by clicking on the little arrow next to your \"Inbox\" folder.\n\n" );
            }

            push( @body, pretty_print( $missed_folders, $missed_fcuids ) );

            firstclass2imap::email_user_notification( $from_address, $to_address, $subject, @body );
        }
    }
    $sth->finish;
    $count++;
    last if ($fc_user);
}

sub exit_gracefully {
    my $status = "$fromhost:$instance : Migration instance was killed.";

    $sth = $dbh->prepare("UPDATE usermap SET migrating = 0, status = ? WHERE fromuser = ? AND touser = ? AND fromfolder = ? LIMIT 1");
    $sth->execute( $status, $fromuser, $touser, $fromfolder );
    $sth->finish;

    print print_timestamp() . " : $status\n";
    exit (0);
}

sub pretty_print {
    my ( $missed_folders, $missed_fcuids ) = @_;

    my @pretty = ();

    my ( $missed_folders_count, $missed_fcuids_count ) = ( 0, 0 );

    if ( defined($missed_folders) ) { $missed_folders_count = @$missed_folders; }
    if ( defined($missed_fcuids) ) {
        foreach my $folder ( keys( %{$missed_fcuids} ) ) {
            foreach my $fcuid ( @{ $missed_fcuids->{$folder} } ) {
                $missed_fcuids_count++;
            }
        }
    }

    if ( ( $missed_folders_count == 0 ) && ( $missed_fcuids_count == 0 ) ) {
        push( @pretty, "Our records indicate that all of your FirstClass folders and their content were successfully migrated to your new destination account.\n\n" );
        push( @pretty, "If you have any questions please reply to this email.\n\n" );
        push( @pretty, "Thank you.\n\n" );

        return @pretty;
    }

    push( @pretty, "Our records indicate that the following FirstClass folders and their content were NOT successfully migrated to your new destination account.\n\n" );
    push( @pretty, "If you have any questions please reply to this email.\n\n" );
    push( @pretty, "Thank you.\n\n" );

    push( @pretty, "\nThe following folders were not migrated:\n" ) if (@$missed_folders);
    foreach my $folder ( sort( { lc($a) cmp lc($b) } @$missed_folders ) ) {
        push( @pretty, "\tFolder: " . $folder . "\n" );
    }

    push( @pretty, "\nThe following items were NOT migrated:\n" ) if ( keys( %{$missed_fcuids} ) );
    foreach my $folder ( keys( %{$missed_fcuids} ) ) {
        push( @pretty, "\nFolder: " . $folder . "\n" );

        foreach my $fcuid ( sort( { $a->{'name'} cmp $b->{'name'} } @{ $missed_fcuids->{$folder} } ) ) {
            my ( $date, $time, $name, $subject ) = ( "", "", "", "" );
            ( $date, $time, $name, $subject ) = ( $fcuid->{'date'}, $fcuid->{'time'}, $fcuid->{'name'}, $fcuid->{'subject'} );

            my $item_string = "";

            $item_string .= "   " . $date;
            $item_string .= "   " . $time;
            $item_string .= "    Name: " . sprintf( "%-30.30s", $name );
            $item_string .= "    Subject: " . sprintf( "%-30.30s", $subject );
            $item_string .= "\n";

            push( @pretty, $item_string );
        }
    }
    return @pretty;
}
sub elapsed_time {
    my $lasttime = shift;
    my $timenow  = time();
    my $elapsed_time = Delta_Format( DateCalc( ParseDateString( "epoch " . $lasttime ), ParseDateString( "epoch " . $timenow ) ),, 0, "%dvd %hvh %mvm %svs" );
    my $elapsed_time_secs = Delta_Format( DateCalc( ParseDateString( "epoch " . $lasttime ), ParseDateString( "epoch " . $timenow ) ),, 0, "%sh" );
    $lasttime = $timenow;
    return ( $elapsed_time, $lasttime, $elapsed_time_secs );
}

sub print_timestamp {
    return UnixDate( ParseDateString( "epoch " . time() ), '%Y-%m-%d %T' );
}
