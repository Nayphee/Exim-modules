#!/usr/bin/perl -w

# EXIM log file Bounce Watcher - EXIM ACL socket
# By Nathan Butcher
#
# Version 2006/06/22
# This is free software. use at your own risk.

# This is the PERL module which needs to be loaded into a socket
# in order for exim to use to track which users have been sending many 
# many bouncy mails.
#
# This module will send back a single string: two numbers seperated by a colon
# If a user is in the Bounce database, this module will return:-
# (bounces in last hour):(bounces in last 24 hours) 
# If we experience an error (or if user is not in the bounce database)
# this module will return '0:0' back to exim to deal with.

# MYSQL database
# CREATE TABLE Bounces (
#   msgid varchar(70) NOT NULL default '',
#   auser varchar(255) NOT NULL default '',
#   sender varchar(255) NOT NULL default '',
#   tstamp int(12) default NULL,
# );

package Bouncelist;

use strict;
use DBI;
use POSIX;
use Socket;

################## PLEASE CONFIGURE THESE:- #############
my $dbname="yourdbname";                                # Database name
my $dbtable="Bounces";                                  # Table in Database
my $dbhost="mysql.dentaku.gol.com";                     # Database host
my $dbuser="yourdbuser";                                # Database Username
my $dbpass="yourdbpassword";                            # Database Password
#########################################################

### Set up db calls
my $dbh;
my $acheck;

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
	
	###Define search for finding number of bounces in timeframe
	unless (defined($acheck)) {
		$acheck = $dbh->prepare("SELECT count(auser) FROM $dbtable WHERE auser=? AND tstamp > ?");

		###Danger, Will Robinson, DANGER
		unless (defined($acheck)) {
			print "Failure to establish acheck: $DBI::errstr\n";
			$dbh->disconnect;
			$dbh = undef;
			return 0;
		}
	}
	return 1;
}

#----------------------------------------------------------------------------
### SUBROUTINE: lookup
### DESCRIPTION: see if user exists in bounce db, and return number
### PURPOSE: Main sub. Receive user argument from MTA, find who is naughty
### ARGS: <authenticated_user> from MTA (exim)

sub lookup {

	## get username from MTA
	my ($user) = (@_);

	## get the current time
	my $now = time;
	## timestamp from one hour ago
	my $lastday = $now - 24*3600;
	my $lasthour = $now - 3600;

	## string to use when we encounter errors or no user
	my $dienasty='0:0';

	###Check to make sure that connection is up
	unless (&connection) {
		return $dienasty;
	}

	##do user search for past 24 hrs
	unless ($acheck->execute($user, $lastday)) {
		print "Bouncelist.pm database error: $DBI::errstr\n";
		$acheck->finish;
		$dbh->disconnect;
		$dbh = undef;
		return $dienasty;
	}
		
	## pull down bounces
	my $day_bounces = $acheck->fetchrow_array;

	## if user is not even in there, quit
	if (! defined($day_bounces) || $day_bounces == 0) {
		return $dienasty;
	}

	## user is there. now get bounces from 1 hr ago
	unless ($acheck->execute($user, $lasthour)) {
		print "Bouncelist.pm database error: $DBI::errstr\n";
		$acheck->finish;
		$dbh->disconnect;
		$dbh = undef;
		return $dienasty;
	}
		
	## pull down entry
	my $hour_bounces = $acheck->fetchrow_array;

	## If we can't get any bounces in the last hour, set to 0
	if (! defined($hour_bounces)) {
		$hour_bounces = 0;
	}

	my $response = "$hour_bounces\:$day_bounces";
	return ($response);	
	
}

1;
