#!/usr/bin/perl

use warnings;
use strict;

use DBI;

use switch_users;
use Date::Parse;
use Date::Manip;

my $my_timeout = 3000;
my $my_rcvdDir = "/home/jeremiah.snapp/switched_user_rcvd/new/";
my $my_sentDir = "/home/jeremiah.snapp/switched_user_sent/new/";
my $my_searchString = "BA Migrate Script switched_user: ";
my $my_migrate_user = "migrate";
my $my_migrate_password = "migrate";
my $my_max_export_script_size = 20000;
my $my_debugimap = 0;
my $my_migrate_email_address = 'migrate@migrate.schoolname.edu';
my $my_fc_admin_email_address = 'administrator@schoolname.edu';
my $my_fc_ip_address = '192.168.1.24';
my $my_migrate_ip_address = '192.168.1.6';
my $my_domain = 'schoolname.edu';

switch_users::initialize($my_rcvdDir, $my_timeout, $my_searchString, $my_migrate_user, $my_migrate_password, $my_max_export_script_size, $my_dry_run, $my_debugimap, $my_migrate_email_address, $my_fc_admin_email_address, $my_fc_ip_address, $my_migrate_ip_address, $my_domain);

# MySQL CONFIG VARIABLES
my($mysqldb, $mysqluser, $mysqlpassword) = ("migrate", "migrate", "test");

# PERL MYSQL CONNECT
my($dbh) = DBI->connect("DBI:mysql:$mysqldb", $mysqluser, $mysqlpassword) or die "Couldn't connect to database: " . DBI->errstr;

my $count = 0;

while ($count < 200) {
	my $starttime = time();
	my $lasttime = $starttime;
	my $elapsed_time = "";
	my $elapsed_time_secs = "";

	my ($switch, $switched, $fromhost, $fromuser, $tohost, $touser) = (0, 0, "", "", "", "");

	my($sth) = $dbh->prepare("SELECT switch, switched, fromhost, fromuser, tohost, touser FROM usermap WHERE switch = 1 AND switched = 0");
	$sth->execute() or die "Couldn't execute SELECT statement: " . $sth->errstr;

	$sth->bind_columns (\$switch, \$switched, \$fromhost, \$fromuser, \$tohost, \$touser);

	$sth->fetchrow_hashref;

	open(STDOUT, '>>', "/var/log/migration/switch_user") or die "Can't redirect STDOUT: $!";
	open(STDERR, ">&STDOUT")                  or die "Can't dup STDOUT: $!";

	system("rm $my_rcvdDir*");
	system("rm $my_sentDir*");

	$switched = switch_users::switch_user_to_zimbra($fromuser, $touser);

	if ($switched) {
		$sth = $dbh->prepare ("UPDATE usermap SET switched = 1 WHERE fromuser = ? AND touser = ? LIMIT 1");
		$sth->execute( $fromuser, $touser );
	}

	($elapsed_time, $lasttime, $elapsed_time_secs) = elapsed_time($starttime);

	$count++;
}

sub elapsed_time {
        my $lasttime = shift;
        my $timenow = time();
        my $elapsed_time = Delta_Format(DateCalc(ParseDate("epoch" . $lasttime), ParseDate("epoch" . $timenow)), , 0, "%dvd %hvh %mvm %svs");
        my $elapsed_time_secs = Delta_Format(DateCalc(ParseDate("epoch" . $lasttime), ParseDate("epoch" . $timenow)), , 0, "%sh");
        $lasttime = $timenow;
        return($elapsed_time, $lasttime, $elapsed_time_secs);
}

sub print_timestamp {
        return UnixDate(ParseDate("epoch" . time()),'%Y-%m-%d %T');
}
