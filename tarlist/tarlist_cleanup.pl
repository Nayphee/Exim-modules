#!/usr/bin/perl

## Run this script regularly from a cronjob on your database server
## Every 30 minutes is a long enough period of time 
## It assumes that Tarlist.pm is in /etc/exim/perl

use lib "/etc/exim/perl";
use Tarlist;

&Tarlist::cleanup();
