#!/usr/bin/perl -w

# Tarlisting - EXIM ACL socket
# By Nathan Butcher 2006
#
# Verison 2006/06/21

# This is the PERL module which needs to be loaded into a socket
# for exim use, to track which servers which have been sending many 
# mails to many non-existant mailboxes (or some other punishable offence)
# The MTA side (exim) will determine what to trigger tarpitting.
#
# This module accepts an IP address as it's input. We assume here that exim
# acls will call this module if it suspects funny business.
# As it's first job, we add a timestamped offense for the IP to the database.
# If an IP is in the Tarlist database, this module will return
# the number of times the given IP address has done this so far back to exim. 
#
# Exim acl will then determine what do to with these offenders, but most likely
# we will delay their mail, multiplied per offense over our offense threshold, 
# until they will be waiting until next week for their mail to work again - by
# which time they are on spam blacklists (presumably). 

# MYSQL database
# CREATE TABLE Tarlist (
#   IP varchar(16) NOT NULL default '',
#   tstamp int(12) default NULL,
# );

package Tarlist;

use strict;
use DBI;
use POSIX;
use Socket;

################## PLEASE CONFIGURE THESE:- #############
my $dbname="yourdbname";				# Database name
my $dbtable="Tarlist";					# Table in Database
my $dbwltable="IPlist";					# Whitelist DB
my $dbhost="yourdbhostname";				# Database host
my $dbuser="yourdbuser";				# Database Username
my $dbpass="yourdbpassword";				# Database Password
my $timeout= 4*3600;					# Timeout for listing
my $white_list=1;					# Use Whitelist?
#########################################################

### Set up db calls
my $dbh;
my $wlcheck;
my $crapcheck;
## Other globals
my $ipee;
my $now;

#----------------------------------------------------------------------------
### SUBROUTINE: connection
### DESCRIPTION: Check to make sure we can connect with DB, and then define searches we will
### PURPOSE:Use later to test entries in the database
### ARGS: <NONE>

sub connection {

	### If not connected to MySQL, do it now
	unless (defined($dbh)) {
		$dbh = DBI->connect("DBI:mysql:database=$dbname;host=$dbhost", $dbuser, $dbpass, { RaiseError => 0, PrintError => 0, AutoCommit => 1 } );

		###error!
		unless (defined($dbh)) {
			print "Connect failure: $DBI::errstr\n";
			return 0;
		}
	}
	
	###Define search for finding if IP is in whitelist already
	unless (defined($wlcheck)) {
		$wlcheck = $dbh->prepare("SELECT IP FROM $dbwltable WHERE IP=?");

		###Danger, Will Robinson, DANGER
		unless (defined($wlcheck)) {
			print "Failure to establish wlcheck: $DBI::errstr\n";
			$dbh->disconnect;
			$dbh = undef;
			return 0;
		}
	}

	###Define search to check crapout score for IP address
	unless (defined($crapcheck)) {
		$crapcheck = $dbh->prepare("SELECT COUNT(IP) FROM $dbtable WHERE IP=?");

		###Danger, Will Robinson, DANGER
		unless (defined($crapcheck)) {
			print "Failure to establish crapcheck: $DBI::errstr\n";
			$dbh->disconnect;
			$dbh = undef;
			return 0;
		}
	}
	return 1;
}

#----------------------------------------------------------------------------
### SUBROUTINE: lookup
### DESCRIPTION: see if user exists in whitelist, add entry, return total
### PURPOSE: Main sub. Receive user argument from MTA, find who is naughty
### ARGS: <suspicious IP address> from MTA (exim)

sub lookup {

	## get IP from MTA
	($ipee) = (@_);

	## get the current time
	$now = time;

	###Check to make sure that connection is up
	unless (&connection) {
		return 0;
	}

	## Do whitelist check? ($white_list must be true)
	unless ($white_list == 0) {

		##do whitelist check for this IP
		unless ($wlcheck->execute($ipee)) {
			$wlcheck->finish;
			$crapcheck->finish;
			$dbh->disconnect;
			$dbh = undef;
			return 0;
		}
		
		## pull down row
		my $wlresult = $wlcheck->fetchrow_hashref;

		## if IP is in our whitelist, then quit
		if (defined($wlresult)) {
			return 0;
		}
	}

	## OK, so we aren't whitelisted, add this transgression
	$dbh->do( "INSERT INTO $dbtable ( IP, tstamp ) VALUES (?, ?)", undef, $ipee, $now) || return 0;

	## now get crapout score for this IP address
	unless ($crapcheck->execute($ipee)) {
		$wlcheck->finish;
		$crapcheck->finish;
		$dbh->disconnect;
		$dbh = undef;
		return 0;
	}
		
	## pull down entry
	my $crapout = $crapcheck->fetchrow_array;

	return ($crapout);	
}

#----------------------------------------------------------------------------
### SUBROUTINE: cleanup
### DESCRIPTION: wipe out old entries in the Tarlist
### PURPOSE: We don't want the database to get too big unneccessarily. Best to run this sub from the SQL server itself.
### ARGS: <NONE>

sub cleanup {
	
	# get current time
	$now = time;

	## get connection
	unless (&connection) {
		return 0;
	}

	## find threshold
	my $threshold = time - $timeout;

	### delete records deemed to be old
	my $rows = $dbh->do("DELETE FROM $dbtable WHERE (!isnull(tstamp) and tstamp < $threshold)") || die "Tarlist -> Item Deletion failure: $DBI::errstr\n";

	## A message for our cron daemon
	printf "Tarlist wiped out %d obsolete row%s.\n", $rows, $rows == 1 ? "" : "s";
	
	##shutdown connection to the db
	$wlcheck->finish;
	$crapcheck->finish;
	$dbh->disconnect;
	$dbh = undef;
	return 0;

}

1;
