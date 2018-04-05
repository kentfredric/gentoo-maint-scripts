#!perl
use strict;
use warnings;
use Path::Tiny qw( path );
use Data::Dump qw(pp);

use constant STABLEREQ => ( $ENV{ACTION}    || 'keywording' ) eq 'stablereq';
use constant SHOWPKG   => !!( $ENV{SHOWPKG} || 0 );

my $interested_keywords = [ get_interested_keywords() ];

warn "[31mConsidering: [0m@{$interested_keywords}\n";

my $wanted_keywords;

if ( $ENV{WANT} ) {
    $wanted_keywords =
      [ STABLEREQ ? splice_keywords( $ENV{WANT} ) : map { to_stable($_) }
          splice_keywords( $ENV{WANT} ) ];
}
else {
    my $target = shift @ARGV;
    $wanted_keywords = get_file_keywords($target);
}

if( $ENV{IGNORE_KEYWORDS} ) {
  my $ignore =   [ STABLEREQ ? splice_keywords( $ENV{IGNORE_KEYWORDS} ) : map { to_stable($_) }
          splice_keywords( $ENV{IGNORE_KEYWORDS} ) ];

  $wanted_keywords = strip_keywords( $ignore, $wanted_keywords );
}

if ( $ENV{EXTRA_KEYWORDS} ) {
  $interested_keywords = [ @{$interested_keywords},
    STABLEREQ ? splice_keywords( $ENV{EXTRA_KEYWORDS} ) : map { to_stable($_) }
          splice_keywords( $ENV{EXTRA_KEYWORDS} )
  ];
}

warn "[31mWant Keywords:\e[0m @{$wanted_keywords}\n";
my $target_interested =
  filter_keywords( $interested_keywords, $wanted_keywords );


warn "[31mTarget Keywords:\e[0m @{$target_interested}\n";

my $test_keywords;
if ( $ENV{TEST_CHANGED} ) {
  $test_keywords = [@$target_interested];
} else {
  $test_keywords = [@$wanted_keywords];
}

my $needed = {};
# printf "%s has: %s\n",   $target, join q[ ], map { "$_" } @{$wanted_keywords};
# printf "%s wants: %s\n", $target, join q[ ], map { "$_" } @{$target_interested};

binmode *STDERR, ":utf8";
binmode *STDOUT, ":utf8";

my (@folders) = @_;

for my $file (@ARGV) {
    my $have_keywords = get_file_keywords($file);
    push @folders, path($file)->relative('.')->stringify;
    my $missing_keywords = missing_keywords( $wanted_keywords, $have_keywords );
    my $filtered_keywords =
      filter_keywords( $interested_keywords, $missing_keywords );

    $needed->{$_}++ for @{$filtered_keywords};
    if ( @{$filtered_keywords} ) {
        if ( not STABLEREQ ) {
            printf "\e[32m=%s\e[0m %s\n", catorize_file($file), join q[ ],
              map { "~$_" } @{$filtered_keywords};
            if ( $ENV{AUTOFIX} ) {
                echo_run( "ekeyword", ( map { "~$_" } @{$filtered_keywords} ),
                    $file );

            }
        }
        else {
            printf "\e[32m=%s\e[0m %s\n", catorize_file($file), join q[ ],
              map { "$_" } @{$filtered_keywords};
            if ( $ENV{AUTOFIX} ) {
                echo_run( "ekeyword", @{$filtered_keywords}, $file );
            }
        }
    }
}

if ( $ENV{AUTOFIX} ) {
    echo_run( "repoman", "full", "-d", "-e", "y", "--if-modified", "y",
        "--include-arches",
        ( join q[ ], map { to_stable($_) } @{$test_keywords} ) );

}
warn "[31mArches Changed:\e[0m " . ( join q[ ], sort keys %{$needed} ) . "\n";

if ( $ENV{FIND_ADDS} || $ENV{FIND_CHANGES} ) {
  my $flags = '';
  $flags .= 'ACR' if $ENV{FIND_ADDS} || $ENV{FIND_CHANGES};
  $flags .= 'M'   if $ENV{FIND_CHANGES};
  my $nchanges = $ENV{N_CHANGES} ? $ENV{N_CHANGES} : 4;
  echo_run("git","--no-pager", "flog", "--diff-filter=" . $flags, '-n', $nchanges, '--', @folders );
}

sub echo_run {
    my $space = chr(0x2423);
    my $fg    = "36";

    my $style    = "\e[$fg;1m";
    my $endstyle = "\e[0m";

    my $caret      = $style . "> " . $endstyle;
    my $innerspace = $style . $space . $endstyle;

    my (@opts) = @_;
    printf "${caret}%s\n", join qq{ }, map { $_ =~ s[ ][$innerspace]gr } @opts;
    system(@opts);
}

sub catorize_file {
    my ($filename) = @_;
    if ( $filename =~ qr{\A([^/]+)/([^/]+)/([^/]+?).ebuild\z} ) {
        return "$1/$2" if SHOWPKG;
        return "$1/$3";
    }
    return $filename;
}

sub env_upto {
    ( exists $ENV{UPTO} && defined $ENV{UPTO} && length $ENV{UPTO} )
      ? uc $ENV{UPTO}
      : 'STABLE';
}

sub get_interested_classes {
    my @classes;
    my @possible = ( 'STABLE', 'DEV', 'EXP', 'PREFIX' );
    my $upto = env_upto;
    warn "Scanning up to [32m${upto}[0m\n";
    while (@possible) {
        push @classes, shift @possible;
        last if $classes[-1] eq $upto;
    }
    return @classes;
}

sub get_interested_keywords {
    my @keywords;
    if ( $ENV{KEYWORDS} ) {
        @keywords = splice_keywords( $ENV{KEYWORDS} );
    }
    else {
        my @wanted_classes = get_interested_classes();
        warn "Wanted classes [32m@wanted_classes[0m\n";
        my $classes =
          parse_keyword_classes('/usr/portage/profiles/profiles.desc');
        push @keywords, @{ $classes->{$_} } for @wanted_classes;
    }
    return STABLEREQ ? @keywords : map { to_stable($_) } @keywords;
}

sub parse_keyword_classes {
    my ($filename) = @_;
    my $classes = {
        STABLE => {},
        DEV    => {},
        EXP    => {},
        PREFIX => {},
    };
    for my $line ( path($filename)->lines_raw( { chomp => 1 } ) ) {
        next if $line =~ /\A\s*[#]/msx;
        next if $line =~ /\A\s*\z/msx;
        if ( $line =~ /\A(\S+)\s*(\S+)\s*(\S+)\z/msx ) {
            my ( $keyword, $path, $arch ) = ( $1, $2, $3 );
            if ( $path =~ 'prefix' ) {
                $classes->{PREFIX}->{$keyword} = 1;
                next;
            }
            $classes->{ uc $arch }->{$keyword} = 1;
        }
        else {
            warn "Cannot parse $line";
        }
    }
    for my $stable ( sort keys %{ $classes->{STABLE} } ) {
        for my $class (qw( DEV EXP PREFIX )) {
            delete $classes->{$class}->{$stable}
              if exists $classes->{STABLE}->{$stable};
        }
    }
    for my $dev ( sort keys %{ $classes->{DEV} } ) {
        for my $class (qw( EXP PREFIX )) {
            delete $classes->{$class}->{$dev}
              if exists $classes->{DEV}->{$dev};
        }
    }
    for my $exp ( sort keys %{ $classes->{EXP} } ) {
        for my $class (qw( PREFIX )) {
            delete $classes->{$class}->{$exp}
              if exists $classes->{EXP}->{$exp};
        }
    }
    return { map { $_ => hash_to_list( $classes->{$_} ) } keys %{$classes} };
}

sub list_to_hash {
    +{ map { $_ => 1 } sort @{ $_[0] || [] } };
}
sub splice_keywords { split /\s+/, $_[0] }
sub hash_to_list { [ sort keys %{ $_[0] } ] }

sub to_stable {
    my ($keyword) = @_;
    $keyword =~ s/^~//;
    return $keyword;
}

sub get_file_keywords {
    my ($file) = @_;
    my %keywords;
    for my $line ( path($file)->lines_raw( { chomp => 1 } ) ) {
        if ( $line =~ /\A\s*KEYWORDS=["']?(.+?)["']?\s*\z/msx ) {
            if ( not STABLEREQ ) {
                $keywords{$_} = 1 for map { to_stable($_) } splice_keywords($1);
            }
            else {
                $keywords{$_} = 1
                  for grep { $_ =~ /\A[^~]/ } splice_keywords($1);
            }
        }
    }
    return [ sort keys %keywords ];
}

# missing_keywords( [ required ], [ have ] )
sub missing_keywords {
    my $have = list_to_hash( $_[1] );
    my $want = $_[0] || [];
    return [ grep { !exists $have->{$_} } @{$want} ];
}

# filter_keywords( [ care for ], [ have ] )
sub filter_keywords {
    my $care_for = list_to_hash( $_[0] );
    my $have = $_[1] || [];
    return [ grep { exists $care_for->{$_} } @{$have} ];
}

# strip_keywords( [exclude], [have] )
sub strip_keywords {
  my $exclude = list_to_hash( $_[0] );
  my $have = $_[1] || [];
  return [ grep { !exists $exclude->{$_} } @{$have} ];
}
