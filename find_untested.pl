#!/usr/bin/env perl

use strict;
use warnings;

use Path::Iterator::Rule;
use Path::Tiny qw( path );
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

use Data::Dump qw(pp);
my @proprules = (
    [ 'perl-module' => qr/inherit.*perl-module/ ],
    [ dist_test     => qr/^\s*DIST_TEST=/m ],
    [ src_test      => qr/^\s*SRC_TEST=/m ],
    [ eapi5         => qr/^\s*EAPI=['"]?5['"]?(\s|$)/m ],
    [ eapi6         => qr/^\s*EAPI=['"]?6['"]?(\s|$)/m ],
    [ test_restrict => qr/^\s*RESTRICT=.*test/m ],
    [ hasdep_test_pod => qr{dev-perl/Test-Pod} ],
);

my $CAT_IT = $CAT_RULE->iter('/usr/local/gentoo');
while ( my $cat = $CAT_IT->() ) {
    my $PKG_IT = $PKG_RULE->iter($cat);
    next unless path($cat)->basename eq 'dev-perl';
    while ( my $pn = $PKG_IT->() ) {
        my $FILE_IT = $FILE_RULE->iter($pn);
        my %bad_pkgprops;
        my %pkg_props;
        my $pn_r = path($pn)->basename;
        while ( my $file = $FILE_IT->() ) {
            my $line_no = 0;
            my %props;
            for my $line ( path($file)->lines_raw( { chomp => 1 } ) ) {
                $line_no++;
                for my $prop (@proprules) {
                    next unless $line =~ $prop->[1];
                    next if $props{ $prop->[0] };
                    $props{ $prop->[0] } = [ $line_no, $line ];
                }
            }
            next unless keys %props;
            my $fn = path($file)->relative($pn);
            $fn =~ s/\.ebuild$//;
            $fn =~ s/^\Q$pn_r-\E//;
            $pkg_props{$fn} = [ keys %props ];
            next unless $props{'perl-module'};
            next unless $props{hasdep_test_pod} or $props{'eapi5'} and not $props{src_test};
            $bad_pkgprops{ $fn } = [ keys %props ];
         }
         next unless keys %bad_pkgprops;
         my $rel = path($pn)->relative('/usr/local/gentoo');
         print "$rel: " . pp \%pkg_props;
         print "\n";
    }
}

