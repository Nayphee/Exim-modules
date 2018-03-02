#!/usr/bin/perl -w

# Copyright (c) 2006 
# Written by Nathan Butcher
#
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
#
# Version: 0.5
# This plugin monitors the status of classic vinum volumes. Desgined for use
# on legacy FreeBSD 4.x systems. Modern gvinum support is not available
#
# Usage:   check_vinum <vinum volumes> ...
# Example: check_vinum myvol mymirror mystripe
#	OK myvol:up mymirror:up mystripe:up

use strict;

### standard nagios variables
my %ERRORS=('DEPENDENT'=>4,'UNKNOWN'=>3,'OK'=>0,'WARNING'=>1,'CRITICAL'=>2);
my $state="UNKNOWN";
my $msg="FAILURE";

### blow out user who fails to mention any volumes
if ($#ARGV +1 < 1) {
	print "Not enough arguments!\nUsage: $0 <vinum volumes> ...\n";
	exit $ERRORS{$state};
}

### give the bird to users who aren't running FreeBSD
if ($^O ne 'freebsd') {
	print "This plugin is only applicable on FreeBSD <= 4.x\n";
	exit $ERRORS{$state};
}

### init vars specific to this plugin
my $statcommand="vinum lv";
my $critflag=0;
my $mess="";
my @output;

### run command
if (! open STAT, "$statcommand|") {
	print ("$state $statcommand returns no result!");
	exit $ERRORS{$state};
}

### gather data and slug it in array
while(<STAT>) {
	push @output, $_;
}
close(STAT);

### run volume names against output
foreach my $volu (@ARGV) {

	## not seen vol yet
	my $seenflag=0;

	## hunt for vol through results
	foreach (@output) {

		## if we see it in results
		if (/^V\s$volu/) {

			## mark as seen, get status, generate output
			$seenflag=1;
			my ($status, $plex, $size ) = /State\:\s+(\S+)\s+Plexes\:\s+([0-9]+)\s+Size:\s+(\S+\s\S+)/;
			$mess=$mess . "{$volu\:$status P\:$plex ($size)} ";
			if ($status ne "up") {
				$critflag=1;
			}
		}
	}	
	
	## if we never saw vol, trgger critical event
	if ($seenflag == 0) {
		$mess=$mess . "{$volu\:N/A} ";
		$critflag=1;
	}
}

close(STAT);
$msg=$mess;

if ($critflag) {
	$state = "CRITICAL";
} else {
	$state = "OK";
}

#goats away!
print $state, " ", $msg;
exit ($ERRORS{$state});
