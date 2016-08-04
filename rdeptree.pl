#!/usr/bin/env perl

use strict;
use warnings;

use Path::Iterator::Rule;
use Path::Tiny qw( path );
use constant root => '/usr/local/gentoo';

use Data::Dump qw(pp);

my (@starting_keys) = (
    'dev-perl/Test-Pod',               'dev-perl/Test-Pod-Coverage',
    'dev-perl/Test-Portability-Files', 'dev-perl/Test-Perl-Critic',
    'dev-perl/Test-CPAN-Meta'
);

my $aggregate = {};

for ( 0 .. 1 ) {
    my $next = find_candidates(@starting_keys);
    for my $source ( keys %{$next} ) {
        $aggregate->{$source} =
          { %{ $aggregate->{$source} || {} }, %{ $next->{$source} } };
    }
    @starting_keys = keys %{$next};
}
print pp $aggregate;
print "\n";
for my $heat ( score_heat($aggregate) ) {
    printf "%s: %s\n", @{$heat};
}

sub find_candidates {
    my (@atoms) = @_;
    *STDERR->print("\nScanning for: @atoms\n");
    do { my $selected = select *STDERR; $|++; select $selected };

    my $it = ebuild_iterator(root);

    # Fast-pass with a compiled regex
    my $matchre_s        = join q[|], map quotemeta, @atoms;
    my $rc_suffix        = qr/_alpha\d*|_beta\d*|_pre\d*|_rc\d*|_p\d*/;
    my $version_suffix   = qr/-\d+(.\d+)*(\s|$|\W|$rc_suffix)/;
    my $nonatom          = qr/[^A-Za-z0-9-]/;
    my $optional_version = qr/(?: \s | $ | ${nonatom} | ${version_suffix} )/x;
    my $matchre = qr{ ${nonatom} (?:${matchre_s}) ${optional_version} }x;

    my %matched_dists;
    my $last_dist = 'DOESNOTEXIST';
    my $last_cat  = 'DOESNOTEXIST';
  file: while ( my ( $cat, $pn, $file ) = @{ $it->() || [] } ) {
        my $cats  = path($cat)->relative(root)->stringify;
        my $dist = path($pn)->relative($cat)->stringify;
        if ( $cats ne $last_cat or $dist ne $last_dist) {
            *STDERR->printf("%30s/%-50s\r", $cats, $dist);
            $last_cat = $cats;
            $last_dist = $dist;
        }
        next if exists $matched_dists{$dist};
        my $fh = path($file)->openr_raw;
      line: while ( my $line = <$fh> ) {
            next line unless $line =~ $matchre;
          atom: for my $atom (@atoms) {
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

sub score_heat {
    my (%hash) = %{ $_[0] };
    my (%wanted);
    for my $package ( keys %hash ) {
        for my $wants ( keys %{ $hash{$package} } ) {
            $wanted{$wants}++;
        }
    }
    my (@pairs) =
      sort { $a->[1] <=> $b->[1] } map { [ $_, $wanted{$_} ] } keys %wanted;
    return @pairs;

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
    my $categories = categories()->iter( $_[0] );
    my $pkg_it;
    my $file_it;
    my ( $cat, $pkg, $file );
    my $done;
    return sub {
        while (1) {
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
                not defined $pkg and do { undef $cat; undef $pkg_it; 1 }
                  and next;
            }
            if ( not defined $file_it ) {
                $file_it = files()->name(qr/.ebuild$/)->iter($pkg);
            }
            $file = $file_it->();
            not defined $file and do { undef $pkg; undef $file_it; 1 }
              and next;
            return [ $cat, $pkg, $file ];
        }
    };
}

