#!/usr/bin/env perl

use strict;
use warnings;

use Path::Iterator::Rule;
use Path::Tiny qw( path );
use constant root => '/usr/local/gentoo/';

my $CAT_RULE = Path::Iterator::Rule->new();
$CAT_RULE->skip_git;
$CAT_RULE->min_depth(1);
$CAT_RULE->max_depth(1);
$CAT_RULE->dir;

if ( $ENV{CATEGORY} ) {
  $CAT_RULE->name($ENV{CATEGORY});
}

my $PKG_RULE = Path::Iterator::Rule->new();
$PKG_RULE->min_depth(1);
$PKG_RULE->max_depth(1);

my $FILE_RULE = Path::Iterator::Rule->new();
$FILE_RULE->file;
$FILE_RULE->name(qr/\.ebuild$/);

my @match_rules;

my $match;
my $keyword_match;

if ( $ARGV[0] ) {
  my $match_text = $ARGV[0]; #|| 'dev-perl/Test-Pod-Coverage';

  my $match_re = join q[(::|-)], map { quotemeta $_ } split qr/::|-/, $match_text;
  $match   = qr/$match_re/i;

  push @match_rules, $match;

}
if ( $ENV{KEYWORDS} ) {  
   my $keyword_res   = join q[|], map quotemeta, split / /, $ENV{KEYWORDS};
   $keyword_match = qr/^\s*KEYWORDS=["']?(?:|.*[ ])(?:$keyword_res)(?:[ ].*|)["']?\s*$/ ;
   push @match_rules, $keyword_match;
}
$FILE_RULE->line_match( ':raw', @match_rules ) if @match_rules;


my $CAT_IT = $CAT_RULE->iter_fast(root);
while ( my $cat = $CAT_IT->() ) {
    my $PKG_IT = $PKG_RULE->iter_fast($cat);
    while ( my $pn = $PKG_IT->() ) {
        my $FILE_IT = $FILE_RULE->iter_fast($pn);
        while ( my $file = $FILE_IT->() ) {
          printf "%s\n", path($pn)->relative(root);
          if ( $ENV{SHOW_CONTEXT} ) {
            show_matches($file);
          }
        }
    }
}

sub show_matches {
  my ( $file ) = @_;
  my $line_no = 0;
  for my $line ( path($file)->lines_raw( { chomp => 1 } ) ) {
    $line_no++;
    for my $match_rule ( @match_rules ) {
      next if $line !~ $match_rule;
      printf "%s:%5d: %s\n", $file, $line_no, $line;
    }
  }
}
