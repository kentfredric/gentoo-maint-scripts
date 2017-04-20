#!/usr/bin/env perl

use strict;
use warnings;

use Path::Iterator::Rule;
use Path::Tiny qw( path );
use feature 'say';
my $match_text = 'dev-lang/perl-5.24';

my $match_re = join q[(::|-)], map { quotemeta $_ } split qr/::|-/, $match_text;
my $match   = qr/$match_re/i;

my $CAT_RULE = Path::Iterator::Rule->new();
$CAT_RULE->skip_git;
$CAT_RULE->min_depth(1);
$CAT_RULE->max_depth(1);
$CAT_RULE->dir;

my $PKG_RULE = Path::Iterator::Rule->new();
$PKG_RULE->min_depth(1);
$PKG_RULE->max_depth(1);

my $FILE_RULE = Path::Iterator::Rule->new();
$FILE_RULE->file;
$FILE_RULE->line_match( ':raw', $match );

my $CAT_IT = $CAT_RULE->iter('/usr/local/gentoo');
while ( my $cat = $CAT_IT->() ) {
    next  unless $cat =~ qr[/virtual\z];
    my $PKG_IT = $PKG_RULE->iter($cat);
    while ( my $pn = $PKG_IT->() ) {
        next unless $pn =~ qr[/perl-[^/]+\z];
        my $had_match = 0;
        my $FILE_IT = $FILE_RULE->iter($pn);
        while ( my $file = $FILE_IT->() ) {
            my $line_no = 0;
            for my $line ( path($file)->lines_raw( { chomp => 1 } ) ) {
                $line_no++;
                next if $line !~ $match;
                $had_match = 1;
            }
        }
        if ( not $had_match ) {
            printf "%s/%s\n", $cat, $pn;
        }
    }
}
