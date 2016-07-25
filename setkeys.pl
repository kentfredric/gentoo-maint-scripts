#!/usr/bin/env perl
# FILENAME: setkeys.pl
# ABSTRACT: Set keywords quickly

use strict;
use warnings;
use Path::Tiny qw( path cwd );
use File::pushd qw( pushd );
use Capture::Tiny qw( capture_stdout );

#my $KEYWORD_STRING=$ENV{WANT_KEYWORDS};
#"alpha amd64 ppc ~ppc64 ~sparc x86 ~amd64-linux ~x86-linux ~ppc-macos ~x86-macos ~sparc-solaris";

my (%KEYWORDS) = map { $_ =~ s/^~//; $_ => 1 } split " ", $ENV{WANT_KEYWORDS}; #$KEYWORD_STRING;

my (@STABLE) = qw( alpha amd64 arm hppa ia64 pcc pcc64 sparc x86 );
my (@DEV)    = qw( alpha amd64 amd64-fbsd arm arm64 hppa ia64 m68k mips ppc ppc64 sh sparc x86 x86-fbsd );
my (@EXP)    = qw( amd64 amd64-fbsd arm arm64 mips nios2 ppc ppc64 riscv s390 sh sparc-fbsd );
my (@PREFIX) = qw(
  amd64-linux
  arm-linux
  hppa-hpux
  ia64-hpux
  m68k-mint
  ppc64-linux
  ppc-aix ppc-macos ppc-openbsd
  sparc64-freebsd sparc64-solaris
  sparc-solaris
  x64-cygwin x64-freebsd x64-macos x64-openbsd x64-solaris
  x86-cygwin x86-freebsd x86-interix x86-linux x86-macos x86-netbsd x86-openbsd x86-solaris
  x86-winnt
);

my (%DEV_KEYWORDS) = map { $_ => 1 } @STABLE, @DEV, @EXP;

#my %KEYWORDS = map { $_ => 1 } qw( arm64 m68k mips s390 sh );

if ( not $ENV{DO_PREFIX} ) {
  for my $keyword ( sort %KEYWORDS ) { 
    delete $KEYWORDS{$keyword} unless exists $DEV_KEYWORDS{$keyword};
  }
}

my $mode = $ARGV[0];

if ( 'fix' eq $mode ) {
  my $best;
  if ( $ARGV[1] ) {
    $best = cwd->child($ARGV[1]);
  } else {
    $best = get_latest();
  }
  if ( not $best ) { die "Can't find ebuilds" };
  info("Rekeywording $best");
  rekeyword( $best );
  exit 0;
}
if ( 'check' eq $mode ) {
  info("Checking " . cwd);
  repoman_full();
  exit 0;
}
info("Unknown mode $mode", ['red']);
exit 1;

use Term::ANSIColor qw( colored );

sub info {
  my $all;
  if ( $_[1] ) { 
    $_[1] = [ grep { $_ eq 'all' ? ($all++, 0)[1] : 1 } @{$_[1]} ];
  }
  print STDERR $_[1] ? colored($_[1], " * " ) : " * ";
  print STDERR "$_[0]\n";
}

sub repoman_full {
  system('repoman','full','-e','y', '--include-arches', ( join ' ', sort keys %KEYWORDS ));
}
sub rekeyword {
  my ( $file ) = @_;
  my $content = $file->slurp_raw;
  my @need_keywords;
  my %got_keywords;
  if ( $content =~ m{KEYWORDS=['"]([^"']+)['"]}ms ) {
    %got_keywords = map { $_ => 1 } split " ", $1;
  }
  my $bn = $file->basename('.ebuild');
  my $cat = $file->parent->parent->basename();

  for my $key ( sort keys %KEYWORDS ) {
    next if exists $got_keywords{$key} or exists $got_keywords{'~' . $key };
    push @need_keywords, "~$key";
  }
  if ( not @need_keywords ) {
    info("Keywords OK for $file", ['green']);
    return;
  }
  info("$cat/$bn: Adding @need_keywords",['yellow']);
  my $cwd = pushd $file->parent->absolute->stringify;
  system("ekeyword", @need_keywords, $bn . '.ebuild' );
  info("$cat/$bn: @need_keywords", ['yellow','all']);
#  my $content = $file->slurp-
#  system("ekeyword", map { "~$_" }
}
sub get_latest {
  my ( @ebuilds ) = cwd->children(qr{\.ebuild$});
  return unless @ebuilds;
  my $cat = cwd->parent->basename;

  my ( $best, @rest ) =
      sort { atom_cmp( $a->[0], $b->[0] ) }
      map { [ "$cat/" . $_->basename('.ebuild'), $_ ] } @ebuilds;

  info("$best->[0]", ['green','all']);
  info($_->[0]) for @rest;

  return $best->[1];
  
}

sub atom_cmp {
    my ( $left, $right ) = @_;
    my ($out,$ret) = capture_stdout {
        system( "qatom", "-c", $left, $right );
    };
    if ( $out =~ /</ ) {
        return 1;
    }
    if ( $out =~ />/ ) {
        return -1;
    }
    return 0;
}


