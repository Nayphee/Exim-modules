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

### Some install info

* copy the Tarlist.pm to /etc/exim/perl

* set the configurations in the module

* install the start script into a place which can start upon system booting,
and make any necessary rc.d links if you need to. You can check that the socket
is up with netstat.

* edit your exim.conf to include the acl fragment, and restart exim. The acl
will get the results of the module and deal with them accordingly.

* On your database server, copy the Tarlist.pm over to /etc/exim/perl and
place the tarlist_cleanup.pl script somewhere. Run the cleanup script from
a cronjob (say every 30 minutes)

Once you have done all this you can
monitor the database with the following SQL command:-

SELECT IP,count(*) FROM Tarlist GROUP BY IP ORDER BY 2 DESC LIMIT 10;

and you should get a top-ten list of who is offending the most.

