#!/usr/bin/env perl
# FILENAME: turbo_scan.pl
# CREATED: 11/03/16 01:22:01 by Kent Fredric (kentnl) <kentfredric@gmail.com>
# ABSTRACT: Faster portage check

use strict;
use warnings;

use Parallel::ForkManager;
use Path::Tiny qw( path );

my @cats = grep { !-f $_ } path('/usr/local/gentoo')->children();

my $pm = Parallel::ForkManager->new( 1 );

while(  my $job = shift @cats ) {
  printf STDERR "Queue: %d\n", scalar @cats;
  my $pid = $pm->start and next;
  chdir $job;
  print STDERR "\e[31m* \e[0mScanning $job\n";
  system('/usr/bin/python3.5', '-bO', '-OO', '/usr/lib/python-exec/python3.5/repoman','full','-q');
  $pm->finish;
}
$pm->wait_all_children;

