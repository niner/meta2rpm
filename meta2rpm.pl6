multi MAIN() {
    for "META.list".IO.lines -> $uri {
        my $request = run 'curl', '-s', $uri, :out;
        my $meta-text = $request.out.slurp;
        create-spec-file($meta-text);
    }
}

multi MAIN($meta-file) {
    create-spec-file($meta-file.IO.slurp);
}

sub create-spec-file($meta-text) {
    my $meta = Rakudo::Internals::JSON.from-json($meta-text);
    my $package-name = "perl6-{ $meta<name>.subst: /'::'/, '-', :g }";
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
        when 'native' { '%{_libdir}/' ~ $*VM.platform-library-name($requires.IO) }
        when 'bin'    { '%{_bindir}/' ~ $requires }
        default       { "perl6($requires)" }
    }
}

sub requires(:$meta!) {
    my @requires = 'perl6 >= 2016.12';
    @requires.append: $meta<depends>.map({ map-dependency($_) }) if $meta<depends>;
    return @requires.map({"Requires:       $_"}).join("\n");
}

sub build-requires(:$meta!) {
    my @requires = 'rakudo >= 2017.04.2';
    @requires.append: $meta<build-depends>.map({ map-dependency($_) }) if $meta<build-depends>;
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

# vim: ft=perl6
