!/usr/bin/perl
#
# Implements commands to be used via ${readsock
#
# Copyright 2003 Alun Jones, auj@aber.ac.uk
#
# This may be freely copied and modified.
#
# The problem:
#
# Calling ${perl leaves you with possible concurrency problems. If
# you are opening a DBM file, you need to lock it first. Under heavy
# load, or if the DBM file is corrupt, you end up with a single wedged
# exim process holding a lock and able to block all other deliveries.
# Or, if the DBM file is corrupted enough to crash the running process,
# you end up with all delivery attempts crashing.
#
# With exim 4 comes readsocket. This chucks data into a unix domain
# socket and reads the answer back. If no answer comes within a specified
# timeout, then it lets you default somewhere. So...
# replace ${perl{ with ${readsocket{ (with sensible timeout and failure
# actions). If this daemon dies or freezes or whatever, ${readsocket will 
# timeout and let mail carry on going.
# 

# MODIFIED: in order to use Bouncelist.pm, by Nathan Butcher 2006


use lib "/etc/exim/perl";
use Bouncelist;
use Socket;

##MODIFICATIONS
my $sockname = "/var/run/exim_bounced.sock";
my $pidfile = "/var/run/exim_bounced.pid";

my %cmds = (
	"BOUNCELIST" => \&Bouncelist::lookup,
);
##END MODIFICATIONS

socket(UNIX, PF_UNIX, SOCK_STREAM, 0) || die "socket: $!";
unlink($sockname);
bind(UNIX, sockaddr_un($sockname)) || die "bind: $!";
chmod(0666, $sockname);
listen(UNIX, SOMAXCONN) || die "listen: $!";

if (open(F, "<$pidfile"))
{
    my $running = <F>;
    close(F);
    chop($running);
    die "Another bounce_sockd is running (pid = $running)\n"
        if (-e "/proc/$running");
}

# Record out PID.
open(F, ">$pidfile") || die "Can't write $pidfile: $!\n";
print F "$$\n";
close(F);

close(STDIN);
close(STDOUT);
close(STDERR);

$SIG{'PIPE'} = sub { };

while (1)
{
    accept(C, UNIX);
    sysread(C, $_, 1024);

    s/^\s*//;
    my ($cmd, @args) = split('\s', $_);
    if (defined($cmds{$cmd}))
    {
		my $result = &{$cmds{$cmd}}(@args);
		syswrite(C, $result);
    }
    close(C);
}
