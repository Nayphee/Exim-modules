###
Some little instructions for using the bouncelisting scipts

* set up a MySQL database that you can use 
(If you don't know how to do this, it's a good thing that you learn how
to do this from the many SQL howtos on the internet)

* drop the bouncewatch.pl and Bouncelist.pm into /etc/exim/perl

* set the configurations in each file

* call bouncewatch.pl, if possible as a non root user (might have to change
permissions in places, every 5 minutes from crontab.

* install the start script into a place which can start upon system booting, 
and make any necessary rc.d links if you need to. You can check that the socket
is up with netstat.

* edit your exim.conf to include the acl fragment, and restart exim. The acl
will get the results of the module and deal with them accordingly.

Once you have done all this you can
monitor the database with the following SQL command:-

SELECT auser,count(*) FROM Bounces GROUP BY auser ORDER BY 2 DESC LIMIT 10;

and you should get a top-ten list of who is bouncing the most
