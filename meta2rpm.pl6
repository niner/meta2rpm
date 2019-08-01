use JSON::Fast;

multi MAIN() {
    for "META.list".IO.lines -> $uri {
        my $request = run 'curl', '-s', $uri, :out;
        my $meta-text = $request.out.slurp;
        create-spec-file($meta-text);
    }
}

multi MAIN($meta-file) {
    my $meta-text = $meta-file.IO.slurp;
    create-spec-file($meta-text);
}

multi MAIN(:$module!) {
    my @sources =
        'https://raw.githubusercontent.com/ugexe/Perl6-ecosystems/master/cpan1.json',
        'https://raw.githubusercontent.com/ugexe/Perl6-ecosystems/master/p6c1.json';
    my @source-metas = @sources.flatmap: { from-json run(<curl -->, $_, :out).out.slurp-rest };
    my @all-metas = @source-metas.flatmap: *.list;
    my %metas = @all-metas.map: {$_<name> => $_};

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

multi sub create-spec-file(Str $meta-text) {
    my $meta = from-json($meta-text);
    callwith($meta);
}

multi sub create-spec-file($meta) {
    my $package-name = "perl6-{ $meta<name>.subst: /'::'/, '-', :g }";
    note $package-name;
    my $version = $meta<version> eq '*' ?? '0.1' !! $meta<version>;
    my $source-url = $meta<source-url> || $meta<support><source>;
    $meta<license> //= '';

    my $dir = "packages/$package-name".IO;
    my $source-dir = "{$package-name}-$version";
    my $tar-name = "{$package-name}-$version.tar.xz";

    mkdir $dir;
    my @files = fetch-source(:$package-name, :$source-url, :$source-dir, :$dir, :$tar-name);
    my $license-file = @files.grep({$_ eq 'LICENSE' or $_ eq 'LICENCE'}).first // '';

    $dir.IO.child("$package-name.spec").spurt:
        fill-template(
            :$meta,
            :$package-name,
            :$version,
            :$tar-name,
            :$source-url,
            :$license-file,
        );
}

sub fetch-source(:$package-name!, :$source-url!, :$source-dir!, :$dir!, :$tar-name! --> Seq) {
        if $source-url {
            if $source-url.starts-with('git://') or $source-url.ends-with('.git') {
                run <git clone>, $source-url, "$dir/$source-dir" unless $dir.add($source-dir).e;
                run <tar --exclude=.git -cJf>, $tar-name, $source-dir, :cwd($dir) unless $dir.add($tar-name).e;
            }
            else {
                run 'wget', '-q', $source-url, '-O', "$dir/$tar-name" unless $dir.add($tar-name).e;
                run 'tar', 'xf', $tar-name, :cwd($dir);

                my $top-level-dir = $source-url.subst(/.*\//, '').subst(/'.tar.gz'||'.tgz'/, '');

                "$dir/$top-level-dir".IO.rename("$dir/$source-dir");
                run 'tar', 'cJf', $tar-name, $source-dir, :cwd($dir);
            }
            return run(<tar tf>, "$dir/$tar-name", :out).out.lines.map(*.substr($source-dir.chars + 1));
            CATCH {
                default {
                    note "Failed to fetch $source-url";
                }
            }

        }
        else {
            note "$package-name does not have a source-url!";
        }
        return;
}

sub provides(:$meta!) {
    my @provides;
    return $meta<provides>.keys.map({"Provides:       perl6($_)"}).join("\n");
}

sub map-dependency($requires is copy) {
    my %adverbs = flat ($requires ~~ s:g/':' $<key> = (\w+) '<' $<value> = (<-[>]>+) '>'//)
        .map({$_<key>.Str, $_<value>.Str});
    given %adverbs<from> {
        when 'native' {
            if %adverbs<ver> {
                my $lib = $*VM.platform-library-name($requires.IO, :version(Version.new(%adverbs<ver>)));
                my $path = </usr/lib64 /lib64 /usr/lib /lib>.first({$_.IO.add($lib).e});
                if $path {
                    my $proc = run '/usr/lib/rpm/find-provides', :in, :out;
                    $proc.in.say($path.IO.add($lib).resolve.Str);
                    $proc.in.close;
                    $proc.out.lines;
                }
                else {
                    note "Falling back to depending on the library path as I couldn't find $lib";
                    '%{_libdir}/' ~ $*VM.platform-library-name($requires.IO)
                }
            }
            else {
                note "Package doesn't specify a library version, so I have to fall back to depending on library path.";
                '%{_libdir}/' ~ $*VM.platform-library-name($requires.IO)
            }
        }
        when 'bin'    { '%{_bindir}/' ~ $requires }
        default       { "perl6($requires)" }
    }
}

sub requires(:$meta!) {
    my @requires = 'perl6 >= 2016.12';
    @requires.append: flat $meta<depends>.map({ map-dependency($_) }) if $meta<depends>;
    return @requires.map({"Requires:       $_"}).join("\n");
}

sub build-requires(:$meta!) {
    my @requires = 'rakudo >= 2017.04.2';
    @requires.append: flat $meta<build-depends>.map({ map-dependency($_) }) if $meta<build-depends>;
    @requires.push: 'Distribution::Builder' ~ $meta<builder> if $meta<builder>;
    return @requires.map({"BuildRequires:  $_"}).join("\n");
}

sub fill-template(:$meta!, :$package-name!, :$tar-name!, :$version!, :$source-url!, :$license-file!) {
    my $provides = provides(:$meta);
    my $requires = requires(:$meta);
    my $build-requires = build-requires(:$meta);
    my $LICENSE = $license-file ?? " $license-file" !! '';
    my $RPM_BUILD_ROOT = '$RPM_BUILD_ROOT'; # Workaround for https://rt.perl.org/Ticket/Display.html?id=127226
    q:s:to/TEMPLATE/
        #
        # spec file for package $package-name
        #
        # Copyright (c) 2017 SUSE LINUX Products GmbH, Nuernberg, Germany.
        #
        # All modifications and additions to the file contributed by third parties
        # remain the property of their copyright owners, unless otherwise agreed
        # upon. The license for this file, and modifications and additions to the
        # file, is the same license as for the pristine package itself (unless the
        # license for the pristine package is not an Open Source License, in which
        # case the license is the MIT License). An "Open Source License" is a
        # license that conforms to the Open Source Definition (Version 1.9)
        # published by the Open Source Initiative.
        
        # Please submit bugfixes or comments via http://bugs.opensuse.org/
        #

        Name:           $package-name
        Version:        $version
        Release:        1.1
        License:        $meta<license>
        Summary:        $meta<description>
        Url:            $source-url
        Group:          Development/Languages/Other
        Source0:        $tar-name
        $build-requires
        $requires
        $provides
        BuildRoot:      %{_tmppath}/%{name}-%{version}-build

        %description

        %prep
        %setup -q

        %build

        %install
        RAKUDO_RERESOLVE_DEPENDENCIES=0 perl6 %{_datadir}/perl6/bin/install-perl6-dist \\
                --to=$RPM_BUILD_ROOT%{_datadir}/perl6/vendor \\
                --for=vendor \\
                --from=.

        %post

        %postun

        %files
        %defattr(-,root,root)
        %doc README.md$LICENSE
        %{_datadir}/perl6/vendor

        %changelog
        TEMPLATE
}

=begin comment
When collecting a tar file not in git the file name may not be correct.
To resolve this we will pack trhe file and then repack it with file name and configuration we want.
=end comment


# vim: ft=perl6

