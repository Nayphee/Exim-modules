!/usr/bin/perl -w

##### EXIM log file Bounce Watcher
# By Nathan Butcher 2006
# This script is free software. Use at your own risk.
# 
# Trawls the Exim log file for bouncing messages, and collates that
# information into a MySQL database
#
# This script relies on the Perl DBI module and the "logtail" command
# line tool. Make sure to install and define where it is

# Version 2006/06/19

# Here's the database schema you will need to add to your database
#
# MYSQL database
# CREATE TABLE Bouncy (
#   msgid varchar(70) NOT NULL default '',
#   auser varchar(255) NOT NULL default '',
#   sender varchar(255) NOT NULL default '',
#   tstamp int(12) default NULL,
# );

use strict;
use DBI;
use POSIX;

################## PLEASE CONFIGURE THESE:- #############
my $dbname="yourdatabase";				# Database name
my $dbtable="Bounces";					# Table in Database 
my $dbhost="yourmysqlhostnamehere";			# Database host
my $dbuser="yourdbuser";				# Database Username
my $dbpass="yourdbpassword";				# Database Password
my $scanfile = "/var/log/exim/mainlog";			# log file to tail
my $offsetfile = "/etc/exim/perl/mainlog.offset";	# log file offset
my $logtail = "/usr/sbin/logtail";                      # logtail command
my $timeout = 24*3600;					# old bounce timeout
#########################################################

##last update timestamp
my $lastup;
### Set up db calls
my $dbh;
my $idcheck;

### Get hostname of system
my $hostnm=(`hostname`);
chomp $hostnm;
## Check to ensure hostname isn't too long
if ( length($hostnm) > 50 ) {
	$hostnm=substr($hostnm,0,50);
}

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
			print "SQL Connect failure: $DBI::errstr\n";
			exit 0;
		}
	}
	
	$idcheck = undef;

	###Define search for finding same msgid
	unless (defined($idcheck)) {
		$idcheck = $dbh->prepare("SELECT * FROM $dbtable WHERE msgid=?");

		###Danger, Will Robinson, DANGER
		unless (defined($idcheck)) {
			print "Failure to establish idcheck: $DBI::errstr\n";
			$dbh->disconnect;
			$dbh = undef;
			exit 0;
		}
	}
}

#----------------------------------------------------------------------------
### SUBROUTINE: find_authuser
### DESCRIPTION: Hunt through the log file to find the first case of the bounced mail
### PURPOSE: To find authuser, so we know who to yell at if he is bouncy
### ARGS: <message id>

sub find_authuser {

	## get argument (in this case, the message id we want)
	my ($find_this_id) = (@_);

	## prototypes and defaults (if we can't find anything)
	my $auth_info="N/A";
	my $send_info="N/A";

	##Open file again, kill self if not there
	open(AUTH_HUNT, $scanfile) || die "Bouncewatcher says: $scanfile file has gone missing!";

	##Walk through each line
	while (<AUTH_HUNT>) {
	
		# Skip lines that do not have the message ID we want
		next unless /$find_this_id\s\<\=/;

		# if we spot an authinfo line, use it
		if (/A\=.....\:/) {

			# fetch the auth info
			($auth_info) = /\sA\=.....\:(\S+)\s/;
		}
		
		#fetch the sender info
		($send_info) = /\s<\=\s(\S+)/;
	}

	##Close file
	close(AUTH_HUNT);

	##send info back from whence it came
	return ($auth_info, $send_info);
}

#----------------------------------------------------------------------------
### MAIN 

###Check to make sure that connection is up
&connection;

###Check to see that logtail is available
unless ( -e "$logtail") {
	print "Bouncewatcher can't find logtail. Please install it.\n";
	exit 0;
}

###execute logtail command to scan new log entries
my @logbatch = (`$logtail $scanfile $offsetfile`);

## go through results
foreach (@logbatch) {
	
	## if we don't see bounces, skip the line
	next unless /\s\*\*\s/;
			
	### this incredible pattern pulls out individual date info in order to make unix timestamp
	my ($t_yr, $t_mon, $t_day, $t_hr, $t_min, $t_sec, $mid, $recip) = /^([0-9]+)\-([0-9]+)\-([0-9]+)\s([0-9]+)\:([0-9]+)\:([0-9]+)\s(\S+)\s\*\*\s(\S+)/;

	## Make info for server - message id pair in db
	my $mid_hn = "$hostnm:$mid";

	## make unix timestamp for new issue
	$t_yr = $t_yr - 1900;
	$t_mon = $t_mon - 1;
	my $utime= mktime($t_sec,$t_min,$t_hr,$t_day,$t_mon,$t_yr,-1,0,-1);

	###OK we add this new entry
	##search for same host-msgid pair in db
	unless ($idcheck->execute($mid_hn)) {
		die "Bouncewatch-> Message ID search failure: $DBI::errstr\n";
	}

	## pull down entry
	my $dbentry = $idcheck->fetchrow_hashref;

	## define mail address refs
	my $auser;
	my $sender;

	## if same msgid exists
	if (defined($dbentry)) {

		## grab details from db
		$auser = $dbentry->{auser};
		$sender = $dbentry->{sender};

	} else {
		
		## scan file for info from log message id (ho hum, how slow)
		($auser, $sender)=&find_authuser($mid);
	}

	##drop new bounce issue into DB
	##unless we have no user info, (or its a local bounce)
	unless ($sender eq '<>' || ($auser eq 'N/A' && $sender eq 'N/A')) {
		$dbh->do( "INSERT INTO $dbtable ( msgid, auser, sender, tstamp) VALUES (?, ?, ?, ?)", undef, $mid_hn, $auser, $sender, $utime ) || die "Bouncewatch -> Item insert failure : $DBI::errstr\n";
	}
}

### Clean out old database entries which have expired.
## find out deletion threshold from current time
my $threshold = time - $timeout;

## delete records deemed to be old
$dbh->do("DELETE FROM $dbtable WHERE (!isnull(tstamp) and tstamp < $threshold)") || die "Bouncewatch -> Item Deletion failure: $DBI::errstr\n";

$idcheck->finish;

##That will be all gentlemen.
$dbh->disconnect;
