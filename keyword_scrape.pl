#!perl
use strict;
use warnings;

my $files = {};

use Data::Dump qw(pp);
while ( my $line = <> ) {
    chomp $line;
    my $config = parse_line($line);
    next unless $config->{rule};

    my ( $rule, $file ) = @{$config}{qw( rule file )};
    delete $config->{$_} for qw( rule file );

    if ( $rule eq 'dependency.bad' ) {
        my ( $arch, $dep, $tokens ) =
          @{$config}{qw( arch dep tokens )};
        $dep = '';
        $files->{$file} //= {};
        my $depbad = ( $files->{$file}->{'dependency.bad'} //= {} );
        $depbad->{$arch} //= {};
        $depbad->{$arch}->{$dep} //= {};
        for my $token ( @{$tokens} ) {
            $depbad->{$arch}->{$dep}->{$token} = 1;
        }
        next;
    }
      if ( $rule eq 'dependency.badindev' ) {
        my ( $arch, $dep, $tokens ) =
          @{$config}{qw( arch dep tokens )};
        $dep = '';
        $files->{$file} //= {};
        my $depbad = ( $files->{$file}->{'dependency.badindev'} //= {} );
        $depbad->{$arch} //= {};
        $depbad->{$arch}->{$dep} //= {};
        for my $token ( @{$tokens} ) {
            $depbad->{$arch}->{$dep}->{$token} = 1;
        }
        next;
    }
    if ( $rule eq 'dependency.unknown' ) {
        my ( $dep, $atom ) = @{$config}{qw( dep atom )};
        $dep = '';
        $files->{$file} //= {};
        my $depbad = ( $files->{$file}->{'dependency.unknown'} //= {} );
        $depbad->{$dep} //= {};
        $depbad->{$dep}->{$atom} = 1;
        next;
    }
    $files->{$file} //= {};
    $files->{$file}->{$rule} //= [];
    push @{ $files->{$file}->{$rule} }, $config;

    #  pp($config);
}

sub acmp {
    my ($var) = @_;
    $var =~ s/[^a-z]//;
    if ( $_[0] =~ /\A~/ ) {
        $var .= '~';
    }
    $var;
}

use Term::ANSIColor qw( colored );

for my $file ( sort keys %{$files} ) {
    printf "%s:\n", colored( ['green'], $file );
    for my $rule ( sort keys %{ $files->{$file} } ) {
        if ( $rule eq 'dependency.bad' ) {
            printf "- %s\n", colored( ['red'], $rule );
            render_dependency_bad( $files->{$file}->{$rule} );
            next;
        }
        if ( $rule eq 'dependency.badindev' ) {
            printf "- %s\n", colored( ['red'], $rule );
            render_dependency_badindev( $files->{$file}->{$rule} );
            next;
        }

        if ( $rule eq 'dependency.unknown' ) {
            printf "- %s\n", $rule;
            render_dependency_unknown( $files->{$file}->{$rule} );
            next;
        }

        if ( $rule eq 'KEYWORDS.dropped' ) {
            printf "- %s: %s\n", colored( ['yellow'], $rule ), join q[, ],
              @{ $_->{keywords} }
              for @{ $files->{$file}->{$rule} };
            next;
        }
        if ( $rule eq 'DESCRIPTION.toolong' ) {
            printf "- %s: %s\n", $rule, $_->{message}
              for @{ $files->{$file}->{$rule} };
            next;
        }
        printf "- %s: %s\n", $rule, pp( $files->{$file}->{$rule} );
    }
    print "\n";
}

sub render_dependency_bad {
    my ($dephash) = @_;
    for my $arch ( sort { acmp($a) cmp acmp($b) } keys %{$dephash} ) {
        for my $dep ( sort keys %{ $dephash->{$arch} } ) {
            $dep .= ' ' if length $dep;
            printf "%20s: %s%s\n", $arch, $dep, join q[, ],
              sort keys %{ $dephash->{$arch}->{$dep} };
        }
    }
}
sub render_dependency_badindev {
    my ($dephash) = @_;
    for my $arch ( sort { acmp($a) cmp acmp($b) } keys %{$dephash} ) {
        for my $dep ( sort keys %{ $dephash->{$arch} } ) {
            $dep .= ' ' if length $dep;
            printf "%20s: %s%s\n", $arch, $dep, join q[, ],
              sort keys %{ $dephash->{$arch}->{$dep} };
        }
    }
}
sub render_dependency_unknown {
    my ($dephash) = @_;
    for my $phase ( sort keys %{$dephash} ) {
        my $phase_desc = $phase;
        $phase_desc .= ': ' if length $phase;
        printf "%20s%s\n", $phase_desc, join q[, ],
          sort keys %{ $dephash->{$phase} };
    }
}

sub parse_dependency_bad {
    my ($config) = @_;
    my ( $dep, $arch, $profile, $tokens ) = $config->{message} =~ qr{
    ([^:]+):      # dep
    \s+
    ([^(]+)       # arch
    [(]
    ([^)]+) # profile
    [)]
    \s+
    (.*\z)        # tokens
  }x;
    delete $config->{message};
    $config->{dep}     = $dep;
    $config->{arch}    = $arch;
    $config->{profile} = $profile;
    local $@;
    $config->{tokens} = eval $tokens;
    die $@ if $@;
    return $config;
}

sub parse_dependency_badindev {
    my ($config) = @_;
    my ( $dep, $arch, $profile, $tokens ) = $config->{message} =~ qr{
    ([^:]+):      # dep
    \s+
    ([^(]+)       # arch
    [(]
    ([^)]+) # profile
    [)]
    \s+
    (.*\z)        # tokens
  }x;
    delete $config->{message};
    $config->{dep}     = $dep;
    $config->{arch}    = $arch;
    $config->{profile} = $profile;
    local $@;
    $config->{tokens} = eval $tokens;
    die $@ if $@;
    return $config;
}

sub parse_dependency_unknown {
    my ($config) = @_;
    my ( $dep, $atom ) = $config->{message} =~ qr{
    ([^:]+):      # dep
    \s+
    (.*\z)        # atom
  }x;
    delete $config->{message};
    $config->{dep}  = $dep;
    $config->{atom} = $atom;
    return $config;
}

sub parse_keywords_dropped {
    my ($config) = @_;
    $config->{keywords} = [ split /\s+/, delete $config->{message} ];
    return $config;
}

sub parse_line {
    my ($line) = @_;
    if ( $line =~ /\A\s*\z/ ) {
        return { skipped => 'empty' };
    }
    if ( $line =~ /\ANumberOf[ ](\S+)[ ](\d+)\s*\z/ ) {
        return { skipped => 'count', count_of => $1, count => $2 };
    }
    if ( $line =~ /\A\s*!!!\s*(.*\z)/ ) {
        return { skipped => 'warning', message => $1 };
    }
    if ( $line =~ /\ARepoMan\s(.*\z)/ ) {
        return { skipped => 'trace', message => $1 };
    }
    if ( $line =~ /\ANote:\s(.*\z)/ ) {
        return { skipped => 'note', message => $1 };
    }
    if ( $line =~ /\A(Please fix.*|\s*I'll take it.*)\z/ ) {
        return { skipped => 'note', message => $line };
    }
    if ( my ( $rule, $file, $message ) = $line =~ /\A(\S+)[ ](\S+):[ ](.*)\z/ )
    {
        if ( $rule eq 'dependency.bad' ) {
            return parse_dependency_bad(
                { rule => $rule, file => $file, message => $message } );
        }
        if ( $rule eq 'dependency.badindev' ) {
            return parse_dependency_badindev(
                { rule => $rule, file => $file, message => $message } );
        }

        if ( $rule eq 'KEYWORDS.dropped' ) {
            return parse_keywords_dropped(
                { rule => $rule, file => $file, message => $message } );
        }
        if ( $rule eq 'dependency.unknown' ) {
            return parse_dependency_unknown(
                { rule => $rule, file => $file, message => $message } );
        }
        return {
            rule    => $rule,
            file    => $file,
            message => $message,
        };
    }
    else {
        warn "Unparsed: $line\n";
        return {};
    }
}
