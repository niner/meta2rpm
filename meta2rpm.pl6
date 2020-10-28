use JSON::Fast;

use RpmSpecMaker;

multi MAIN() {
    for "META.list".IO.lines -> $uri {
        my $request = run 'curl', '-s', $uri, :out;
        my $meta;

        try {
            $meta = from-json($request.out.slurp);
            CATCH {
                default {
                    note "Could not find meta as json from $uri";
                    next;
                }
            }
        }
            create-spec-file($meta);
    }
}

multi MAIN($meta-file) {
    create-spec-file(from-json($meta-file.IO.slurp));
}

multi MAIN(:$module!) {
    my @sources =
        'https://raw.githubusercontent.com/ugexe/Perl6-ecosystems/master/cpan1.json',
        'https://raw.githubusercontent.com/ugexe/Perl6-ecosystems/master/p6c1.json';
    my @source-metas = @sources.map({ say "Fetch: $_"; from-json run(<curl -s -->, $_, :out).out.slurp }).flat
        .sort: { Version.new($^a<version>) <=> Version.new($^b<version>) };
    my %metas = @source-metas.map: {$_<name> => $_};

    sub recursively-create-spec-files($module) {
        my $meta = %metas{$module};
        unless $meta {
            note "Did not find META for $module!";
            next;
        }

        create-spec-file($meta);

        my @requires;
        @requires.append: flat $meta<depends>.map({ map-dependency($_) }) if $meta<depends>;
        @requires.append: flat $meta<build-depends>.map({ map-dependency($_) }) if $meta<build-depends>;
        for @requires {
            if $_ ~~ /'perl6(' (.*) ')'/ {
                recursively-create-spec-files($0);
            }
        }
    }

    recursively-create-spec-files($module);
}

sub create-spec-file($meta) {
    my $package-name = get-name($meta);
    my $package-dir = get-directory($package-name);

    $package-dir.mkdir;
    my $spec = generate-spec($meta);
    $package-dir.add($package-name ~ ".spec").spurt($spec);
}

# vim: ft=perl6

