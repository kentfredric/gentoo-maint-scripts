#!/usr/bin/env perl

use strict;
use warnings;

use Path::Iterator::Rule;
use Path::Tiny qw( path );
use constant root => '/usr/local/gentoo';

my $match_text = $ARGV[0] || 'dev-perl/Test-Pod-Coverage';

#my $match_re = join q[(::|-)], map { quotemeta $_ } split qr/::|-/, $match_text;
#my $match   = qr/$match_re/i;

use Data::Dump qw(pp);

my $aggregate = {};

my $initial = find_candidates('dev-perl/Test-Pod-Coverage','dev-perl/Test-Pod');
$aggregate = $initial;
my $last = $initial;
for ( 0..2 ) {
  my $next = find_candidates(keys %{$last});
  for my $source ( keys %{ $next } ) {
    $aggregate->{$source} = { %{$aggregate->{$source} || {} }, %{$next->{$source}} };
  }
  $last = $next;
}
print pp $aggregate;


sub find_candidates {
  my ( @atoms ) = @_;
  *STDERR->print("\nScanning for: @atoms\n");
  do { my $selected = select *STDERR; $|++; select $selected };

  my $it = ebuild_iterator(root);
  # Fast-pass with a compiled regex
  my $matchre_s = join q[|], map quotemeta, @atoms;
  my $rc_suffix = qr/_alpha\d*|_beta\d*|_pre\d*|_rc\d*|_p\d*/;
  my $version_suffix = qr/-\d+(.\d+)*(\s|$|\W|$rc_suffix)/;
  my $nonatom = qr/[^A-Za-z0-9-]/;
  my $optional_version = qr/(?: \s | $ | ${nonatom} | ${version_suffix} )/x;
  my $matchre   = qr{ ${nonatom} (?:${matchre_s}) ${optional_version} }x; 

  my %matched_dists;
  my $last_dist = 'DOESNOTEXIST';
  my $last_cat  = 'DOESNOTEXIST';
  file: while ( my ( $cat, $pn, $file ) = @{ $it->() || [] }) {
    my $cat = path($cat)->relative(root)->stringify;
    my $dist = path($pn)->relative(root)->stringify;
    if ( $cat ne $last_cat ) {
      *STDERR->print("$cat...");
      $last_cat = $cat;
    }
    if ( $dist ne $last_dist ) {
      $last_dist = $dist;
    }
    next if exists $matched_dists{$dist};
    my $fh = path($file)->openr_raw;
    line: while ( my $line = <$fh> ) {
      next line unless $line =~ $matchre;
      atom: for my $atom ( @atoms ) {
        next atom if exists $matched_dists{$dist}{$atom};
        if ( $line =~ qr/${nonatom}${atom}${optional_version}/ ) {
          $matched_dists{$dist}{$atom} = 1;
          # printf "%s -> %s\n", path($file)->relative(root), $atom;
          chomp $line;
          # print STDERR "## $line\n";
        }
      }
    }
  }
  return \%matched_dists;
}

sub categories {
  my $CAT_RULE = Path::Iterator::Rule->new();
  $CAT_RULE->skip_git;
  $CAT_RULE->min_depth(1);
  $CAT_RULE->max_depth(1);
  $CAT_RULE->dir;
  return $CAT_RULE;
}

sub packages {
  my $PKG_RULE = Path::Iterator::Rule->new();
  $PKG_RULE->min_depth(1);
  $PKG_RULE->max_depth(1);
  return $PKG_RULE;
}
sub files {
  my $FILE_RULE = Path::Iterator::Rule->new();
  $FILE_RULE->file;
  return $FILE_RULE;
}

sub ebuild_iterator {
  my $categories = categories()->iter($_[0]);
  my $pkg_it;
  my $file_it;
  my ( $cat, $pkg, $file );
  my $done;
  return sub {
    while ( 1 ) {
      return undef if $done;
      if ( not defined $cat ) {
        $cat = $categories->();
        not defined $cat and $done = 1 and return undef;
      }
      if ( not defined $pkg_it ) {
        $pkg_it = packages()->iter($cat);
      }
      if ( not defined $pkg ) {
        $pkg = $pkg_it->();
        not defined $pkg and do { undef $cat; undef $pkg_it; 1 } and next;
      }
      if ( not defined $file_it ) {
        $file_it = files()->name(qr/.ebuild$/)->iter( $pkg );
      }
      $file = $file_it->();
      not defined $file and do { undef $pkg; undef $file_it; 1 } and next;
      return [ $cat, $pkg, $file ];
    }
  };
}

