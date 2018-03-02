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
