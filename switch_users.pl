#!/usr/bin/perl

use warnings;
use strict;

use DBI;
use YAML::Tiny;

use switch_users;
use Date::Manip;

# Create a YAML file
my $yaml = YAML::Tiny->new;

# Open the config
$yaml = YAML::Tiny->read('migration.cfg');

my $rcvdDir    = $yaml->[0]->{mailDir} . ".switched_user_rcvd/";
my $sentDir    = $yaml->[0]->{mailDir} . ".switched_user_sent/";
my $dbname     = $yaml->[0]->{dbname};
my $dbuser     = $yaml->[0]->{dbuser};
my $dbpassword = $yaml->[0]->{dbpassword};

switch_users::initialize;

# PERL Database CONNECT
my ($dbh) = DBI->connect( "DBI:mysql:$dbname", $dbuser, $dbpassword ) or die "Couldn't connect to database: " . DBI->errstr;

$dbh->{mysql_auto_reconnect} = 1;

my $count = 0;

while ( $count < 200 ) {
    my $starttime         = time();
    my $lasttime          = $starttime;
    my $elapsed_time      = "";
    my $elapsed_time_secs = "";

    my ( $switch, $switched, $fromuser, $touser ) = ( 0, 0, "", "" );

    my ($sth) = $dbh->prepare("SELECT switch, switched, fromuser, touser FROM usermap WHERE switch = 1 AND switched = 0");
    $sth->execute() or die "Couldn't execute SELECT statement: " . $sth->errstr;

    $sth->bind_columns( \$switch, \$switched, \$fromuser, \$touser );

    $sth->fetchrow_hashref;
    $sth->finish;

    open( STDOUT, '>>', "/var/log/migration/switch_user" ) or die "Can't redirect STDOUT: $!";
    open( STDERR, ">&STDOUT" ) or die "Can't dup STDOUT: $!";

    system("rm $rcvdDir*");
    system("rm $sentDir*");

    $switched = switch_users::switch_user_to_destination( $fromuser, $touser );

    if ($switched) {
        $sth = $dbh->prepare("UPDATE usermap SET switched = 1 WHERE fromuser = ? AND touser = ? LIMIT 1");
        $sth->execute( $fromuser, $touser );
        $sth->finish;
    }

    ( $elapsed_time, $lasttime, $elapsed_time_secs ) = elapsed_time($starttime);

    $count++;
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
