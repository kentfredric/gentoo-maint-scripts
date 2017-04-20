#!/usr/bin/env perl

use strict;
use warnings;

use Path::Iterator::Rule;
use Path::Tiny qw( path );
use Capture::Tiny qw( capture_stdout );
use constant root => '/usr/local/gentoo/';

my $CAT_RULE = Path::Iterator::Rule->new();
$CAT_RULE->skip_git;
$CAT_RULE->min_depth(1);
$CAT_RULE->max_depth(1);
$CAT_RULE->dir;

$CAT_RULE->name('dev-perl');

my $PKG_RULE = Path::Iterator::Rule->new();
$PKG_RULE->min_depth(1);
$PKG_RULE->max_depth(1);
$PKG_RULE->name(qr/\A[Cc]/);

my $FILE_RULE = Path::Iterator::Rule->new();
$FILE_RULE->file;
$FILE_RULE->name(qr/\.ebuild$/);

my $recs;
my $cache = {};

my $min_timeout = time() - ( 60 * 60 * 24 * 30 );
my $bad_timeout = time() - ( 60 * 60 * 24 * 120 );

my $CAT_IT = $CAT_RULE->iter_fast(root);
while ( my $cat = $CAT_IT->() ) {
    my $PKG_IT = $PKG_RULE->iter_fast($cat);

    while ( my $pn = $PKG_IT->() ) {
        my %package_data;

        my $FILE_IT = $FILE_RULE->iter_fast($pn);
        while ( my $file = $FILE_IT->() ) {
            my (@keywords) = get_keywords($file);
            if ( not @keywords ) {
                warn "$file has no KEYWORDS";
            }
            for my $stable ( grep /\A[a-z]/, @keywords ) {
                push @{ $package_data{'stable'}->{$stable} }, $file;
            }
            for my $unstable ( grep /\A~[a-z]/, @keywords ) {
                push @{ $package_data{'unstable'}->{$unstable} }, $file;
            }
        }
        my $pn_warned;

        if ( exists $package_data{stable} and exists $package_data{unstable} ) {
          KEYWORD: for my $stable ( sort keys %{ $package_data{stable} } ) {
                if ( exists $package_data{unstable}->{"~${stable}"} ) {
                    my (@unstable_files);
                  FILE:
                    for my $file ( @{ $package_data{unstable}->{"~$stable"} } )
                    {
                        my $file_mtime = pkg_mtime($file);
                        next FILE if $file_mtime >= $min_timeout;
                        push @unstable_files, $file;
                    }
                    next KEYWORD if not @unstable_files;
                    $pn_warned ||= warn "$pn: possible stabilization\n";

                    warn "- $stable : @{$package_data{stable}->{$stable}}\n";
                    warn "  ~$stable:\n";

                  FILE:
                    for my $file ( @{ $package_data{unstable}->{"~$stable"} } )
                    {
                        my $file_mtime = pkg_mtime($file);
                        my $grade =
                            $file_mtime < $bad_timeout ? '[31mBAD[0m'
                          : $file_mtime < $min_timeout ? '[32mOK[0m'
                          :                              '[34mFRESH[0m';

                        warn "    $grade: $file\n";
                    }
                }

            }
        }
    }
}

sub get_keywords {
    my ($path) = @_;
    my $fh = path($file)->openr_raw;

    my %keywords;
    while ( my $line = <$fh> ) {
        next unless $line =~ /^\s*KEYWORDS=['"]?(.*)['"]?\s*\z/;
        my $keywords = $1;
        $keywords{$_} = $_ for split /\s+/, $keywords;
    }
    return sort keys %keywords;

}

sub pkg_mtime {
    my ($path) = @_;
    return $cache->{$path} if exists $cache->{$path};
    my ( $out, $ret ) = capture_stdout {
        system( 'git', 'log', '-n1', '--format=%ct', '--', $path );
    };
    if ( not $ret == 0 ) {
        die "Capture failed";
    }
    chomp $out;
    return $cache->{$path} = $out;
}
