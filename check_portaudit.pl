#!/usr/bin/perl -w

# check_portaudit Nagios plugin for monitoring FreeBSD ports
# Copyright (c) 2007 
# Written by Nathan Butcher

# Released under the GNU Public License
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA

# Version: 0.5.1
# Date : 7th June 2007
# for FreeBSD only

# Usage:   check_portaudit <command> <display> <database age limit (days)>
# Example: check_portaudit security show 3
#
# COMMANDS:-
# security - runs portaudit and displays vulnerable packages
# updates - run portversion and lists packages which could be updated
#
# You can choose whether to show or not show vulnerable/old packages by name
# The message line may be incredibly huge if you have a lot of old/vulnerable
# packages
#
# DISPLAY:-
# show - shows all packages by name when WARNING
# noshow - do not show package names. Simply display number of packages
#
# The database age limit option will produce CRITICAL errors by default if
# either the portaudit database or the ports tree is older than a certain
# number of days. If this argument is not specified, the default will be 7 days.
#
# WARNINGS will be delivered should old/vulnerable packages be discovered 
# otherwise you will get an OK result.
# 
# It is STRONGLY recommended that you update the portaudit database and portsdb
# regularly from crontab. This will prevent the databases from ever going 
# out of date. This plugin cannot do this job because doing so would require
# super-user privileges.

use strict;

my %ERRORS=('DEPENDENT'=>4,'UNKNOWN'=>3,'OK'=>0,'WARNING'=>1,'CRITICAL'=>2);
my $state="UNKNOWN";
my $msg="FAILURE";

#################LOCATION OF IMPORTANT FILES#######################
my $portauditloc="/usr/local/sbin/portaudit";
my $portauditdb="/var/db/portaudit/auditfile.tbz";
my $portverloc="/usr/local/sbin/portversion";
my $portsdb="/usr/ports/" . `ls /usr/ports | grep .db | head -n1`;
chomp $portsdb;
###################################################################

if ($^O ne 'freebsd') {
	print "This plugin is designed for use on FreeBSD\n";
	exit $ERRORS{$state};
}

if ($#ARGV+1 !=2 && $#ARGV+1 != 3) {
	print "Usage: $0 <security/updates> <show/noshow> <db age limit>\n";
	exit $ERRORS{$state};
}

my $command=$ARGV[0];
if ($command ne "security" && $command ne "updates") {
	print "Commands are : security, updates\n";
	exit $ERRORS{$state};
}

my $displaypkg=$ARGV[1];
if ($displaypkg ne "show" && $displaypkg ne "noshow") {
	print "Display commands are : show, noshow\n";
	exit $ERRORS{$state};
}

my $dbage=7;
if ($ARGV[2]) {
	$dbage=$ARGV[2];
}

###common variable declaration
my $msglist="";
my $packcount=0;
my $exeloc;
my $dbloc;
my $statcommand;
my $pkgtype;

### security or updates
if ($command eq "security") {
	$exeloc = $portauditloc;
	$dbloc = $portauditdb;
	$statcommand = "$portauditloc | grep Affected";
	$pkgtype="vulnerable";
}

if ($command eq "updates") {
	$exeloc = $portverloc;
	$dbloc = $portsdb;
	$statcommand = "$portverloc -v | grep needs";
	$pkgtype="obsolete";
}

#########################################
	
### sanity check existence of binary
unless ((stat("$exeloc"))[9]) {
	print "$exeloc executable not found! Please install\n";
	exit $ERRORS{$state};
}

### sanity check and check timestamp of portaudit database
my $dbstat = (stat("$dbloc"))[9];
unless ( $dbstat ) {
	print "$dbloc database does not exist! Please update database\n";
	exit $ERRORS{$state};
}

### calculate the age of the database and error report an old one
$dbage = (($dbage * 86400));
$dbstat = ((time - $dbstat));

### report if database is old
if ($dbage < $dbstat) {
	$state="CRITICAL";
	print "$state Database is out of date! Please update database\n";
	exit $ERRORS{$state};
}

### run portaudit
if (! open STAT, "$statcommand|") {
	print ("$state '$statcommand' command returns no result!\n");
	exit $ERRORS{$state};
}

### exists to trap packages with multiple vulns from showing up twice
my %seen = ();

### discover vulnerable packages
while(<STAT>) {
	chomp;
	my $pack="";

	### pick and choose information depending on search command
	if ($command eq "security" ) {
		($pack) = (/^Affected package\:\s+(\S+)/);
	}
	if ($command eq "updates" ) {
		($pack) = (/^(\S+)\s+/);
	}
	
	### only add to the list if we haven't seen this package before
	unless ($seen{$pack}) {	
		$msglist=$msglist . " $pack";
		$seen{$pack}=1;
		$packcount=$packcount+1;
	}
}
close (STAT);

### prepare to report vulnerable packages
if ($packcount == 0) {

	### no old/bad packages
	$state = "OK";

} else {

	### old/bad packages detected
	$state = "WARNING";

	### to display or not display packages, that is the question
	if ($displaypkg eq "show") {
		$msglist = "- {$msglist } ";
	} else {
		$msglist="";
	}
}

### take this message to Nagios
$msg = sprintf "%s : %s %s %s\n", $command, $packcount, $pkgtype, $msglist;
print $state, " ", $msg;
exit ($ERRORS{$state});
