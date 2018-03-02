#!/usr/bin/perl -w

##### EXIM log file MailMaid (Mailfull Watcher)
# By Nathan Butcher 2006
# This script is free software. Use at your own risk.
# 
# Trawls the Exim log file for full maildir messages, and collates that
# information into a MySQL database. A perfect compliment to your
# happy mailfull life! ^^;
#
# This script relies on the Perl DBI module and the "logtail" command
# line tool. Make sure to install and define where it is

# Version 2006/10/17

# Here's the database schema you will need to add to your database
#
# MYSQL database
# CREATE TABLE Mailfull (
#   auser varchar(100) NOT NULL default '',
#   udir varchar(255) NOT NULL default '',
#   tstamp int(12) default NULL,
# );

use strict;
use DBI;
use POSIX;

################## PLEASE CONFIGURE THESE:- #############
my $dbname="Bouncy";					# Database name
my $dbtable="Mailfull";					# Table in Database 
my $dbhost="localhost";					# Database host
my $dbuser="bouncer";					# Database Username
my $dbpass="!nathan!";					# Database Password
my $scanfile = "/var/log/exim/mainlog";			# log file to tail
my $offsetfile = "/root/work/mainlog.offset";		# log file offset
my $logtail = "/usr/sbin/logtail";                      # logtail command
#########################################################

### Set up db calls
my $dbh;
my $usercheck;

#-------------------------------------------------------------------------
### SUBROUTINE: connection
### DESCRIPTION: Check to make sure we can connect with DB, and then define searches we will be using
### PURPOSE: set up db
### ARGS: <NONE>

sub connection {

	### If not connected to MySQL, do it now
	unless (defined($dbh)) {
		$dbh = DBI->connect("DBI:mysql:database=$dbname;host=$dbhost", $dbuser, $dbpass, { RaiseError => 0, PrintError => 0, AutoCommit => 1 } );

		###error!
		unless (defined($dbh)) {
			die "Mailfull -> SQL Connect failure: $DBI::errstr\n";
		}
	}
	
	$usercheck = undef;

	###Define search for finding same msgid
	unless (defined($usercheck)) {
		$usercheck = $dbh->prepare("SELECT * FROM $dbtable WHERE auser=?");

		###Danger, Will Robinson, DANGER
		unless (defined($usercheck)) {
			$dbh->disconnect;
			$dbh = undef;
			die "Mailfull-> Failure to establish usercheck: $DBI::errstr\n";
		}
	}
}

################################## MAIN 

###Check to see that logtail is available
unless ( -e "$logtail") {
	die "Mailfull can't find logtail. Please install it.\n";
}

###Check to make sure that connection is up
&connection;

###execute logtail command to scan new log entries
my @logbatch = (`$logtail $scanfile $offsetfile`);

## go through results
foreach (@logbatch) {
	
	## if we don't see bounces, or retries, or external bounces, skip the line
	next unless /\s\*\*\s/;
	next unless /retry timeout exceeded/;
	next unless /<\S+>/;
	
	### this yanks out the maildir
	my ($umdir) = /\*\*\s(\S+)\s</;
	### this yanks out the user responsible
	my ($usern) = /<(\S+)>/;

	### Sanity check size of user data for this incident
	if ((length($umdir) > 255) || (length($usern) > 100) ) {
		warn "Mailfull-> Sanity error: User name [ $usern ] or mail directory [ $umdir ] too big for database!\n";
		next;
	}

	### this incredible pattern pulls out individual date info in order to make unix timestamp
	my ($t_yr, $t_mon, $t_day, $t_hr, $t_min, $t_sec, $mid, $recip) = /^([0-9]+)\-([0-9]+)\-([0-9]+)\s([0-9]+)\:([0-9]+)\:([0-9]+)\s(\S+)\s\*\*\s(\S+)/;

	## make unix timestamp for new issue
	$t_yr = $t_yr - 1900;
	$t_mon = $t_mon - 1;
	my $utime= mktime($t_sec,$t_min,$t_hr,$t_day,$t_mon,$t_yr,-1,0,-1);

	###OK we do something with this information
	##search for same user in db
	unless ($usercheck->execute($usern)) {
		die "Mailfull-> User search failure: $DBI::errstr\n";
	}

	## pull down entry
	my $dbentry = $usercheck->fetchrow_hashref;

	## if user already exists
	if (defined($dbentry)) {
	
		##Don't really have to do anything here, but we could update timestamp, so why don't we?
		##If resources are really a problem, we can comment this section out (unlikely)
		unless ($dbh->do( "UPDATE $dbtable SET tstamp=? WHERE auser=?", undef, $utime, $usern)) {
			$usercheck->finish;
			$dbh->disconnect; 
			die "Mailfull -> Updating entry failure : $DBI::errstr\n";
		}

	} else {

		##drop new mailfull bounce issue into DB
		unless ($dbh->do( "INSERT INTO $dbtable (auser, udir, tstamp) VALUES (?, ?, ?)", undef, $usern, $umdir, $utime )) {
			$usercheck->finish;
			$dbh->disconnect;
			die "Mailfull -> Item insert failure : $DBI::errstr\n";
		}

	}
}

##That will be all gentlemen.
$usercheck->finish;
$dbh->disconnect;
