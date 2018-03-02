#!/usr/bin/perl -w

##### EXIM log file MailMaid (Maidfull Watcher)
# By Nathan Butcher 2006
# This script is free software. Use at your own risk. It may blow your head off.
# 
# Trawls the database of full mailboxes and rechecks their status
# updating the information in the MySQL database. A perfect compliment to your
# happy maidfull life! Okaerinasai Go shuujinsama ^^;
#
# Checks occur in the maildirsize file in the offending directory.
# if it's under the limit, the user is deleted from the database.
# if not, the time stamp is updated.
#

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
my $localdom="/etc/exim/localdomains";			# exim localdomains file
#########################################################

### Set up db calls
my $dbh;
my $usercheck;
### other globals
my @entry;
my $mbservers="";

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
			die "Maidfull -> SQL Connect failure: $DBI::errstr\n";
		}
	}
	
	$usercheck = undef;

	###Define search for finding same msgid
	unless (defined($usercheck)) {
		$usercheck = $dbh->prepare("SELECT * FROM $dbtable");

		###Danger, Will Robinson, DANGER
		unless (defined($usercheck)) {
			$dbh->disconnect;
			$dbh = undef;
			die "Maidfull -> Failure to establish usercheck: $DBI::errstr\n";
		}
	}
}

#---------------------------------------------------------------------------------
### MAIN 

### establish what mailboxes we can access at this point in time
open (LOCDOM, $localdom) || die "Maidfull -> Localdomain file not found. Unable to establish accessible mailboxes\n";

### much faster to pump the mailbox serverlist into a scalar. It won't be too huge (will we need hundreds of mb servers?).
### besides, pattern matching across an array would consume more cpu cycles and be unwieldy to code.
while (<LOCDOM>) {
	chomp;
	next unless (/\S+/);
	$mbservers="$mbservers$_ "; 
}
close (LOCDOM);

###Sanity check our mailbox servers
unless ($mbservers) {
	die "Maidfull -> Not authorised to act on behalf of any mailbox server!\n";
} 

###Now we can establish a database connection
&connection;

###establish our search criteria
unless ($usercheck->execute()) {
	$usercheck->finish;
	$dbh->disconnect;
	die "Maidfull-> User search failure: $DBI::errstr\n";
}

### trawl through search results, line by line
while (@entry = $usercheck->fetchrow_array()) {

	### Pull username and domain from data`
	chomp @entry;
	my $auser = $entry[0];
	my ($uname, $userdom) = split(/\@/, $entry[0]);

	### If we don't manage user's mailbox at this server, skip this database entry
	next unless ($mbservers =~ /$userdom/);
	
	### Pull user information and mail directory from database record
	my $udir = $entry[1];
	my $utime = $entry[2];

	### reset maildirsize variables used in checking this user
	my $firstline=1;
	my $listsize=0;
	my $sizetotal=0;

	### now to access the maildirsize in this user's directory and calculate totals
	### first, open user's maildirsize file
	unless (open (DIRINFO, "$udir/maildirsize")) {
		warn "Maidfull -> Maildirsize file for [ $udir ] at [ $uname ] does not exist!\n";
		next;
	}

	### go through file line by line collecting data
	while (<DIRINFO>) {
		
		### some sanity checking
		next unless(/[0-9]+/);
	
		### if this is the first line, take listed size
		if ($firstline == 1) {

			($listsize)=/(\S+)S/;
			$firstline = 0;

		} else {
			
			### otherwise add other modification file size lines into a total
			my ($value)=/(\S+)\s/;
			$sizetotal= ($sizetotal + $value);
		}
	}	
	close (DIRINFO);
	
	### decide whether to remove user from db, or update timestamp
	if ($sizetotal lt $listsize) {

		### remove user from database as maildir not full anymore (good customer)
		unless ($dbh->do( "DELETE FROM $dbtable WHERE auser=?", undef, $auser)) {
			$usercheck->finish;
			$dbh->disconnect;
			die "maidfull -> Deleting DB entry [ $auser ] failed\n";
		}

	} else {

		### update users timestamp in database as maildir is still full (lazy customer)
		my $tstamp = (time());
		unless ($dbh->do( "UPDATE $dbtable SET tstamp=$tstamp WHERE auser=?", undef, $auser)) {
			$usercheck->finish;
			$dbh->disconnect;
			die "Maidfull -> Updating DB entry [ $auser ] failed\n";
		}
	}
}

###no more goats or maids left
$usercheck->finish;
$dbh->disconnect;
