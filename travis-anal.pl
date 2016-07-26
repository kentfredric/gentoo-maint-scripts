#!perl
use strict;
use warnings;

use Path::Tiny qw( path );
use Term::ANSIColor qw( colorstrip );

for my $child ( grep { $_->is_dir } path('.')->children ) {
  print "$child\n";
  my @entries;
  for my $log ( $child->children(qr/.*\.log$/)) {
    my %facts;
    my $content = $log->slurp_raw();
    my (@lines) = split /\n|\r/, colorstrip($content);
    for my $line ( @lines ) {
      if ( $line =~ /\$\s*export\s*(.*$)/ ) {
        my $export = $1;
        if ( $export =~ /CC=(.*$)/ ) {
          $facts{'compiler'} = $1;
          next;
        }
        if ( $export =~ /CLANG_VERSION=(.*)/ ) {
          $facts{clang} = $1;
          next
        }
        if ( $export =~ /GCC_VERSION=(.*)/ ) {
          $facts{gcc} = $1;
          next;
        }
        if ( $export =~ /VANILLA=/ ) {
          $facts{'vanilla'} = 1;
          next;
        }
        if ( $export =~ /myconf="(.*)"$/ ) {
          $facts{'myconf'} = $1;
          next
        }
        if ( $export =~ /TARGET_PERL=(.*)$/ ) {
          $facts{'perl'} = $1;
          next;
        }
        next;
      }
      if ( $line =~ /Done. Your build exited with 0\./ ) {
        $facts{pass} = 1;
      }
      if ( $line =~ /(Files=\d+,\s*Tests=\d+,.*?CPU\))/ ) {
        $facts{times} = $1;
        if ( $facts{times} =~ /Tests=(\d+).*?(\d+\.\d+)\s*CPU/  ) {
          $facts{n_tests} = $1;
          $facts{cputime} = $2;
          $facts{tests_per_cpu} = $1 / $2;
        }
        next;
      }
      next;
    }
    if ( keys %facts ) {
      my $cc_type;
      my $message;
      if ( $facts{gcc} ) {
        $cc_type = "GCC $facts{gcc}";
      }
      if ( $facts{clang} ) {
        $cc_type = "CLANG $facts{clang}";
      }
      if ( not $cc_type ) {
        $cc_type = 'GCC 4';
      }
      my $brand;
      if ( $facts{vanilla} ) {
        $brand = "VANILLA $cc_type";
      } else {
        $brand = "GENTOO  $cc_type";
      }
      if ( $facts{myconf} ) {
        $brand .= ' + myconf ' . $facts{myconf};
      }
      if ( $facts{perl} and $facts{perl} =~ /^.*(perl-.*?\.tar\.\S+)/ ) {
        $brand = "$1 $brand";
      }
      if ( not $facts{pass} ) {
        $message  = " Fail: $brand\n";
      }
      else {
        $message = " Pass: $brand";
        if ( $facts{tests_per_cpu} ) {
          $message =  sprintf "%-80s - %8d/%8.3f = %12.3f Tests Per CPU Sec", $message,$facts{n_tests}, $facts{cputime}, $facts{tests_per_cpu};
        } 
        elsif ( $facts{times} ) {
          $message = sprintf "%-80s - %s", $message,$facts{times};
        }
        $message .= "\n";
      }
      push @entries, { %facts, message => $message, brand => $brand, cc_type => $cc_type };
    }
  }

  my (@sorting) = sort {
    $a->{cc_type} cmp $b->{cc_type}
    ||
    ( $a->{myconf} || '' ) cmp ( $b->{myconf} || '' )
    ||
    ( $a->{vanilla} || 0 ) <=> ( $b->{vanilla} || 0 )
  } @entries;
  for my $entry ( @sorting ) {
    print $entry->{message};
  }
}
