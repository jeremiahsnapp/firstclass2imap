#!/usr/bin/perl

open( STDOUT, '>', "/var/log/migration/build_usermap" ) or die "Can't redirect STDOUT: $!";
open( STDERR, ">&STDOUT" ) or die "Can't dup STDOUT: $!";

use YAML::Tiny;
use build_usermap;

# you need to have a csv file that matches FirstClass userid's with the corresponding account on the new email system
# firstclass_userid,new_email_system_account_name

# Create a YAML file
my $yaml = YAML::Tiny->new;

# Open the config
$yaml = YAML::Tiny->read('migration.cfg');

my $rcvdDir = $yaml->[0]->{mailDir} . ".build_usermap_rcvd/";
my $sentDir = $yaml->[0]->{mailDir} . ".build_usermap_sent/";

build_usermap::initialize;

system("rm -rf $rcvdDir");
system("rm -rf $sentDir");

build_usermap::build_usermap;
