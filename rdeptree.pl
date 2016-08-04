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
    my ( $name, $score, $items ) = @{$heat};
    printf "%-60s: %4s <= %60s\n", $name, $score,
      substr do { join q[, ], @{$items} }, 0, 60;
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
    my $last_pn  = 'DOESNOTEXIST';
    my $last_cat = 'DOESNOTEXIST';
  file: while ( my ( $cat, $pn, $file ) = @{ $it->() || [] } ) {
        my $cats = path($cat)->relative(root)->stringify;
        my $pns  = path($pn)->relative($cat)->stringify;
        if ( $cats ne $last_cat or $pns ne $last_pn ) {
            *STDERR->printf( "%30s/%-50s\r", $cats, $pns );
            $last_cat = $cats;
            $last_pn  = $pns;
        }
        my $dist = "$cats/$pns";
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
    my (%wanted_scores);
    for my $package ( keys %hash ) {
        for my $wants ( keys %{ $hash{$package} } ) {
            push @{ $wanted{$wants} }, $package;
            $wanted_scores{$wants}++;
        }
    }
    my (@pairs);
    for my $module (
        sort { $wanted_scores{$a} <=> $wanted_scores{$b} || $a cmp $b }
        keys %wanted
      )
    {
        my (@want_dep) =
          sort { ( $wanted_scores{$b} || 0 ) <=> ( $wanted_scores{$a} || 0 ) || $a cmp $b }
          @{ $wanted{$module} || [] };
        push @pairs, [ $module, $wanted_scores{$module}, \@want_dep ];
    }
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
    my $categories = categories()->iter_fast( $_[0] );
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
                $pkg_it = packages()->iter_fast($cat);
            }
            if ( not defined $pkg ) {
                $pkg = $pkg_it->();
                not defined $pkg and do { undef $cat; undef $pkg_it; 1 }
                  and next;
            }
            if ( not defined $file_it ) {
                $file_it = files()->name(qr/.ebuild$/)->iter_fast($pkg);
            }
            $file = $file_it->();
            not defined $file and do { undef $pkg; undef $file_it; 1 }
              and next;
            return [ $cat, $pkg, $file ];
        }
    };
}

