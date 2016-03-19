#!/usr/bin/env perl
# FILENAME: packlist_to_metadata.pl
# CREATED: 08/03/16 02:53:52 by Kent Fredric (kentnl) <kentfredric@gmail.com>
# ABSTRACT: Turn a .packlist into a <upstream> list

use strict;
use warnings;

use constant PADDING => "\t";
use constant PREFIX  => quotemeta("/usr/lib64/perl5/vendor_perl/5.22.1/");

use ExtUtils::Packlist;

my $pl = ExtUtils::Packlist->new( $ARGV[0] );
for my $entry ( sort keys %{ $pl } ) {
  next unless $entry =~ /\.pm$/;
  $entry =~ s{@{[PREFIX]}}{};
  $entry =~ s{\.pm$}{};
  $entry =~ s{/}{::}g;
 
  print ( PADDING x 2 . "<remote-id type=\"cpan-module\">$entry</remote-id>\n" ); 
}


