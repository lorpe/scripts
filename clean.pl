#!/usr/bin/perl -w

use warnings;
use strict;
use FindBin;
use lib "$FindBin::RealBin/../../inc";
use Tools;

my $puppetmaster_ip = "puppetserverhostname";
my $hostname =  $ARGV[0];

my $CONFIG = do "$FindBin::RealBin/../../inc/Config.pl";
set_debug($CONFIG->{DEBUG});
set_log_file($CONFIG->{LOG_DIRECTORY} . "/" . $hostname);

# Suppression du certificat sur le serveur puppet
syscmd("/usr/bin/ssh -o StrictHostKeyChecking=no root@".$puppetmaster_ip." puppetca --clean $hostname.vmhostname", 1);
