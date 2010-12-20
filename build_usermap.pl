#!/usr/bin/perl

open(STDOUT, '>>', "/var/log/migration/build_usermap") or die "Can't redirect STDOUT: $!";
open(STDERR, ">&STDOUT")                  or die "Can't dup STDOUT: $!";

use build_usermap;


# you need to have a csv file that matches FirstClass userid's with the corresponding account on the new email system
# firstclass_userid,new_email_system_account_name

my $my_list_of_users_filename = "";

my $my_rcvdDir = "/home/migrate/Maildir/.build_usermap_rcvd/";
my $my_sentDir = "/home/migrate/Maildir/.build_usermap_sent/";
my $my_timeout = 300;
my $my_searchString = "BA Migrate Script Usermap: ";
my $my_max_export_script_size = 20000;
my $my_migrate_email_address = 'migrate@migrate.schoolname.edu';
my $my_fc_admin_email_address = 'administrator@schoolname.edu';
my $my_fc_ip_address = '192.168.1.24';
my $my_migrate_ip_address = '192.168.1.6';
my $my_to_ip_address = '192.168.1.26';

build_usermap::initialize($my_list_of_users_filename, $my_rcvdDir, $my_timeout, $my_searchString, $my_max_export_script_size, $my_migrate_email_address, $my_fc_admin_email_address, $my_fc_ip_address, $my_migrate_ip_address, $my_to_ip_address);

system("rm -rf $my_rcvdDir");
system("rm -rf $my_sentDir");

build_usermap::build_usermap();
