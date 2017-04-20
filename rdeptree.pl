#!/usr/bin/env perl

use strict;
use warnings;

use Path::Iterator::Rule;
use Path::Tiny qw( path );

use constant root => '/usr/local/gentoo';

# ignore, skip, require
use constant KEYWORDS => (
      $ENV{KEYWORD_MODE}
    ? $ENV{KEYWORD_MODE}
    : 'ignore'
);
use constant KEYWORD_LIST => (
    $ENV{KEYWORD_LIST}
    ? ( split / /, $ENV{KEYWORD_LIST} )
    : ( 'm68k', '~m68k' )
);
use constant SHOW_DEPS => (
    $ENV{NO_DEPS}
    ? 0
    : 1
);
use constant ITEM_LIMIT => (
    exists $ENV{ITEM_LIMIT} and length $ENV{ITEM_LIMIT}
    ? $ENV{ITEM_LIMIT}
    : -1
);
use constant TRACE_MATCH => $ENV{TRACE_MATCH};
use constant SHOW_MATCH  => ( $ENV{TRACE_MATCH} || 0 ) == 2;
use constant TRACE_KEYWORDS => $ENV{TRACE_KEYWORDS};

use Data::Dump qw(pp);

my ($target_depth)  = 3;
my (@starting_keys) = (
    'dev-perl/CPAN-Changes',      'dev-perl/Test-Pod',
    'dev-perl/Test-Pod-Coverage', 'dev-perl/Test-Portability-Files',
    'dev-perl/Test-Perl-Critic',  'dev-perl/Test-CPAN-Meta',
    'dev-perl/Test-Distribution', 'dev-perl/Test-EOL',
    'dev-perl/Test-Manifest',     'dev-perl/Test-NoTabs',
    'dev-perl/Test-DistManifest', 'dev-perl/Pod-Coverage',
    'dev-perl/Test-use-ok',       'dev-perl/Test-Tester',
    'dev-perl/Moose',
);

if ( $ARGV[0] ) {
    @starting_keys = @ARGV;
}

if ( $ENV{ALL} ) {
    do { my $selected = select *STDERR; $|++; select $selected };
    *STDERR->print("Reticulating splines:");
    my $ticker = arrow_ticker( 0.04 => sub { *STDERR->print( $_[0] ) } );
    my $ticker_x = ticker( 0.4 => sub { *STDERR->print('-') } );
    @starting_keys = ();
    $target_depth  = 0;
    my $it = package_iterator(root);

    while ( my $package = $it->() ) {
        $ticker->();
        $ticker_x->();
        my ( $cat, $pn ) = @{$package};
        my ($distname) = path($pn)->relative(root)->stringify;
        next
          unless $distname =~ qr[dev-perl/]
           or $distname =~ qr[virtual/perl-]
          ;
             push @starting_keys, $distname;
    }
    *STDERR->print("\n");
}

if ( exists $ENV{TARGET_DEPTH} and length "$ENV{TARGET_DEPTH}" ) {
    $target_depth = $ENV{TARGET_DEPTH};
}

my $aggregate = { map { $_ => {} } @starting_keys };

for ( 0 .. $target_depth ) {
    my $previous_state = { %{$aggregate} };
    my $next           = find_candidates(@starting_keys);
    for my $source ( keys %{$next} ) {
        $aggregate->{$source} =
          { %{ $aggregate->{$source} || {} }, %{ $next->{$source} } };
    }
    @starting_keys = grep { not exists $previous_state->{$_} } keys %{$next};
}

use Text::Wrap qw( wrap );
use Time::HiRes qw( clock_gettime CLOCK_THREAD_CPUTIME_ID );

print pp $aggregate;
print "\n";
for my $heat ( score_heat($aggregate) ) {
    local $Text::Wrap::columns = 120 + 4 + 72;
    local $Text::Wrap::huge    = 'overflow';

    my ( $name, $score, $items, $wants ) = @{$heat};
    my $leader = sprintf "%-60s: %10d", $name, $score;
    my $wrapped = "";
    if ( ITEM_LIMIT == 0 ) {
        $wrapped = $leader;
    }
    else {
        my @new_items = @{$items};
        if ( ITEM_LIMIT > 0 and scalar @new_items > ITEM_LIMIT ) {
            @new_items = splice @new_items, 0, ITEM_LIMIT;
        }
        $wrapped =
          wrap( "$leader <= ", ' ' x ( 72 + 4 ), join q[, ], @new_items );
    }
    printf "\e[1m%s\e[0m\n", ( length $wrapped ? $wrapped : $leader );
    if ( SHOW_DEPS and ITEM_LIMIT != 0 ) {
        $leader = sprintf "%72s => ", "";
        my @new_items = @{$wants};
        if ( ITEM_LIMIT > 0 and scalar @new_items > ITEM_LIMIT ) {
            @new_items = splice @new_items, 0, ITEM_LIMIT;
        }
        $wrapped = wrap( $leader, ' ' x ( 72 + 4 ), join q[, ], @new_items );
        printf "%s\n", $wrapped;
    }
}

sub find_candidates {
    my (@atoms) = @_;
    {
        my $atom_text = substr ${ \join q[, ], @atoms }, 0, 240;
        $atom_text =~ s/,\s\S*?\z/.../ if 200 < length $atom_text;
        *STDERR->print("\nScanning for(${\scalar @atoms}): $atom_text\n");
    }
    return {} if not @atoms;
    do { my $selected = select *STDERR; $|++; select $selected };

    my $it      = ebuild_iterator(root);
    my $n_atoms = scalar @atoms;

    # Fast-pass with a compiled regex
    my $matchre_s        = join q[|], map quotemeta, @atoms;
    my $rc_suffix        = qr/_alpha\d*|_beta\d*|_pre\d*|_rc\d*|_p\d*/;
    my $version_suffix   = qr/-\d+(?:.\d+)*(?:\s|$|\W|$rc_suffix)/;
    my $nonatom          = qr/[^A-Za-z0-9-]/;
    my $optional_version = qr/(?: \s | $ | ${nonatom} | ${version_suffix} )/x;

    # Excludes !< ! !> and !! on purpose.
    my $prequalifier = qr/(?: (?:\s|^|["']) (?: = | [><]=? | ~ )? )/x;
    my $matchre = qr{ ${prequalifier} (?:${matchre_s}) ${optional_version} }x;
    my $keyword_res      = join q[|], map quotemeta, KEYWORD_LIST;
    my $keyword_re       = qr/(?:^|[ ])(?:$keyword_res)(?:[ ]|$)/;
    my $blankline_re     = qr/^\s*(#|$)/;
    my $keywords_extract = qr/^\s*KEYWORDS=["']?(.*)["']?\s*$/;
    my $commands         = qr/src_remove_dual(_man)?/;
    my %matched_dists;
    my $cats = 'DOESNOTEXIST';
    my $pns  = 'DOESNOTEXIST';

# NB: When you have ~30k regex, compiling them once for every line of every file is slow
    my %atomrules;
    for my $atom (@atoms) {
        $atomrules{$atom} = qr/${prequalifier}\Q${atom}\E${optional_version}/;
    }
    my @keyword_rules;
    for my $keyword ( map quotemeta, KEYWORD_LIST ) {
      push @keyword_rules, [ qr{(?:^|[ ])(?:$keyword)(?:[ ]|$)}, $keyword ];
    }
    my $ticker =
      ticker( 0.04 => sub { *STDERR->printf( "%30s/%-50s\r", $cats, $pns ) } );

  file: while ( my ( $cat, $pn, $file ) = @{ $it->() || [] } ) {
        $cats = path($cat)->relative(root)->stringify;
        $pns  = path($pn)->relative($cat)->stringify;
        $ticker->();
        my $dist = "$cats/$pns";

        my $fh = path($file)->openr_raw;
        my $keywords;
        my $keywords_matched;
        my @matched_keywords;

      line: while ( my $line = <$fh> ) {

     # Optimisation speeds up early passes by stopping IO if all atoms are found
            next file if $n_atoms == keys %{ $matched_dists{$dist} || {} };

            # skip comments/blanks
            next line if $line =~ $blankline_re;

            # skip deps mentioned in function calls
            next line if $line =~ $commands;

              if ( KEYWORDS eq 'require' and $line =~ $keywords_extract ) {
                $keywords = $1;
                next file unless $keywords =~ $keyword_re;
                $keywords_matched = 1;
            }
            if ( KEYWORDS eq 'skip' and $line =~ $keywords_extract ) {
                $keywords = $1;
                next file if $keywords =~ $keyword_re;
            }


            next line unless $line =~ $matchre;
          atom: for my $atom (@atoms) {

                # Ignore self-dependency
                next atom if $atom eq $dist;
                next atom if exists $matched_dists{$dist}{$atom};
                if ( $line =~ $atomrules{$atom} ) {

                    $matched_dists{$dist}{$atom} = 1;
                    if ( TRACE_MATCH ) {
                      *STDERR->printf(" \e[32m*\e[0m Match: %10s -> %s", $atom, $dist);
                      
                      if ( $keywords_matched and not @matched_keywords ) {
                           for my $rule ( @keyword_rules ) {
                           push @matched_keywords, $rule->[1] if $keywords =~ $rule->[0];
                        }
                      }
                      $keywords_matched and *STDERR->printf(" (%s)",join q[ ], @matched_keywords);
                    }
                    if ( SHOW_MATCH ) {
                      chomp $line;
                      *STDERR->printf( "\e[31m<%s>\e[0m", $line );
                    }
                    if ( SHOW_MATCH or TRACE_MATCH ) {
                      *STDERR->print("\n");
                    }
                }
            }
        }
    }
    return \%matched_dists;
}

sub mk_wanted_by {
    my ($hash) = @_;

    # hash is a hash of
    # { WHAT => { WANTED => 1 }}
    my ($out) = {};
    for my $what ( keys %{$hash} ) {
        for my $wanted ( keys %{ $hash->{$what} } ) {
            $out->{$wanted}->{$what} = 1;
        }
    }
    return $out;
}

sub ticker {
    my ( $freq, $callback ) = @_;
    my $last_update;
    return sub {
        my $now = clock_gettime(CLOCK_THREAD_CPUTIME_ID);
        if ( not defined $last_update or $freq < ( $now - $last_update ) ) {
            $last_update = $now;
            $callback->();
        }
    };
}

sub smile_ticker {
    my ( $freq, $callback ) = @_;
    my (@symbols) = ( " ;)", " :)", ">:)", " :P", " :]", "3:)" );
    my $i = 0;
    return ticker(
        $freq,
        sub {
            my $symbol = $symbols[ $i++ % ( scalar @symbols ) ];
            $callback->( $symbol . ( qq[\b] x 3 ) );
        }
    );
}

sub slash_ticker {
    my ( $freq, $callback ) = @_;
    my (@symbols) = ( "/", "-", "\\", "|" );
    my $i = 0;
    return ticker(
        $freq,
        sub {
            my $symbol = $symbols[ $i++ % ( scalar @symbols ) ];
            $callback->( $symbol . ( qq[\b] x 1 ) );
        }
    );
}

sub arrow_ticker {
    my ( $freq, $callback ) = @_;

    #    my ( @symbols ) = ( " ;)" , " :)", ">:)", " :P", " :]", "3:)" );
    my (@symbols) = (
        "\e[31m>\e[0m   ", "\e[31m>\e[32m>\e[0m  ",    #
        " \e[32m>\e[0m  ", " \e[32m>\e[33m>\e[0m ",    #
        "  \e[33m>\e[0m ", "  \e[33m>\e[34m>\e[0m",    #
        "   \e[34m>\e[0m", "\e[31m>  \e[34m>\e[0m",    #
    );
    my $i = 0;
    return ticker(
        $freq,
        sub {
            my $symbol = $symbols[ $i++ % ( scalar @symbols ) ];
            $callback->( $symbol . ( qq[\b] x 4 ) );
        }
    );
}

my %does_cycles;
my %inside;

sub heat_for {
    my ( $hash, $key ) = @_;

    # hash is list of
    # package => wantedby => 1
    if ( not exists $hash->{$key} ) {
        return 1;
    }
    if ( exists $hash->{$key} and not keys %{ $hash->{$key} } ) {
        return 1;
    }
    my $total = 1;
    for my $dependent ( keys %{ $hash->{$key} } ) {
        next if $does_cycles{$dependent};
        if ( $inside{$dependent} ) {
            *STDERR->print("\e[31m Cycle! Members: $dependent ->");
            pp \%inside;
            $does_cycles{$dependent} = {%inside};
            *STDERR->print("\e[0m\n");
            next;
        }
        $inside{$dependent} = 1;
        $total += heat_for( $hash, $dependent );
        delete $inside{$dependent};
    }
    return $total;
}

sub score_heat {
    my (%hash) = %{ $_[0] };

    my $wanted_by = mk_wanted_by( \%hash );

    my (%wanted);
    my (%wanted_scores);
    my $max_score = 0;

    for my $package (
        keys %{ { map { ( $_ => 1 ) } keys %hash, keys %{$wanted_by} } } )
    {
        $wanted_scores{$package} = heat_for( $wanted_by, $package );
        $wanted{$package} = [ keys %{ $wanted_by->{$package} } ];
    }

    # Initial sort
    my (@pairs) = sort { $a->[1] <=> $b->[1] || $a->[0] cmp $b->[0] }
      map { [ $_, $wanted_scores{$_}, [], 1 ] } keys %wanted;

    for my $pair (@pairs) {
        my ( $module, $score ) = @{$pair};
        $pair->[2] = [
            map { $_ . '(' . ( $wanted_scores{$_} || 0 ) . ')' }
              sort {
                ( $wanted_scores{$b} || 0 ) <=> ( $wanted_scores{$a} || 0 )
                  || $a cmp $b
              } @{ $wanted{$module} || [] }
        ];
        $pair->[3] = [
            map { $_ . '(' . ( $wanted_scores{$_} || 0 ) . ')' }
              sort {
                ( $wanted_scores{$b} || 0 ) <=> ( $wanted_scores{$a} || 0 )
                  || $a cmp $b
              } keys %{ $hash{$module} || {} }
        ];

    }

    # Resort after rescoring
    return sort { $a->[1] <=> $b->[1] || $a->[0] cmp $b->[0] } @pairs;

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

sub ebuilds {
    return files()->name(qr/.ebuild$/);
}

sub package_iterator {
    my $categories = categories()->iter_fast( $_[0] );
    my $pkg_it;
    my ( $cat, $pkg, );
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
            $pkg = $pkg_it->();
            not defined $pkg and do { undef $cat; undef $pkg_it; 1 }
              and next;

            my $ebuild = ebuilds()->iter_fast($pkg)->();
            next unless defined $ebuild;

            return [ $cat, $pkg ];
        }
    };
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

